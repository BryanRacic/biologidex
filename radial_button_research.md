# Radial Button Research for Godot 4.5

## Overview

This document compiles research on implementing radial/pie menu buttons in Godot 4.5.1, prioritizing native solutions and established patterns. The goal is to replace the BiologiDex home screen with radial buttons surrounding a central button, with curved/segmented design.

---

## Approach Summary (Ranked by Recommendation)

| Approach | Pros | Cons | Complexity |
|----------|------|------|------------|
| **1. Custom Control with `_draw()` + `_has_point()`** | Full control, native Godot, no dependencies | More code required | Medium |
| **2. Shader-based rendering + Control hit detection** | Performant, smooth visuals | Shader complexity, text handling issues | Medium-High |
| **3. TextureButton with click masks** | Simple setup, familiar API | Requires pre-made textures, scaling issues | Low |
| **4. Existing addon (jesuisse/godot-radial-menu-control)** | Feature-complete, maintained | External dependency, may need customization | Low |
| **5. Positioned standard buttons (no curves)** | Simplest, uses native buttons | Not curved/segmented appearance | Very Low |

**Recommendation**: Approach #1 (Custom Control) is best for BiologiDex - provides full control over appearance and behavior while staying native to Godot.

---

## Native Godot Solutions

### 1. Custom Control with `_draw()` and `_has_point()`

This is the most "Godot-native" approach for curved, segmented buttons.

#### Key Components

**Drawing Arc Segments** (filled pie slices):
```gdscript
extends Control
class_name RadialButton

@export var inner_radius: float = 80.0
@export var outer_radius: float = 200.0
@export var start_angle: float = 0.0  # radians
@export var end_angle: float = PI / 3  # radians (60 degrees)
@export var segment_color: Color = Color.WHITE
@export var hover_color: Color = Color.LIGHT_BLUE
@export var pressed_color: Color = Color.DARK_BLUE
@export var gap_angle: float = 0.05  # radians between segments

var _is_hovered := false
var _is_pressed := false

func _draw() -> void:
    var color = segment_color
    if _is_pressed:
        color = pressed_color
    elif _is_hovered:
        color = hover_color

    _draw_arc_segment(Vector2.ZERO, inner_radius, outer_radius,
                      start_angle + gap_angle/2, end_angle - gap_angle/2, color)

func _draw_arc_segment(center: Vector2, inner_r: float, outer_r: float,
                       angle_from: float, angle_to: float, color: Color) -> void:
    var nb_points := 32
    var points := PackedVector2Array()
    var colors := PackedColorArray([color])

    # Outer arc (clockwise)
    for i in range(nb_points + 1):
        var angle := angle_from + i * (angle_to - angle_from) / nb_points
        points.push_back(center + Vector2(cos(angle), sin(angle)) * outer_r)

    # Inner arc (counter-clockwise to close the shape)
    for i in range(nb_points, -1, -1):
        var angle := angle_from + i * (angle_to - angle_from) / nb_points
        points.push_back(center + Vector2(cos(angle), sin(angle)) * inner_r)

    draw_polygon(points, colors)
```

**Custom Hit Detection** (`_has_point` override):
```gdscript
func _has_point(point: Vector2) -> bool:
    # Convert point to local coordinates (relative to control center)
    var center := size / 2
    var local_point := point - center

    # Check distance (between inner and outer radius)
    var distance := local_point.length()
    if distance < inner_radius or distance > outer_radius:
        return false

    # Check angle
    var angle := atan2(local_point.y, local_point.x)
    angle = fposmod(angle, TAU)  # Normalize to [0, TAU)
    var start_norm := fposmod(start_angle, TAU)
    var end_norm := fposmod(end_angle, TAU)

    # Handle wrap-around case
    if start_norm <= end_norm:
        return angle >= start_norm and angle <= end_norm
    else:
        return angle >= start_norm or angle <= end_norm

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                _is_pressed = true
            else:
                if _is_pressed and _is_hovered:
                    pressed.emit()  # Custom signal
                _is_pressed = false
            queue_redraw()
            accept_event()
    elif event is InputEventMouseMotion:
        var was_hovered := _is_hovered
        _is_hovered = _has_point(event.position)
        if was_hovered != _is_hovered:
            queue_redraw()
```

**Complete Radial Menu Container**:
```gdscript
extends Control
class_name RadialMenu

signal button_pressed(index: int)

@export var button_count: int = 5
@export var inner_radius: float = 80.0
@export var outer_radius: float = 200.0
@export var gap_angle: float = 0.05  # radians
@export var start_offset: float = -PI/2  # Start at top (12 o'clock)

var _buttons: Array[RadialButton] = []

func _ready() -> void:
    _create_buttons()

func _create_buttons() -> void:
    var angle_per_button := TAU / button_count

    for i in range(button_count):
        var button := RadialButton.new()
        button.inner_radius = inner_radius
        button.outer_radius = outer_radius
        button.start_angle = start_offset + i * angle_per_button
        button.end_angle = start_offset + (i + 1) * angle_per_button
        button.gap_angle = gap_angle
        button.pressed.connect(_on_button_pressed.bind(i))
        add_child(button)
        _buttons.append(button)

func _on_button_pressed(index: int) -> void:
    button_pressed.emit(index)
```

#### Sources
- [Custom Drawing in 2D - Godot Docs](https://docs.godotengine.org/en/stable/tutorials/2d/custom_drawing_in_2d.html)
- [Custom GUI Controls - Godot Docs](https://docs.godotengine.org/en/stable/tutorials/ui/custom_gui_controls.html)
- [Control Class - Godot Docs](https://docs.godotengine.org/en/stable/classes/class_control.html)

---

### 2. TextureButton with Click Mask

Godot's `TextureButton` supports custom click masks for non-rectangular hit areas.

#### How It Works

```gdscript
# In editor or code:
var texture_button := TextureButton.new()
texture_button.texture_normal = preload("res://assets/arc_segment_normal.png")
texture_button.texture_hover = preload("res://assets/arc_segment_hover.png")
texture_button.texture_pressed = preload("res://assets/arc_segment_pressed.png")
texture_button.texture_click_mask = preload("res://assets/arc_segment_mask.png")  # B&W bitmap
```

**Click Mask Format**:
- Pure black and white BitMap image
- White pixels = clickable area
- Black pixels = transparent/non-clickable

**Known Issues (Godot 4.2+)**:
- Click mask scaling is buggy when only some texture slots are filled ([GitHub #91898](https://github.com/godotengine/godot/issues/91898))
- Workaround: Fill all required texture slots (normal, hover, pressed)

#### Pros/Cons
- **Pro**: Familiar Button API, signals, theming
- **Pro**: Simple for pre-designed assets
- **Con**: Requires creating textures for each button state
- **Con**: Scaling issues require workarounds
- **Con**: Less flexible for dynamic segment counts

#### Sources
- [TextureButton - Godot Docs](https://docs.godotengine.org/en/stable/classes/class_texturebutton.html)
- [TextureButton Click Mask Issue](https://github.com/godotengine/godot/issues/91898)

---

### 3. ButtonGroup for Exclusive Selection

If radial buttons need radio-button behavior (only one selected at a time):

```gdscript
var button_group := ButtonGroup.new()

for button in radial_buttons:
    button.toggle_mode = true
    button.button_group = button_group

# Get currently selected
var selected := button_group.get_pressed_button()

# Listen for selection changes
button_group.pressed.connect(_on_selection_changed)
```

---

### 4. Positioned Standard Buttons (Simple Approach)

For non-curved buttons arranged in a circle (like KidsCanCode tutorial):

```gdscript
extends Control

@export var radius: float = 150.0
@export var button_count: int = 5
@export var animation_speed: float = 0.25

var _buttons: Array[Button] = []
var _active := false

func _ready() -> void:
    # Position buttons around center
    var angle_step := TAU / button_count
    for i in range(button_count):
        var angle := -PI/2 + i * angle_step  # Start at top
        var pos := Vector2(cos(angle), sin(angle)) * radius
        var button := $Buttons.get_child(i) as Button
        button.position = size/2 + pos - button.size/2
        _buttons.append(button)

func show_menu() -> void:
    var tween := create_tween()
    tween.set_parallel(true)

    var angle_step := TAU / button_count
    for i in range(button_count):
        var angle := -PI/2 + i * angle_step
        var target_pos := Vector2(cos(angle), sin(angle)) * radius + size/2
        var button := _buttons[i]
        button.visible = true
        tween.tween_property(button, "position", target_pos, animation_speed)\
             .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
        tween.tween_property(button, "scale", Vector2.ONE, animation_speed)\
             .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

    _active = true
```

#### Sources
- [Radial Popup Menu - KidsCanCode Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/ui/radial_menu/index.html)
- [GitHub: godotrecipes/ui_radial_menu](https://github.com/godotrecipes/ui_radial_menu)

---

## Shader-Based Approaches

### Circular Progress Bar / Segmented Ring Shader

For smooth, performant rendering of segmented arcs:

```glsl
shader_type canvas_item;

uniform float segments : hint_range(1, 12) = 5;
uniform float inner_radius : hint_range(0.0, 0.5) = 0.2;
uniform float outer_radius : hint_range(0.0, 0.5) = 0.45;
uniform float gap : hint_range(0.0, 0.1) = 0.02;
uniform float rotation : hint_range(-1.0, 1.0) = -0.25;  // Start at top
uniform int hovered_segment : hint_range(-1, 11) = -1;
uniform vec4 base_color : source_color = vec4(0.3, 0.3, 0.3, 1.0);
uniform vec4 hover_color : source_color = vec4(0.5, 0.5, 0.8, 1.0);

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);
    float angle = atan(uv.y, uv.x) / (2.0 * PI) + 0.5;  // 0-1 range
    angle = mod(angle - rotation, 1.0);  // Apply rotation

    // Check if within ring
    if (dist < inner_radius || dist > outer_radius) {
        COLOR = vec4(0.0);
        return;
    }

    // Determine segment
    float segment_size = 1.0 / segments;
    float segment_pos = mod(angle, segment_size) / segment_size;
    int current_segment = int(angle * segments);

    // Gap between segments
    if (segment_pos < gap || segment_pos > 1.0 - gap) {
        COLOR = vec4(0.0);
        return;
    }

    // Apply hover color
    if (current_segment == hovered_segment) {
        COLOR = hover_color;
    } else {
        COLOR = base_color;
    }
}
```

**Usage with Hit Detection**:
```gdscript
extends Control

@onready var shader_material: ShaderMaterial = material

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouse:
        var segment := _get_segment_at_position(event.position)
        shader_material.set_shader_parameter("hovered_segment", segment)

        if event is InputEventMouseButton and event.pressed:
            if segment >= 0:
                _on_segment_pressed(segment)

func _get_segment_at_position(pos: Vector2) -> int:
    var center := size / 2
    var local := pos - center
    var dist := local.length() / min(size.x, size.y)

    var inner_r: float = shader_material.get_shader_parameter("inner_radius")
    var outer_r: float = shader_material.get_shader_parameter("outer_radius")

    if dist < inner_r or dist > outer_r:
        return -1

    var segments: int = shader_material.get_shader_parameter("segments")
    var rotation: float = shader_material.get_shader_parameter("rotation")

    var angle := atan2(local.y, local.x) / TAU + 0.5
    angle = fposmod(angle - rotation, 1.0)

    return int(angle * segments) % segments
```

#### Known Issues with Shaders on Buttons
- Button text has unpredictable UV values, making shaders on `Button` nodes problematic
- **Workaround**: Use `Control` with shader + separate `Label` children for text

#### Sources
- [Procedural Circular Progress Bar - Godot Shaders](https://godotshaders.com/shader/procedural-circular-progress-bar/)
- [Circle Shader - Godot Shaders](https://godotshaders.com/shader/circle-shader/)

---

## Existing Addons

### 1. godot-radial-menu-control (Recommended)

**Repository**: [jesuisse/godot-radial-menu-control](https://github.com/jesuisse/godot-radial-menu-control)
**Asset Library**: [Radial Menu Control](https://godotengine.org/asset-library/asset/3469)
**Godot Version**: 4.3+

#### Features
- Keyboard, mouse, and gamepad support
- Submenu support
- Themeable with light/dark defaults
- Configurable: radius, width, arc coverage, gap size, animation
- Center deselection zone

#### Key API
```gdscript
var menu := RadialMenu.new()
menu.set_items([
    {'texture': icon1, 'title': 'Camera', 'id': 'camera'},
    {'texture': icon2, 'title': 'Dex', 'id': 'dex'},
    {'texture': icon3, 'title': 'Social', 'id': 'social'},
])
menu.item_selected.connect(_on_item_selected)
menu.open_menu(center_position)
```

#### Configuration Properties
- `radius`, `width`, `center_radius`
- `circle_coverage` (0-1, for partial arcs)
- `center_angle` (starting angle in radians)
- `gap_size` (spacing between segments)
- `icon_scale`, `show_titles`, `show_animation`

### 2. tavurth/godot-radial-menu (Shader-Based)

**Repository**: [tavurth/godot-radial-menu](https://github.com/tavurth/godot-radial-menu)
**Godot Version**: 4.x branch available

#### Features
- Shader-based rendering (performant)
- Mobile and desktop support
- Touch/mouse/gamepad input
- Snap-to-button option

#### Key API
```gdscript
$RadialMenu.set_width_min(0.3)  # Inner radius (0-1)
$RadialMenu.set_width_max(0.8)  # Outer radius (0-1)
$RadialMenu.set_snap_enabled(true)
$RadialMenu.connect("selected", _on_selected)
```

### 3. Circular Container (Godot 3 only)

**Asset Library**: [Circular Container](https://godotengine.org/asset-library/asset/24)
**Note**: Only supports Godot 3.1, not updated for Godot 4

---

## Implementation Considerations for BiologiDex

### Requirements
1. **Center button** - Main action or logo
2. **5-6 surrounding buttons** - Camera, Dex, Feed, Social, Tree (already background), Settings
3. **Curved/segmented appearance** - Arc-shaped buttons
4. **Touch-friendly** - Minimum 44x44px touch targets
5. **Web export compatible** - Avoid instanced scene children issues

### Recommended Architecture

```
Home (Node2D)
├── PaperCameraScene (tree background, pan/zoom)
│   └── WorldContent/ContentContainer
│       └── TreeVisualization
└── HomeUILayer (CanvasLayer, layer=10)
    └── Control (full rect anchors)
        └── RadialMenu (centered)
            ├── CenterButton (circular, in middle)
            └── RadialButtonContainer (custom Control)
                ├── RadialButton[0] - Camera
                ├── RadialButton[1] - Dex
                ├── RadialButton[2] - Feed
                ├── RadialButton[3] - Social
                └── RadialButton[4] - Settings
```

### File Structure Proposal

```
features/ui/components/radial_menu/
├── radial_menu.gd          # Container managing buttons
├── radial_menu.tscn        # Scene (minimal, avoid web export issues)
├── radial_button.gd        # Individual arc segment button
└── radial_menu.gdshader    # Optional: shader for smooth rendering
```

### Touch Target Sizing

For 5 buttons around a center:
- **Arc angle**: 72° (360° / 5)
- **Inner radius**: ~80px (small enough for center button)
- **Outer radius**: ~200px (provides adequate touch area)
- **Gap**: ~3-5° between segments

At minimum, the arc length at the midpoint radius should be ≥44px:
- Midpoint radius = (80 + 200) / 2 = 140px
- Arc length = 140 × (72° × π/180°) ≈ 176px (well above minimum)

### Animation Considerations

```gdscript
# Reveal animation (similar to KidsCanCode approach)
func show_menu() -> void:
    var tween := create_tween()
    tween.set_parallel(true)

    for i in range(_buttons.size()):
        var button := _buttons[i]
        button.modulate.a = 0.0
        button.scale = Vector2(0.5, 0.5)

        tween.tween_property(button, "modulate:a", 1.0, 0.3)\
             .set_delay(i * 0.05)
        tween.tween_property(button, "scale", Vector2.ONE, 0.3)\
             .set_delay(i * 0.05)\
             .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
```

---

## Summary

**Best approach for BiologiDex**: Custom `Control` subclass with `_draw()` for rendering and `_has_point()` for hit detection.

**Rationale**:
1. No external dependencies
2. Full control over appearance (curved segments, colors, animations)
3. Integrates naturally with existing Godot patterns
4. Web export compatible (create nodes programmatically)
5. Can be styled to match existing BiologiDex aesthetic

**Alternative**: If development time is critical, the `jesuisse/godot-radial-menu-control` addon provides a solid, feature-complete solution that can be customized.

---

## References

### Official Documentation
- [Custom Drawing in 2D](https://docs.godotengine.org/en/stable/tutorials/2d/custom_drawing_in_2d.html)
- [Custom GUI Controls](https://docs.godotengine.org/en/stable/tutorials/ui/custom_gui_controls.html)
- [Control Class](https://docs.godotengine.org/en/stable/classes/class_control.html)
- [TextureButton Class](https://docs.godotengine.org/en/stable/classes/class_texturebutton.html)

### Tutorials
- [Radial Popup Menu - KidsCanCode Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/ui/radial_menu/index.html)

### Addons
- [godot-radial-menu-control (GitHub)](https://github.com/jesuisse/godot-radial-menu-control)
- [tavurth/godot-radial-menu (GitHub)](https://github.com/tavurth/godot-radial-menu)
- [Radial Menu Control - Asset Library](https://godotengine.org/asset-library/asset/3469)

### Shaders
- [Procedural Circular Progress Bar](https://godotshaders.com/shader/procedural-circular-progress-bar/)
- [Circle Shader](https://godotshaders.com/shader/circle-shader/)

### GitHub Issues (Known Bugs)
- [TextureButton click mask scaling - #91898](https://github.com/godotengine/godot/issues/91898)
- [Control._has_point description outdated - #72283](https://github.com/godotengine/godot/issues/72283)
- [Instanced scene children bug (web export) - #101975](https://github.com/godotengine/godot/issues/101975)
