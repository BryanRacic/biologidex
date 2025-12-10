# Tree Scene Culling Optimization - Implementation Plan

## Overview

This document provides a detailed implementation plan for optimizing DexRecordImage loading performance in the tree_camera scene. The goal is to eliminate lag during scrolling by:

1. Using `VisibleOnScreenNotifier2D` for native engine visibility detection
2. Throttling visibility update calculations
3. Implementing lazy image loading with frame-budget queuing

---

## Current Architecture Summary

### Components Involved

| Component | Location | Role |
|-----------|----------|------|
| `TreeRenderer` | `features/tree/tree_renderer.gd` | Manages visibility, pooling, and rendering |
| `TreeDexImage` | `features/tree/tree_dex_image.gd` | Wrapper node for each pooled dex image |
| `DexRecordImage` | `features/ui/components/dex_record_image/` | Reusable UI component for image display |
| `DexImageLoader` | `features/dex/dex_image_loader.gd` | Centralized async image loading service |
| `TreeCameraController` | `features/tree/camera_controller.gd` | Camera pan/zoom input handling |

### Current Flow

```
Camera moves → view_changed signal → update_view()
    ↓
_update_visible_nodes() - loops ALL render_nodes, checks view_rect
    ↓
_update_dex_images() - for each visible capture:
    - Check if already active
    - If not: get pooled TreeDexImage, call activate()
        ↓
    activate() → record_image.load_image_from_entry()
        ↓
    DexImageLoader.load_image() → cache check OR HTTP download
        ↓
    Callback → texture applied, image_loaded signal
```

### Bottlenecks Identified

1. **Per-frame GDScript loop** over 50,000+ nodes in `_update_visible_nodes()`
2. **Synchronous activation** of multiple images when scrolling into new area
3. **HTTP I/O spikes** when multiple images download simultaneously
4. **No preloading** - images only start loading when fully visible

---

## Implementation Plan

### Phase 1: Add VisibleOnScreenNotifier2D to TreeDexImage

**Goal:** Leverage native engine visibility detection for preloading triggers.

#### 1.1 Modify TreeDexImage to include notifier

**File:** `features/tree/tree_dex_image.gd`

```gdscript
# Add after line 11 (const DexRecordImageScene):
const PRELOAD_MARGIN: float = 500.0  # World units - start loading before fully visible

# Add member variables after line 22 (_current_ratio):
var _visibility_notifier: VisibleOnScreenNotifier2D = null
var _image_load_state: int = LoadState.IDLE  # Track loading state

enum LoadState {
    IDLE,           # Not loaded, not loading
    QUEUED,         # In the loading queue
    LOADING,        # Currently loading (HTTP in progress)
    LOADED,         # Image loaded successfully
    FAILED          # Load failed
}

# Signals for tree_renderer to subscribe to
signal visibility_entered
signal visibility_exited
signal load_state_changed(new_state: int)
```

#### 1.2 Create and configure the notifier

**Add to `_ready()` after `_setup_record_image()`:**

```gdscript
func _ready() -> void:
    _setup_record_image()
    _setup_visibility_notifier()

func _setup_visibility_notifier() -> void:
    """Create VisibleOnScreenNotifier2D for native visibility detection."""
    _visibility_notifier = VisibleOnScreenNotifier2D.new()
    _visibility_notifier.name = "VisibilityNotifier"
    add_child(_visibility_notifier)

    # Connect signals
    _visibility_notifier.screen_entered.connect(_on_screen_entered)
    _visibility_notifier.screen_exited.connect(_on_screen_exited)

    # Initial rect will be set when activate() is called with size
```

#### 1.3 Update rect when size changes

**Modify `set_image_size()`:**

```gdscript
func set_image_size(size: float) -> void:
    """Set the target size for this image in world units."""
    _target_size = size
    _apply_scale()
    _update_notifier_rect()

func _update_notifier_rect() -> void:
    """Update visibility notifier rect based on current size and preload margin."""
    if not _visibility_notifier:
        return

    # Calculate rect centered on this node with preload margin
    var half_size := _target_size / 2.0
    var margin := PRELOAD_MARGIN

    # Rect2 is (position, size) - position is relative to this node
    _visibility_notifier.rect = Rect2(
        Vector2(-half_size - margin, -half_size - margin),
        Vector2(_target_size + margin * 2, _target_size + margin * 2)
    )
```

#### 1.4 Handle visibility signals

```gdscript
func _on_screen_entered() -> void:
    """Called by engine when notifier rect enters viewport."""
    visibility_entered.emit()

    # Request image load if not already loaded/loading
    if _image_load_state == LoadState.IDLE:
        _request_image_load()

func _on_screen_exited() -> void:
    """Called by engine when notifier rect completely exits viewport."""
    visibility_exited.emit()

    # Note: We don't unload here - that's managed by the pool
    # This signal is informational for the renderer

func _request_image_load() -> void:
    """Request to be added to the loading queue."""
    if _image_load_state != LoadState.IDLE:
        return

    _set_load_state(LoadState.QUEUED)

func _set_load_state(new_state: int) -> void:
    """Update load state and emit signal."""
    if _image_load_state == new_state:
        return
    _image_load_state = new_state
    load_state_changed.emit(new_state)
```

#### 1.5 Modify activate() to track state

**Update existing `activate()` function:**

```gdscript
func activate(world_position: Vector2, creation_index: int, user_id: String, entry_data: Dictionary, size: float = DEFAULT_IMAGE_SIZE) -> void:
    """Activate this image at a world position. Does NOT auto-load - use start_load()."""
    position = world_position
    _creation_index = creation_index
    _user_id = user_id
    _target_size = size
    _is_active = true
    _image_load_state = LoadState.IDLE  # Reset state
    visible = true

    _apply_scale()
    _update_notifier_rect()

    # Store entry data but don't load yet
    record_image.set_entry_data(entry_data, user_id)

    if Engine.is_editor_hint():
        record_image.set_placeholder()
        _set_load_state(LoadState.LOADED)

func start_load() -> void:
    """Actually start loading the image (called by loading queue)."""
    if _image_load_state == LoadState.LOADING or _image_load_state == LoadState.LOADED:
        return

    _set_load_state(LoadState.LOADING)
    record_image.load_image_from_entry()

func _on_image_loaded(success: bool) -> void:
    """Handle image load completion from DexRecordImage component."""
    if not is_instance_valid(self) or not _is_active:
        return

    if success:
        _set_load_state(LoadState.LOADED)
        _current_ratio = record_image.ratio
        _apply_scale()
    else:
        _set_load_state(LoadState.FAILED)
```

#### 1.6 Update deactivate() to reset state

```gdscript
func deactivate() -> void:
    """Deactivate and hide this image (returns to pool)."""
    _is_active = false
    _creation_index = -1
    _user_id = "self"
    _current_ratio = 1.0
    _image_load_state = LoadState.IDLE  # Reset load state
    visible = false

    if record_image:
        record_image.clear_texture()
```

#### 1.7 Add helper methods

```gdscript
func is_on_screen() -> bool:
    """Check if currently visible on screen (via notifier)."""
    if _visibility_notifier:
        return _visibility_notifier.is_on_screen()
    return false

func is_loading() -> bool:
    """Check if currently loading."""
    return _image_load_state == LoadState.LOADING

func is_loaded() -> bool:
    """Check if image is loaded."""
    return _image_load_state == LoadState.LOADED

func is_queued() -> bool:
    """Check if waiting in queue."""
    return _image_load_state == LoadState.QUEUED

func get_load_state() -> int:
    """Get current load state."""
    return _image_load_state

# Expose LoadState enum for external use
static func get_load_state_idle() -> int:
    return LoadState.IDLE

static func get_load_state_queued() -> int:
    return LoadState.QUEUED

static func get_load_state_loading() -> int:
    return LoadState.LOADING

static func get_load_state_loaded() -> int:
    return LoadState.LOADED
```

---

### Phase 2: Throttle Visibility Updates in TreeRenderer

**Goal:** Reduce per-frame work by only recalculating visibility when the view changes significantly.

#### 2.1 Add throttling state variables

**File:** `features/tree/tree_renderer.gd`

**Add after line 120 (_viewport_size):**

```gdscript
# Visibility throttling
var _visibility_dirty: bool = false
var _last_view_rect: Rect2 = Rect2()
const VIEW_CHANGE_THRESHOLD: float = 50.0  # World units - minimum change to trigger update
const MIN_UPDATE_INTERVAL: float = 0.05    # 50ms minimum between updates (20 FPS cap on updates)
var _last_update_time: float = 0.0
```

#### 2.2 Modify update_view() to use dirty flag

**Replace existing `update_view()` function:**

```gdscript
func update_view(scroll: Vector2, scale: float, center: Vector2) -> void:
    """Update view parameters (called when transform changes).
    Uses dirty flag to throttle visibility recalculation."""
    var old_scale = _current_scale
    _scroll_offset = scroll
    _current_scale = scale
    _viewport_center = center
    _viewport_size = get_viewport_rect().size

    if not tree_data:
        return

    var new_rect := _get_view_rect()

    # Check if view changed enough to warrant update
    var scale_changed := abs(scale - old_scale) > 0.01
    var position_changed := _rect_moved_significantly(new_rect, _last_view_rect)

    if scale_changed or position_changed:
        _visibility_dirty = true
        _last_view_rect = new_rect

func _rect_moved_significantly(new_rect: Rect2, old_rect: Rect2) -> bool:
    """Check if the view rect moved enough to warrant a visibility update."""
    if old_rect.size == Vector2.ZERO:
        return true  # First update

    # Check if center moved more than threshold (in world units)
    var old_center := old_rect.position + old_rect.size / 2.0
    var new_center := new_rect.position + new_rect.size / 2.0

    return old_center.distance_to(new_center) > VIEW_CHANGE_THRESHOLD
```

#### 2.3 Add _process() for deferred updates

**Add new function after update_view():**

```gdscript
func _process(delta: float) -> void:
    """Process deferred visibility updates and image loading queue."""
    if Engine.is_editor_hint():
        return

    if not tree_data:
        return

    # Throttle updates by time
    var current_time := Time.get_ticks_msec() / 1000.0
    if _visibility_dirty and (current_time - _last_update_time) >= MIN_UPDATE_INTERVAL:
        _visibility_dirty = false
        _last_update_time = current_time

        _update_visible_nodes()
        _update_dex_images()
        _update_multimesh()
        _render_radial_edges()
        _render_taxonomy_labels()

    # Process loading queue (Phase 3)
    _process_loading_queue()
```

#### 2.4 Remove direct calls from update_view

**Remove these lines from update_view() (they're now in _process()):**

```gdscript
# REMOVE these lines from update_view():
# _update_visible_nodes()
# _update_dex_images()
# _update_multimesh()
# if view_changed:
#     _render_radial_edges()
# _render_taxonomy_labels()
```

---

### Phase 3: Lazy Image Loading with Frame-Budget Queue

**Goal:** Spread image loading across frames to prevent spikes.

#### 3.1 Add loading queue state

**File:** `features/tree/tree_renderer.gd`

**Add after visibility throttling variables:**

```gdscript
# Image loading queue (lazy loading)
var _pending_loads: Array[String] = []  # Queue of image_keys waiting to load
var _loading_in_progress: Dictionary = {}  # {image_key: true} - currently loading
const IMAGES_PER_FRAME: int = 2  # Maximum images to start loading per frame
const MAX_CONCURRENT_LOADS: int = 4  # Maximum simultaneous HTTP requests
```

#### 3.2 Modify _update_dex_images() to queue instead of load

**Replace the image activation section in `_update_dex_images()`:**

```gdscript
func _update_dex_images() -> void:
    """Update dex images for visible animal nodes captured by user or friends.
    Queues image loads instead of loading immediately for better performance."""
    if not dex_images_container:
        return

    # Collect all visible captures (unchanged from current implementation)
    var visible_captures: Dictionary = {}

    for render_data in visible_nodes:
        var node = render_data.node
        if not node.is_animal():
            continue

        # User's own capture
        if node.captured_by_user and node.creation_index > 0:
            var image_key := "self:%d" % node.creation_index
            visible_captures[image_key] = {
                "render_data": render_data,
                "user_id": "self",
                "creation_index": node.creation_index,
                "capture_info": {}
            }

        # Friend captures
        if node.captured_by_friends.size() > 0 and not node.captured_by_user:
            var friend_capture: Dictionary = node.captured_by_friends[0]
            var friend_id: String = friend_capture.get("user_id", "")
            if not friend_id.is_empty():
                var image_key := "%s:%s" % [friend_id, node.id]
                visible_captures[image_key] = {
                    "render_data": render_data,
                    "user_id": friend_id,
                    "creation_index": -1,
                    "capture_info": friend_capture
                }

    # Deactivate images no longer visible
    var to_deactivate: Array[String] = []
    for image_key in active_dex_images:
        if not visible_captures.has(image_key):
            to_deactivate.append(image_key)

    for key in to_deactivate:
        var img: TreeDexImage = active_dex_images[key]
        img.deactivate()
        active_dex_images.erase(key)
        # Remove from queues
        _pending_loads.erase(key)
        _loading_in_progress.erase(key)

    # Rebuild nodes_with_dex_images
    nodes_with_dex_images.clear()

    # Track newly visible captures to queue
    var newly_visible: Array[String] = []

    for image_key in visible_captures:
        var capture_data: Dictionary = visible_captures[image_key]
        var render_data = capture_data.render_data
        var user_id: String = capture_data.user_id
        var creation_index: int = capture_data.creation_index
        var node = render_data.node

        nodes_with_dex_images[node.id] = true

        var image_position: Vector2 = _get_extended_position(node)

        if active_dex_images.has(image_key):
            # Already active, just update position
            var img: TreeDexImage = active_dex_images[image_key]
            img.position = image_position
        else:
            # NEW: Activate but don't load - add to queue
            var entry_data = _get_dex_entry_data(creation_index, user_id, node, capture_data.capture_info)

            var img = _get_available_dex_image()
            if not img:
                continue  # Pool exhausted

            # Activate WITHOUT loading
            img.activate(image_position, creation_index, user_id, entry_data, DEX_IMAGE_SIZE)
            active_dex_images[image_key] = img

            # Queue for loading (if not already queued or loading)
            if not _pending_loads.has(image_key) and not _loading_in_progress.has(image_key):
                newly_visible.append(image_key)

    # Add newly visible to queue, prioritized by distance to viewport center
    _queue_images_by_priority(newly_visible, visible_captures)
```

#### 3.3 Add prioritization helper

```gdscript
func _queue_images_by_priority(image_keys: Array[String], capture_data: Dictionary) -> void:
    """Add images to loading queue, prioritized by distance to viewport center."""
    if image_keys.is_empty():
        return

    # Calculate priority scores (lower = higher priority)
    var scored_keys: Array = []
    var viewport_center := _scroll_offset  # World position at center of view

    for key in image_keys:
        if not capture_data.has(key):
            continue
        var data: Dictionary = capture_data[key]
        var render_data = data.render_data
        var distance := render_data.position.distance_to(viewport_center)
        scored_keys.append({"key": key, "distance": distance})

    # Sort by distance (closest first)
    scored_keys.sort_custom(func(a, b): return a.distance < b.distance)

    # Add to queue in priority order
    for item in scored_keys:
        _pending_loads.append(item.key)
```

#### 3.4 Add queue processing

```gdscript
func _process_loading_queue() -> void:
    """Process the image loading queue with frame budget."""
    if _pending_loads.is_empty():
        return

    # Don't exceed concurrent load limit
    if _loading_in_progress.size() >= MAX_CONCURRENT_LOADS:
        return

    var loads_this_frame := 0
    var available_slots := MAX_CONCURRENT_LOADS - _loading_in_progress.size()
    var max_loads := mini(IMAGES_PER_FRAME, available_slots)

    while _pending_loads.size() > 0 and loads_this_frame < max_loads:
        var image_key: String = _pending_loads.pop_front()

        # Verify still active
        if not active_dex_images.has(image_key):
            continue

        var img: TreeDexImage = active_dex_images[image_key]

        # Skip if already loading or loaded
        if img.is_loading() or img.is_loaded():
            continue

        # Start load
        _loading_in_progress[image_key] = true
        img.load_state_changed.connect(_on_image_load_state_changed.bind(image_key))
        img.start_load()
        loads_this_frame += 1

func _on_image_load_state_changed(new_state: int, image_key: String) -> void:
    """Handle load state changes from TreeDexImage."""
    # Remove from in-progress when no longer loading
    if new_state != TreeDexImage.LoadState.LOADING:
        _loading_in_progress.erase(image_key)

    # Disconnect signal to avoid memory leaks
    if active_dex_images.has(image_key):
        var img: TreeDexImage = active_dex_images[image_key]
        if img.load_state_changed.is_connected(_on_image_load_state_changed):
            img.load_state_changed.disconnect(_on_image_load_state_changed)
```

#### 3.5 Clean up queues on clear()

**Add to existing `clear()` function:**

```gdscript
func clear() -> void:
    """Clear all rendered content."""
    # ... existing code ...

    # Clear loading queues
    _pending_loads.clear()
    _loading_in_progress.clear()
    _visibility_dirty = false
    _last_view_rect = Rect2()
```

---

### Phase 4: Update render_tree() for New Flow

**Modify `render_tree()` to work with new system:**

```gdscript
func render_tree(data: TreeDataModels.TreeData) -> void:
    """Render the complete tree data."""
    if not data:
        push_error("[TreeRenderer] No tree data provided")
        return

    print("[TreeRenderer] Rendering tree with %d nodes" % data.nodes.size())
    tree_data = data

    # Clear previous state
    render_nodes.clear()
    visible_nodes.clear()
    nodes_by_position.clear()
    _deactivate_all_dex_images()
    _pending_loads.clear()
    _loading_in_progress.clear()

    # Build render data for all nodes
    for node in data.nodes:
        var render_data = NodeRenderData.new(node)
        render_data.color = _get_node_color(node)
        render_data.scale = _get_node_scale(node)
        render_nodes.append(render_data)

        var grid_key = _get_grid_key(node.position)
        if not nodes_by_position.has(grid_key):
            nodes_by_position[grid_key] = []
        nodes_by_position[grid_key].append(render_data)

    print("[TreeRenderer] Built render data for %d nodes" % render_nodes.size())

    _calculate_extended_positions()
    _calculate_label_positions()

    # Initial visibility update (will queue image loads)
    _last_view_rect = _get_view_rect()
    _update_visible_nodes()
    _update_dex_images()
    _update_multimesh()
    _render_radial_edges()
    _render_taxonomy_labels()

    print("[TreeRenderer] Tree rendering complete, %d images queued" % _pending_loads.size())
```

---

## Testing Plan

### Unit Tests

1. **VisibleOnScreenNotifier2D rect accuracy**
   - Verify rect updates when size changes
   - Verify preload margin is applied correctly
   - Test with different aspect ratios

2. **Load state transitions**
   - IDLE → QUEUED → LOADING → LOADED
   - IDLE → QUEUED → (deactivated) → IDLE
   - LOADING → FAILED

3. **Queue prioritization**
   - Images closest to center should load first
   - Deactivated images should be removed from queue

### Integration Tests

1. **Scrolling performance**
   - Pan across tree with 100+ visible images
   - Measure frame time variance (should be < 16ms)
   - Verify no frame spikes > 33ms

2. **Rapid zoom**
   - Zoom in/out quickly
   - Verify queued images are correctly cancelled when deactivated
   - Verify no memory leaks from orphaned loads

3. **Web export**
   - Test with single-threaded export
   - Verify < 1000 visible CanvasItems at any time
   - Test on iOS Safari via Cloudflare Tunnel

### Performance Metrics

| Metric | Current | Target | Method |
|--------|---------|--------|--------|
| Frame time during scroll | TBD | < 16ms | `Engine.get_frames_per_second()` |
| Images loaded per second | TBD | 10-20 | Custom counter |
| Peak concurrent loads | TBD | 4 | `_loading_in_progress.size()` |
| Preload hit rate | TBD | > 80% | Track loads vs already-loaded |

---

## Migration Checklist

### Pre-Implementation

- [ ] Create feature branch: `feature/tree-culling-optimization`
- [ ] Back up current tree_dex_image.gd and tree_renderer.gd
- [ ] Add performance logging to current implementation for baseline

### Phase 1: TreeDexImage Changes

- [ ] Add LoadState enum
- [ ] Add visibility_entered/exited signals
- [ ] Add load_state_changed signal
- [ ] Create _setup_visibility_notifier()
- [ ] Modify activate() to not auto-load
- [ ] Add start_load() method
- [ ] Update _on_image_loaded() for state tracking
- [ ] Update deactivate() to reset state
- [ ] Add helper methods (is_loaded, is_queued, etc.)
- [ ] Test: Single image visibility detection works

### Phase 2: Visibility Throttling

- [ ] Add throttling state variables
- [ ] Modify update_view() to use dirty flag
- [ ] Add _rect_moved_significantly()
- [ ] Add _process() for deferred updates
- [ ] Remove direct update calls from update_view()
- [ ] Test: Visibility updates are throttled correctly

### Phase 3: Loading Queue

- [ ] Add queue state variables
- [ ] Modify _update_dex_images() to queue loads
- [ ] Add _queue_images_by_priority()
- [ ] Add _process_loading_queue()
- [ ] Add _on_image_load_state_changed()
- [ ] Update clear() to clean queues
- [ ] Test: Images load in priority order

### Phase 4: Integration

- [ ] Update render_tree() for new flow
- [ ] Run full integration tests
- [ ] Performance profiling
- [ ] Web export testing

### Post-Implementation

- [ ] Remove debug logging
- [ ] Update CLAUDE.md with new architecture
- [ ] Code review
- [ ] Merge to main

---

## Configuration Constants Summary

| Constant | Location | Value | Purpose |
|----------|----------|-------|---------|
| `PRELOAD_MARGIN` | TreeDexImage | 500.0 | World units to extend visibility rect for preloading |
| `VIEW_CHANGE_THRESHOLD` | TreeRenderer | 50.0 | World units - minimum movement to trigger update |
| `MIN_UPDATE_INTERVAL` | TreeRenderer | 0.05 | Seconds - minimum time between visibility updates |
| `IMAGES_PER_FRAME` | TreeRenderer | 2 | Maximum new image loads to start per frame |
| `MAX_CONCURRENT_LOADS` | TreeRenderer | 4 | Maximum simultaneous HTTP requests |
| `DEX_IMAGE_POOL_SIZE` | TreeRenderer | 100 | Size of pre-allocated image pool |

---

## Future Considerations

### Priority 5 Note: VisibleOnScreenEnabler2D for Process Disabling

If performance issues persist after implementing the above optimizations, consider using `VisibleOnScreenEnabler2D` instead of `VisibleOnScreenNotifier2D`. This would automatically disable `process_mode` on TreeDexImage nodes when off-screen.

**Caveat:** There are known issues with `process_mode` toggling causing problems with Area2D and some Control nodes. The DexRecordImage component contains multiple Controls, so thorough testing would be required.

**Implementation would look like:**

```gdscript
# In TreeDexImage._setup_visibility_notifier():
var enabler := VisibleOnScreenEnabler2D.new()
enabler.rect = Rect2(...)
enabler.enable_node_path = NodePath(".")  # This node
enabler.enable_mode = VisibleOnScreenEnabler2D.ENABLE_MODE_INHERIT
add_child(enabler)
```

**Only pursue this if:**
1. Profiling shows `_process()` overhead in TreeDexImage is significant
2. The current optimizations don't achieve < 16ms frame times
3. Thorough testing confirms no issues with the Control hierarchy

---

## References

- [VisibleOnScreenNotifier2D Docs](https://docs.godotengine.org/en/stable/classes/class_visibleonscreennotifier2d.html)
- [ResourceLoader Threaded Loading](https://docs.godotengine.org/en/stable/classes/class_resourceloader.html)
- [GameDev Academy - ResourceLoader Guide](https://gamedevacademy.org/resourceloader-in-godot-complete-guide/)
- [Godot Forum - Batching in Godot 4](https://forum.godotengine.org/t/understanding-batching-in-godot-4/65635)
- [Web Export in 4.3](https://godotengine.org/article/progress-report-web-export-in-4-3/)
