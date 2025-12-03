# Tree Scene Comprehensive Audit

**Date**: 2025-12-03
**Scope**: Client-side tree visualization (Godot 4.5)
**Files Analyzed**:
- `scenes/tree/tree.tscn`
- `scenes/tree/tree_controller.gd`
- `features/tree/tree_renderer.gd`
- `features/tree/tree_data_models.gd`
- `features/ui/components/interactive_background/background_touch_controller.gd`
- `features/ui/components/interactive_background/interactive_background.gd`
- `features/server_interface/api/services/tree_service.gd`

---

## Executive Summary

The tree visualization has several significant issues affecting user experience:

| Issue | Severity | Root Cause |
|-------|----------|------------|
| Inverted momentum after pinch | **Critical** | Velocity samples polluted by emulated mouse during pinch |
| Elements pop-in at wrong borders | **High** | Fixed-pixel culling margin doesn't account for zoom level |
| Lines invisible when zoomed | **High** | Culling only checks node visibility, not edge viewport intersection |
| Overlapping labels | **Medium** | No collision detection or priority-based label culling |

---

## Issue 1: Inverted Pan Momentum After Two-Finger Zoom

**Symptoms**: After performing a two-finger pinch zoom, releasing causes the view to "rubber band" in the opposite direction of the intended pan.

**Location**: `background_touch_controller.gd`

### Root Cause Analysis

The touch controller has a fundamental flaw in how it handles velocity calculation during multi-touch gestures:

1. **Velocity samples get polluted during pinch** (lines 68-99):
   ```gdscript
   if event is InputEventScreenDrag:
       # ...
       if _touch_state.size() >= 2:
           _handle_pinch_zoom()
           accept_event()  # Accepts the ScreenDrag event
       return
   ```
   The `accept_event()` call only prevents further processing of the `InputEventScreenDrag`. However, with `emulate_mouse_from_touch=true`, an **additional** `InputEventMouseMotion` event is generated for the first finger and processed separately.

2. **Emulated mouse motion records bad velocity samples** (lines 306-328):
   ```gdscript
   func _handle_mouse_motion(event: InputEventMouseMotion) -> bool:
       if not _mouse_dragging:
           return false
       # ...
       _record_position_sample(event.position)  # Records first finger position during pinch!
   ```
   During a pinch gesture, `_mouse_dragging` is still true (set when the first finger went down), so position samples from the first finger continue to be recorded even though the user is performing a pinch zoom.

3. **Velocity calculation uses wrong sample order** (lines 375-399):
   ```gdscript
   func _calculate_velocity() -> Vector2:
       # ...
       return (oldest_pos - newest_pos) / time_delta  # BUG: Should be newest - oldest
   ```
   The velocity is calculated as `oldest - newest` instead of `newest - oldest`. This gives the opposite sign.

4. **Inertia sign convention** (lines 354-356):
   ```gdscript
   scroll_offset -= _velocity * delta
   ```
   Combined with the inverted velocity calculation, this causes:
   - During single-finger pan: Bug #3 causes wrong direction, but somehow this might be working (needs verification)
   - During pinch: First finger samples + Bug #3 = rubber-band effect

### Additional Issues

5. **`_stop_inertia()` not called for touch start** (lines 68-79):
   When touches start via `InputEventScreenTouch`, the code only tracks state but doesn't call `_stop_inertia()`. Old velocity from previous gestures may persist.

6. **No velocity samples during pinch pan** (lines 222-258):
   `_handle_pinch_zoom()` updates `scroll_offset` but never calls `_record_position_sample()`, so the calculated velocity doesn't reflect the actual pinch pan motion.

### Recommended Fix

```gdscript
# In _gui_input, for InputEventScreenTouch:
if event is InputEventScreenTouch:
    if touch_event.pressed:
        _touch_state[touch_event.index] = touch_event.position
        if _touch_state.size() == 1:
            _stop_inertia()  # Clear velocity on first touch
    # ...

# In _handle_pinch_zoom, record center position:
var current_center := (p1 + p2) / 2.0
_record_position_sample(current_center)  # Track pinch center for velocity

# Fix velocity calculation:
func _calculate_velocity() -> Vector2:
    # ...
    return (newest_pos - oldest_pos) / time_delta  # Correct direction
```

---

## Issue 2: Elements Pop-in at Wrong Screen Borders

**Symptoms**: Nodes and edges appear/disappear at arbitrary boundaries within the viewport rather than at or slightly past the screen edges.

**Location**: `tree_renderer.gd:285-290`

### Root Cause Analysis

The culling margin is a fixed pixel value that doesn't scale with zoom:

```gdscript
const CULL_MARGIN: float = 100.0

func _get_view_rect() -> Rect2:
    var half_size = (_viewport_size / 2.0) / _current_scale + Vector2(CULL_MARGIN, CULL_MARGIN)
    var center = _scroll_offset / _current_scale
    return Rect2(center - half_size, half_size * 2)
```

**Problems**:
1. `CULL_MARGIN` of 100 is added in **world space** (after dividing viewport by scale)
2. At high zoom (e.g., `_current_scale = 10`), the viewport in world space is small (~128x72 world units for 1280x720 screen), but the margin is still 100 world units - nearly as large as the viewport itself
3. At low zoom (e.g., `_current_scale = 0.1`), the viewport in world space is huge (~12800x7200 world units), but the margin is only 100 world units - effectively no buffer

### Recommended Fix

The culling margin should be in **screen space** and converted to world space:

```gdscript
const CULL_MARGIN_SCREEN: float = 200.0  # Screen pixels outside viewport

func _get_view_rect() -> Rect2:
    var margin_world = CULL_MARGIN_SCREEN / _current_scale
    var half_size = (_viewport_size / 2.0) / _current_scale + Vector2(margin_world, margin_world)
    var center = _scroll_offset / _current_scale
    return Rect2(center - half_size, half_size * 2)
```

---

## Issue 3: Lines Turn Invisible When Zoomed In

**Symptoms**: When zooming in significantly, tree edges (lines connecting nodes) disappear even though the nodes they connect are visible.

**Location**: `tree_renderer.gd:327-351` and `420-432`

### Root Cause Analysis

**Primary Issue - Edge Visibility Culling** (lines 339-351):
```gdscript
func _render_radial_edges() -> void:
    # ...
    var visible_ids = {}
    for rd in visible_nodes:
        visible_ids[rd.node.id] = true

    for edge in tree_data.edges:
        if visible_ids.has(edge.source) and visible_ids.has(edge.target):
            _draw_radial_edge(edge)
```

Edges are only drawn if **both** connected nodes are in `visible_nodes`. When zoomed in, many parent nodes (especially higher-rank taxonomy nodes near the root) are outside the viewport, causing their edges to disappear even though the child nodes are visible.

**Secondary Issue - Edge Width at High Zoom** (lines 420-432):
```gdscript
func _get_edge_width(source, target) -> float:
    var base_width: float
    # ...
    var scaled_width = base_width / _current_scale
    return maxf(scaled_width, 0.5)
```

At high zoom (scale = 10), a 6px edge becomes 0.6px world units = 6px on screen. The minimum of 0.5 world units prevents complete disappearance, but the inverse scaling approach means edges get thinner as you zoom in, which is counter-intuitive.

**Tertiary Issue - Line2D Rendering**:
Line2D nodes with very large coordinate values relative to their width can have rendering artifacts in Godot's renderer.

### Recommended Fixes

1. **Expand edge visibility to include edges crossing the viewport**:
```gdscript
func _render_radial_edges() -> void:
    var view_rect = _get_view_rect()
    # Include edges that intersect the view rect, not just those with both endpoints visible
    for edge in tree_data.edges:
        var source_node = tree_data.get_node_by_id(edge.source)
        var target_node = tree_data.get_node_by_id(edge.target)
        if not source_node or not target_node:
            continue

        # Check if edge intersects view (simplified: check if either endpoint is visible
        # or if the edge's bounding box intersects the view)
        var edge_rect = Rect2(source_node.position, Vector2.ZERO).expand(target_node.position)
        if view_rect.intersects(edge_rect):
            _draw_radial_edge(edge)
```

2. **Consider constant screen-space line width**:
```gdscript
func _get_edge_width(source, target) -> float:
    # Use a fixed screen-space width (will be counter-scaled by the transform)
    var screen_width: float
    if source.is_taxonomic() and target.is_taxonomic():
        screen_width = 3.0  # 3 screen pixels
    else:
        screen_width = 2.0
    return screen_width / _current_scale
```

---

## Issue 4: Overlapping Labels

**Symptoms**: When multiple nodes are close together (especially at certain zoom levels), their labels overlap and become unreadable.

**Location**: `tree_renderer.gd:446-494`

### Root Cause Analysis

Labels are created for all visible nodes without any collision detection:

```gdscript
func _render_taxonomy_labels() -> void:
    # ...
    for render_data in visible_nodes:
        if should_show_label:
            var label = Label.new()
            label.text = label_text
            # ... no overlap checking
            labels_container.add_child(label)
```

**Additional Issues**:

1. **All visible nodes get labels**: No prioritization based on zoom level or node importance
2. **No spatial partitioning**: No quadtree or grid for efficient overlap detection
3. **Counter-scaling math may be off** (lines 488-491):
   ```gdscript
   var label_size = label.get_minimum_size()
   var offset = Vector2(-label_size.x * inverse_scale / 2.0, node_size + 5 * inverse_scale)
   label.position = render_data.position + offset
   ```
   `label_size` is in screen pixels, but `offset` applies `inverse_scale` to it, which may produce incorrect positioning when combined with the label's own counter-scale.

### Recommended Fixes

1. **Implement priority-based label culling**:
```gdscript
const MAX_LABELS: int = 50
const MIN_LABEL_DISTANCE_SCREEN: float = 80.0  # Minimum screen pixels between labels

func _render_taxonomy_labels() -> void:
    # Sort by importance (taxonomic rank, capture status)
    var candidates = _get_label_candidates()
    candidates.sort_custom(_compare_label_priority)

    var placed_labels: Array[Rect2] = []
    var labels_created = 0

    for candidate in candidates:
        if labels_created >= MAX_LABELS:
            break

        var label_rect = _calculate_label_screen_rect(candidate)
        if not _overlaps_any(label_rect, placed_labels):
            _create_label(candidate)
            placed_labels.append(label_rect)
            labels_created += 1
```

2. **Zoom-based label filtering**:
```gdscript
func _should_show_label_at_zoom(node: TaxonomicNode) -> bool:
    # Only show higher-rank labels when zoomed out
    if node.is_taxonomic():
        match node.rank:
            TaxonomicRank.ROOT, TaxonomicRank.KINGDOM:
                return _current_scale >= 0.1
            TaxonomicRank.PHYLUM, TaxonomicRank.CLASS:
                return _current_scale >= 0.3
            TaxonomicRank.ORDER, TaxonomicRank.FAMILY:
                return _current_scale >= 0.5
            _:
                return _current_scale >= 1.0
    return _current_scale >= 1.5  # Animal labels only when zoomed in
```

---

## Additional Issues Identified

### 5. Coordinate Space Inconsistency

**Location**: `tree_controller.gd:235-246` vs `tree_renderer.gd:285-290`

The transform calculation and view rect calculation appear to use different interpretations of `scroll_offset`:

```gdscript
# tree_controller.gd - scroll_offset multiplied by scale
transform.origin = _viewport_center - _scroll_offset * _current_scale

# tree_renderer.gd - scroll_offset divided by scale
var center = _scroll_offset / _current_scale
```

This inconsistency suggests `scroll_offset` is being treated as screen-space in one place and world-space in another. While the current implementation may work due to compensating factors, this is fragile and confusing.

**Recommendation**: Establish a clear coordinate convention and document it. Either:
- `scroll_offset` is the world position we're looking at (divide by scale to use in world-space calculations)
- `scroll_offset` is the screen-space offset from center (use directly for screen-space, divide by scale for world)

### 6. Edge Re-rendering Performance

**Location**: `tree_renderer.gd:237-238`

```gdscript
if scale != old_scale:
    _render_radial_edges()
```

Edges are completely re-created when scale changes. This involves:
- Deleting all existing Line2D children
- Creating new Line2D instances for each visible edge
- Calculating bezier curves for each edge

With potentially thousands of edges, this is expensive for smooth pinch-zoom. Consider:
- Using a single Line2D with multiple polylines
- Caching bezier points and only updating width
- Using a custom shader for edge rendering

### 7. Spatial Index Grid Size

**Location**: `tree_renderer.gd:577-580`

```gdscript
func _get_grid_key(pos: Vector2) -> Vector2i:
    var grid_size = 100.0
    return Vector2i(int(pos.x / grid_size), int(pos.y / grid_size))
```

The grid size of 100 world units is fixed. At high zoom levels, this may be too coarse for efficient click detection. Consider scaling the grid with zoom level or using a quadtree.

### 8. Missing Callback Validation in Some Places

**Location**: Various places in `tree_service.gd`

```gdscript
# Line 74 - correct pattern
if context.callback and context.callback.is_valid():
    context.callback.call(response, 200)

# Line 158 - missing is_valid() check
if callback:
    callback.call({"error": "Query cannot be empty"}, 400)
```

Inconsistent callback validation could cause crashes if the scene that initiated the call has been freed.

### 9. Touch Controller State Not Fully Reset

**Location**: `background_touch_controller.gd:414-427`

The `reset()` function clears most state but doesn't reset `_last_positions` and `_last_times`:

```gdscript
func reset() -> void:
    scroll_offset = Vector2.ZERO
    current_scale = 1.0
    _velocity = Vector2.ZERO
    _touch_state.clear()
    _touch_start_positions.clear()
    _gesture_recognized = false
    _base_touch_state.clear()
    _mouse_dragging = false
    _mouse_drag_recognized = false
    # Missing: _last_positions.clear(), _last_times.clear()
```

### 10. Search Centering Uses Wrong Scale Factor

**Location**: `tree_controller.gd:413-419`

```gdscript
func _on_search_results(results: Array) -> void:
    # ...
    var pos = Vector2(position_array[0], position_array[1])
    touch_controller.scroll_offset = pos * _current_scale
```

The scroll_offset is set to `pos * _current_scale`, but based on the transform math, if `pos` is in world coordinates, the scroll_offset should likely just be `pos` (or the inverse, depending on the coordinate convention).

---

## Scene Structure Review

The scene hierarchy in `tree.tscn` is well-organized:

```
Tree (Node2D, tree_controller.gd)
├── BackgroundLayer (CanvasLayer, layer=-1)
│   └── InteractiveBackground (Control)
├── TreeGraph (Node2D)
│   ├── EdgesLayer (z=-1)
│   ├── NodesLayer (z=0)
│   └── LabelsLayer (z=2)
└── UILayer (CanvasLayer, layer=10)
    └── Control (mouse_filter=2/IGNORE)
        └── VBoxContainer (buttons, search, etc.)
```

**Positive aspects**:
- Proper layer separation (background, tree, UI)
- Z-index used correctly for edges/nodes/labels ordering
- UI container has `mouse_filter=2` to pass events through
- Touch targets meet minimum 44x44px requirement

**Concerns**:
- InteractiveBackground is in a CanvasLayer while TreeGraph is a direct child - their transforms are in different coordinate spaces. The touch controller signals are used to synchronize them, but this adds complexity.

---

## Performance Considerations

### Current Bottlenecks

1. **Edge rendering**: Creating/destroying Line2D nodes on every zoom
2. **Label rendering**: Creating/destroying Label nodes on every view change
3. **Full visibility check**: Iterating all nodes every frame to update visibility

### Recommendations

1. **Object pooling**: Reuse Line2D and Label nodes instead of creating/destroying
2. **Dirty flag**: Only recalculate visibility when scroll/scale actually changed
3. **LOD system**: Reduce detail at low zoom levels (fewer edges, no labels)
4. **Chunked loading**: Only load/render chunks in view (partially implemented but not used)

---

## Summary of Recommended Priority Fixes

1. **[Critical]** Fix velocity calculation and sample tracking in `background_touch_controller.gd`
2. **[High]** Scale culling margin with zoom in `_get_view_rect()`
3. **[High]** Expand edge visibility to include edges crossing viewport
4. **[Medium]** Implement label overlap detection and priority culling
5. **[Medium]** Clarify coordinate space conventions with documentation
6. **[Low]** Add object pooling for edges and labels
7. **[Low]** Complete state reset in touch controller

---

## Test Cases for Verification

After fixes, verify:

1. **Pan momentum**: Single-finger pan → release → view continues in swipe direction
2. **Pinch momentum**: Two-finger pinch+pan → release → view continues smoothly
3. **Pop-in boundaries**: Nodes/edges appear just outside visible viewport edge
4. **Edge visibility**: When zoomed in on leaf nodes, edges to parent are still visible
5. **Label readability**: At any zoom level, visible labels don't overlap
6. **Performance**: Smooth 60fps during pan/zoom with 1000+ nodes
