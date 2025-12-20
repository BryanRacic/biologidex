# Tree Navigation Arrows Implementation Audit

**Date**: 2025-12-19
**Files Reviewed**:
- `client/biologidex-client/features/tree_visualization/tree_navigation_arrow.gd`
- `client/biologidex-client/features/tree_visualization/tree_navigation_arrows_layer.gd`
- `client/biologidex-client/features/tree_visualization/tree_visualization.gd`
- `client/biologidex-client/features/tree/tree_renderer.gd`

---

## Executive Summary

The tree navigation arrows implementation has several architectural issues that affect maintainability, introduce subtle bugs, and create unnecessary complexity. The primary concerns are:

1. **Duplicated coordinate conversion logic** across files
2. **Inconsistent coordinate space handling** with unclear conventions
3. **Diff circle offset calculation bug** causing arrows to appear inside the circle
4. **Redundant parameter synchronization** between layers
5. **Suboptimal object pool usage patterns**
6. **Missing coordinate space documentation**

---

## Issue 1: Duplicated Coordinate Conversion Logic

### Problem

Both `tree_navigation_arrows_layer.gd` and `tree_renderer.gd` implement nearly identical coordinate conversion functions:

**In `tree_navigation_arrows_layer.gd` (lines 127-131):**
```gdscript
func _screen_to_tree_local(screen_pos: Vector2) -> Vector2:
    var world_pos = (screen_pos - _viewport_center) / _current_scale + _scroll_offset
    return world_pos / _tree_scale
```

**In `tree_renderer.gd` (lines 1349-1355):**
```gdscript
func _screen_to_world(screen_pos: Vector2) -> Vector2:
    var world_pos = (screen_pos - _viewport_center) / _current_scale + _scroll_offset
    return world_pos / _tree_scale
```

**In `tree_renderer.gd` (lines 1260-1267):**
```gdscript
func _world_to_screen(local_pos: Vector2) -> Vector2:
    var world_pos = local_pos * _tree_scale
    return (world_pos - _scroll_offset) * _current_scale + _viewport_center
```

### Impact
- **DRY Violation**: Same logic duplicated across files
- **Maintenance burden**: Changes to coordinate math must be synchronized manually
- **Bug risk**: Divergence between implementations could cause subtle positioning errors
- **Naming inconsistency**: `_screen_to_tree_local` vs `_screen_to_world` do the same thing but have different names

### Recommendation
Create a shared `CoordinateConverter` utility class or move these functions to a common location that both components can reference.

---

## Issue 2: Duplicated View State Variables

### Problem

Both `TreeNavigationArrowsLayer` and `TreeRenderer` maintain their own copies of view state:

**In `tree_navigation_arrows_layer.gd` (lines 51-55):**
```gdscript
var _scroll_offset: Vector2 = Vector2.ZERO
var _current_scale: float = 1.0
var _viewport_center: Vector2 = Vector2.ZERO
var _viewport_size: Vector2 = Vector2(1280, 720)
var _tree_scale: float = 1.0
```

**In `tree_renderer.gd` (lines 132-136):**
```gdscript
var _scroll_offset: Vector2 = Vector2.ZERO
var _current_scale: float = 1.0
var _viewport_center: Vector2 = Vector2.ZERO
var _viewport_size: Vector2 = Vector2(1280, 720)
var _tree_scale: float = 1.0
```

**In `tree_visualization.gd` (lines 168-170):**
```gdscript
var _scroll_offset: Vector2 = Vector2.ZERO
var _current_scale: float = 1.0
var _viewport_center: Vector2 = Vector2.ZERO
```

### Impact
- **Triple redundancy**: Same state stored in three places
- **Synchronization overhead**: Every view change requires updating all three copies
- **Memory inefficiency**: Unnecessary duplication of Vector2 objects
- **Potential desync**: If one update fails, components could have inconsistent view states

### Recommendation
Use a shared `ViewState` object or reference-based pattern. The arrows layer could receive a reference to the renderer's view state instead of maintaining its own copy.

---

## Issue 3: Duplicated `_get_view_rect()` Implementation

### Problem

Both classes implement their own view rect calculation with identical logic:

**In `tree_navigation_arrows_layer.gd` (lines 400-407):**
```gdscript
func _get_view_rect() -> Rect2:
    var combined_scale := _current_scale * _tree_scale
    var margin := 100.0 / combined_scale
    var half_size := (_viewport_size / 2.0) / combined_scale + Vector2(margin, margin)
    var center := _scroll_offset / _tree_scale
    return Rect2(center - half_size, half_size * 2)
```

**In `tree_renderer.gd` (lines 463-477):**
```gdscript
func _get_view_rect() -> Rect2:
    var combined_scale = _current_scale * _tree_scale
    var margin_local = CULL_MARGIN_SCREEN / combined_scale
    var half_size = (_viewport_size / 2.0) / combined_scale + Vector2(margin_local, margin_local)
    var center = _scroll_offset / _tree_scale
    return Rect2(center - half_size, half_size * 2)
```

### Differences
- `CULL_MARGIN_SCREEN` (200.0) in renderer vs hardcoded `100.0` in arrows layer
- Different margin semantics even though same purpose

### Recommendation
Unify into a single source of truth. The arrows layer should query the renderer's view rect or use a shared utility.

---

## Issue 4: Diff Circle Offset Calculation Bug (Root Node Arrows Inside Circle)

### Problem

The diff circle offset logic in `_update_visible_arrows()` (lines 300-315, 330-335) has a bug where arrows can still appear inside the diff circle.

**Current code (lines 314-315):**
```gdscript
if source_at_diff_center:
    source_offset = maxf(source_offset, _diff_circle_radius + 20.0)
```

### Bug Analysis

1. **The `+20.0` constant is in tree-local units**, but the diff circle radius may be in different units depending on the tree scale context.

2. **The check `source_pos.distance_to(_diff_circle_center) < 1.0` (line 300)** only triggers when the node is exactly at the diff circle center, but the root node's position may be at `(0,0)` while `_diff_circle_center` could be non-zero after coordinate transformations.

3. **Missing consideration of arrow size**: The offset should account for the arrow's visual radius, not just its center point:
   ```gdscript
   # Should be:
   source_offset = maxf(source_offset, _diff_circle_radius + arrow_size/2.0 + padding)
   ```

4. **The diff circle values are never converted to the correct coordinate space**. The `_diff_circle_center` and `_diff_circle_radius` are set directly from `TreeVisualization.diff_circle_center` and `diff_circle_radius` without considering if they need transformation.

### Root Cause
The diff circle is defined in tree-local coordinates (per `tree_visualization.gd` line 100), but the arrows layer stores these values directly without documentation of what space they're in, leading to confusion and incorrect calculations.

### Recommendation

```gdscript
# Calculate proper arrow offset from diff circle edge
var min_offset_from_circle := _diff_circle_radius + (arrow_size / 2.0) + 30.0  # 30 = padding
if source_at_diff_center:
    source_offset = maxf(source_offset, min_offset_from_circle)
```

Also add explicit coordinate space documentation:
```gdscript
## Diff circle center in TREE-LOCAL coordinates (same as node.position)
var _diff_circle_center: Vector2 = Vector2.ZERO
```

---

## Issue 5: Redundant Parameter Propagation

### Problem

Arrow configuration is duplicated across `TreeVisualization` exports and `TreeNavigationArrowsLayer` instance variables, requiring manual synchronization.

**In `tree_visualization.gd` (lines 108-138):**
```gdscript
@export var navigation_arrows_enabled: bool = true
@export var arrow_size: float = 30.0
@export var arrow_distance: float = 60.0
@export var arrow_opacity: float = 0.75
@export var arrow_dex_image_offset: float = 500.0
```

Each setter manually propagates to `_arrows_layer`:
```gdscript
set(value):
    arrow_size = value
    if _arrows_layer:
        _arrows_layer.arrow_size = value
```

**In `tree_navigation_arrows_layer.gd` (lines 20-38):**
```gdscript
var arrow_size: float = 20.0  # Note: default differs from TreeVisualization!
var arrow_distance_from_node: float = 60.0
var arrow_opacity: float = 1  # Note: default differs from TreeVisualization!
var dex_image_offset: float = 500.0
```

### Issues
- **Default value mismatch**: `arrow_size` is 30.0 in TreeVisualization but 20.0 in ArrowsLayer
- **Default value mismatch**: `arrow_opacity` is 0.75 in TreeVisualization but 1.0 in ArrowsLayer
- **Naming inconsistency**: `arrow_distance` vs `arrow_distance_from_node`
- **Boilerplate setters**: 5 identical setter patterns

### Recommendation
Use a configuration object pattern:
```gdscript
class ArrowConfig:
    var size: float = 30.0
    var distance_from_node: float = 60.0
    var opacity: float = 0.75
    var dex_image_offset: float = 500.0

# Pass config to arrows layer
_arrows_layer.configure(arrow_config)
```

---

## Issue 6: Mixed Coordinate Space Conventions

### Problem

The codebase uses three coordinate spaces (per CLAUDE.md) but lacks consistent naming and documentation:

| Variable | File | Coordinate Space | Documentation |
|----------|------|-----------------|---------------|
| `position` | arrow.gd:58 | tree-local | Implied by activate() docstring |
| `target_position` | arrow.gd:14 | tree-local | Docstring says "tree-local coordinates" |
| `_scroll_offset` | arrows_layer.gd:51 | world | Undocumented |
| `_diff_circle_center` | arrows_layer.gd:65 | tree-local? | Undocumented |
| `world_position` | signal:13 | world | Signal param name suggests world |

### Inconsistencies

1. **Signal emits world position** (`navigate_to_node.emit(..., world_pos)` at line 138) but internal calculations use tree-local
2. **The `_trigger_navigation` function (lines 134-139)** converts tree-local to world, but the naming is unclear:
   ```gdscript
   var target_pos: Vector2 = arrow.target_position  # tree-local
   var world_pos: Vector2 = target_pos * _tree_scale  # converted to world
   navigate_to_node.emit(arrow.target_node_id, world_pos)
   ```

3. **Comments and docstrings are inconsistent**:
   - Some say "tree-local coordinates"
   - Some say "tree-local (world) space" (conflating the two)
   - Some have no documentation

### Recommendation
Adopt a naming convention that embeds the coordinate space:
```gdscript
var position_tree_local: Vector2
var scroll_offset_world: Vector2
var viewport_center_screen: Vector2
```

Or use type aliases/wrapper classes:
```gdscript
class TreeLocalPosition:
    var value: Vector2
```

---

## Issue 7: Object Pool Usage Patterns

### Problems

**Pool size constant but usage varies (arrows_layer.gd line 26):**
```gdscript
const ARROW_POOL_SIZE: int = 200
```

The pool creates 200 arrow instances upfront, but typical usage only shows arrows for the node closest to screen center (usually 1-10 arrows). This wastes memory.

**Linear search for available arrows (line 142-147):**
```gdscript
func _get_available_arrow():
    for arrow in _arrow_pool:
        if not arrow.is_active():
            return arrow
    return null
```

This O(n) search runs for every arrow activation. With 200 pool entries, this adds unnecessary overhead.

**No pool exhaustion handling (line 376-377):**
```gdscript
if not arrow:
    continue  # Pool exhausted
```

Silent failure when pool is exhausted. No warning, no dynamic growth.

### Comparison with `tree_renderer.gd`

The renderer uses a more efficient pattern for dex images:
```gdscript
# Uses active tracking dictionary
var active_dex_images: Dictionary = {}  # {image_key: TreeDexImage}
```

### Recommendation

1. **Reduce pool size** to a reasonable maximum (e.g., 20-50)
2. **Use a free list** instead of linear search:
   ```gdscript
   var _free_arrows: Array = []
   var _used_arrows: Dictionary = {}

   func _get_available_arrow():
       if _free_arrows.is_empty():
           return _grow_pool()
       return _free_arrows.pop_back()
   ```
3. **Add pool exhaustion warning** for debugging
4. **Consider dynamic pool sizing** based on actual usage

---

## Issue 8: Visibility Update Inconsistency

### Problem

The arrows layer has a `_visibility_dirty` flag (line 69) but the update pattern differs from the renderer.

**Arrows layer (lines 196-203):**
```gdscript
func update_arrows() -> void:
    if not _visibility_dirty or not _tree_data:
        return
    _visibility_dirty = false
    _update_visible_arrows()
```

This requires the parent (`TreeVisualization`) to call `update_arrows()` explicitly after `update_view()`:
```gdscript
# tree_visualization.gd lines 526-528
_arrows_layer.update_view(_scroll_offset, _current_scale, _viewport_center)
_arrows_layer.update_arrows()
```

**Renderer uses `_process()` for deferred updates (lines 375-396):**
```gdscript
func _process(_delta: float) -> void:
    if _visibility_dirty and (current_time - _last_update_time) >= MIN_UPDATE_INTERVAL:
        _visibility_dirty = false
        # ... update logic
```

### Issues
- **Inconsistent patterns**: One uses explicit calls, one uses `_process()`
- **Arrows layer lacks throttling**: No `MIN_UPDATE_INTERVAL` like the renderer
- **Double update risk**: Both `update_view()` and `update_arrows()` could trigger redundant work

### Recommendation
Unify the update patterns. Either:
1. Move arrows update into its own `_process()` with throttling, OR
2. Have the renderer trigger arrow updates (since they share data)

---

## Issue 9: Edge-Arrow Distance Calculation Issues

### Problem

Arrow placement along edges uses multiple overlapping offset calculations (lines 299-346):

```gdscript
# Base distance
var base_dist := arrow_distance_from_node  # 60.0

# Add dex image offset if node has image
if source_has_image:
    source_offset += dex_image_offset  # +500.0

# Add diff circle offset if at center
if source_at_diff_center:
    source_offset = maxf(source_offset, _diff_circle_radius + 20.0)

# Cap at 40% of edge length
source_offset = minf(source_offset, max_arrow_dist)
```

### Issues

1. **Dex image offset (500.0)** seems arbitrary - should relate to actual image size
2. **40% max edge length** may conflict with diff circle offset requirement
3. **Multiple offset additions** make final position hard to predict
4. **Diff circle padding (20.0)** doesn't account for arrow visual size

### Example Bug Scenario
If `edge_length = 400` and `_diff_circle_radius = 330`:
- `max_arrow_dist = 400 * 0.4 = 160`
- `required_offset = 330 + 20 = 350`
- `final_offset = min(350, 160) = 160` -- Arrow placed INSIDE diff circle!

### Recommendation
Calculate diff circle offset BEFORE applying max distance cap, or skip arrows entirely when edge is too short to place outside diff circle:

```gdscript
var required_offset := base_dist
if source_at_diff_center:
    required_offset = _diff_circle_radius + arrow_size/2.0 + PADDING

if required_offset > max_arrow_dist:
    continue  # Skip this arrow - can't place outside diff circle

source_offset = required_offset
```

---

## Issue 10: Missing Input Handling Guard

### Problem

The `_input()` function in `tree_navigation_arrows_layer.gd` (lines 87-111) processes input even when the layer might not be properly initialized:

```gdscript
func _input(event: InputEvent) -> void:
    if not visible or _active_arrows.is_empty():
        return
    # ... process input
```

### Missing Guards
- No check for `_tree_data` validity
- No check for `is_inside_tree()`
- No check for `_current_scale` being valid (avoid division by zero)

### Comparison
The renderer has proper guards in `update_view()`:
```gdscript
if not is_inside_tree():
    return
```

### Recommendation
Add initialization guards:
```gdscript
func _input(event: InputEvent) -> void:
    if not visible or _active_arrows.is_empty():
        return
    if not _tree_data or not is_inside_tree():
        return
    if _current_scale <= 0.0:
        return
```

---

## Summary of Recommendations

### High Priority (Bugs)

1. **Fix diff circle offset calculation** - Add proper arrow size consideration and prevent capping from placing arrows inside circle
2. **Add coordinate space documentation** - Every Vector2 should have clear space annotation
3. **Sync default values** - Ensure TreeVisualization and ArrowsLayer defaults match

### Medium Priority (Maintainability)

4. **Extract coordinate converter utility** - Single source of truth for space conversions
5. **Use shared ViewState** - Eliminate triple-redundant view state
6. **Create ArrowConfig object** - Replace 5 redundant export/setter pairs
7. **Unify update patterns** - Consistent dirty-flag processing

### Low Priority (Performance)

8. **Optimize object pool** - Reduce size, use free list instead of linear search
9. **Add pool exhaustion logging** - Help debug edge cases
10. **Add input handling guards** - Prevent edge case crashes

---

## Best Practices References

- [Game and UI Coordinates: the Difference](https://docs.ctjs.rocks/tips-n-tricks/game-and-ui-coordinates) - Separating coordinate spaces
- [Multiple Coordinate Spaces - 3D Math Primer](https://gamemath.com/book/multiplespaces.html) - Coordinate space theory
- [Godot Object Pooling Examples](https://github.com/anasrar/godot-object-pooling) - Best practices for pooling in Godot 4
- [Design Patterns in Godot](https://www.gdquest.com/tutorial/godot/design-patterns/intro-to-design-patterns/) - GDQuest patterns guide
- [Arrow Buttons in UI Design](https://medium.com/design-bootcamp/the-role-and-application-of-arrow-buttons-in-user-interface-design-7d2277c45bff) - Navigation arrow UX best practices
