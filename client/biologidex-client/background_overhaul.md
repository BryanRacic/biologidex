# Background System Overhaul Plan

## Executive Summary

This document outlines a comprehensive plan to migrate all BiologiDex client scenes from the current `InteractiveBackground` (Control-based) system to a unified `Camera2D`-based architecture. The new system, proven working in `tree_camera.tscn`, provides **perfect background/foreground synchronization** by leveraging Godot's native Camera2D transform chain.

**Key Benefits:**
- Single source of truth (Camera2D position/zoom)
- No parallax drift between background and content
- Unified codebase following DRY principles
- Consistent touch/input handling across all scenes
- Cleaner architecture with fewer coordinate conversions

---

## Current State Analysis

### OLD System (8 scenes affected)

| Scene | Background | Touch Controller | Special Features |
|-------|------------|------------------|------------------|
| home | InteractiveBackground | BackgroundTouchController | Infinite canvas |
| login | InteractiveBackground | BackgroundTouchController | Infinite canvas |
| create_acct | InteractiveBackground | BackgroundTouchController | Infinite canvas |
| camera | InteractiveBackground | BackgroundTouchController | Infinite canvas |
| dex | InteractiveBackground | BackgroundTouchController | Infinite canvas |
| dex_feed | InteractiveBackground | BackgroundTouchController | **Scroll limits**, rubber-band |
| social | InteractiveBackground | BackgroundTouchController | **Scroll limits**, vertical only |
| tree (old) | InteractiveBackground | BackgroundTouchController | Tree graph transforms separate |

**Files to remove/replace:**
- `features/ui/components/interactive_background/interactive_background.gd`
- `features/ui/components/interactive_background/interactive_background.tscn`
- `features/ui/components/interactive_background/background_touch_controller.gd`
- `shaders/paper.gdshader` (replace with paper_camera.gdshader)

### NEW System (test/reference implementation)

**tree_camera.tscn** is a **test scene** that demonstrates the target architecture. It will be **deleted after migration** once the original tree scene is updated to use the shared components.

The working tree_camera scene proves:
- Camera2D as single transform source
- Polygon2D background (Node2D-based, NOT ColorRect/Control)
- `paper_camera.gdshader` captures world coords via MODEL_MATRIX
- Direct pan/zoom handling via controller
- WorldContent (Node2D) contains everything that transforms with camera
- UILayer (CanvasLayer) for fixed UI

---

## Target Architecture

### New File Structure

```
features/
├── camera_system/                        # NEW unified camera system
│   ├── paper_camera_scene.gd            # Reusable orchestrator component
│   ├── paper_camera_scene.tscn          # Instancable prefab
│   ├── camera_touch_controller.gd       # Unified pan/zoom/gesture handler
│   └── README.md                        # Usage documentation
├── tree/
│   ├── tree_renderer.gd                 # KEEP (tree-specific rendering)
│   ├── tree_dex_image.gd                # KEEP (tree-specific image wrapper)
│   ├── tree_data_models.gd              # KEEP (tree data structures)
│   └── ...
└── ui/components/
    └── interactive_background/           # DELETE entire folder

shaders/
├── paper_camera.gdshader                # KEEP (primary shader)
└── paper.gdshader                       # DELETE (old shader)

scenes/
├── home/home.tscn                       # UPDATE to use new system
├── login/login.tscn                     # UPDATE
├── create_account/create_acct.tscn      # UPDATE
├── camera/camera.tscn                   # UPDATE
├── dex/dex.tscn                         # UPDATE
├── dex_feed/dex_feed.tscn               # UPDATE (with scroll limits)
├── social/social.tscn                   # UPDATE (with scroll limits)
├── tree/                                # UPDATE (use shared components)
└── tree_camera/                         # DELETE (test scene, no longer needed)
```

---

## Component Design

### 1. PaperCameraScene (Main Reusable Component)

**File:** `features/camera_system/paper_camera_scene.tscn`

This is an **instancable scene** that provides:
- Camera2D with configurable settings
- Paper background (Polygon2D with shader)
- Touch/input controller
- UILayer placeholder for scene-specific UI

**Scene Structure:**
```
PaperCameraScene (Node2D, root)
├── Camera2D (unique_name)
│   └── CameraController (Node, gesture handling)
├── WorldContent (Node2D, unique_name)
│   ├── PaperBackground (Polygon2D, z_index=-100)
│   └── ContentContainer (Node2D, unique_name) ← Scene content goes here
└── UILayer (CanvasLayer, layer=10)
    └── UIContainer (Control, unique_name) ← Fixed UI goes here
```

**Exported Properties** (on root script):

```gdscript
## Camera Settings
@export_group("Camera")
@export var initial_zoom: float = 1.0
@export var min_zoom: float = 0.1
@export var max_zoom: float = 10.0
@export var zoom_enabled: bool = true
@export var pan_enabled: bool = true

## Touch Controller Settings
@export_group("Touch & Gestures")
@export var drag_threshold: float = 10.0
@export var pan_sensitivity: float = 1.0
@export var zoom_step: float = 0.1
@export var pinch_sensitivity: float = 1.0
@export var scroll_sensitivity: float = 1.0

## Inertia Settings
@export_group("Inertia")
@export var inertia_enabled: bool = false
@export var inertia_decay: float = 5.0
@export var inertia_stop_threshold: float = 1.0

## Scroll Limits (for bounded scrolling like feeds)
@export_group("Scroll Limits")
@export var scroll_limits_enabled: bool = false
@export var scroll_min: Vector2 = Vector2(-INF, -INF)
@export var scroll_max: Vector2 = Vector2(INF, INF)
@export var rubber_band_enabled: bool = true
@export var rubber_band_factor: float = 0.3
@export var rubber_band_max: float = 100.0
@export var snap_back_lerp: float = 0.15

## Paper Appearance
@export_group("Paper Grid")
@export_range(8.0, 64.0, 0.5) var grid_scale: float = 22.0
@export_range(0.5, 3.0, 0.1) var grid_line_px: float = 0.5
@export var grid_line_color: Color = Color(0.55, 0.53, 0.5, 1.0)
@export_range(0.0, 0.6, 0.01) var grid_line_alpha: float = 0.07

@export_group("Paper Base")
@export var paper_color: Color = Color(0.85, 0.82, 0.78, 1.0)
@export_range(0.0, 0.15, 0.001) var paper_noise_amount: float = 0.05
@export_range(0.05, 1.5, 0.01) var paper_noise_scale: float = 0.35

@export_group("Paper Speckles")
@export_range(0.0, 0.30, 0.001) var speckle_amount: float = 0.064
@export_range(0.25, 3.0, 0.01) var speckle_density: float = 1.68
@export_range(0.5, 6.0, 0.01) var speckle_scale: float = 6.0

@export_group("Paper Fibers")
@export_range(0.0, 0.20, 0.001) var fiber_amount: float = 0.111
@export_range(0.2, 4.0, 0.01) var fiber_scale: float = 0.57
```

**Signals:**
```gdscript
signal view_changed(position: Vector2, zoom: float)
signal tap_detected(world_position: Vector2)
signal gesture_started()
signal gesture_ended()
```

**Public API:**
```gdscript
func center_on(world_pos: Vector2, animated: bool = false) -> void
func set_zoom(new_zoom: float, animated: bool = false) -> void
func get_current_zoom() -> float
func get_camera_position() -> Vector2
func get_view_rect() -> Rect2
func scroll_to(offset: Vector2, animated: bool = false) -> void  # For scroll-limited modes
func reset() -> void
func get_content_container() -> Node2D  # For adding dynamic content
func get_ui_container() -> Control       # For adding fixed UI
```

---

### 2. CameraTouchController (Unified Input Handler)

**File:** `features/camera_system/camera_touch_controller.gd`

This merges the best features from both:
- `TreeCameraController` (direct pan/zoom, cursor-centric zoom)
- `BackgroundTouchController` (scroll limits, rubber-banding, inertia, tap detection)

**Key Features:**
- Works with Camera2D position/zoom (not manual scroll_offset/scale)
- Supports both infinite canvas AND bounded scrolling modes
- Configurable inertia (off by default for responsiveness)
- Tap detection with gesture recognition threshold
- Web-compatible touch handling (position-based, not index-based)

**Implementation Notes:**

For **infinite canvas mode** (home, login, camera, dex):
```gdscript
# Pan: modify camera position directly
camera.position -= delta * pan_sensitivity / camera.zoom.x

# Zoom: cursor-centric
var world_before = camera.position + screen_offset / camera.zoom
camera.zoom = Vector2(new_zoom, new_zoom)
var world_after = camera.position + screen_offset / camera.zoom
camera.position += world_before - world_after
```

For **bounded scroll mode** (dex_feed, social):
```gdscript
# Convert camera position to scroll offset for limit checking
var scroll_offset = camera.position  # Camera position IS the scroll offset

# Apply rubber-banding at limits
if rubber_band_enabled and new_offset.y > scroll_max.y:
    new_offset.y = scroll_offset.y + delta.y * rubber_band_factor
    new_offset.y = minf(new_offset.y, scroll_max.y + rubber_band_max)

# Snap back in _process when overscrolled
if _is_overscrolled():
    camera.position = camera.position.lerp(clamped_target, snap_back_lerp)
```

---

### 3. Paper Shader (Keep Existing)

**File:** `shaders/paper_camera.gdshader` (already working)

No changes needed. The shader:
1. Captures world coordinates via `MODEL_MATRIX * VERTEX` in vertex shader
2. Uses world coords for procedural noise sampling
3. Renders grid lines in world space
4. Automatically transforms with Camera2D

---

## Scene Migration Plan

### Phase 1: Create Unified Components (2 files)

1. **Create** `features/camera_system/paper_camera_scene.tscn`
   - Build scene structure as specified above
   - Configure default shader material from paper_camera.gdshader
   - Set up unique node names for script access

2. **Create** `features/camera_system/paper_camera_scene.gd`
   - Implement all exported properties
   - Wire up shader parameter syncing
   - Implement public API methods
   - Handle view_changed signal propagation

3. **Create** `features/camera_system/camera_touch_controller.gd`
   - Merge BackgroundTouchController + TreeCameraController
   - Support both infinite and bounded modes
   - Implement cursor-centric zoom
   - Add inertia support (optional)
   - Implement tap detection

### Phase 2: Update Simple Scenes (4 scenes)

These scenes use infinite canvas without special features:

**2a. Update home.tscn**
```
Before:
  Home (Node2D)
  └── UI (CanvasLayer)
      ├── InteractiveBackground ← REMOVE
      └── Control (UI content)

After:
  Home (Node2D)
  └── PaperCameraScene (instanced) ← ADD
      ├── UIContainer gets home buttons/content
      └── ContentContainer unused (static scene)
```

**2b. Update login.tscn**
- Same pattern as home
- Move login form to UIContainer

**2c. Update create_acct.tscn**
- Same pattern as home
- Move registration form to UIContainer

**2d. Update camera.tscn**
- Same pattern
- Move image capture UI to UIContainer

**2e. Update dex.tscn**
- Same pattern
- Move gallery UI to UIContainer

### Phase 3: Update Bounded Scroll Scenes (2 scenes)

These scenes need scroll limits enabled:

**3a. Update dex_feed.tscn**

Configuration:
```gdscript
# In scene or script:
paper_camera.scroll_limits_enabled = true
paper_camera.scroll_min = Vector2(-viewport_width * 0.5, 0)
paper_camera.scroll_max = Vector2(viewport_width * 0.5, max_scroll_y)
paper_camera.rubber_band_enabled = true
paper_camera.zoom_enabled = false  # Feed doesn't zoom
paper_camera.inertia_enabled = true  # Smooth scrolling
```

Special handling:
- `FeedCarouselRenderer` needs to add images to ContentContainer
- Scroll limits need dynamic update when content size changes
- Tap detection routes to `_on_tap_detected` for navigation

**3b. Update social.tscn**

Configuration:
```gdscript
paper_camera.scroll_limits_enabled = true
paper_camera.scroll_min = Vector2(0, 0)  # No horizontal scroll
paper_camera.scroll_max = Vector2(0, content_height)
paper_camera.zoom_enabled = false
paper_camera.inertia_enabled = true
```

Special handling:
- Friend list content goes in UIContainer (Control-based layout)
- Dynamic content height calculation for scroll limits

### Phase 4: Update Tree Scene to Use Shared Components

The tree scene has unique rendering needs (TreeRenderer, dex images, labels) but should still use the shared camera system for consistency and DRY compliance.

**4a. Update tree.tscn structure**

```
Before:
  Tree (Node2D)
  ├── BackgroundLayer (CanvasLayer, layer=-1)
  │   └── InteractiveBackground ← REMOVE
  ├── TreeGraph (Node2D)
  │   ├── EdgesLayer, NodesLayer, DexImagesLayer, LabelsLayer
  └── UILayer (CanvasLayer)

After:
  Tree (Node2D)
  ├── Camera2D ← ADD (single source of truth)
  │   └── CameraController ← ADD (shared component)
  ├── WorldContent (Node2D) ← ADD (transforms with camera)
  │   ├── PaperBackground (Polygon2D) ← ADD
  │   └── TreeGraph (Node2D) ← MOVE here
  │       ├── EdgesLayer, NodesLayer, DexImagesLayer, LabelsLayer
  └── UILayer (CanvasLayer, layer=10)
```

**4b. Update tree_controller.gd**
- Remove InteractiveBackground/BackgroundTouchController references
- Use shared CameraTouchController for pan/zoom
- Update coordinate conversion code to use Camera2D directly
- Connect to CameraController.view_changed signal
- Update TreeRenderer.update_view() calls

**4c. Key code changes in tree_controller.gd**
```gdscript
# OLD (remove):
@onready var interactive_bg: InteractiveBackground = %InteractiveBackground
var touch_controller: BackgroundTouchController
touch_controller = interactive_bg.get_node_or_null("TouchController")

# NEW (add):
@onready var camera: Camera2D = %Camera2D
@onready var camera_controller: CameraTouchController = %CameraController

func _on_view_changed(cam_position: Vector2, zoom: float) -> void:
    # Camera position IS the scroll offset
    var viewport_center = get_viewport_rect().size / 2.0
    tree_renderer.update_view(cam_position, zoom, viewport_center)
```

**4d. Delete test scene**
- Remove `scenes/tree_camera/tree_camera.tscn`
- Remove `scenes/tree_camera/tree_camera_controller.gd`
- Keep `features/tree/camera_controller.gd` (now shared)

**4e. Update home.gd**
- Remove "Tree (Camera2D)" button
- "Lineage Tree" button now navigates to the updated tree scene

### Phase 5: Cleanup

1. **Delete old files:**
   - `features/ui/components/interactive_background/` (entire folder)
   - `shaders/paper.gdshader`
   - `scenes/tree_camera/` (test scene, no longer needed)

2. **Update CLAUDE.md:**
   - Remove InteractiveBackground documentation
   - Remove tree_camera documentation
   - Add PaperCameraScene documentation
   - Update scene descriptions

3. **Update home.gd:**
   - Remove "Tree (Camera2D)" button (test scene deleted)
   - Ensure "Lineage Tree" navigates to updated tree scene

---

## Detailed Component Implementation

### PaperCameraScene Script

```gdscript
class_name PaperCameraScene
extends Node2D

## Unified Camera2D-based scene component with paper background.
## Provides pan/zoom/touch handling for all scenes.

# [All export groups from design section above]

# Node references
@onready var camera: Camera2D = %Camera2D
@onready var camera_controller: CameraTouchController = %CameraController
@onready var world_content: Node2D = %WorldContent
@onready var paper_background: Polygon2D = %PaperBackground
@onready var content_container: Node2D = %ContentContainer
@onready var ui_container: Control = %UIContainer

# Signals
signal view_changed(position: Vector2, zoom: float)
signal tap_detected(world_position: Vector2)
signal gesture_started()
signal gesture_ended()


func _ready() -> void:
    # Configure camera controller
    camera_controller.camera = camera
    camera_controller.min_zoom = min_zoom if zoom_enabled else 1.0
    camera_controller.max_zoom = max_zoom if zoom_enabled else 1.0
    camera_controller.drag_threshold = drag_threshold
    camera_controller.pan_sensitivity = pan_sensitivity
    camera_controller.zoom_step = zoom_step
    camera_controller.pinch_sensitivity = pinch_sensitivity
    camera_controller.scroll_sensitivity = scroll_sensitivity
    camera_controller.inertia_enabled = inertia_enabled
    camera_controller.inertia_decay = inertia_decay
    camera_controller.scroll_limits_enabled = scroll_limits_enabled
    camera_controller.scroll_min = scroll_min
    camera_controller.scroll_max = scroll_max
    camera_controller.rubber_band_enabled = rubber_band_enabled
    camera_controller.rubber_band_factor = rubber_band_factor
    camera_controller.rubber_band_max = rubber_band_max
    camera_controller.snap_back_lerp = snap_back_lerp
    camera_controller.pan_enabled = pan_enabled
    camera_controller.zoom_enabled = zoom_enabled

    # Connect controller signals
    camera_controller.view_changed.connect(_on_view_changed)
    camera_controller.tap_detected.connect(_on_tap_detected)
    camera_controller.gesture_started.connect(func(): gesture_started.emit())
    camera_controller.gesture_ended.connect(func(): gesture_ended.emit())

    # Set initial zoom
    camera.zoom = Vector2(initial_zoom, initial_zoom)

    # Sync shader parameters
    _sync_all_shader_params()


func _on_view_changed(position: Vector2, zoom: float) -> void:
    view_changed.emit(position, zoom)


func _on_tap_detected(screen_pos: Vector2) -> void:
    # Convert screen position to world position
    var viewport_center = get_viewport_rect().size / 2.0
    var world_pos = (screen_pos - viewport_center) / camera.zoom.x + camera.position
    tap_detected.emit(world_pos)


func _sync_all_shader_params() -> void:
    var mat = paper_background.material as ShaderMaterial
    if not mat:
        return

    mat.set_shader_parameter("grid_scale", grid_scale)
    mat.set_shader_parameter("line_px", grid_line_px)
    mat.set_shader_parameter("line_color", Vector4(grid_line_color.r, grid_line_color.g, grid_line_color.b, 1.0))
    mat.set_shader_parameter("line_alpha", grid_line_alpha)
    mat.set_shader_parameter("paper_color", Vector4(paper_color.r, paper_color.g, paper_color.b, 1.0))
    mat.set_shader_parameter("paper_noise_amount", paper_noise_amount)
    mat.set_shader_parameter("paper_noise_scale", paper_noise_scale)
    mat.set_shader_parameter("speckle_amount", speckle_amount)
    mat.set_shader_parameter("speckle_density", speckle_density)
    mat.set_shader_parameter("speckle_scale", speckle_scale)
    mat.set_shader_parameter("fiber_amount", fiber_amount)
    mat.set_shader_parameter("fiber_scale", fiber_scale)


# Property setters for runtime updates
func _update_shader_param(param: String, value: Variant) -> void:
    if not is_inside_tree() or not paper_background:
        return
    var mat = paper_background.material as ShaderMaterial
    if mat:
        mat.set_shader_parameter(param, value)


# Public API
func center_on(world_pos: Vector2, animated: bool = false) -> void:
    if animated:
        var tween = create_tween()
        tween.tween_property(camera, "position", world_pos, 0.3).set_ease(Tween.EASE_OUT)
        tween.tween_callback(func(): view_changed.emit(camera.position, camera.zoom.x))
    else:
        camera.position = world_pos
        view_changed.emit(camera.position, camera.zoom.x)


func set_zoom(new_zoom: float, animated: bool = false) -> void:
    var clamped = clampf(new_zoom, min_zoom, max_zoom)
    if animated:
        var tween = create_tween()
        tween.tween_property(camera, "zoom", Vector2(clamped, clamped), 0.3).set_ease(Tween.EASE_OUT)
        tween.tween_callback(func(): view_changed.emit(camera.position, camera.zoom.x))
    else:
        camera.zoom = Vector2(clamped, clamped)
        view_changed.emit(camera.position, camera.zoom.x)


func get_current_zoom() -> float:
    return camera.zoom.x


func get_camera_position() -> Vector2:
    return camera.position


func get_view_rect() -> Rect2:
    var viewport_size = get_viewport_rect().size
    var half_size = viewport_size / (2.0 * camera.zoom.x)
    return Rect2(camera.position - half_size, half_size * 2.0)


func scroll_to(offset: Vector2, animated: bool = false) -> void:
    center_on(offset, animated)


func reset() -> void:
    camera.position = Vector2.ZERO
    camera.zoom = Vector2(initial_zoom, initial_zoom)
    view_changed.emit(camera.position, camera.zoom.x)


func get_content_container() -> Node2D:
    return content_container


func get_ui_container() -> Control:
    return ui_container


func set_scroll_limits(min_val: Vector2, max_val: Vector2) -> void:
    scroll_min = min_val
    scroll_max = max_val
    camera_controller.scroll_min = min_val
    camera_controller.scroll_max = max_val
    camera_controller.scroll_limits_enabled = true
```

---

### CameraTouchController Script

```gdscript
class_name CameraTouchController
extends Node

## Unified touch/mouse controller for Camera2D-based scenes.
## Supports both infinite canvas and bounded scroll modes.

signal view_changed(position: Vector2, zoom: float)
signal tap_detected(screen_position: Vector2)
signal gesture_started()
signal gesture_ended()

# Camera reference (set by parent)
@export var camera: Camera2D

# Feature toggles
var pan_enabled: bool = true
var zoom_enabled: bool = true

# Zoom configuration
var min_zoom: float = 0.1
var max_zoom: float = 10.0
var zoom_step: float = 0.1
var pinch_sensitivity: float = 1.0
var scroll_sensitivity: float = 1.0

# Pan configuration
var drag_threshold: float = 10.0
var pan_sensitivity: float = 1.0

# Inertia
var inertia_enabled: bool = false
var inertia_decay: float = 5.0
var inertia_stop_threshold: float = 1.0
var _velocity: Vector2 = Vector2.ZERO
var _last_positions: Array[Vector2] = []
var _last_times: Array[float] = []
const VELOCITY_SAMPLES: int = 5
const VELOCITY_MAX_AGE: float = 0.1

# Scroll limits (for bounded modes like feeds)
var scroll_limits_enabled: bool = false
var scroll_min: Vector2 = Vector2(-INF, -INF)
var scroll_max: Vector2 = Vector2(INF, INF)
var rubber_band_enabled: bool = true
var rubber_band_factor: float = 0.3
var rubber_band_max: float = 100.0
var snap_back_lerp: float = 0.15

# Touch/mouse tracking
var _is_dragging: bool = false
var _drag_recognized: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _last_mouse_pos: Vector2 = Vector2.ZERO

# Multi-touch for pinch zoom
var _touches: Dictionary = {}
var _pinch_base_distance: float = 0.0
var _pinch_base_zoom: float = 1.0
var _pinch_base_center: Vector2 = Vector2.ZERO
var _pinch_base_camera_pos: Vector2 = Vector2.ZERO


func _input(event: InputEvent) -> void:
    if not camera:
        return

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
                gesture_started.emit()
            else:
                var was_drag = _drag_recognized
                _end_drag()
                if not was_drag:
                    tap_detected.emit(event.position)
                gesture_ended.emit()
        MOUSE_BUTTON_WHEEL_UP:
            if event.pressed and zoom_enabled:
                _zoom_at_point(event.position, 1.0 + zoom_step * scroll_sensitivity)
        MOUSE_BUTTON_WHEEL_DOWN:
            if event.pressed and zoom_enabled:
                _zoom_at_point(event.position, 1.0 - zoom_step * scroll_sensitivity)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
    if not _is_dragging or not pan_enabled:
        return

    var distance = event.position.distance_to(_drag_start)
    if not _drag_recognized and distance >= drag_threshold:
        _drag_recognized = true
        _stop_inertia()

    if not _drag_recognized:
        return

    var delta = event.position - _last_mouse_pos
    _last_mouse_pos = event.position

    # Record for inertia
    _record_position_sample(event.position)

    # Apply pan (with limits if enabled)
    _apply_pan_delta(-delta * pan_sensitivity / camera.zoom.x)
    get_viewport().set_input_as_handled()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
    if event.pressed:
        _touches[event.index] = event.position
        if _touches.size() == 1:
            _start_drag(event.position)
            gesture_started.emit()
        elif _touches.size() == 2 and zoom_enabled:
            _start_pinch()
    else:
        _touches.erase(event.index)
        if _touches.size() < 2:
            _pinch_base_distance = 0.0
        if _touches.is_empty():
            var was_drag = _drag_recognized
            _end_drag()
            if not was_drag:
                tap_detected.emit(event.position)
            gesture_ended.emit()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
    if not _touches.has(event.index):
        return

    _touches[event.index] = event.position

    if _touches.size() >= 2 and zoom_enabled:
        _process_pinch()
    elif _touches.size() == 1 and _drag_recognized and pan_enabled:
        _record_position_sample(event.position)
        _apply_pan_delta(-event.relative * pan_sensitivity / camera.zoom.x)
        get_viewport().set_input_as_handled()


func _start_drag(pos: Vector2) -> void:
    _is_dragging = true
    _drag_recognized = false
    _drag_start = pos
    _last_mouse_pos = pos


func _end_drag() -> void:
    if _drag_recognized and inertia_enabled:
        _start_inertia()
    _is_dragging = false
    _drag_recognized = false


func _start_pinch() -> void:
    var positions = _touches.values()
    if positions.size() < 2:
        return
    var p1: Vector2 = positions[0]
    var p2: Vector2 = positions[1]
    _pinch_base_distance = p1.distance_to(p2)
    _pinch_base_zoom = camera.zoom.x
    _pinch_base_center = (p1 + p2) / 2.0
    _pinch_base_camera_pos = camera.position
    _drag_recognized = true


func _process_pinch() -> void:
    var positions = _touches.values()
    if positions.size() < 2 or _pinch_base_distance < 10.0:
        return

    var p1: Vector2 = positions[0]
    var p2: Vector2 = positions[1]
    var current_distance = p1.distance_to(p2)
    var current_center = (p1 + p2) / 2.0

    # Calculate zoom
    var raw_scale = current_distance / _pinch_base_distance
    var scale_factor = 1.0 + (raw_scale - 1.0) * pinch_sensitivity
    var new_zoom = clampf(_pinch_base_zoom * scale_factor, min_zoom, max_zoom)

    # Apply zoom at pinch center (cursor-centric)
    var viewport_center = get_viewport().get_visible_rect().size / 2.0
    var screen_offset = current_center - viewport_center
    var world_before = _pinch_base_camera_pos + screen_offset / _pinch_base_zoom

    camera.zoom = Vector2(new_zoom, new_zoom)

    var world_after = camera.position + screen_offset / camera.zoom

    # Also handle pan from pinch center movement
    var center_delta = current_center - _pinch_base_center
    var pan_world = -center_delta / camera.zoom.x

    camera.position = world_before - screen_offset / camera.zoom.x + pan_world

    _emit_view_changed()
    get_viewport().set_input_as_handled()


func _zoom_at_point(screen_pos: Vector2, factor: float) -> void:
    var viewport_center = get_viewport().get_visible_rect().size / 2.0
    var screen_offset = screen_pos - viewport_center

    var world_before = camera.position + screen_offset / camera.zoom

    var new_zoom = clampf(camera.zoom.x * factor, min_zoom, max_zoom)
    camera.zoom = Vector2(new_zoom, new_zoom)

    var world_after = camera.position + screen_offset / camera.zoom
    camera.position += world_before - world_after

    _emit_view_changed()


func _apply_pan_delta(world_delta: Vector2) -> void:
    var new_pos = camera.position + world_delta

    if scroll_limits_enabled:
        if rubber_band_enabled:
            # Apply rubber-banding at limits
            if is_finite(scroll_min.x) and new_pos.x < scroll_min.x:
                new_pos.x = camera.position.x + world_delta.x * rubber_band_factor
                new_pos.x = maxf(new_pos.x, scroll_min.x - rubber_band_max / camera.zoom.x)
            elif is_finite(scroll_max.x) and new_pos.x > scroll_max.x:
                new_pos.x = camera.position.x + world_delta.x * rubber_band_factor
                new_pos.x = minf(new_pos.x, scroll_max.x + rubber_band_max / camera.zoom.x)

            if is_finite(scroll_min.y) and new_pos.y < scroll_min.y:
                new_pos.y = camera.position.y + world_delta.y * rubber_band_factor
                new_pos.y = maxf(new_pos.y, scroll_min.y - rubber_band_max / camera.zoom.x)
            elif is_finite(scroll_max.y) and new_pos.y > scroll_max.y:
                new_pos.y = camera.position.y + world_delta.y * rubber_band_factor
                new_pos.y = minf(new_pos.y, scroll_max.y + rubber_band_max / camera.zoom.x)
        else:
            # Hard clamp
            if is_finite(scroll_min.x): new_pos.x = maxf(new_pos.x, scroll_min.x)
            if is_finite(scroll_max.x): new_pos.x = minf(new_pos.x, scroll_max.x)
            if is_finite(scroll_min.y): new_pos.y = maxf(new_pos.y, scroll_min.y)
            if is_finite(scroll_max.y): new_pos.y = minf(new_pos.y, scroll_max.y)

    camera.position = new_pos
    _emit_view_changed()


func _process(delta: float) -> void:
    if not camera:
        return

    # Apply inertia
    if _touches.is_empty() and not _is_dragging:
        if inertia_enabled and _velocity.length() > inertia_stop_threshold:
            _apply_pan_delta(-_velocity * delta / camera.zoom.x)
            _velocity = _velocity.move_toward(Vector2.ZERO, _velocity.length() * inertia_decay * delta)
        elif scroll_limits_enabled and _is_overscrolled():
            _snap_back()
        else:
            _velocity = Vector2.ZERO


func _is_overscrolled() -> bool:
    if not scroll_limits_enabled:
        return false
    if is_finite(scroll_min.x) and camera.position.x < scroll_min.x: return true
    if is_finite(scroll_max.x) and camera.position.x > scroll_max.x: return true
    if is_finite(scroll_min.y) and camera.position.y < scroll_min.y: return true
    if is_finite(scroll_max.y) and camera.position.y > scroll_max.y: return true
    return false


func _snap_back() -> void:
    var target = camera.position

    if is_finite(scroll_min.x) and camera.position.x < scroll_min.x:
        target.x = scroll_min.x
    elif is_finite(scroll_max.x) and camera.position.x > scroll_max.x:
        target.x = scroll_max.x

    if is_finite(scroll_min.y) and camera.position.y < scroll_min.y:
        target.y = scroll_min.y
    elif is_finite(scroll_max.y) and camera.position.y > scroll_max.y:
        target.y = scroll_max.y

    if target != camera.position:
        camera.position = camera.position.lerp(target, snap_back_lerp)
        if camera.position.distance_to(target) < 1.0:
            camera.position = target
        _emit_view_changed()


func _record_position_sample(pos: Vector2) -> void:
    var now = Time.get_ticks_msec() / 1000.0
    _last_positions.append(pos)
    _last_times.append(now)
    while _last_positions.size() > VELOCITY_SAMPLES:
        _last_positions.pop_front()
        _last_times.pop_front()


func _calculate_velocity() -> Vector2:
    if _last_positions.size() < 2:
        return Vector2.ZERO

    var now = Time.get_ticks_msec() / 1000.0
    var oldest_idx = 0
    for i in range(_last_times.size()):
        if now - _last_times[i] <= VELOCITY_MAX_AGE:
            oldest_idx = i
            break

    if oldest_idx >= _last_positions.size() - 1:
        return Vector2.ZERO

    var oldest = _last_positions[oldest_idx]
    var newest = _last_positions[-1]
    var dt = _last_times[-1] - _last_times[oldest_idx]

    if dt < 0.001:
        return Vector2.ZERO

    return (newest - oldest) / dt


func _start_inertia() -> void:
    _velocity = _calculate_velocity()
    _last_positions.clear()
    _last_times.clear()


func _stop_inertia() -> void:
    _velocity = Vector2.ZERO
    _last_positions.clear()
    _last_times.clear()


func _emit_view_changed() -> void:
    view_changed.emit(camera.position, camera.zoom.x)


# Public API
func center_on(world_pos: Vector2) -> void:
    camera.position = world_pos
    _emit_view_changed()


func set_zoom(new_zoom: float) -> void:
    var clamped = clampf(new_zoom, min_zoom, max_zoom)
    camera.zoom = Vector2(clamped, clamped)
    _emit_view_changed()


func get_current_zoom() -> float:
    return camera.zoom.x if camera else 1.0


func get_view_rect() -> Rect2:
    if not camera:
        return Rect2()
    var viewport_size = get_viewport().get_visible_rect().size
    var half_size = viewport_size / (2.0 * camera.zoom.x)
    return Rect2(camera.position - half_size, half_size * 2.0)


func reset() -> void:
    camera.position = Vector2.ZERO
    camera.zoom = Vector2(1.0, 1.0)
    _velocity = Vector2.ZERO
    _emit_view_changed()
```

---

## Migration Checklist

### Phase 1: Create Components
- [ ] Create `features/camera_system/` directory
- [ ] Implement `paper_camera_scene.gd`
- [ ] Implement `camera_touch_controller.gd`
- [ ] Create `paper_camera_scene.tscn` with correct structure
- [ ] Test component in isolation

### Phase 2: Migrate Simple Scenes
- [ ] Update `home.tscn` to use PaperCameraScene
- [ ] Update `home.gd` to work with new architecture
- [ ] Test home scene
- [ ] Update `login.tscn`
- [ ] Test login scene
- [ ] Update `create_acct.tscn`
- [ ] Test create account scene
- [ ] Update `camera.tscn`
- [ ] Test camera scene
- [ ] Update `dex.tscn`
- [ ] Test dex scene

### Phase 3: Migrate Bounded Scroll Scenes
- [ ] Update `dex_feed.tscn` with scroll limits
- [ ] Update `dex_feed.gd` for new API
- [ ] Update `FeedCarouselRenderer` for new architecture
- [ ] Test dex feed scene
- [ ] Update `social.tscn` with scroll limits
- [ ] Update `social.gd` for new API
- [ ] Test social scene

### Phase 4: Update Tree Scene
- [ ] Update `tree.tscn` structure (add Camera2D, WorldContent, move TreeGraph)
- [ ] Add PaperBackground (Polygon2D with paper_camera.gdshader)
- [ ] Update `tree_controller.gd` to use shared CameraTouchController
- [ ] Remove InteractiveBackground references from tree_controller.gd
- [ ] Update coordinate conversion code to use Camera2D directly
- [ ] Test tree pan/zoom/rendering
- [ ] Delete `scenes/tree_camera/` directory (test scene no longer needed)
- [ ] Remove "Tree (Camera2D)" button from home.gd

### Phase 5: Cleanup
- [ ] Delete `features/ui/components/interactive_background/` directory
- [ ] Delete `shaders/paper.gdshader`
- [ ] Verify `scenes/tree_camera/` deleted (from Phase 4)
- [ ] Update `CLAUDE.md` documentation
- [ ] Run full app test on all scenes
- [ ] Test on web export
- [ ] Test on mobile (if applicable)

---

## Risk Mitigation

### Potential Issues

1. **Touch handling differences**
   - OLD: Uses `_gui_input()` on Control
   - NEW: Uses `_input()` on Node
   - Risk: Different event propagation order
   - Mitigation: Test tap-through to buttons thoroughly

2. **Coordinate space differences**
   - OLD: scroll_offset separate from camera
   - NEW: camera.position IS scroll_offset
   - Risk: Scenes expecting old coordinate math
   - Mitigation: Update all code using coordinate conversions

3. **UI Layout changes**
   - OLD: UI in CanvasLayer, background in same layer
   - NEW: UI in CanvasLayer (layer 10), background in world space
   - Risk: Z-ordering issues
   - Mitigation: Set appropriate z_index values

4. **Performance**
   - OLD: ColorRect shader covers exact viewport
   - NEW: Polygon2D shader covers large area (±25000 units)
   - Risk: Shader performance on large background
   - Mitigation: Already proven working in tree_camera; can reduce polygon size if needed

## Success Criteria

1. **All scenes use unified PaperCameraScene component**
2. **No duplicate background/touch code**
3. **Perfect background/foreground sync** (no parallax drift)
4. **All existing functionality preserved:**
   - Pan/zoom on infinite canvas scenes
   - Bounded scroll with rubber-banding on feed/social
   - Tap detection passes through to buttons
   - Inertia scrolling where enabled
5. **Web export works correctly**
6. **Touch gestures work on mobile**

---

## Future Improvements

Once migration is complete, consider:

1. **Shared paper settings resource**
   - Create `paper_settings.tres` resource
   - Reference from all scenes for consistent look
   - Change once, update everywhere

2. **Scene presets**
   - `InfiniteCanvasPreset` - no limits, zoom enabled
   - `VerticalFeedPreset` - vertical scroll, no zoom, inertia
   - `HorizontalFeedPreset` - horizontal scroll, no zoom

3. **Advanced features**
   - Focus/highlight areas (zoom to specific region)
   - Background animations (subtle paper movement)
   - Dynamic paper color themes

---

## Appendix: Key Technical Decisions

### Why Camera2D over Transform2D?

| Aspect | Transform2D (old) | Camera2D (new) |
|--------|-------------------|----------------|
| Transform source | Manual scroll_offset/scale | Camera.position/zoom |
| Background sync | Shader uniforms | Automatic via CANVAS_MATRIX |
| Drift risk | High (accumulation errors) | None (single source) |
| Complexity | More code, more bugs | Less code, cleaner |
| Godot idiom | Custom solution | Native approach |

### Why Polygon2D over ColorRect?

| Aspect | ColorRect | Polygon2D |
|--------|-----------|-----------|
| Base class | Control | Node2D |
| Camera2D transform | Not applied | Applied automatically |
| Shader coords | Need viewport_size uniform | Use MODEL_MATRIX |
| UI layer | Same layer as UI | Separate from UI |

### Why merge touch controllers?

The old `BackgroundTouchController` had features the tree controller lacked (scroll limits, inertia). The tree `TreeCameraController` had cleaner Camera2D integration. Merging gives us the best of both:
- Clean Camera2D integration
- Scroll limits for feed/social
- Optional inertia
- Unified codebase
