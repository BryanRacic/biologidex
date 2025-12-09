# Tree Camera Scene Implementation Plan

**Date**: 2025-12-09
**Status**: ✅ IMPLEMENTED AND WORKING
**Goal**: Create `tree_camera.tscn` - a Camera2D-based tree visualization scene that achieves perfect background/foreground synchronization.

---

## Executive Summary

This plan details the migration from manual `Transform2D` manipulation to a proper `Camera2D`-first architecture. The Camera2D approach provides:

1. **Perfect sync** - Camera2D transforms ALL Node2D children uniformly
2. **Built-in features** - Position smoothing, zoom interpolation, limit handling
3. **Proper coordinate systems** - `VisibleOnScreenNotifier2D`, `get_screen_center_position()` work correctly
4. **Simpler shader** - World coords computed once in vertex shader, no manual uniforms

## Implementation Summary (What Actually Worked)

### Key Discoveries During Implementation

1. **Background MUST be Node2D-based**: `ColorRect` is a `Control` node and is NOT transformed by Camera2D. Changed to `Polygon2D` which IS a Node2D and transforms correctly.

2. **Shader approach simplified**: Removed `skip_vertex_transform`. Let Godot handle the standard transform chain. Vertex shader only needs to compute world coordinates for the fragment shader:
   ```glsl
   void vertex() {
       vec4 world_pos = MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0);
       world_coord = world_pos.xy;
       // Don't modify VERTEX - let Godot handle transforms
   }
   ```

3. **Input handling**: Changed from `_unhandled_input()` to `_input()` in camera controller to ensure mouse events are captured.

4. **Viewport methods**: `Node` class doesn't have `get_viewport_rect()` - use `get_viewport().get_visible_rect()` instead.

### Files Created

| File | Purpose |
|------|---------|
| `scenes/tree_camera/tree_camera.tscn` | Camera2D-based tree scene |
| `scenes/tree_camera/tree_camera_controller.gd` | Scene controller using Camera2D |
| `features/tree/camera_controller.gd` | Reusable Camera2D pan/zoom controller |
| `shaders/paper_camera.gdshader` | Shader that computes world coords for procedural texture |

### Files Modified

| File | Changes |
|------|---------|
| `scenes/home/home.tscn` | Added "Tree (Camera2D)" button |
| `scenes/home/home.gd` | Added navigation to tree_camera scene |
| `CLAUDE.md` | Added tree_camera documentation |

---

## Problem Analysis

### Current Architecture Issues

```
Tree (Node2D)
├── BackgroundLayer (CanvasLayer, layer=-1)  ← PROBLEM: Isolated coordinate space
│   └── InteractiveBackground (Control)
│       ├── Background (ColorRect + shader)   ← Receives manual uniforms
│       └── TouchController
├── TreeGraph (Node2D)                        ← Manual Transform2D applied
│   └── ...
└── UILayer (CanvasLayer, layer=10)
```

**Root Cause**: The background shader runs in a `CanvasLayer` with `layer=-1`, which creates an isolated coordinate space. The shader uses `FRAGCOORD.xy` (window space) and manual uniforms to reconstruct world coordinates, but this doesn't perfectly match the `Transform2D` applied to `TreeGraph`.

**Key Insight**: When using `Camera2D`, Godot's built-in `CANVAS_MATRIX` shader variable contains the correct camera transform, eliminating manual synchronization.

---

## Target Architecture

```
TreeCamera (Node2D)
├── Camera2D (current=true)                   ← Single source of truth
│   └── CameraController.gd                   ← Pan/zoom/touch handling
├── WorldContent (Node2D)                     ← Camera automatically transforms this
│   ├── PaperBackground (Sprite2D)            ← Large tiled texture OR
│   │   └── paper_camera.gdshader             ← Shader using CANVAS_MATRIX
│   ├── TreeGraph (Node2D)
│   │   ├── EdgesLayer (Node2D)
│   │   ├── NodesLayer (Node2D)
│   │   ├── DexImagesLayer (Node2D)
│   │   └── LabelsLayer (Node2D)
└── UILayer (CanvasLayer, layer=10)           ← Fixed UI (unchanged)
    └── Controls
```

---

## Implementation Phases

### Phase 1: Scene Structure Setup

#### 1.1 Create tree_camera.tscn

Copy `tree.tscn` and restructure:

```gdscript
# tree_camera.tscn structure
[node name="TreeCamera" type="Node2D"]
script = "tree_camera_controller.gd"

[node name="Camera2D" type="Camera2D" parent="."]
unique_name_in_owner = true
position_smoothing_enabled = true
position_smoothing_speed = 15.0
zoom = Vector2(2.0, 2.0)  # Match current initial scale

[node name="WorldContent" type="Node2D" parent="."]
unique_name_in_owner = true

[node name="PaperBackground" type="Sprite2D" parent="WorldContent"]
unique_name_in_owner = true
z_index = -100
centered = false
# Material set programmatically or via .tscn

[node name="TreeGraph" type="Node2D" parent="WorldContent"]
unique_name_in_owner = true
# ... (EdgesLayer, NodesLayer, etc. unchanged)
```

#### 1.2 Camera2D Configuration

Set these properties in the scene or `_ready()`:

```gdscript
# In tree_camera_controller.gd
@onready var camera: Camera2D = %Camera2D

func _setup_camera() -> void:
    camera.enabled = true
    camera.position_smoothing_enabled = true
    camera.position_smoothing_speed = 15.0
    camera.zoom = Vector2(2.0, 2.0)  # Initial zoom

    # No limits initially (infinite pan)
    camera.limit_left = -10000000
    camera.limit_right = 10000000
    camera.limit_top = -10000000
    camera.limit_bottom = 10000000
```

---

### Phase 2: Camera Controller Implementation

#### 2.1 Create CameraController.gd

A dedicated controller for Camera2D pan/zoom with touch support:

```gdscript
# features/tree/camera_controller.gd
class_name TreeCameraController
extends Node

## Camera controller for tree visualization.
## Handles pan, zoom, touch gestures, and smooth animations.
## Attach as child of Camera2D or reference camera via export.

signal view_changed(position: Vector2, zoom: float)

@export var camera: Camera2D

# Zoom configuration
@export_group("Zoom")
@export var min_zoom: float = 0.1
@export var max_zoom: float = 10.0
@export var zoom_step: float = 0.1
@export var zoom_smoothing: float = 0.15

# Pan configuration
@export_group("Pan")
@export var pan_smoothing: float = 0.15
@export var drag_threshold: float = 10.0

# Inertia configuration
@export_group("Inertia")
@export var inertia_enabled: bool = true
@export var inertia_decay: float = 5.0
@export var inertia_stop_threshold: float = 1.0

# Goal state (where we want to be)
var _position_goal: Vector2 = Vector2.ZERO
var _zoom_goal: Vector2 = Vector2.ONE

# SmoothDamp state
var _position_velocity: Vector2 = Vector2.ZERO
var _zoom_velocity: Vector2 = Vector2.ZERO

# Touch/mouse tracking
var _is_dragging: bool = false
var _drag_recognized: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _zoom_focus_point: Vector2 = Vector2.ZERO

# Multi-touch for pinch zoom
var _touches: Dictionary = {}  # {index: position}
var _pinch_base_distance: float = 0.0
var _pinch_base_zoom: float = 1.0

# Velocity tracking for inertia
var _velocity_samples: Array[Vector2] = []
var _velocity_times: Array[float] = []
var _velocity: Vector2 = Vector2.ZERO
const VELOCITY_SAMPLE_COUNT: int = 5
const VELOCITY_MAX_AGE: float = 0.1


func _ready() -> void:
    if not camera:
        camera = get_parent() as Camera2D
    if not camera:
        push_error("[CameraController] No Camera2D found")
        return

    _position_goal = camera.position
    _zoom_goal = camera.zoom


func _process(delta: float) -> void:
    if not camera:
        return

    var old_position := camera.position
    var old_zoom := camera.zoom

    # Smooth zoom with cursor-centric adjustment
    var pre_zoom_world := _screen_to_world(_zoom_focus_point)
    camera.zoom = _smooth_damp_vec2(camera.zoom, _zoom_goal, _zoom_velocity, zoom_smoothing, delta)
    var post_zoom_world := _screen_to_world(_zoom_focus_point)

    # Adjust position to keep zoom focus point stationary
    var zoom_offset := pre_zoom_world - post_zoom_world
    _position_goal += zoom_offset

    # Apply inertia when not dragging
    if not _is_dragging and inertia_enabled:
        if _velocity.length() > inertia_stop_threshold:
            _position_goal -= _velocity * delta
            _velocity = _velocity.move_toward(Vector2.ZERO, _velocity.length() * inertia_decay * delta)
        else:
            _velocity = Vector2.ZERO

    # Smooth pan
    camera.position = _smooth_damp_vec2(camera.position, _position_goal, _position_velocity, pan_smoothing, delta)

    # Emit signal if view changed
    if camera.position != old_position or camera.zoom != old_zoom:
        view_changed.emit(camera.position, camera.zoom.x)


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        _handle_mouse_button(event as InputEventMouseButton)
    elif event is InputEventMouseMotion:
        _handle_mouse_motion(event as InputEventMouseMotion)
    elif event is InputEventScreenTouch:
        _handle_screen_touch(event as InputEventScreenTouch)
    elif event is InputEventScreenDrag:
        _handle_screen_drag(event as InputEventScreenDrag)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
    match event.button_index:
        MOUSE_BUTTON_LEFT:
            if event.pressed:
                _start_drag(event.position)
            else:
                _end_drag()
        MOUSE_BUTTON_WHEEL_UP:
            if event.pressed:
                _zoom_at_point(event.position, 1.0 + zoom_step)
        MOUSE_BUTTON_WHEEL_DOWN:
            if event.pressed:
                _zoom_at_point(event.position, 1.0 - zoom_step)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
    if not _is_dragging:
        return

    var distance := event.position.distance_to(_drag_start)
    if not _drag_recognized and distance >= drag_threshold:
        _drag_recognized = true

    if not _drag_recognized:
        return

    var delta := event.position - _last_mouse_pos
    _last_mouse_pos = event.position

    # Record for velocity calculation
    _record_velocity_sample(event.position)

    # Pan: move camera opposite to drag direction
    _position_goal -= delta / camera.zoom.x
    get_viewport().set_input_as_handled()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
    if event.pressed:
        _touches[event.index] = event.position
        if _touches.size() == 1:
            _start_drag(event.position)
        elif _touches.size() == 2:
            _start_pinch()
    else:
        _touches.erase(event.index)
        if _touches.size() < 2:
            _pinch_base_distance = 0.0
        if _touches.is_empty():
            _end_drag()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
    if not _touches.has(event.index):
        return

    _touches[event.index] = event.position

    if _touches.size() >= 2:
        _process_pinch()
    elif _touches.size() == 1 and _drag_recognized:
        _record_velocity_sample(event.position)
        _position_goal -= event.relative / camera.zoom.x
        get_viewport().set_input_as_handled()


func _start_drag(pos: Vector2) -> void:
    _is_dragging = true
    _drag_recognized = false
    _drag_start = pos
    _last_mouse_pos = pos
    _velocity = Vector2.ZERO
    _velocity_samples.clear()
    _velocity_times.clear()


func _end_drag() -> void:
    if _drag_recognized:
        _calculate_velocity()
    _is_dragging = false
    _drag_recognized = false


func _start_pinch() -> void:
    var positions := _touches.values()
    if positions.size() < 2:
        return
    _pinch_base_distance = (positions[0] as Vector2).distance_to(positions[1] as Vector2)
    _pinch_base_zoom = camera.zoom.x
    _drag_recognized = true  # Pinch is always a gesture


func _process_pinch() -> void:
    var positions := _touches.values()
    if positions.size() < 2 or _pinch_base_distance < 10.0:
        return

    var p1: Vector2 = positions[0]
    var p2: Vector2 = positions[1]
    var current_distance := p1.distance_to(p2)
    var center := (p1 + p2) / 2.0

    var scale_factor := current_distance / _pinch_base_distance
    var new_zoom := clampf(_pinch_base_zoom * scale_factor, min_zoom, max_zoom)

    _zoom_focus_point = center - get_viewport_rect().size / 2.0
    _zoom_goal = Vector2(new_zoom, new_zoom)

    get_viewport().set_input_as_handled()


func _zoom_at_point(screen_pos: Vector2, factor: float) -> void:
    _zoom_focus_point = screen_pos - get_viewport_rect().size / 2.0
    var new_zoom := clampf(camera.zoom.x * factor, min_zoom, max_zoom)
    _zoom_goal = Vector2(new_zoom, new_zoom)


func _screen_to_world(screen_offset: Vector2) -> Vector2:
    """Convert screen offset (relative to center) to world position."""
    return camera.position + screen_offset / camera.zoom


func _record_velocity_sample(pos: Vector2) -> void:
    var now := Time.get_ticks_msec() / 1000.0
    _velocity_samples.append(pos)
    _velocity_times.append(now)
    while _velocity_samples.size() > VELOCITY_SAMPLE_COUNT:
        _velocity_samples.pop_front()
        _velocity_times.pop_front()


func _calculate_velocity() -> void:
    if _velocity_samples.size() < 2:
        _velocity = Vector2.ZERO
        return

    var now := Time.get_ticks_msec() / 1000.0
    var oldest_idx := 0
    for i in range(_velocity_times.size()):
        if now - _velocity_times[i] <= VELOCITY_MAX_AGE:
            oldest_idx = i
            break

    if oldest_idx >= _velocity_samples.size() - 1:
        _velocity = Vector2.ZERO
        return

    var time_delta := _velocity_times[-1] - _velocity_times[oldest_idx]
    if time_delta < 0.001:
        _velocity = Vector2.ZERO
        return

    # Velocity in screen space, will be applied opposite to pan direction
    _velocity = (_velocity_samples[-1] - _velocity_samples[oldest_idx]) / time_delta / camera.zoom.x


func _smooth_damp_vec2(current: Vector2, target: Vector2, velocity: Vector2, smooth_time: float, delta: float) -> Vector2:
    """Unity-style SmoothDamp for buttery smooth motion."""
    if smooth_time <= 0.0:
        return target

    var omega := 2.0 / smooth_time
    var x := omega * delta
    var exp_factor := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)

    var change := current - target
    var temp := (velocity + omega * change) * delta
    velocity = (velocity - omega * temp) * exp_factor
    return target + (change + temp) * exp_factor


# Public API

func center_on(world_pos: Vector2, animated: bool = true) -> void:
    """Center camera on a world position."""
    if animated:
        _position_goal = world_pos
    else:
        _position_goal = world_pos
        camera.position = world_pos
        _position_velocity = Vector2.ZERO


func set_zoom(new_zoom: float, animated: bool = true) -> void:
    """Set zoom level."""
    var clamped := clampf(new_zoom, min_zoom, max_zoom)
    if animated:
        _zoom_goal = Vector2(clamped, clamped)
    else:
        _zoom_goal = Vector2(clamped, clamped)
        camera.zoom = _zoom_goal
        _zoom_velocity = Vector2.ZERO


func get_current_zoom() -> float:
    return camera.zoom.x if camera else 1.0


func get_view_rect() -> Rect2:
    """Get current view rectangle in world coordinates."""
    if not camera:
        return Rect2()
    var viewport_size := get_viewport_rect().size
    var half_size := viewport_size / (2.0 * camera.zoom.x)
    return Rect2(camera.position - half_size, half_size * 2.0)


func reset() -> void:
    """Reset camera to default state."""
    _position_goal = Vector2.ZERO
    _zoom_goal = Vector2(2.0, 2.0)
    _velocity = Vector2.ZERO
    if camera:
        camera.position = Vector2.ZERO
        camera.zoom = Vector2(2.0, 2.0)
    _position_velocity = Vector2.ZERO
    _zoom_velocity = Vector2.ZERO
```

---

### Phase 3: Background Shader Approach

#### Option A: Camera-Aware Shader (Recommended)

Create a new shader that uses `CANVAS_MATRIX` to automatically get camera transform:

```glsl
// shaders/paper_camera.gdshader
shader_type canvas_item;
render_mode skip_vertex_transform;

// Paper appearance (same as original)
uniform float grid_scale : hint_range(8.0, 64.0, 0.5) = 24.0;
uniform float line_px    : hint_range(0.5, 3.0, 0.1) = 1.0;
uniform vec4  line_color = vec4(0.55, 0.53, 0.50, 1.0);
uniform float line_alpha : hint_range(0.0, 0.6, 0.01) = 0.20;
uniform vec4 paper_color = vec4(0.96, 0.94, 0.90, 1.0);
uniform float paper_noise_amount : hint_range(0.0, 0.15, 0.001) = 0.05;
uniform float paper_noise_scale  : hint_range(0.05, 1.5, 0.01)  = 0.35;
uniform float speckle_amount  : hint_range(0.0, 0.30, 0.001) = 0.10;
uniform float speckle_density : hint_range(0.25, 3.0, 0.01)  = 1.0;
uniform float speckle_scale   : hint_range(0.5, 6.0, 0.01)   = 2.0;
uniform float fiber_amount : hint_range(0.0, 0.20, 0.001) = 0.06;
uniform float fiber_scale  : hint_range(0.2, 4.0, 0.01)   = 1.3;

varying vec2 world_coord;

// Noise helpers (same as original)
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for(int i = 0; i < 4; i++) {
        v += a * value_noise(p);
        p *= 2.05;
        a *= 0.5;
    }
    return v;
}

mat2 rot(float a) {
    float s = sin(a), c = cos(a);
    return mat2(vec2(c, -s), vec2(s, c));
}

void vertex() {
    // With skip_vertex_transform, we manually transform and capture world coords
    // CANVAS_MATRIX contains the Camera2D transform
    // inverse(CANVAS_MATRIX) goes from canvas/view space back to world space
    world_coord = (inverse(CANVAS_MATRIX) * MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;

    // Apply the standard transform for rendering
    VERTEX = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    // Use world coordinates from vertex shader
    vec2 px = world_coord;

    // Rest of shader is identical to original...
    float scaled_line = line_px;

    // Base paper noise
    vec2 paper_uv = px / grid_scale;
    float n1 = fbm(paper_uv * paper_noise_scale);
    float n2 = fbm(paper_uv * paper_noise_scale * 2.6);
    float paper_n = (n1 * 0.7 + n2 * 0.3) - 0.5;
    vec3 col = paper_color.rgb + paper_n * paper_noise_amount;

    // Speckles
    vec2 sp_uv = paper_uv * speckle_scale * 6.0 * speckle_density;
    float spots_big   = value_noise(sp_uv * 0.55);
    float spots_small = value_noise(sp_uv * 1.8);
    float thresh_var = fbm(sp_uv * 0.25) * 0.18;
    float big_mask   = smoothstep(0.80 + thresh_var, 1.0, spots_big);
    float small_mask = smoothstep(0.84 + thresh_var, 1.0, spots_small);
    float big_opacity   = mix(0.25, 1.0, value_noise(sp_uv * 0.9 + 12.3));
    float small_opacity = mix(0.10, 0.8, value_noise(sp_uv * 2.2 - 7.1));
    float specks = big_mask * big_opacity * 1.0 + small_mask * small_opacity * 0.7;

    // Fibers
    float ang = fbm(paper_uv * 0.6) * 6.28318;
    vec2 fib_uv = (rot(ang) * paper_uv) * fiber_scale * 10.0;
    fib_uv.x *= 3.5;
    fib_uv.y *= 0.55;
    float fib_noise   = value_noise(fib_uv);
    float fib_mask    = smoothstep(0.78, 1.0, fib_noise);
    float fib_opacity = mix(0.2, 1.0, value_noise(fib_uv * 0.7 + 4.4));
    specks += fib_mask * fib_opacity * 0.9;

    col -= specks * speckle_amount;
    col -= fib_mask * fib_opacity * fiber_amount;

    // Grid
    vec2 cell_pos = mod(px, grid_scale);
    float vline = step(cell_pos.x, scaled_line) + step(grid_scale - cell_pos.x, scaled_line);
    float hline = step(cell_pos.y, scaled_line) + step(grid_scale - cell_pos.y, scaled_line);
    float grid_mask = clamp(vline + hline, 0.0, 1.0);
    col = mix(col, line_color.rgb, grid_mask * line_alpha);

    COLOR = vec4(col, 1.0);
}
```

#### Option B: Large Background Sprite

If the shader approach has issues, use a large Sprite2D that transforms with the camera:

```gdscript
# In tree_camera_controller.gd
const BACKGROUND_SIZE := 50000.0  # World units

func _setup_background() -> void:
    var bg: Sprite2D = %PaperBackground
    bg.texture = _create_tiled_paper_texture()
    bg.position = Vector2(-BACKGROUND_SIZE / 2, -BACKGROUND_SIZE / 2)
    bg.region_enabled = true
    bg.region_rect = Rect2(0, 0, BACKGROUND_SIZE, BACKGROUND_SIZE)
```

---

### Phase 4: Controller Migration

#### 4.1 Create tree_camera_controller.gd

Adapt from `tree_controller.gd` with Camera2D integration:

```gdscript
# scenes/tree_camera/tree_camera_controller.gd
@tool
"""
TreeCameraController - Camera2D-based taxonomic tree visualization.
Uses Camera2D for view control instead of manual Transform2D.
"""
extends BaseSceneNode

const APITypes = preload("res://features/server_interface/api/core/api_types.gd")
const TreeRenderer = preload("res://features/tree/tree_renderer.gd")
const TreeCameraController = preload("res://features/tree/camera_controller.gd")

# Node references
@onready var camera: Camera2D = %Camera2D
@onready var camera_controller: TreeCameraController = $Camera2D/CameraController
@onready var world_content: Node2D = %WorldContent
@onready var tree_graph: Node2D = %TreeGraph
@onready var paper_background: Sprite2D = %PaperBackground

# ... (rest similar to tree_controller.gd but without manual transform code)

func _on_scene_ready() -> void:
    # ... existing setup ...

    # Connect camera controller signals
    camera_controller.view_changed.connect(_on_view_changed)

    # Setup background shader
    _setup_background()


func _setup_background() -> void:
    """Setup paper background with camera-aware shader."""
    var material := paper_background.material as ShaderMaterial
    # No uniforms needed - shader gets transform from CANVAS_MATRIX


func _on_view_changed(position: Vector2, zoom: float) -> void:
    """Called when camera position/zoom changes."""
    if tree_renderer:
        var viewport_size := get_viewport_rect().size
        var viewport_center := viewport_size / 2.0
        tree_renderer.update_view(position, zoom, viewport_center)


# Remove these methods (no longer needed):
# - _on_scroll_changed()
# - _on_scale_changed()
# - _update_tree_transform()
# - _setup_touch_controller()

# Modify zoom controls to use camera_controller:
func _on_zoom_in() -> void:
    camera_controller.set_zoom(camera_controller.get_current_zoom() * 1.2)

func _on_zoom_out() -> void:
    camera_controller.set_zoom(camera_controller.get_current_zoom() / 1.2)

func _on_zoom_reset() -> void:
    camera_controller.reset()

func _on_center_on_root() -> void:
    camera_controller.center_on(Vector2.ZERO)
```

#### 4.2 Update TreeRenderer

Minimal changes needed - just update coordinate conversion:

```gdscript
# In tree_renderer.gd

# update_view signature stays the same
func update_view(camera_pos: Vector2, zoom: float, center: Vector2) -> void:
    """Update view parameters (called when camera changes)."""
    _scroll_offset = camera_pos  # Now this IS camera.position
    _current_scale = zoom
    _viewport_center = center
    _viewport_size = get_viewport_rect().size
    # ... rest unchanged


func _get_view_rect() -> Rect2:
    """Get current view rectangle in world coordinates."""
    var margin_world = CULL_MARGIN_SCREEN / _current_scale
    var half_size = (_viewport_size / 2.0) / _current_scale + Vector2(margin_world, margin_world)
    # With Camera2D, scroll_offset IS camera.position (world center)
    return Rect2(_scroll_offset - half_size, half_size * 2)
```

---

### Phase 5: Scene File Structure

#### 5.1 tree_camera.tscn

```ini
[gd_scene load_steps=6 format=3 uid="uid://tree_camera_001"]

[ext_resource type="Script" path="res://scenes/tree_camera/tree_camera_controller.gd" id="1_controller"]
[ext_resource type="Script" path="res://features/tree/camera_controller.gd" id="2_camera_ctrl"]
[ext_resource type="Shader" path="res://shaders/paper_camera.gdshader" id="3_shader"]
[ext_resource type="Theme" path="res://theme.tres" id="4_theme"]

[sub_resource type="ShaderMaterial" id="ShaderMaterial_paper"]
resource_local_to_scene = true
shader = ExtResource("3_shader")
shader_parameter/grid_scale = 22.0
shader_parameter/line_px = 0.5
shader_parameter/line_color = Vector4(0.55, 0.53, 0.5, 1)
shader_parameter/line_alpha = 0.07
shader_parameter/paper_color = Vector4(0.85, 0.82, 0.78, 1)
shader_parameter/paper_noise_amount = 0.05
shader_parameter/paper_noise_scale = 0.35
shader_parameter/speckle_amount = 0.064
shader_parameter/speckle_density = 1.68
shader_parameter/speckle_scale = 6.0
shader_parameter/fiber_amount = 0.111
shader_parameter/fiber_scale = 0.57

[node name="TreeCamera" type="Node2D"]
script = ExtResource("1_controller")

[node name="Camera2D" type="Camera2D" parent="."]
unique_name_in_owner = true
position_smoothing_enabled = true
position_smoothing_speed = 15.0
zoom = Vector2(2, 2)

[node name="CameraController" type="Node" parent="Camera2D"]
script = ExtResource("2_camera_ctrl")
min_zoom = 0.1
max_zoom = 10.0

[node name="WorldContent" type="Node2D" parent="."]
unique_name_in_owner = true

[node name="PaperBackground" type="ColorRect" parent="WorldContent"]
unique_name_in_owner = true
z_index = -100
offset_left = -25000.0
offset_top = -25000.0
offset_right = 25000.0
offset_bottom = 25000.0
material = SubResource("ShaderMaterial_paper")

[node name="TreeGraph" type="Node2D" parent="WorldContent"]
unique_name_in_owner = true

[node name="EdgesLayer" type="Node2D" parent="WorldContent/TreeGraph"]
unique_name_in_owner = true
z_index = -1

[node name="NodesLayer" type="Node2D" parent="WorldContent/TreeGraph"]
unique_name_in_owner = true

[node name="DexImagesLayer" type="Node2D" parent="WorldContent/TreeGraph"]
unique_name_in_owner = true
z_index = 1

[node name="LabelsLayer" type="Node2D" parent="WorldContent/TreeGraph"]
unique_name_in_owner = true
z_index = 2

[node name="UILayer" type="CanvasLayer" parent="."]
layer = 10

[node name="Control" type="Control" parent="UILayer"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
theme = ExtResource("4_theme")

# ... (UI nodes same as tree.tscn)
```

---

## File Inventory

### New Files to Create

| File | Purpose |
|------|---------|
| `scenes/tree_camera/tree_camera.tscn` | New Camera2D-based tree scene |
| `scenes/tree_camera/tree_camera_controller.gd` | Controller adapted for Camera2D |
| `features/tree/camera_controller.gd` | Reusable Camera2D pan/zoom controller |
| `shaders/paper_camera.gdshader` | Camera-aware paper shader |

### Files to Modify

| File | Changes |
|------|---------|
| `features/tree/tree_renderer.gd` | Minor - coordinate convention docs |

### Files Unchanged

| File | Reason |
|------|--------|
| `scenes/tree/tree.tscn` | Keep original for comparison |
| `scenes/tree/tree_controller.gd` | Keep original for comparison |
| `shaders/paper.gdshader` | Keep original for other scenes |

---

## Testing Plan

### Test Cases

1. **Basic Rendering**
   - [ ] Tree nodes render at correct positions
   - [ ] Edges connect correct nodes
   - [ ] Dex images load and display
   - [ ] Labels appear at appropriate zoom levels

2. **Pan/Zoom Synchronization** (Primary Goal)
   - [ ] Background grid lines align with tree nodes at rest
   - [ ] During pan, background and nodes move at exactly same speed
   - [ ] During zoom, background and nodes scale identically
   - [ ] At extreme zoom out (0.1x), alignment holds
   - [ ] At extreme zoom in (10x), alignment holds
   - [ ] After rapid pan/zoom gestures, alignment holds

3. **Touch/Mouse Input**
   - [ ] Single finger pan works
   - [ ] Two finger pinch zoom works
   - [ ] Mouse wheel zoom works
   - [ ] Cursor-centric zoom (zoom toward cursor) works
   - [ ] Inertia/momentum after release
   - [ ] Tap on node selects it

4. **Performance**
   - [ ] 60fps maintained during pan
   - [ ] 60fps maintained during zoom
   - [ ] No visible jitter/stutter
   - [ ] Memory usage comparable to original

5. **Edge Cases**
   - [ ] Window resize handled correctly
   - [ ] Returning to scene after navigating away
   - [ ] Very large tree (5000+ nodes)

### Test Commands

```bash
# Run specific scene for testing
cd client/biologidex-client
godot --path . res://scenes/tree_camera/tree_camera.tscn
```

---

## Rollback Strategy

If the Camera2D approach fails:

1. Keep `tree.tscn` and `tree_controller.gd` unchanged
2. New scene is isolated in `scenes/tree_camera/`
3. Can delete new files without affecting production code
4. NavigationManager can switch between scenes for A/B testing

---

## Implementation Order

1. **Create shader first** (`paper_camera.gdshader`) - Can test independently
2. **Create camera controller** (`camera_controller.gd`) - Generic, reusable
3. **Create scene file** (`tree_camera.tscn`) - Structure only
4. **Create controller script** (`tree_camera_controller.gd`) - Wire everything together
5. **Test and iterate** on synchronization
6. **Performance optimization** if needed

---

## Sources & References

- [Godot Camera2D Documentation](https://docs.godotengine.org/en/stable/classes/class_camera2d.html)
- [Viewport and Canvas Transforms](https://docs.godotengine.org/en/stable/tutorials/2d/2d_transforms.html)
- [CanvasItem Shaders Reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html)
- [Smooth Camera Pan/Zoom (thygrrr)](https://gist.github.com/thygrrr/8288cabeb5cd25031ce6132c4a886311)
- [TouchCamera2D Reference](https://github.com/williambcosta/godot-touch-camera-2d)
- [Parallax2D Documentation](https://docs.godotengine.org/en/stable/classes/class_parallax2d.html)
- [World Coordinates in Canvas Shaders Issue](https://github.com/godotengine/godot-docs/issues/7860)
- [Vertex Shader World Position Forum](https://forum.godotengine.org/t/vertex-shader-world-position-of-a-vertex-how/64237)
