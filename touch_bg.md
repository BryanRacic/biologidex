# Touch-Interactive Background Implementation Plan

## Overview

Transform the home screen's auto-scrolling paper background into a touch/mouse-interactive, zoomable canvas. Users can pan via drag gestures and zoom via pinch (touch) or scroll wheel (mouse).

## Current State Analysis

### Existing Implementation
- **home.gd**: Auto-scrolls background via `scroll_accum += scroll_speed * delta` in `_process()`
- **paper.gdshader**: Accepts `uniform vec2 scroll` for offset; uses `FRAGCOORD.xy + scroll` for pattern generation
- **home.tscn**: Background is a `ColorRect` with shader material, UI buttons overlay in a centered `VBoxContainer`

### Reference Implementations
- **multitouch_view**: Simple touch tracking via `InputEventScreenTouch`/`InputEventScreenDrag` in singleton
- **multitouch_cubes/gesture_area.gd**: Full pinch-zoom and rotation with 2-finger gesture handling
- **tree_controller.gd**: Mouse-based pan/zoom (right-click drag, scroll wheel) pattern already in codebase

---

## Known Web Export Constraints

### Platform Issues (Documented Bugs)
| Issue | Impact | Workaround |
|-------|--------|------------|
| [iOS/iPadOS web export index bug (#95941)](https://github.com/godotengine/godot/issues/95941) | Touch index values overflow on iOS web | Track touches by absolute position, not index |
| [Multitouch relative calculation (#94346)](https://github.com/godotengine/godot/issues/94346) | `event.relative` incorrect during multitouch | Calculate delta from stored positions, ignore `relative` |
| [Cross-platform index inconsistency (#3772)](https://github.com/godotengine/godot-proposals/issues/3772) | Index behavior differs per platform | Use position-based tracking, reset state on finger count change |

### Project Settings Required
```ini
[input_devices]
pointing/emulate_touch_from_mouse = true   # Enable for desktop testing
pointing/emulate_mouse_from_touch = false  # Disable to prevent double-handling
```

---

## Architecture Design

### Component Structure

```
home.gd (Scene Controller)
├── BackgroundTouchController (new - handles all gesture input)
│   ├── Processes InputEventScreenTouch/Drag
│   ├── Processes InputEventMouseButton/Motion
│   ├── Emits: scroll_changed(offset: Vector2), scale_changed(scale: float)
│   └── Manages inertia/momentum physics
└── paper.gdshader (modified)
    └── Accepts: scroll (vec2), scale (float)
```

### Input Flow

```
User Touch/Mouse Event
        │
        ▼
┌───────────────────────────────────┐
│     BackgroundTouchController     │
│  ┌─────────────────────────────┐  │
│  │  Touch State Dictionary     │  │
│  │  { index: position }        │  │
│  └─────────────────────────────┘  │
│              │                    │
│  ┌───────────┴───────────┐        │
│  │  Gesture Detector     │        │
│  │  - 0 fingers: idle    │        │
│  │  - 1 finger: pan      │        │
│  │  - 2 fingers: pinch   │        │
│  └───────────────────────┘        │
│              │                    │
│  ┌───────────┴───────────┐        │
│  │  Inertia Physics      │        │
│  │  - Velocity tracking  │        │
│  │  - Exponential decay  │        │
│  └───────────────────────┘        │
└───────────────────────────────────┘
        │
        ▼
    Shader Uniforms Updated
    (scroll, scale)
```

---

## Implementation Steps

### Phase 1: Shader Modifications

#### 1.1 Add Scale Uniform to paper.gdshader

**File**: `res://shaders/paper.gdshader`

```glsl
// Add new uniform after scroll
uniform float scale : hint_range(0.5, 4.0) = 1.0;  // Zoom multiplier

void fragment() {
    // Apply scale to scroll and coordinates
    vec2 scaled_scroll = scroll / scale;
    vec2 px = (FRAGCOORD.xy / scale) + scaled_scroll;

    // Rest of shader uses px instead of FRAGCOORD.xy + scroll
    // Grid scale also needs adjustment for consistent appearance
    float effective_grid_scale = grid_scale * scale;

    // ... existing pattern generation with effective_grid_scale
}
```

**Key Considerations**:
- Dividing FRAGCOORD by scale zooms the pattern
- Dividing scroll by scale keeps pan distance consistent at all zoom levels
- Grid lines should maintain visual consistency (adjust `line_px` calculation)

#### 1.2 Update Shader Grid Calculations

The grid and pattern calculations need scale-awareness:

```glsl
void fragment() {
    vec2 scaled_scroll = scroll / scale;
    vec2 px = (FRAGCOORD.xy / scale) + scaled_scroll;

    // Paper noise (unaffected by zoom for natural feel)
    vec2 paper_uv = px / grid_scale;

    // Grid lines (scale-aware for consistent line width)
    float scaled_grid = grid_scale;  // Grid spacing zooms
    float scaled_line = line_px / scale;  // Lines stay same screen-width

    vec2 cell_pos = mod(px, scaled_grid);
    float vline = step(cell_pos.x, scaled_line) + step(scaled_grid - cell_pos.x, scaled_line);
    float hline = step(cell_pos.y, scaled_line) + step(scaled_grid - cell_pos.y, scaled_line);
    // ...
}
```

---

### Phase 2: BackgroundTouchController Component

#### 2.1 Create New Script

**File**: `res://features/home/background_touch_controller.gd`

```gdscript
class_name BackgroundTouchController
extends Control

## Handles touch/mouse gestures for panning and zooming the shader background.
## Designed for web export compatibility across all platforms.

signal scroll_changed(offset: Vector2)
signal scale_changed(scale: float)
signal gesture_started()
signal gesture_ended()

# Configuration
@export var min_scale: float = 0.5
@export var max_scale: float = 4.0
@export var pan_sensitivity: float = 1.0
@export var zoom_sensitivity: float = 0.002
@export var inertia_enabled: bool = true
@export var inertia_decay: float = 5.0  # Higher = faster slowdown
@export var inertia_stop_threshold: float = 1.0  # px/sec

# State
var scroll_offset: Vector2 = Vector2.ZERO
var current_scale: float = 1.0

# Touch tracking (position-based for web compatibility)
var _touch_state: Dictionary = {}  # { index: Vector2 position }
var _base_touch_state: Dictionary = {}  # State when finger count changed
var _base_scroll: Vector2 = Vector2.ZERO
var _base_scale: float = 1.0
var _base_pinch_distance: float = 0.0

# Inertia
var _velocity: Vector2 = Vector2.ZERO
var _last_positions: Array[Vector2] = []  # For velocity smoothing
var _last_times: Array[float] = []
const VELOCITY_SAMPLES: int = 5
const VELOCITY_MAX_AGE: float = 0.1  # seconds

# Mouse state
var _mouse_dragging: bool = false
var _mouse_last_pos: Vector2 = Vector2.ZERO
```

#### 2.2 Input Handling Methods

```gdscript
func _ready() -> void:
    # Ensure we receive input
    mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
    # Handle touch events
    if event is InputEventScreenTouch:
        _handle_screen_touch(event)
    elif event is InputEventScreenDrag:
        _handle_screen_drag(event)

    # Handle mouse events (for desktop/web mouse users)
    elif event is InputEventMouseButton:
        _handle_mouse_button(event)
    elif event is InputEventMouseMotion:
        _handle_mouse_motion(event)


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
    var prev_finger_count := _touch_state.size()

    if event.pressed:
        # Finger down
        _touch_state[event.index] = event.position
        _stop_inertia()

        if prev_finger_count == 0:
            gesture_started.emit()
    else:
        # Finger up
        _touch_state.erase(event.index)

        if _touch_state.size() == 0:
            _start_inertia()
            gesture_ended.emit()

    # Finger count changed - reset base state
    if _touch_state.size() != prev_finger_count:
        _update_base_state()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
    if not _touch_state.has(event.index):
        return

    # Update position (use absolute position, not relative - web compatibility)
    _touch_state[event.index] = event.position

    # Track for inertia
    _record_position_sample(event.position)

    var finger_count := _touch_state.size()

    if finger_count == 1:
        _handle_single_finger_pan()
    elif finger_count == 2:
        _handle_two_finger_gesture()
```

#### 2.3 Gesture Calculation Methods

```gdscript
func _handle_single_finger_pan() -> void:
    if _base_touch_state.is_empty():
        return

    var current_pos: Vector2 = _touch_state.values()[0]
    var base_pos: Vector2 = _base_touch_state.values()[0]
    var delta: Vector2 = current_pos - base_pos

    # Apply pan (invert direction - dragging right moves pattern left)
    scroll_offset = _base_scroll - delta * pan_sensitivity
    scroll_changed.emit(scroll_offset)

    # Continuously update base for smooth panning
    _base_touch_state[_touch_state.keys()[0]] = current_pos
    _base_scroll = scroll_offset


func _handle_two_finger_gesture() -> void:
    if _base_touch_state.size() < 2:
        return

    # Get current and base finger positions
    var keys := _touch_state.keys()
    var p1: Vector2 = _touch_state[keys[0]]
    var p2: Vector2 = _touch_state[keys[1]]

    var base_keys := _base_touch_state.keys()
    var bp1: Vector2 = _base_touch_state[base_keys[0]]
    var bp2: Vector2 = _base_touch_state[base_keys[1]]

    # Calculate pinch zoom
    var current_distance := p1.distance_to(p2)
    var base_distance := bp1.distance_to(bp2)

    if base_distance > 10.0:  # Avoid division by tiny numbers
        var scale_factor := current_distance / base_distance
        var new_scale := clampf(_base_scale * scale_factor, min_scale, max_scale)

        if absf(new_scale - current_scale) > 0.001:
            current_scale = new_scale
            scale_changed.emit(current_scale)

    # Calculate pan from midpoint movement
    var current_center := (p1 + p2) / 2.0
    var base_center := (bp1 + bp2) / 2.0
    var center_delta := current_center - base_center

    scroll_offset = _base_scroll - center_delta * pan_sensitivity
    scroll_changed.emit(scroll_offset)


func _update_base_state() -> void:
    _base_touch_state = _touch_state.duplicate()
    _base_scroll = scroll_offset
    _base_scale = current_scale

    if _touch_state.size() == 2:
        var positions := _touch_state.values()
        _base_pinch_distance = (positions[0] as Vector2).distance_to(positions[1] as Vector2)
```

#### 2.4 Mouse Support

```gdscript
func _handle_mouse_button(event: InputEventMouseButton) -> void:
    # Left click for pan
    if event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            _mouse_dragging = true
            _mouse_last_pos = event.position
            _stop_inertia()
            gesture_started.emit()
        else:
            _mouse_dragging = false
            _start_inertia()
            gesture_ended.emit()

    # Scroll wheel for zoom
    elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
        _zoom_at_point(event.position, 1.1)
    elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
        _zoom_at_point(event.position, 0.9)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
    if not _mouse_dragging:
        return

    var delta := event.position - _mouse_last_pos
    _mouse_last_pos = event.position

    # Track for inertia
    _record_position_sample(event.position)

    # Apply pan
    scroll_offset -= delta * pan_sensitivity
    scroll_changed.emit(scroll_offset)


func _zoom_at_point(point: Vector2, factor: float) -> void:
    """Zoom centered on a specific point (mouse cursor)."""
    var old_scale := current_scale
    current_scale = clampf(current_scale * factor, min_scale, max_scale)

    if absf(current_scale - old_scale) < 0.001:
        return

    # Adjust scroll to keep point stationary
    var scale_ratio := current_scale / old_scale
    var point_offset := point - get_viewport_rect().size / 2.0
    scroll_offset = scroll_offset * scale_ratio + point_offset * (1.0 - scale_ratio)

    scroll_changed.emit(scroll_offset)
    scale_changed.emit(current_scale)
```

#### 2.5 Inertia System

```gdscript
func _process(delta: float) -> void:
    if not inertia_enabled:
        return

    # Apply inertia when no active touches
    if _touch_state.is_empty() and not _mouse_dragging:
        if _velocity.length() > inertia_stop_threshold:
            scroll_offset -= _velocity * delta
            scroll_changed.emit(scroll_offset)

            # Exponential decay
            _velocity = _velocity.move_toward(Vector2.ZERO, _velocity.length() * inertia_decay * delta)
        else:
            _velocity = Vector2.ZERO


func _record_position_sample(pos: Vector2) -> void:
    var now := Time.get_ticks_msec() / 1000.0
    _last_positions.append(pos)
    _last_times.append(now)

    # Keep only recent samples
    while _last_positions.size() > VELOCITY_SAMPLES:
        _last_positions.pop_front()
        _last_times.pop_front()


func _calculate_velocity() -> Vector2:
    """Calculate smoothed velocity from recent position samples."""
    if _last_positions.size() < 2:
        return Vector2.ZERO

    var now := Time.get_ticks_msec() / 1000.0

    # Find oldest valid sample
    var oldest_idx := 0
    for i in range(_last_times.size()):
        if now - _last_times[i] <= VELOCITY_MAX_AGE:
            oldest_idx = i
            break

    if oldest_idx >= _last_positions.size() - 1:
        return Vector2.ZERO

    var oldest_pos := _last_positions[oldest_idx]
    var newest_pos := _last_positions[-1]
    var time_delta := _last_times[-1] - _last_times[oldest_idx]

    if time_delta < 0.001:
        return Vector2.ZERO

    return (oldest_pos - newest_pos) / time_delta


func _start_inertia() -> void:
    _velocity = _calculate_velocity()
    _last_positions.clear()
    _last_times.clear()


func _stop_inertia() -> void:
    _velocity = Vector2.ZERO
    _last_positions.clear()
    _last_times.clear()


func reset() -> void:
    """Reset scroll and scale to defaults."""
    scroll_offset = Vector2.ZERO
    current_scale = 1.0
    _velocity = Vector2.ZERO
    _touch_state.clear()
    _base_touch_state.clear()
    scroll_changed.emit(scroll_offset)
    scale_changed.emit(current_scale)
```

---

### Phase 3: Integration with home.gd

#### 3.1 Modify home.gd

```gdscript
extends Node2D

# Background settings
@onready var mat := get_node("%Background").material as ShaderMaterial
@onready var touch_controller: BackgroundTouchController = get_node("%TouchController")

# Removed: scroll_speed, scroll_accum (no longer auto-scrolling)

# UI Elements (unchanged)
@onready var camera_button: Button = get_node("%CameraButton")
# ... other buttons

func _ready() -> void:
    print("[Home] Scene loaded")
    _initialize_services()

    if not token_manager.is_logged_in():
        print("[Home] WARNING: User not logged in, redirecting to login")
        navigation_manager.navigate_to("res://scenes/login/login.tscn", true)
        return

    # Connect touch controller signals
    touch_controller.scroll_changed.connect(_on_scroll_changed)
    touch_controller.scale_changed.connect(_on_scale_changed)

    # Connect navigation buttons (unchanged)
    camera_button.pressed.connect(_on_camera_pressed)
    # ...


func _on_scroll_changed(offset: Vector2) -> void:
    mat.set_shader_parameter("scroll", offset)


func _on_scale_changed(scale: float) -> void:
    mat.set_shader_parameter("scale", scale)


# REMOVED: _process() with auto-scroll
# All other methods unchanged
```

#### 3.2 Update home.tscn Structure

```
Home (Node2D)
├── UI (CanvasLayer)
│   ├── Background (ColorRect with shader) [unchanged]
│   ├── TouchController (BackgroundTouchController) [NEW]
│   │   └── anchors_preset = 15 (full screen)
│   │   └── mouse_filter = STOP
│   └── Control (UI overlay)
│       └── CenterContainer
│           └── VBoxContainer (buttons)
```

**Critical**: TouchController must be BETWEEN Background and Control in the tree order so:
1. Background renders first
2. TouchController receives unhandled input
3. UI buttons still receive clicks (they have higher priority in the tree)

---

### Phase 4: Testing Matrix

#### 4.1 Test Cases

| Gesture | Desktop Mouse | Desktop Touch | Mobile Touch | Web (Desktop) | Web (Mobile) |
|---------|---------------|---------------|--------------|---------------|--------------|
| Single drag pan | LMB drag | 1 finger | 1 finger | LMB drag | 1 finger |
| Scroll zoom | Wheel | N/A | N/A | Wheel | N/A |
| Pinch zoom | N/A | 2 fingers | 2 fingers | N/A | 2 fingers |
| Inertia | Release LMB | Release touch | Release touch | Release LMB | Release touch |
| Button clicks | LMB | Tap | Tap | LMB | Tap |

#### 4.2 Edge Cases to Test

1. **Button overlap**: Ensure buttons still receive clicks when over touch area
2. **Gesture interruption**: Start pan, then add second finger for pinch
3. **Rapid gestures**: Quick flicks for inertia testing
4. **Scale limits**: Verify min/max scale enforced
5. **iOS web index bug**: Test on actual iOS Safari
6. **Low frame rate**: Inertia should behave correctly during lag

#### 4.3 Web Export Verification

```bash
# Build for web
cd client/biologidex-client
godot --headless --export-release "Web" build/web/index.html

# Test locally
python -m http.server 8080 -d build/web
# Test in Chrome, Firefox, Safari, mobile browsers
```

---

### Phase 5: Project Configuration

#### 5.1 Project Settings Updates

Add to `project.godot`:

```ini
[input_devices]

pointing/emulate_touch_from_mouse=true
pointing/emulate_mouse_from_touch=false
```

#### 5.2 Export Template Verification

Ensure in web export settings:
- `vram_texture_compression/for_desktop = true`
- `variant/thread_support = false` (single-threaded for web compatibility, per CLAUDE.md)

---

## File Summary

| File | Action | Description |
|------|--------|-------------|
| `res://shaders/paper.gdshader` | Modify | Add `scale` uniform, update fragment calculations |
| `res://features/home/background_touch_controller.gd` | Create | New touch/mouse gesture handler class |
| `res://scenes/home/home.gd` | Modify | Remove auto-scroll, connect to touch controller |
| `res://scenes/home/home.tscn` | Modify | Add TouchController node |
| `project.godot` | Modify | Add input device settings |

---

## Risk Mitigation

### Web Platform Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| iOS touch index bug | High on iOS | Medium | Use position-based tracking, not index |
| Performance on mobile | Medium | High | Limit velocity samples, use move_toward for decay |
| Gesture conflicts with UI | Low | High | Careful scene tree ordering, test extensively |

### Fallback Plan

If multitouch proves unreliable on web:
1. Disable pinch-zoom on web platform: `if OS.has_feature("web"): disable_pinch = true`
2. Add on-screen +/- zoom buttons (like tree_controller.gd)
3. Keep single-finger pan (more reliable)

---

## Implementation Order

1. **Shader modifications** (30 min) - Low risk, easily tested
2. **BackgroundTouchController class** (2 hrs) - Core functionality
3. **Integration with home.gd/tscn** (30 min) - Wire up signals
4. **Desktop testing** (30 min) - Mouse and emulated touch
5. **Web export testing** (1 hr) - Multiple browsers
6. **Mobile web testing** (1 hr) - iOS Safari, Android Chrome
7. **Polish and edge cases** (1 hr) - Inertia tuning, button conflicts

---

## References

- [InputEventScreenTouch Documentation](https://docs.godotengine.org/en/stable/classes/class_inputeventscreentouch.html)
- [Canvas Item Shader Reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html)
- [Multi-touch camera with inertia (Levi's Devlog)](https://devlog.levi.dev/2022/04/implementing-multi-touch-camera.html)
- [FinePointCGI Touchscreen Camera Guide](https://finepointcgi.io/2023/06/16/building-a-touchscreen-camera-in-godot-4-a-comprehensive-guide/)
- [GitHub Issue #95941 - iOS web touch index bug](https://github.com/godotengine/godot/issues/95941)
- [GitHub Issue #94346 - Web multitouch relative bug](https://github.com/godotengine/godot/issues/94346)
- [Godot Proposal #3772 - Cross-platform touch consistency](https://github.com/godotengine/godot-proposals/issues/3772)
