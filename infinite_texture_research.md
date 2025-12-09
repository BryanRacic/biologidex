# Infinite Texture Background Research & Audit

**Date**: 2025-12-09 (Updated)
**Status**: ✅ SOLVED - See "Working Solution" section below
**Goal**: Synchronize shader-based paper/grid background with UI elements during pan/zoom operations

---

## Working Solution (2025-12-09)

The Camera2D approach works! Implementation in `scenes/tree_camera/`.

### Key Insights

1. **Use Camera2D as single source of truth** - Don't manually apply Transform2D to tree graph
2. **Background MUST be Node2D-based** - `ColorRect` is a Control and won't transform with Camera2D. Use `Polygon2D` instead.
3. **Shader is simple** - No `skip_vertex_transform` needed. Just compute world coords in vertex shader:
   ```glsl
   void vertex() {
       vec4 world_pos = MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0);
       world_coord = world_pos.xy;
       // Let Godot handle VERTEX transformation
   }
   ```
4. **Everything in world space** - Camera2D transforms all Node2D children uniformly. No manual coordinate conversion.

### Working Architecture

```
TreeCamera (Node2D)
├── Camera2D (enabled=true) ← Controls view
│   └── CameraController ← Pan/zoom input handling
├── WorldContent (Node2D) ← Camera transforms this
│   ├── PaperBackground (Polygon2D + shader) ← Node2D, NOT Control!
│   └── TreeGraph (Node2D)
│       └── ... layers
└── UILayer (CanvasLayer, layer=10) ← Fixed UI
```

### Why Previous Approach Failed

- Background was in separate `CanvasLayer` with isolated coordinate space
- Manual uniform passing (`scroll`, `scale`) to shader didn't perfectly match Transform2D math
- `ColorRect` (Control node) wasn't affected by Camera2D transforms

---

## Problem Statement (Historical)

The app displays UI elements (especially on the tree & dex feed) as if they're pictures, drawings, and text on realistic paper. Panning & zooming should move the grid, paper texture, and UI elements at the same speed, zoom, and with the same momentum. However, since the grid & paper texture are in shader code and the UI elements have their own interactive logic, there's a disconnect between the speed & amount of movement that breaks the illusion (especially noticeable the farther zoomed out you are).

---

## Current Implementation Analysis

### Architecture

```
Tree (Node2D)
├── BackgroundLayer (CanvasLayer, layer=-1)
│   └── InteractiveBackground (Control)
│       ├── Background (ColorRect + paper.gdshader)
│       └── TouchController (BackgroundTouchController)
├── TreeGraph (Node2D) ← Transform2D applied here
│   ├── EdgesLayer
│   ├── NodesLayer
│   └── ...
└── UILayer (CanvasLayer, layer=10)
```

**Key issue**: The shader (in BackgroundLayer) and UI elements (in TreeGraph) are in **separate CanvasLayers** with **independent transforms**.

### 1. Paper Shader (`client/biologidex-client/shaders/paper.gdshader`)

```glsl
uniform vec2 scroll = vec2(0.0);
uniform float scale = 1.0;
uniform vec2 viewport_size = vec2(1280.0, 720.0);

void fragment() {
    // Convert screen coordinates to world coordinates
    vec2 px = (FRAGCOORD.xy - viewport_size / 2.0) / scale + scroll;
    // ... rest uses px for grid, noise, etc.
}
```

### 2. Tree Controller (`scenes/tree/tree_controller.gd`)

```gdscript
func _update_tree_transform() -> void:
    var transform = Transform2D()
    transform = transform.scaled(Vector2(_current_scale, _current_scale))
    transform.origin = _viewport_center - _scroll_offset * _current_scale
    tree_graph.transform = transform
```

### 3. Mathematical Analysis

**TreeGraph transform**: `screen_pos = world_pos * scale + (viewport_center - scroll_offset * scale)`

Solving for world_pos:
```
screen_pos - viewport_center = (world_pos - scroll_offset) * scale
world_pos = (screen_pos - viewport_center) / scale + scroll_offset
```

**Shader formula**: `world_pos = (FRAGCOORD.xy - viewport_size / 2.0) / scale + scroll`

Where `viewport_size / 2.0 = viewport_center` and `scroll = scroll_offset`.

**These are mathematically identical!** The drift must come from somewhere else.

### 4. Potential Causes of Drift

1. **CanvasLayer isolation**: The shader's ColorRect is in a CanvasLayer with `layer=-1`. CanvasLayers have their own coordinate space and don't inherit parent transforms.

2. **FRAGCOORD origin**: FRAGCOORD.xy is in **window/viewport space**, starting from (0,0) at top-left. If the CanvasLayer has any offset, this could cause misalignment.

3. **Timing/sync issues**: Shader uniforms and TreeGraph transform may update at different times within the same frame.

4. **Floating-point precision**: At large scroll values or extreme zoom levels, precision loss could cause drift.

---

## Researched Solutions

### Solution 1: Stack Overflow Vertex Shader Approach

**Source**: [Godot 4: Move canvas_item shader with camera](https://stackoverflow.com/questions/75666385/godot-4-move-canvas-item-shader-with-camera)

**Key insight**: Use `skip_vertex_transform` and pass world coordinates from vertex to fragment shader:

```glsl
shader_type canvas_item;
render_mode skip_vertex_transform;

varying vec2 coord;

void vertex() {
    // Get world coordinates by transforming through matrix chain
    coord = (SCREEN_MATRIX * inverse(CANVAS_MATRIX) * vec4(VERTEX, 0.0, 1.0)).xy;
    VERTEX = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    vec2 fixed_uv = -coord + TIME * velocity;
    // Use fixed_uv for texture sampling
}
```

**Still requires script** to position the ColorRect:
```gdscript
func _process(_delta: float) -> void:
    var viewport = get_viewport()
    var center := viewport.get_camera_2d().get_screen_center_position()
    var viewport_size := viewport.get_visible_rect().size
    global_position = Vector2(-viewport_size / 2.0) + center
    size = viewport_size
```

**CRITICAL LIMITATION**: This approach assumes a **Camera2D** exists. BiologiDex uses manual Transform2D on TreeGraph, not Camera2D.

**Adaptation for no Camera2D**:
```gdscript
# In InteractiveBackground or similar
func _process(_delta: float) -> void:
    var viewport_size := get_viewport_rect().size
    # scroll_offset IS our "camera center" in world space
    global_position = -viewport_size / 2.0 + scroll_offset * current_scale
    size = viewport_size
```

Wait - this changes the problem. If we move the ColorRect, FRAGCOORD changes relative to it, which is what we need!

**Pros**:
- Shader calculates world coords via matrix transforms
- Works without passing manual uniforms for displacement

**Cons**:
- Requires script to move ColorRect to follow "camera"
- `skip_vertex_transform` may affect other rendering
- The matrix chain `SCREEN_MATRIX * inverse(CANVAS_MATRIX)` may not account for our manual transform

---

### Solution 2: Parallax2D Node (Godot Built-in)

**Sources**:
- [Godot Parallax2D Documentation](https://docs.godotengine.org/en/stable/classes/class_parallax2d.html)
- [2D Parallax Tutorial](https://docs.godotengine.org/en/stable/tutorials/2d/2d_parallax.html)
- [Parallax2D Progress Report](https://godotengine.org/article/parallax-progress-report/)

**New in Godot 4.3**: Parallax2D is a single node replacing ParallaxBackground + ParallaxLayer.

**Key Properties**:
- `repeat_size`: How textures repeat (enables infinite scrolling)
- `repeat_times`: Extra repeats for zoom-out scenarios
- `scroll_scale`: How fast layer moves relative to camera (1.0 = same speed)
- `scroll_offset`: Manual scroll position
- `ignore_camera_scroll`: **Allows manual control without Camera2D**
- `follow_viewport`: Whether to track viewport/camera

**Usage for manual scrolling (no Camera2D)**:
```gdscript
# Setup
@onready var parallax: Parallax2D = $Parallax2D
parallax.ignore_camera_scroll = true
parallax.repeat_size = Vector2(texture_width, texture_height)
parallax.repeat_times = 10  # Enough for zoom out

# On scroll/zoom change
parallax.scroll_offset = scroll_offset
# Note: Parallax2D handles the scaling internally based on scroll_scale
```

**How it works**: Godot performs "visual trickery" - textures repeat and position "zips back" when scrolling too far, creating infinite scroll illusion.

**Pros**:
- Built-in Godot solution, well-tested
- Handles infinite scrolling automatically
- Works with or without Camera2D
- Inherits from Node2D (not CanvasLayer), allowing proper transform inheritance

**Cons**:
- Designed for texture-based backgrounds, not procedural shaders
- Would need to render paper texture to image first, or use a Sprite2D with shader
- May not support complex procedural effects without modification

**Hybrid approach**: Use Parallax2D as container, put a Sprite2D with shader material inside:
```
Parallax2D (handles scroll/repeat)
└── Sprite2D (with paper shader)
```

---

### Solution 3: Move Background into TreeGraph (Same Transform)

**Concept**: Instead of a separate CanvasLayer, make the background a child of TreeGraph so it receives the same Transform2D.

**New structure**:
```
Tree (Node2D)
├── TreeGraph (Node2D) ← Transform2D applied
│   ├── PaperBackground (ColorRect or large Sprite2D)
│   ├── EdgesLayer
│   ├── NodesLayer
│   └── ...
└── UILayer (CanvasLayer, layer=10)
```

**Shader changes**: Since the background now transforms with TreeGraph, the shader just needs to work in local coordinates:
```glsl
void fragment() {
    // Use UV or VERTEX directly since transform is applied by parent
    vec2 px = UV * some_scale;
    // or
    vec2 px = FRAGCOORD.xy;  // But this still needs adjustment
}
```

**Challenge**: The background needs to be **large enough** to cover the visible area at all zoom levels. At scale=0.1, you'd see 10x the world area.

**Options**:
1. Make background very large (e.g., 20000x20000)
2. Use procedural shader that tiles infinitely (current approach)
3. Dynamically resize background based on zoom level

**Pros**:
- Guarantees perfect sync (same transform)
- No coordinate conversion needed
- Simpler mental model

**Cons**:
- Requires scene restructuring
- Large background uses more memory/GPU
- May affect z-ordering and rendering order

---

### Solution 4: Fix the CanvasLayer Offset Issue

**Root cause investigation**: CanvasLayer with `layer=-1` might introduce an offset.

**CanvasLayer properties that could affect coordinates**:
- `offset`: Displacement of the layer
- `transform`: 2D transform applied to the layer
- `follow_viewport_enabled`: Whether layer follows viewport (defaults to true)
- `follow_viewport_scale`: Scale factor when following viewport

**Debugging steps**:
1. Check if CanvasLayer has any offset/transform set
2. Verify `follow_viewport_enabled` is true
3. Print shader uniforms vs TreeGraph transform values per frame
4. Test at scale=1.0 to isolate zoom-related drift from pan-related drift

**Potential fix**: Ensure CanvasLayer properties don't introduce offset:
```gdscript
# In InteractiveBackground._ready()
var canvas_layer = get_parent() as CanvasLayer
if canvas_layer:
    canvas_layer.offset = Vector2.ZERO
    canvas_layer.transform = Transform2D.IDENTITY
    canvas_layer.follow_viewport_enabled = true
    canvas_layer.follow_viewport_scale = 1.0
```

---

### Solution 5: Fake Camera2D (Recommended for Investigation)

**Concept**: Create a Camera2D that mirrors the manual transform, allowing Godot's built-in coordinate systems to work.

```gdscript
# Add a Camera2D to the tree scene
@onready var fake_camera: Camera2D = $FakeCamera

func _update_tree_transform() -> void:
    # Keep existing TreeGraph transform
    var transform = Transform2D()
    transform = transform.scaled(Vector2(_current_scale, _current_scale))
    transform.origin = _viewport_center - _scroll_offset * _current_scale
    tree_graph.transform = transform

    # Mirror to Camera2D
    fake_camera.global_position = _scroll_offset
    fake_camera.zoom = Vector2(_current_scale, _current_scale)
```

**Then** use either:
- Stack Overflow vertex shader approach (gets correct matrices)
- Parallax2D with default follow behavior
- Shader's `inverse(CANVAS_MATRIX)` will have correct values

**Pros**:
- Enables all Camera2D-dependent solutions
- Single source of truth for view state
- May simplify other features (screen shake, transitions, etc.)

**Cons**:
- Adds complexity (two systems representing same state)
- Camera2D may affect other CanvasLayer behavior

---

## Recommended Path Forward

### Immediate Debugging (Before Implementing Solutions)

1. **Verify the math is being applied correctly**:
   ```gdscript
   # Add to tree_controller.gd
   func _update_tree_transform() -> void:
       # ... existing code ...
       print("scroll_offset: %s, scale: %s, viewport_center: %s" % [_scroll_offset, _current_scale, _viewport_center])
       print("TreeGraph origin: %s" % tree_graph.transform.origin)
   ```

2. **Check shader receives correct values**:
   ```gdscript
   # In InteractiveBackground
   func _on_scroll_changed(offset: Vector2) -> void:
       _shader_material.set_shader_parameter("scroll", offset)
       print("Shader scroll: %s" % offset)
   ```

3. **Test with a known point**:
   - Place a Node2D at world (0, 0) in TreeGraph
   - Add a marker in shader at world (0, 0)
   - Pan/zoom and verify both stay aligned

### If Debugging Confirms Math Issue

Try **Solution 4** first (fix CanvasLayer offset) - minimal changes.

### If Issue is Architectural

**Recommended**: **Solution 3** (Move background into TreeGraph)
- Most architecturally sound
- Guarantees sync forever
- Aligns with "proper Godot" practices from CLAUDE.md

**Alternative**: **Solution 2** (Parallax2D) if you want to use Godot's built-in infinite scroll.

---

## Performance Considerations

| Approach | Draw Calls | GPU Cost | Sync Accuracy | Implementation Effort |
|----------|------------|----------|---------------|----------------------|
| Current (broken) | 1 | Low | Drifts | N/A |
| Solution 1 (SO vertex) | 1 | Low | Good* | Medium |
| Solution 2 (Parallax2D) | 1 | Low | Good | Medium |
| Solution 3 (Same transform) | 1 | Low | Perfect | High |
| Solution 4 (Fix CanvasLayer) | 1 | Low | Perfect | Low |
| Solution 5 (Fake Camera2D) | 1 | Low | Good | Medium |

*Depends on correct adaptation for non-Camera2D usage

---

## Sources

- [Godot 4: Move canvas_item shader with camera](https://stackoverflow.com/questions/75666385/godot-4-move-canvas-item-shader-with-camera) - Stack Overflow full solution
- [Parallax2D Documentation](https://docs.godotengine.org/en/stable/classes/class_parallax2d.html) - Official API reference
- [2D Parallax Tutorial](https://docs.godotengine.org/en/stable/tutorials/2d/2d_parallax.html) - Usage guide
- [Parallax2D Progress Report](https://godotengine.org/article/parallax-progress-report/) - Design rationale
- [Getting world coordinates in canvas_item shaders](https://forum.godotengine.org/t/get-world-space-coordinates-from-fragcoord/87463) - Forum discussion
- [World coordinate shader issues](https://github.com/godotengine/godot-docs/issues/7860) - Known documentation gap
- [CanvasItem Shader Reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html) - Official docs
- [CanvasLayer Documentation](https://docs.godotengine.org/en/stable/classes/class_canvaslayer.html) - Layer behavior

---

## Appendix: Full Stack Overflow Solution

### Shader (no script uniforms needed)
```glsl
shader_type canvas_item;
render_mode skip_vertex_transform;

uniform vec2 velocity = vec2(1.0, 1.0);
uniform vec4 fog_color: source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform sampler2D noise: repeat_enable;

varying vec2 coord;

void vertex() {
    coord = (SCREEN_MATRIX * inverse(CANVAS_MATRIX) * vec4(VERTEX, 0.0, 1.0)).xy;
    VERTEX = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    vec2 fixed_uv = -coord + TIME * velocity;
    float fog = texture(noise, fixed_uv).r;
    COLOR = mix(vec4(0.0), fog_color, fog);
}
```

### Script (required for positioning)
```gdscript
extends ColorRect

func _process(_delta: float) -> void:
    var viewport = get_viewport()
    var center := viewport.get_camera_2d().get_screen_center_position()
    var viewport_size := viewport.get_visible_rect().size
    global_position = Vector2(-viewport_size / 2.0) + center
    size = viewport_size
```

### Adaptation for Manual Transform (no Camera2D)
```gdscript
extends ColorRect

var scroll_offset: Vector2 = Vector2.ZERO
var current_scale: float = 1.0

func _process(_delta: float) -> void:
    var viewport_size := get_viewport_rect().size
    # Position ColorRect so its center is at scroll_offset in screen space
    # (This might need adjustment based on CanvasLayer behavior)
    global_position = -viewport_size / 2.0  # or more complex positioning
    size = viewport_size
```

**Note**: The adaptation for non-Camera2D usage is untested and may require experimentation. The key is ensuring `CANVAS_MATRIX` contains the correct transform information.

---

## Camera2D-First Architecture (Recommended)

After research, migrating to Camera2D provides significant benefits beyond just fixing the background sync issue:

### Benefits of Camera2D

| Feature | Current (Manual Transform) | Camera2D |
|---------|---------------------------|----------|
| Background sync | Broken | Automatic via `CANVAS_MATRIX` |
| Smooth animations | Custom implementation | Built-in `position_smoothing_*` |
| Cursor-centric zoom | Complex math | Well-tested patterns |
| Frustum culling | Manual | `VisibleOnScreenNotifier2D` works correctly |
| Parallax effects | Manual | Parallax2D automatic integration |
| Shader matrices | May be incorrect | Correct `CANVAS_MATRIX`, `SCREEN_MATRIX` |

### Architecture Overview

```
Tree (Node2D)
├── Camera2D (controls view) ← NEW: Single source of truth
│   └── CameraController.gd (smooth zoom/pan logic)
├── WorldLayer (Node2D) ← TreeGraph moves here
│   ├── PaperBackground (Parallax2D + Sprite2D with shader)
│   ├── TreeGraph (Node2D)
│   │   ├── EdgesLayer
│   │   ├── NodesLayer
│   │   ├── DexImagesLayer (with VisibleOnScreenNotifier2D per image)
│   │   └── LabelsLayer
└── UILayer (CanvasLayer, layer=10) ← Fixed UI unchanged
    └── Controls
```

### Key Components

#### 1. Camera2D Setup

```gdscript
# Camera2D node in tree scene
# Properties to set in editor or _ready():
position_smoothing_enabled = true
position_smoothing_speed = 15.0  # Adjust for feel
zoom = Vector2(2.0, 2.0)  # Initial zoom level
```

#### 2. CameraController (Smooth Pan/Zoom)

Based on [thygrrr's SmoothDamp implementation](https://gist.github.com/thygrrr/8288cabeb5cd25031ce6132c4a886311):

```gdscript
class_name CameraController
extends Node

@onready var camera: Camera2D = get_parent()

@export_group("Zoom")
@export var min_zoom: float = 0.1
@export var max_zoom: float = 10.0
@export var zoom_step: float = 0.1

@export_group("Smoothing")
@export var pan_smoothing: float = 0.2
@export var zoom_smoothing: float = 0.2

@export_group("Zoom Behavior")
@export var zoom_to_cursor: bool = true

# Goal state (where we want to be)
var position_goal: Vector2
var zoom_goal: Vector2

# SmoothDamp state
var damped_pos: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var damped_zoom: Array[Vector2] = [Vector2.ONE, Vector2.ZERO]

# Input tracking
var is_dragging: bool = false
var drag_start_pos: Vector2
var last_mouse_pos: Vector2
var zoom_mouse: Vector2

func _ready() -> void:
    position_goal = camera.position
    zoom_goal = camera.zoom
    damped_pos[0] = camera.position
    damped_zoom[0] = camera.zoom

func _process(delta: float) -> void:
    # Smooth zoom with cursor-centric adjustment
    _smooth_damp(damped_zoom, zoom_goal, zoom_smoothing, delta)

    var mouse_pre := _screen_to_world(zoom_mouse)
    camera.zoom = damped_zoom[0]
    var mouse_post := _screen_to_world(zoom_mouse)

    # Adjust position to keep cursor point stationary during zoom
    if zoom_to_cursor:
        var offset := mouse_pre - mouse_post
        position_goal += offset
        damped_pos[0] += offset

    # Smooth pan
    _smooth_damp(damped_pos, position_goal, pan_smoothing, delta)
    camera.position = damped_pos[0]

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton

        # Pan with middle mouse or touch drag
        if mb.button_index == MOUSE_BUTTON_MIDDLE:
            is_dragging = mb.pressed
            if is_dragging:
                last_mouse_pos = mb.position

        # Zoom with scroll wheel
        if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            zoom_mouse = mb.position - get_viewport_rect().size * 0.5
            zoom_goal *= 1.0 / (1.0 - zoom_step)
            zoom_goal = zoom_goal.clamp(Vector2.ONE * min_zoom, Vector2.ONE * max_zoom)

        if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            zoom_mouse = mb.position - get_viewport_rect().size * 0.5
            zoom_goal *= (1.0 - zoom_step)
            zoom_goal = zoom_goal.clamp(Vector2.ONE * min_zoom, Vector2.ONE * max_zoom)

    if event is InputEventMouseMotion and is_dragging:
        var motion := event as InputEventMouseMotion
        var delta_world := (last_mouse_pos - motion.position) / camera.zoom
        position_goal += delta_world
        last_mouse_pos = motion.position

func _screen_to_world(screen_pos: Vector2) -> Vector2:
    """Convert screen position (relative to center) to world coordinates."""
    return camera.position + screen_pos / camera.zoom

func center_on(world_pos: Vector2, animated: bool = true) -> void:
    """Center camera on world position."""
    if animated:
        position_goal = world_pos
    else:
        position_goal = world_pos
        camera.position = world_pos
        damped_pos[0] = world_pos

func set_zoom(new_zoom: float, animated: bool = true) -> void:
    """Set zoom level."""
    var clamped := clampf(new_zoom, min_zoom, max_zoom)
    if animated:
        zoom_goal = Vector2(clamped, clamped)
    else:
        zoom_goal = Vector2(clamped, clamped)
        camera.zoom = zoom_goal
        damped_zoom[0] = zoom_goal

func _smooth_damp(state: Array[Vector2], target: Vector2, smooth_time: float, delta: float) -> void:
    """Unity-style SmoothDamp for buttery smooth motion."""
    smooth_time /= 2.0

    if smooth_time == 0:
        state[0] = target
        state[1] = Vector2.ZERO
        return

    var omega := 2.0 / smooth_time
    var x := omega * delta
    var expo := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)

    var change := state[0] - target
    var temp := (state[1] + omega * change) * delta
    state[1] = (state[1] - omega * temp) * expo
    state[0] = target + (change + temp) * expo
```

#### 3. Background with Parallax2D

```gdscript
# Scene setup for infinite paper background
# Parallax2D (Node2D-based, integrates with Camera2D)
#   └── PaperSprite (Sprite2D with paper.gdshader)

# In parent script:
func _ready() -> void:
    var parallax := $PaperBackground as Parallax2D
    parallax.scroll_scale = Vector2(1.0, 1.0)  # Move 1:1 with camera
    parallax.repeat_size = Vector2(2048, 2048)  # Size of paper tile
    parallax.repeat_times = 20  # Enough for extreme zoom out
```

Or use the Stack Overflow shader approach (now with correct matrices):

```glsl
shader_type canvas_item;
render_mode skip_vertex_transform;

varying vec2 world_coord;

void vertex() {
    // With Camera2D, CANVAS_MATRIX contains correct camera transform
    world_coord = (SCREEN_MATRIX * inverse(CANVAS_MATRIX) * vec4(VERTEX, 0.0, 1.0)).xy;
    VERTEX = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    // world_coord now correctly tracks camera position
    vec2 px = -world_coord * some_scale;
    // ... rest of paper shader
}
```

#### 4. VisibleOnScreenNotifier2D for Lazy Loading

Add to DexRecordImage for automatic load/unload:

```gdscript
# In dex_record_image.gd or tree_dex_image.gd

var _visibility_notifier: VisibleOnScreenNotifier2D
var _is_visible: bool = false
var _load_requested: bool = false

func _ready() -> void:
    # ... existing code ...

    # Add visibility notifier
    _visibility_notifier = VisibleOnScreenNotifier2D.new()
    _visibility_notifier.rect = Rect2(-size.x/2, -size.y/2, size.x, size.y)
    add_child(_visibility_notifier)

    _visibility_notifier.screen_entered.connect(_on_screen_entered)
    _visibility_notifier.screen_exited.connect(_on_screen_exited)

func _on_screen_entered() -> void:
    _is_visible = true
    if _load_requested and not _has_texture():
        load_image_from_entry()

func _on_screen_exited() -> void:
    _is_visible = false
    # Optionally unload texture to free memory
    # clear_texture()

func load_image_from_entry() -> void:
    _load_requested = true
    if not _is_visible:
        return  # Defer loading until visible

    # ... existing loading code ...
```

**Key insight**: VisibleOnScreenNotifier2D signals (`screen_entered`/`screen_exited`) work correctly with Camera2D because the notifier checks against the actual viewport bounds.

#### 5. Migration Path

**Phase 1: Add Camera2D (keep existing system)**
1. Add Camera2D node to tree scene
2. Add CameraController script
3. Connect touch events to CameraController instead of BackgroundTouchController
4. Verify Camera2D moves correctly

**Phase 2: Fix background**
1. Move background ColorRect to world layer (not CanvasLayer)
2. Use Parallax2D or update shader to use `CANVAS_MATRIX`
3. Verify background syncs with camera

**Phase 3: Add performance features**
1. Add VisibleOnScreenNotifier2D to DexRecordImage
2. Implement lazy loading (only load when visible)
3. Optionally unload offscreen images for memory savings

**Phase 4: Cleanup**
1. Remove old BackgroundTouchController (or repurpose for dex feed)
2. Remove manual transform code from tree_controller.gd
3. Update TreeRenderer to not need `update_view()` for transforms

### Touch Integration

The existing BackgroundTouchController can be adapted:

```gdscript
# Modified to emit events that CameraController listens to
signal pan_delta(delta: Vector2)
signal zoom_delta(factor: float, center: Vector2)
signal tap_detected(position: Vector2)

# In CameraController:
func _ready() -> void:
    # ...
    var touch_ctrl = get_node("../TouchController")
    touch_ctrl.pan_delta.connect(_on_pan_delta)
    touch_ctrl.zoom_delta.connect(_on_zoom_delta)

func _on_pan_delta(delta: Vector2) -> void:
    position_goal += delta / camera.zoom

func _on_zoom_delta(factor: float, center: Vector2) -> void:
    zoom_mouse = center - get_viewport_rect().size * 0.5
    zoom_goal *= factor
    zoom_goal = zoom_goal.clamp(Vector2.ONE * min_zoom, Vector2.ONE * max_zoom)
```

### Performance Characteristics

| Aspect | Improvement |
|--------|-------------|
| Image loading | Only loads visible images (reduces initial load) |
| Memory | Can unload offscreen textures |
| Animation | GPU-accelerated via camera transform |
| Draw calls | Unchanged (already optimized) |
| Frame time | More consistent (no loading spikes during scroll) |

### Sources

- [Camera2D Documentation](https://docs.godotengine.org/en/stable/classes/class_camera2d.html)
- [VisibleOnScreenNotifier2D Documentation](https://docs.godotengine.org/en/stable/classes/class_visibleonscreennotifier2d.html)
- [SmoothDamp Camera Implementation](https://gist.github.com/thygrrr/8288cabeb5cd25031ce6132c4a886311)
- [GDQuest Camera Zoom Tutorial](https://www.gdquest.com/tutorial/godot/2d/camera-zoom/)
- [KidsCanCode Visibility Tutorial](https://kidscancode.org/godot_recipes/4.x/2d/enter_exit_screen/index.html)
- [Godot Off-Screen Processing Control](https://www.golden-tamarin.com/2024/10/10/godot-off-screen-processing-control/)