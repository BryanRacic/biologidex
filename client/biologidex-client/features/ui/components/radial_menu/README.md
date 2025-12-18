# RadialMenu Component

A reusable radial menu component for Godot 4.5 featuring a large circular center button surrounded by arc-segment ring buttons.

## Overview

The RadialMenu provides a visually appealing and touch-friendly navigation interface. It consists of:

- **RadialCenterButton**: Large circular button for the primary action
- **RadialButtonRing**: Arc-segment buttons arranged in a ring around the center
- **RadialMenu**: Container that orchestrates both components

## Architecture

```
RadialMenu (Control)
├── CenterButton (RadialCenterButton) - created programmatically
└── ButtonRing (RadialButtonRing) - created programmatically
```

Components are created programmatically in `_ready()` for web export compatibility (GitHub #101975 workaround).

## Usage

### Basic Usage

```gdscript
# Create and add to scene
var menu := RadialMenu.new()
parent.add_child(menu)

# Configure center button
menu.set_center_button("upload", "Upload\nImage")

# Configure ring buttons
menu.add_ring_button("feed", "Dex Feed")
menu.add_ring_button("dex", "View Dex")
menu.add_ring_button("social", "Friends")
menu.add_ring_button("settings", "Settings")

# Connect signals
menu.center_pressed.connect(_on_upload_pressed)
menu.button_pressed.connect(_on_nav_button_pressed)

func _on_upload_pressed():
    print("Upload button pressed!")

func _on_nav_button_pressed(button_id: String):
    match button_id:
        "feed": navigate_to_feed()
        "dex": navigate_to_dex()
        # ...
```

### Configuration via Setup

```gdscript
var center := {"id": "upload", "text": "Upload", "visible": true, "disabled": false}
var ring := [
    {"id": "feed", "text": "Feed", "visible": true, "disabled": false},
    {"id": "dex", "text": "Dex", "visible": true, "disabled": false},
]
menu.setup(center, ring)
```

### Customizing Appearance

```gdscript
# Layout dimensions
menu.center_radius = 120.0
menu.ring_inner_radius = 150.0
menu.ring_outer_radius = 300.0
menu.ring_gap_angle = 0.08  # radians

# Colors
menu.center_normal_color = Color(0.15, 0.15, 0.18, 0.95)
menu.center_hover_color = Color(0.25, 0.25, 0.35, 0.95)
menu.ring_normal_color = Color(0.2, 0.2, 0.25, 0.85)

# Text
menu.text_color = Color.BLACK
menu.center_font_size = 48
menu.ring_font_size = 32
menu.font = load("res://path/to/font.ttf")
```

## Signals

### RadialMenu

| Signal | Parameters | Description |
|--------|------------|-------------|
| `center_pressed` | None | Center button was pressed |
| `button_pressed` | `button_id: String` | Ring button was pressed |
| `button_hovered` | `button_id: String` | Button hover started |
| `button_unhovered` | None | Button hover ended |

### RadialCenterButton

| Signal | Parameters | Description |
|--------|------------|-------------|
| `pressed` | None | Button was pressed |
| `hover_changed` | `is_hovered: bool` | Hover state changed |

### RadialButtonRing

| Signal | Parameters | Description |
|--------|------------|-------------|
| `segment_pressed` | `index: int, button_id: String` | Segment was pressed |
| `segment_hovered` | `index: int, button_id: String` | Segment hover started |
| `segment_unhovered` | None | Segment hover ended |

## Export Variables

### Layout

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `center_radius` | float | 120.0 | Radius of center button |
| `ring_inner_radius` | float | 150.0 | Inner edge of ring |
| `ring_outer_radius` | float | 300.0 | Outer edge of ring |
| `ring_gap_angle` | float | 0.08 | Gap between segments (radians) |
| `start_angle` | float | -PI/2 | Start angle (12 o'clock) |

### Center Button Colors

| Variable | Type | Default |
|----------|------|---------|
| `center_normal_color` | Color | (0.15, 0.15, 0.18, 0.95) |
| `center_hover_color` | Color | (0.25, 0.25, 0.35, 0.95) |
| `center_pressed_color` | Color | (0.1, 0.1, 0.12, 1.0) |
| `center_border_width` | float | 3.0 |
| `center_border_color` | Color | (0.4, 0.4, 0.5, 0.8) |

### Ring Button Colors

| Variable | Type | Default |
|----------|------|---------|
| `ring_normal_color` | Color | (0.2, 0.2, 0.25, 0.85) |
| `ring_hover_color` | Color | (0.3, 0.3, 0.4, 0.95) |
| `ring_pressed_color` | Color | (0.1, 0.1, 0.15, 1.0) |
| `ring_border_width` | float | 2.0 |
| `ring_border_color` | Color | (0.4, 0.4, 0.5, 0.6) |

### Text

| Variable | Type | Default |
|----------|------|---------|
| `text_color` | Color | Black |
| `center_font_size` | int | 48 |
| `ring_font_size` | int | 32 |
| `font` | Font | null (uses fallback) |

### Animation

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `animate_on_ready` | bool | true | Animate reveal on ready |
| `reveal_duration` | float | 0.3 | Duration of reveal animation |

## Touch Target Validation

The component ensures adequate touch targets (minimum 44px per Apple HIG / Material Design):

| Buttons | Segment Angle | Arc Length at Midpoint |
|---------|---------------|------------------------|
| 4 | ~85 deg | ~335px |
| 6 | ~55 deg | ~218px |
| 8 | ~40 deg | ~160px |

All configurations exceed the 44px minimum touch target.

## Web Export Compatibility

This component follows web export best practices:

1. **Programmatic creation**: Components created in `_ready()` instead of .tscn children
2. **No unique name lookups**: Uses explicit references instead of `%NodeName`
3. **Guard viewport calls**: Checks `is_inside_tree()` before viewport operations

## Files

```
features/ui/components/radial_menu/
├── radial_menu.gd            # Main container class
├── radial_menu.tscn          # Minimal scene file
├── radial_button_ring.gd     # Arc segment ring component
├── radial_center_button.gd   # Circular center button
└── README.md                 # This file
```

## Implementation Details

### Custom Drawing

Both `RadialCenterButton` and `RadialButtonRing` use `_draw()` for rendering:

- **Center button**: `draw_circle()` + `draw_arc()` for border
- **Ring segments**: `draw_polygon()` with computed arc points

### Hit Detection

Custom `_has_point()` implementation:

- **Center button**: Distance check from center
- **Ring segments**: Polar coordinate check (radius + angle)

### Input Handling

`_gui_input()` processes mouse/touch events:

- Tracks hover state for visual feedback
- Emits signals on press/release
- Uses `accept_event()` to prevent propagation

## Example: Home Scene Integration

```gdscript
func _build_radial_menu() -> void:
    _radial_menu = RadialMenu.new()
    _radial_menu.name = "RadialMenu"

    # Configure dimensions
    _radial_menu.center_radius = 120.0
    _radial_menu.ring_inner_radius = 150.0
    _radial_menu.ring_outer_radius = 300.0

    # Center at world origin
    _radial_menu.position = Vector2(-300, -300)

    # Add to parent
    _home_ui.add_child(_radial_menu)

    # Configure buttons
    _radial_menu.set_center_button("camera", "Upload\nImage")
    _radial_menu.add_ring_button("feed", "Dex Feed")
    _radial_menu.add_ring_button("dex", "View Dex")
    _radial_menu.add_ring_button("social", "Friends")
    _radial_menu.add_ring_button("settings", "Settings")

    # Connect signals
    _radial_menu.center_pressed.connect(_on_camera_pressed)
    _radial_menu.button_pressed.connect(_on_radial_button_pressed)
```
