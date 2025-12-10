# Godot 4 Native 2D Culling Research

## Context

The tree_camera scene uses Camera2D for synchronized background/foreground rendering. During scrolling, noticeable lag occurs when DexRecordImage nodes are loaded. This research investigates native Godot culling solutions to offload visibility management to the engine.

---

## Current Implementation Analysis

### Tree Renderer (`tree_renderer.gd`)
- **Manual frustum culling**: `_update_visible_nodes()` checks if each node's position is within `_get_view_rect()`
- **Dex image pool**: 100 pre-instantiated `TreeDexImage` nodes, recycled as user scrolls
- **View rect calculation**: `CULL_MARGIN_SCREEN` (200px screen-space) converted to world-space
- **Update trigger**: `update_view()` called on every `view_changed` signal from camera controller

### Bottleneck Identification
The lag likely comes from:
1. **Image loading** during `activate()` → triggers HTTP/disk I/O
2. **Per-frame visibility recalculation** for all 50,000+ potential nodes
3. **Node instantiation overhead** even with pooling (DexRecordImage contains a scene tree)

---

## Godot 4 Native Culling Options

### 1. VisibleOnScreenNotifier2D / VisibleOnScreenEnabler2D

**How it works:**
- `VisibleOnScreenNotifier2D`: Emits `screen_entered`/`screen_exited` signals when its `rect` intersects the viewport
- `VisibleOnScreenEnabler2D`: Extends Notifier, automatically sets target node's `process_mode` to `PROCESS_MODE_DISABLED` when off-screen

**Key Properties:**
- `rect: Rect2` - The detection area (default: centered at node origin)
- `enable_mode` - How target is enabled: `ENABLE_MODE_INHERIT`, `ENABLE_MODE_ALWAYS`, `ENABLE_MODE_WHEN_PAUSED`
- `enable_node_path: NodePath` - Target node to enable/disable

**Camera2D Compatibility:**
These nodes work with Camera2D automatically - they use the viewport's canvas transform, which Camera2D modifies.

**Pros:**
- Native engine implementation (faster than GDScript checks)
- Automatic signal-based notifications
- Works with Camera2D out of the box
- Can disable processing, not just rendering

**Cons:**
- One node per monitored object (overhead for thousands of items)
- Rect is local to the node (doesn't account for parent transforms well)
- Known issues with `process_mode` when transitioning back to enabled state
- **Web export issue**: There's a bug where 1000+ visible objects can blank the screen in single-threaded web exports

**Sources:**
- [VisibleOnScreenEnabler2D Docs](https://docs.godotengine.org/en/stable/classes/class_visibleonscreenenabler2d.html)
- [VisibleOnScreenNotifier2D Docs](https://docs.godotengine.org/en/stable/classes/class_visibleonscreennotifier2d.html)
- [GitHub Issue #88192 - 1000 object limit in web exports](https://github.com/godotengine/godot/issues/88192)

---

### 2. Automatic CanvasItem Culling (Built-in)

**How it works:**
Godot automatically culls CanvasItems (Sprite2D, Node2D with draw calls, etc.) that are outside the viewport. The engine calculates each item's bounding rect and skips rendering if it doesn't intersect the view.

**Key Points:**
- **Rendering only** - `_process()` and `_physics_process()` still run
- **Automatic for all CanvasItems** - No setup required
- Works correctly with Camera2D transforms
- Culling is based on the item's draw commands, not its position

**Custom Rect Override:**
```gdscript
# Override automatic culling rect (useful for shaders that modify vertex positions)
RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), true, my_rect)
```

**When to use custom rect:**
- Vertex shaders that move geometry outside original bounds
- Particles that extend beyond emitter
- Effects that draw outside the node's natural bounds

**Pros:**
- Zero overhead for basic use
- Handles Camera2D transforms automatically
- No per-node setup needed

**Cons:**
- Only affects rendering, not processing (scripts still run)
- Custom rect requires RenderingServer calls
- Bounding rect is recalculated per frame for animated items

**Sources:**
- [CanvasItem Docs](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html)
- [GitHub Issue #34432 - Shader vertex visibility](https://github.com/godotengine/godot/issues/34432)
- [GitHub Proposal #7553 - Custom Rect property](https://github.com/godotengine/godot-proposals/issues/7553)

---

### 3. Node Visibility (`visible` property)

**How it works:**
Setting `node.visible = false` or calling `node.hide()` prevents the node and all children from being rendered.

**Critical Limitation:**
- **Does NOT disable `_process()` or `_physics_process()`**
- Hidden nodes still receive input events (`_unhandled_input()`)
- Only affects rendering, not game logic

**For full disable, combine with process control:**
```gdscript
func disable_offscreen():
    visible = false
    set_process(false)
    set_physics_process(false)

func enable_onscreen():
    visible = true
    set_process(true)
    set_physics_process(true)
```

**Or use `process_mode`:**
```gdscript
# Disable all processing
process_mode = Node.PROCESS_MODE_DISABLED

# Re-enable (inherit from parent)
process_mode = Node.PROCESS_MODE_INHERIT
```

**Sources:**
- [Godot Forum - hide()/show() vs process_mode](https://forum.godotengine.org/t/should-i-use-hide-show-and-or-process-mode-to-stop-node/106673)
- [GDQuest - VisibilityNotifier Tutorial](https://www.gdquest.com/tutorial/godot/2d/visibility-notifier-2d/)

---

### 4. Camera2D Frustum Check (Manual)

**For 2D, calculate visible rect from Camera2D:**
```gdscript
func get_visible_rect() -> Rect2:
    var viewport_size := get_viewport().get_visible_rect().size
    var zoom := camera.zoom.x  # Assuming uniform zoom
    var cam_pos := camera.global_position
    var half_size := viewport_size / (2.0 * zoom)
    return Rect2(cam_pos - half_size, half_size * 2.0)

func is_position_visible(world_pos: Vector2) -> bool:
    return get_visible_rect().has_point(world_pos)
```

**For bounding boxes:**
```gdscript
func is_rect_visible(world_rect: Rect2) -> bool:
    return get_visible_rect().intersects(world_rect)
```

**Pros:**
- Full control over culling logic
- Can add margins for preloading
- Works with any node type

**Cons:**
- Manual implementation (more code)
- Must be called appropriately (not per-frame for all objects)
- Your current implementation already does this

**Sources:**
- [Godot Forum - Camera2D visible rect](https://forum.godotengine.org/t/is-there-a-way-to-get-the-rect2-of-the-camera-instead-of-the-viewport/7456)
- [Golden Tamarin - Off-Screen Processing Control](https://www.golden-tamarin.com/2024/10/10/godot-off-screen-processing-control/)

---

### 5. MultiMesh and Batching

**Current Usage:**
Your `tree_renderer.gd` already uses `MultiMeshInstance2D` for taxonomy nodes - this is excellent.

**Batching Rules (Godot 4):**
Items batch together when they share:
- Same mesh resource
- Same material
- Same blend mode
- Same shader
- Same texture atlas

**What breaks batching:**
- Different textures (unless atlased)
- Different materials
- Different modulate colors (significant performance drop)
- Z-index changes
- Scene layer changes

**For DexRecordImages:**
Each DexRecordImage has a unique texture (the animal photo), so they **cannot batch**. This is expected.

**Sources:**
- [Godot Batching Docs (3.5, concepts apply)](https://docs.godotengine.org/en/3.5/tutorials/performance/batching.html)
- [Godot Forum - Understanding Batching in Godot 4](https://forum.godotengine.org/t/understanding-batching-in-godot-4/65635)
- [Godot 4.4 Beta - CanvasItem shader instance uniforms](https://godotengine.org/article/dev-snapshot-godot-4-4-beta-1/)

---

## Web Export Compatibility

### Critical Issues

1. **1000 Object Culling Bug** (Single-threaded builds)
   - Running 1000+ visible objects blanks the screen
   - Bug in threaded culling incorrectly used in single-threaded mode
   - Status: Fixed in Godot 4.3+
   - **Source**: [GitHub Issue #88192](https://github.com/godotengine/godot/issues/88192)

2. **GPUParticles2D Trails Not Rendered**
   - Single-threaded web exports don't render particle trails
   - **Source**: [GitHub Issue #88748](https://github.com/godotengine/godot/issues/88748)

3. **Audio Garbling in Single-Threaded Mode**
   - Low frame rates cause audio buffer underruns
   - **Source**: [Godot Web Export 4.3 Article](https://godotengine.org/article/progress-report-web-export-in-4-3/)

### Web Export Recommendations

- Use Godot 4.3+ for fixed single-threaded culling
- Test with 500-800 visible nodes to stay under historical limits
- Prefer single-threaded mode for iOS Safari compatibility
- Compatibility renderer is mandatory for web (WebGL 2.0)

---

## Recommended Optimizations for Tree Scene

### Priority 1: Reduce Node Count in Tree

**Problem:** Current architecture creates 100 `TreeDexImage` nodes, each containing a `DexRecordImage` scene with multiple Controls.

**Solution: Consider CanvasItem direct drawing**
Instead of instantiating scene trees, draw directly using `_draw()`:
```gdscript
class_name TreeDexImageDirect
extends Node2D

var texture: Texture2D
var label_text: String

func _draw() -> void:
    if texture:
        var rect := Rect2(-size/2, size)
        draw_texture_rect(texture, rect, false)
        # Draw border, label, etc.
```

**Benefit:** ~5-10x fewer nodes in tree, faster visibility checks.

---

### Priority 2: Use VisibleOnScreenNotifier2D for Image Loading

**Approach:**
Add `VisibleOnScreenNotifier2D` to each `TreeDexImage` with a larger rect (for preloading):

```gdscript
# In TreeDexImage
func _ready() -> void:
    var notifier := VisibleOnScreenNotifier2D.new()
    notifier.rect = Rect2(-size/2 - preload_margin, size + preload_margin*2)
    notifier.screen_entered.connect(_on_screen_entered)
    notifier.screen_exited.connect(_on_screen_exited)
    add_child(notifier)

func _on_screen_entered() -> void:
    if not _image_loaded:
        load_image_from_entry()

func _on_screen_exited() -> void:
    # Optionally unload texture to free memory
    pass
```

**Benefit:**
- Engine handles visibility detection (faster than GDScript loop)
- Can preload images before they're fully visible
- Pairs well with pooling

---

### Priority 3: Throttle Visibility Updates

**Problem:** `update_view()` is called on every camera movement, recalculating visibility for all nodes.

**Solution: Debounce or spatial chunking**

```gdscript
var _visibility_dirty: bool = false
var _last_view_rect: Rect2

func update_view(scroll: Vector2, scale: float, center: Vector2) -> void:
    _scroll_offset = scroll
    _current_scale = scale
    _viewport_center = center

    var new_rect := _get_view_rect()
    # Only recalculate if view changed significantly
    if not _rects_similar(new_rect, _last_view_rect):
        _visibility_dirty = true
        _last_view_rect = new_rect

func _process(_delta: float) -> void:
    if _visibility_dirty:
        _update_visible_nodes()
        _update_dex_images()
        _visibility_dirty = false
```

---

### Priority 4: Lazy Image Loading with Intersection Observer Pattern

**Approach:**
Don't load images immediately when they become visible. Instead:
1. Mark node as "pending load"
2. Load N images per frame (e.g., 2-3)
3. Prioritize images closest to viewport center

```gdscript
var pending_image_loads: Array = []
const IMAGES_PER_FRAME: int = 3

func _update_dex_images() -> void:
    # ... existing visibility logic ...

    # Queue new visible images instead of loading immediately
    for image_key in newly_visible:
        pending_image_loads.append(image_key)

func _process(_delta: float) -> void:
    var loaded_this_frame := 0
    while pending_image_loads.size() > 0 and loaded_this_frame < IMAGES_PER_FRAME:
        var key = pending_image_loads.pop_front()
        _start_image_load(key)
        loaded_this_frame += 1
```

**Benefit:** Prevents frame spikes from multiple simultaneous image loads.

---

### Priority 5: Consider VisibleOnScreenEnabler2D for Process Disabling

**For DexImages that have complex scripts:**
```gdscript
# In tree_dex_image.gd
func _setup_enabler() -> void:
    var enabler := VisibleOnScreenEnabler2D.new()
    enabler.rect = Rect2(-target_size/2, Vector2(target_size, target_size))
    enabler.enable_node_path = NodePath(".")  # This node
    enabler.enable_mode = VisibleOnScreenEnabler2D.ENABLE_MODE_INHERIT
    add_child(enabler)
```

**Caveat:** `process_mode` toggling has known issues with Area2D - test thoroughly.

---

## Summary Table

| Technique | Rendering Culling | Process Culling | Setup Overhead | Web Compatible |
|-----------|------------------|-----------------|----------------|----------------|
| Automatic CanvasItem | Yes | No | None | Yes |
| VisibleOnScreenNotifier2D | Via signals | No | 1 node/object | Yes (with limits) |
| VisibleOnScreenEnabler2D | Via signals | Yes | 1 node/object | Yes (with limits) |
| Manual frustum check | Yes | Via code | Script overhead | Yes |
| `visible = false` | Yes | No | None | Yes |
| `process_mode` | No | Yes | None | Yes |
| MultiMesh | N/A (batch all) | N/A | Setup once | Yes |

---

## Recommended Implementation Order

1. **Throttle visibility updates** - Quick win, reduces per-frame work
2. **Lazy image loading** - Spreads I/O across frames, smooths performance
3. **Add VisibleOnScreenNotifier2D** - For preload triggering
4. **Consider direct drawing** - Longer term, reduces node overhead significantly
5. **Test web export at scale** - Verify 1000 object limit is fixed in your Godot version

---

## References

### Official Documentation
- [VisibleOnScreenEnabler2D](https://docs.godotengine.org/en/stable/classes/class_visibleonscreenenabler2d.html)
- [VisibleOnScreenNotifier2D](https://docs.godotengine.org/en/stable/classes/class_visibleonscreennotifier2d.html)
- [RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html)
- [CanvasItem](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html)
- [Camera2D](https://docs.godotengine.org/en/stable/classes/class_camera2d.html)
- [General Optimization Tips](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
- [CPU Optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html)

### Godot Blog/Articles
- [Web Export in 4.3](https://godotengine.org/article/progress-report-web-export-in-4-3/)
- [Godot 4.4 Beta 1 - Batching improvements](https://godotengine.org/article/dev-snapshot-godot-4-4-beta-1/)

### GitHub Issues
- [#88192 - 1000 object culling bug](https://github.com/godotengine/godot/issues/88192)
- [#88748 - GPUParticles2D trails on web](https://github.com/godotengine/godot/issues/88748)
- [#34432 - Shader vertex visibility](https://github.com/godotengine/godot/issues/34432)
- [#7553 - Custom Rect proposal](https://github.com/godotengine/godot-proposals/issues/7553)
- [#9069 - VisibleOnScreenEnabler disable request](https://github.com/godotengine/godot-proposals/issues/9069)

### Forum/Community
- [Understanding Batching in Godot 4](https://forum.godotengine.org/t/understanding-batching-in-godot-4/65635)
- [hide()/show() vs process_mode](https://forum.godotengine.org/t/should-i-use-hide-show-and-or-process-mode-to-stop-node/106673)
- [Camera2D visible rect](https://forum.godotengine.org/t/is-there-a-way-to-get-the-rect2-of-the-camera-instead-of-the-viewport/7456)
- [Disabling culling for shaders](https://forum.godotengine.org/t/how-to-disable-culling-when-canvasitem-goes-out-of-screen/73888)

### Tutorials
- [GDQuest - VisibilityNotifier Tutorial](https://www.gdquest.com/tutorial/godot/2d/visibility-notifier-2d/)
- [Golden Tamarin - Off-Screen Processing Control](https://www.golden-tamarin.com/2024/10/10/godot-off-screen-processing-control/)
- [Howik - Optimizing 2D Performance](https://howik.com/optimizing-2d-performance-in-godot)
- [GameDev Academy - AtlasTexture Guide](https://gamedevacademy.org/atlastexture-in-godot-complete-guide/)
