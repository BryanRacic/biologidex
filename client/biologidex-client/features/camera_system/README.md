# Camera System

Unified Camera2D-based background and input system for BiologiDex scenes.

## Overview

This system provides:
- Single source of truth for view transforms (Camera2D position/zoom)
- Perfect background/foreground synchronization
- Consistent touch/input handling across all scenes
- Support for both infinite canvas and bounded scroll modes

## Usage

### Basic Setup (Infinite Canvas)

Instance `paper_camera_scene.tscn` in your scene:

```gdscript
# In your scene script
@onready var paper_camera: PaperCameraScene = $PaperCameraScene

func _ready() -> void:
    # Add UI to the fixed UI container
    var my_button = Button.new()
    paper_camera.get_ui_container().add_child(my_button)

    # Listen for view changes
    paper_camera.view_changed.connect(_on_view_changed)
    paper_camera.tap_detected.connect(_on_tap_detected)
```

### Bounded Scroll Mode (Feeds)

Configure scroll limits for scrollable content:

```gdscript
func _ready() -> void:
    paper_camera.scroll_limits_enabled = true
    paper_camera.scroll_min = Vector2(0, 0)
    paper_camera.scroll_max = Vector2(0, content_height)
    paper_camera.zoom_enabled = false  # Disable zoom for feeds
    paper_camera.inertia_enabled = true  # Smooth scrolling
```

Or use the API:
```gdscript
paper_camera.set_scroll_limits(Vector2(0, 0), Vector2(0, max_scroll))
```

## Components

### PaperCameraScene (paper_camera_scene.tscn)

Main instancable scene with:
- Camera2D for view control
- Paper background (Polygon2D with shader)
- Touch controller for gestures
- UILayer for fixed UI elements

**Scene Structure:**
```
PaperCameraScene (Node2D)
├── Camera2D
│   └── CameraController
├── WorldContent (Node2D)
│   ├── PaperBackground (Polygon2D)
│   └── ContentContainer (Node2D) <- Dynamic world content
└── UILayer (CanvasLayer)
    └── UIContainer (Control) <- Fixed UI
```

### CameraTouchController (camera_touch_controller.gd)

Handles all input:
- Mouse drag for pan
- Scroll wheel for zoom (cursor-centric)
- Single-finger drag for pan
- Two-finger pinch for zoom
- Tap detection with gesture threshold
- Optional inertia with scroll limits

## Exported Properties

### Camera
- `initial_zoom`: Starting zoom level
- `min_zoom` / `max_zoom`: Zoom limits
- `zoom_enabled` / `pan_enabled`: Feature toggles

### Touch & Gestures
- `drag_threshold`: Pixels before drag is recognized
- `pan_sensitivity` / `zoom_step`: Sensitivity multipliers
- `pinch_sensitivity` / `scroll_sensitivity`: Touch/wheel sensitivity

### Inertia
- `inertia_enabled`: Enable momentum scrolling
- `inertia_decay`: How fast inertia slows down
- `inertia_stop_threshold`: Minimum velocity before stopping

### Scroll Limits
- `scroll_limits_enabled`: Enable bounded scrolling
- `scroll_min` / `scroll_max`: Boundaries (use INF for unbounded axes)
- `rubber_band_enabled`: Overscroll resistance effect
- `rubber_band_factor` / `rubber_band_max`: Resistance parameters
- `snap_back_lerp`: Speed of snap-back animation

### Paper Appearance
All paper shader parameters are exposed for customization.

## Signals

- `view_changed(position: Vector2, zoom: float)`: Camera moved or zoomed
- `tap_detected(world_position: Vector2)`: Tap without drag
- `gesture_started()`: Drag or pinch began
- `gesture_ended()`: Gesture completed

## Public API

```gdscript
func center_on(world_pos: Vector2, animated: bool = false) -> void
func set_zoom(new_zoom: float, animated: bool = false) -> void
func get_current_zoom() -> float
func get_camera_position() -> Vector2
func get_view_rect() -> Rect2
func scroll_to(offset: Vector2, animated: bool = false) -> void
func reset() -> void
func get_content_container() -> Node2D
func get_ui_container() -> Control
func set_scroll_limits(min_val: Vector2, max_val: Vector2) -> void
```
