# Radial Menu Implementation Plan for BiologiDex Home Screen

## Executive Summary

This document outlines a comprehensive plan to replace the current linear VBoxContainer button layout on the BiologiDex home screen with a dynamic radial menu featuring a prominent center "Upload Image" button surrounded by evenly-distributed circular navigation buttons.

**Design Approach**: Custom Control with `_draw()` and `_has_point()` override (Approach #1 from research)

**Key Benefits**:
- Full control over appearance and behavior
- No external dependencies
- Native Godot implementation
- Web export compatible
- Reusable across scenes

---

## 1. Current State Analysis

### Current Home Scene Architecture (`scenes/home/home.tscn`)

```
Home (Node2D)
├── PaperCameraScene (tree background, pan/zoom)
│   └── WorldContent/ContentContainer
│       ├── TreeVisualization
│       └── HomeUI (WorldSpaceUI)
│           └── CenterContainer (1600x1200)
│               └── VBoxContainer
│                   ├── TitleLabel ("BiologiDex")
│                   ├── Separator
│                   ├── Spacers
│                   ├── Upload Image Button
│                   ├── Dex Feed Button
│                   ├── View Dex Button
│                   ├── Friends Button
│                   └── Menu Button (hidden)
└── HomeOverlayLayer (CanvasLayer, layer=10)
    └── Control → TopRightContainer → RecenterButton
```

### Current Buttons (from `home.gd:221-241`)
| Button | Text | Navigation |
|--------|------|------------|
| camera_button | "Upload Image" | `camera.tscn` |
| feed_button | "Dex Feed" | `dex_feed.tscn` |
| dex_button | "View Dex" | `dex.tscn` |
| social_button | "Friends" | `social.tscn` |
| menu_button | "Menu" | Logout (hidden) |

### Current Styling
- **Font**: Fraunces Italic Variable (theme.tres)
- **Font Size**: 124px for buttons
- **Colors**: Black text on transparent/borderless backgrounds
- **Title**: 246px Fraunces font

---

## 2. Target Architecture

### Visual Design

```
                    [Dex Feed]
                        ●
                       /
                      /
        [Friends]    /     [View Dex]
            ●-------●-------●
                  /   \
                 /     \
                /  ◉◉◉  \
               |  ◉ ◉ ◉  |  ← Center "Upload" button (large circular)
                \  ◉◉◉  /
                 \     /
                  \   /
            ●-------●-------●
           /         \
          /           \
    [Settings]       [Tree View]
         ●               ●
```

**Center Button**: Large circular button for primary action ("Upload Image")
**Surrounding Buttons**: Evenly distributed in a ring around center

### Node Hierarchy (Proposed)

```
Home (Node2D)
├── PaperCameraScene
│   └── WorldContent/ContentContainer
│       ├── TreeVisualization
│       └── HomeUI (WorldSpaceUI)
│           ├── TitleLabel ("BiologiDex") - positioned above radial menu
│           └── RadialMenu (custom Control)
│               ├── CenterButton (TextureButton or custom circular)
│               └── RadialButtonRing (custom Control with _draw())
│                   └── [No child nodes - draws arc segments directly]
└── HomeOverlayLayer (CanvasLayer, layer=10)
    └── Control → TopRightContainer → RecenterButton
```

---

## 3. Component Architecture

### 3.1 File Structure

```
features/ui/components/radial_menu/
├── radial_menu.gd            # RadialMenu (Control) - container orchestrating components
├── radial_menu.tscn          # Minimal scene (web export workaround)
├── radial_button_ring.gd     # RadialButtonRing (Control) - draws/handles arc segments
├── radial_center_button.gd   # RadialCenterButton (Control) - circular center button
└── README.md                 # Component documentation
```

### 3.2 Class Hierarchy

```
Control
├── RadialMenu (radial_menu.gd)
│   └── Container orchestrating center button + ring
│
├── RadialButtonRing (radial_button_ring.gd)
│   └── Draws arc segments, handles hit detection for ring
│
└── RadialCenterButton (radial_center_button.gd)
    └── Circular center button with custom drawing
```

---

## 4. Component Specifications

### 4.1 RadialMenu (Container)

**Purpose**: Orchestrates the radial menu layout and manages button configuration.

```gdscript
extends Control
class_name RadialMenu

## Signals
signal button_pressed(button_id: String)
signal center_pressed()

## Export Variables
@export_group("Layout")
@export var center_radius: float = 120.0          # Radius of center button
@export var ring_inner_radius: float = 140.0      # Inner radius of button ring
@export var ring_outer_radius: float = 280.0      # Outer radius of button ring
@export var ring_gap_angle: float = 0.08          # Gap between segments (radians)
@export var start_angle: float = -PI / 2          # Start at 12 o'clock

@export_group("Appearance")
@export var center_color: Color = Color(0.15, 0.15, 0.18, 0.95)
@export var ring_color: Color = Color(0.2, 0.2, 0.25, 0.85)
@export var hover_color: Color = Color(0.3, 0.3, 0.4, 0.95)
@export var pressed_color: Color = Color(0.1, 0.1, 0.15, 1.0)
@export var text_color: Color = Color.BLACK
@export var font_size: int = 32

@export_group("Animation")
@export var hover_scale: float = 1.05
@export var press_scale: float = 0.95
@export var animation_duration: float = 0.15

## Button Configuration (set via code)
var _center_config: Dictionary = {}
var _ring_buttons: Array[Dictionary] = []

## Child Components
var _center_button: RadialCenterButton = null
var _button_ring: RadialButtonRing = null
```

**Key Methods**:
- `setup(center_config: Dictionary, ring_configs: Array[Dictionary])` - Configure all buttons
- `set_center_button(id: String, text: String, icon: Texture2D = null)` - Configure center
- `add_ring_button(id: String, text: String, icon: Texture2D = null)` - Add ring button
- `clear_ring_buttons()` - Remove all ring buttons
- `get_button_count() -> int` - Number of ring buttons

**Button Config Dictionary**:
```gdscript
{
    "id": "camera",           # Unique identifier (emitted in signal)
    "text": "Upload",         # Display text
    "icon": Texture2D,        # Optional icon
    "visible": true,          # Whether button is shown
    "disabled": false         # Whether button is interactive
}
```

### 4.2 RadialCenterButton (Center Button)

**Purpose**: Large circular button for the primary action.

```gdscript
extends Control
class_name RadialCenterButton

signal pressed()
signal hover_changed(is_hovered: bool)

@export var radius: float = 120.0
@export var normal_color: Color = Color(0.15, 0.15, 0.18, 0.95)
@export var hover_color: Color = Color(0.25, 0.25, 0.35, 0.95)
@export var pressed_color: Color = Color(0.1, 0.1, 0.12, 1.0)
@export var border_width: float = 3.0
@export var border_color: Color = Color(0.4, 0.4, 0.5, 0.8)
@export var text: String = "Upload"
@export var text_color: Color = Color.BLACK
@export var font_size: int = 48
@export var icon: Texture2D = null
@export var icon_size: Vector2 = Vector2(64, 64)

var _is_hovered: bool = false
var _is_pressed: bool = false
```

**Key Methods**:
- `_draw()` - Draw circular button with text/icon
- `_has_point(point: Vector2) -> bool` - Circular hit detection
- `_gui_input(event: InputEvent)` - Handle mouse/touch input
- `set_text(new_text: String)` - Update display text
- `set_icon(new_icon: Texture2D)` - Update icon

**Drawing Implementation**:
```gdscript
func _draw() -> void:
    var center := size / 2
    var color := normal_color
    if _is_pressed:
        color = pressed_color
    elif _is_hovered:
        color = hover_color

    # Draw filled circle
    draw_circle(center, radius, color)

    # Draw border
    draw_arc(center, radius, 0, TAU, 64, border_color, border_width, true)

    # Draw text/icon centered
    _draw_content(center)

func _has_point(point: Vector2) -> bool:
    var center := size / 2
    return point.distance_to(center) <= radius
```

### 4.3 RadialButtonRing (Arc Segment Ring)

**Purpose**: Draws and handles input for arc-segment buttons arranged in a ring.

```gdscript
extends Control
class_name RadialButtonRing

signal segment_pressed(index: int, button_id: String)
signal segment_hovered(index: int, button_id: String)
signal segment_unhovered()

@export var inner_radius: float = 140.0
@export var outer_radius: float = 280.0
@export var gap_angle: float = 0.08          # Radians between segments
@export var start_angle: float = -PI / 2     # Start at 12 o'clock

@export var normal_color: Color = Color(0.2, 0.2, 0.25, 0.85)
@export var hover_color: Color = Color(0.3, 0.3, 0.4, 0.95)
@export var pressed_color: Color = Color(0.1, 0.1, 0.15, 1.0)
@export var disabled_color: Color = Color(0.15, 0.15, 0.15, 0.5)
@export var text_color: Color = Color.BLACK
@export var font_size: int = 32

## Button data
var _buttons: Array[Dictionary] = []
var _hovered_index: int = -1
var _pressed_index: int = -1

## Precomputed segment angles
var _segment_angles: Array[Dictionary] = []  # [{start, end, mid}]
```

**Key Methods**:
- `setup_buttons(buttons: Array[Dictionary])` - Configure ring buttons
- `_compute_segment_angles()` - Precompute angles for N segments
- `_draw()` - Draw all arc segments
- `_draw_arc_segment(...)` - Draw single segment with fill
- `_has_point(point: Vector2) -> bool` - Always true (handles own hit detection)
- `_gui_input(event: InputEvent)` - Determine which segment was hit
- `_get_segment_at_point(point: Vector2) -> int` - Return segment index or -1

**Arc Segment Drawing Algorithm**:
```gdscript
func _draw_arc_segment(center: Vector2, inner_r: float, outer_r: float,
                       angle_from: float, angle_to: float, color: Color) -> void:
    var nb_points := 32
    var points := PackedVector2Array()

    # Outer arc (clockwise)
    for i in range(nb_points + 1):
        var angle := angle_from + i * (angle_to - angle_from) / nb_points
        points.push_back(center + Vector2(cos(angle), sin(angle)) * outer_r)

    # Inner arc (counter-clockwise to close shape)
    for i in range(nb_points, -1, -1):
        var angle := angle_from + i * (angle_to - angle_from) / nb_points
        points.push_back(center + Vector2(cos(angle), sin(angle)) * inner_r)

    draw_polygon(points, PackedColorArray([color]))
```

**Hit Detection Algorithm**:
```gdscript
func _get_segment_at_point(point: Vector2) -> int:
    var center := size / 2
    var local := point - center
    var distance := local.length()

    # Check if within ring radius
    if distance < inner_radius or distance > outer_radius:
        return -1

    # Calculate angle
    var angle := atan2(local.y, local.x)
    angle = fposmod(angle, TAU)  # Normalize to [0, TAU)

    # Find which segment contains this angle
    for i in range(_segment_angles.size()):
        var seg := _segment_angles[i]
        var seg_start := fposmod(seg.start, TAU)
        var seg_end := fposmod(seg.end, TAU)

        # Handle wrap-around case
        if seg_start <= seg_end:
            if angle >= seg_start and angle <= seg_end:
                return i
        else:
            if angle >= seg_start or angle <= seg_end:
                return i

    return -1
```

---

## 5. Sizing & Touch Target Calculations

### Requirements
- **Minimum touch target**: 44×44 pixels (Apple HIG / Material Design)
- **Primary action (center)**: Larger for emphasis
- **Ring segments**: Adequate arc length at midpoint

### Proposed Dimensions (World-Space Units)

| Property | Value | Rationale |
|----------|-------|-----------|
| Center button radius | 120 | Large, prominent primary action |
| Ring inner radius | 150 | 30px gap from center edge |
| Ring outer radius | 300 | 150px ring width for comfortable touch |
| Ring midpoint | 225 | At midpoint radius |

### Arc Length Validation

For N buttons, each segment spans `(TAU - N * gap) / N` radians.

**With 4 buttons** (gap = 0.08 rad ≈ 4.6°):
- Segment angle = (2π - 4 × 0.08) / 4 = 1.49 rad ≈ 85°
- Arc length at midpoint (225px) = 225 × 1.49 ≈ **335px** ✓

**With 6 buttons**:
- Segment angle = (2π - 6 × 0.08) / 6 = 0.97 rad ≈ 55°
- Arc length at midpoint = 225 × 0.97 ≈ **218px** ✓

**With 8 buttons**:
- Segment angle = (2π - 8 × 0.08) / 8 = 0.71 rad ≈ 40°
- Arc length at midpoint = 225 × 0.71 ≈ **160px** ✓

All configurations exceed the 44px minimum touch target.

### Scaling for Display

Since the menu is in world-space (inside PaperCameraScene's content_container), it will scale with the camera zoom. At default `initial_zoom = 1.5`:

- Effective center radius on screen: 120 × 1.5 = **180px**
- Effective ring outer radius: 300 × 1.5 = **450px**
- Total menu diameter: ~900px on 1280×720 viewport

This is appropriate for full-screen navigation.

---

## 6. Home Scene Integration

### 6.1 Modified Scene Structure

```
Home (Node2D)
├── PaperCameraScene
│   └── WorldContent/ContentContainer
│       ├── TreeVisualization (background)
│       └── HomeUI (WorldSpaceUI, centered at origin)
│           ├── TitleContainer (positioned above menu)
│           │   └── TitleLabel ("BiologiDex")
│           └── RadialMenu (centered at world origin)
└── HomeOverlayLayer (CanvasLayer, layer=10)
    └── Control → TopRightContainer → RecenterButton
```

### 6.2 home.gd Modifications

**Replace `_build_home_buttons()` with**:

```gdscript
func _build_radial_menu() -> void:
    """Build the radial menu for home navigation."""
    # Create title above radial menu (positioned higher in world space)
    _create_title_label()

    # Create RadialMenu programmatically (web export compatible)
    var radial_menu := RadialMenu.new()
    radial_menu.name = "RadialMenu"

    # Configure appearance to match theme
    radial_menu.center_radius = 120.0
    radial_menu.ring_inner_radius = 150.0
    radial_menu.ring_outer_radius = 300.0
    radial_menu.text_color = Color.BLACK
    radial_menu.font_size = 36

    # Add to world-space UI (will be centered at origin)
    _home_ui.add_child(radial_menu)

    # Configure center button
    radial_menu.set_center_button("camera", "Upload\nImage")

    # Configure ring buttons (will be evenly distributed)
    radial_menu.add_ring_button("feed", "Dex Feed")
    radial_menu.add_ring_button("dex", "View Dex")
    radial_menu.add_ring_button("social", "Friends")
    radial_menu.add_ring_button("settings", "Settings")

    # Connect signals
    radial_menu.center_pressed.connect(_on_camera_pressed)
    radial_menu.button_pressed.connect(_on_radial_button_pressed)

    _radial_menu = radial_menu


func _on_radial_button_pressed(button_id: String) -> void:
    """Handle radial menu button press."""
    match button_id:
        "feed":
            _on_feed_pressed()
        "dex":
            _on_dex_pressed()
        "social":
            _on_social_pressed()
        "settings":
            _on_menu_pressed()  # Reuse existing handler


func _create_title_label() -> void:
    """Create title label positioned above radial menu."""
    var title_container := Control.new()
    title_container.name = "TitleContainer"
    title_container.custom_minimum_size = Vector2(1400, 300)
    title_container.size = Vector2(1400, 300)
    title_container.position = Vector2(-700, -700)  # Above menu center
    title_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _home_ui.add_child(title_container)

    title_label = Label.new()
    title_label.name = "TitleLabel"
    title_label.text = "BiologiDex"
    title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    title_label.anchors_preset = Control.PRESET_FULL_RECT

    var font = load("res://resources/fonts/Fraunces/Fraunces-VariableFont_SOFT,WONK,opsz,wght.ttf")
    var label_settings = LabelSettings.new()
    label_settings.font = font
    label_settings.font_size = 200
    label_settings.font_color = Color.BLACK
    title_label.label_settings = label_settings

    title_container.add_child(title_label)
```

### 6.3 Variables to Update in home.gd

**Remove**:
```gdscript
var camera_button: Button = null
var dex_button: Button = null
var feed_button: Button = null
var social_button: Button = null
var menu_button: Button = null
```

**Add**:
```gdscript
var _radial_menu: RadialMenu = null
```

---

## 7. Text Rendering on Arc Segments

### Challenge
Text on curved segments is complex. Options:

1. **Centered text at segment midpoint** (Recommended)
   - Simple, readable
   - Text positioned at radial midpoint of segment
   - Rotated to be roughly tangent or radial

2. **Curved text along arc** (Complex)
   - Each character positioned and rotated individually
   - Performance overhead
   - Can be hard to read

3. **Icon + short label** (Alternative)
   - Icon centered in segment
   - Small label below icon
   - Works well for compact designs

### Recommended Approach: Centered Text

```gdscript
func _draw_segment_label(segment_index: int) -> void:
    var seg := _segment_angles[segment_index]
    var mid_angle: float = seg.mid
    var mid_radius := (inner_radius + outer_radius) / 2.0
    var center := size / 2

    # Position at segment center
    var label_pos := center + Vector2(cos(mid_angle), sin(mid_angle)) * mid_radius

    # Get text
    var btn := _buttons[segment_index]
    var text: String = btn.get("text", "")

    # Draw text centered at position
    var font: Font = ThemeDB.fallback_font
    var font_size := self.font_size
    var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)

    # Option A: Horizontal text (easier to read)
    draw_string(font, label_pos - text_size / 2, text, HORIZONTAL_ALIGNMENT_CENTER,
                -1, font_size, text_color)

    # Option B: Radially-oriented text (uncomment to use)
    # push_transform(Transform2D().rotated(mid_angle + PI/2).translated(label_pos))
    # draw_string(font, -text_size / 2, text, ...)
    # pop_transform()
```

---

## 8. Animation Specifications

### 8.1 Hover Animation

```gdscript
## On segment hover
func _animate_hover(segment_index: int, entering: bool) -> void:
    # Could scale the segment slightly or brighten
    # For custom drawing, just change color and queue_redraw()
    if entering:
        _hovered_index = segment_index
    else:
        _hovered_index = -1
    queue_redraw()
```

### 8.2 Press Animation

```gdscript
func _animate_press(segment_index: int, pressed: bool) -> void:
    if pressed:
        _pressed_index = segment_index
        # Optional: Play haptic feedback on mobile
    else:
        _pressed_index = -1
    queue_redraw()
```

### 8.3 Menu Reveal Animation (Optional Enhancement)

For a polished feel when the home screen loads:

```gdscript
func _ready() -> void:
    # Start with menu invisible
    modulate.a = 0.0
    scale = Vector2(0.8, 0.8)

    # Animate in
    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_property(self, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_OUT)
    tween.tween_property(self, "scale", Vector2.ONE, 0.3) \
         .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
```

---

## 9. Web Export Compatibility

### Critical Considerations (from CLAUDE.md)

1. **GitHub #101975**: Children added to instanced scenes in .tscn files don't load on web export
   - **Solution**: Create RadialMenu programmatically in `home.gd`, not in .tscn

2. **Unique name lookups can fail**: `%NodeName` returns null on web
   - **Solution**: Use explicit paths or store references from creation

3. **Control.size unreliable**: Dynamically created Controls may report wrong size
   - **Solution**: Set `custom_minimum_size` and use that for calculations

4. **get_viewport_rect() timing**: Can fail before node is in tree
   - **Solution**: Guard with `if not is_inside_tree(): return`

### Implementation Pattern

```gdscript
# In home.gd
func _setup_world_space_ui() -> void:
    _home_ui = WorldSpaceUI.new()
    _home_ui.name = "HomeUI"
    _home_ui.anchor_position = Vector2.ZERO
    _paper_camera.content_container.add_child(_home_ui)

    # Create radial menu PROGRAMMATICALLY (not from scene)
    _build_radial_menu()

func _build_radial_menu() -> void:
    # All creation done in code, not .tscn
    var radial_menu := RadialMenu.new()
    # ... configure and add as shown in section 6.2
```

---

## 10. Reusability Considerations

### Making the Component Scene-Agnostic

The RadialMenu should work in any context:

1. **No hardcoded navigation** - Emit signals, let parent handle
2. **Configurable buttons** - Runtime configuration via `setup()` or individual methods
3. **Theming support** - Accept colors/fonts as export vars or from Theme
4. **Size flexibility** - Accept radius/size parameters

### Usage in Other Scenes (Example)

```gdscript
# In a different scene (e.g., quick action popup)
var action_menu := RadialMenu.new()
action_menu.center_radius = 80.0
action_menu.ring_inner_radius = 100.0
action_menu.ring_outer_radius = 200.0

action_menu.set_center_button("confirm", "OK")
action_menu.add_ring_button("edit", "Edit")
action_menu.add_ring_button("delete", "Delete")
action_menu.add_ring_button("share", "Share")

action_menu.button_pressed.connect(_on_action_selected)
add_child(action_menu)
```

---

## 11. Implementation Phases

### Phase 1: Core Components (Foundation)

**Files to create**:
- `features/ui/components/radial_menu/radial_center_button.gd`
- `features/ui/components/radial_menu/radial_button_ring.gd`

**Tasks**:
1. Implement `RadialCenterButton` with `_draw()`, `_has_point()`, `_gui_input()`
2. Implement `RadialButtonRing` with arc segment drawing and hit detection
3. Test each component in isolation with debug scenes

**Validation**:
- Center button draws correctly and responds to hover/press
- Ring segments draw with proper gaps
- Hit detection works accurately in ring

### Phase 2: Container Integration

**Files to create**:
- `features/ui/components/radial_menu/radial_menu.gd`
- `features/ui/components/radial_menu/radial_menu.tscn` (minimal)

**Tasks**:
1. Implement `RadialMenu` container that composes center + ring
2. Add configuration API (`setup()`, `add_ring_button()`, etc.)
3. Wire up signals from children to container signals
4. Add text rendering to segments

**Validation**:
- Menu displays correctly with configurable button count
- All buttons are interactive
- Signals emit correctly

### Phase 3: Home Scene Integration

**Files to modify**:
- `scenes/home/home.gd`
- `scenes/home/home.tscn` (remove old UI, may be minimal changes)

**Tasks**:
1. Replace `_build_home_buttons()` with `_build_radial_menu()`
2. Connect radial menu signals to navigation handlers
3. Position title label appropriately
4. Test with tree background

**Validation**:
- Home screen displays radial menu
- All navigation works correctly
- Menu pans with tree (world-space)
- RecenterButton still functions

### Phase 4: Polish & Testing

**Tasks**:
1. Add reveal animation on scene load
2. Fine-tune colors/sizing for visual appeal
3. Test on web export (critical!)
4. Test touch interactions on mobile
5. Add any missing hover/press states

**Validation**:
- Works in editor, desktop, and web export
- Touch targets are adequate
- Animations feel smooth
- No console errors or warnings

---

## 12. Testing Checklist

### Functional Tests
- [ ] Center button press navigates to camera scene
- [ ] Each ring button navigates to correct scene
- [ ] Buttons can be added/removed dynamically
- [ ] Menu works with 2, 4, 6, 8 ring buttons

### Visual Tests
- [ ] Arc segments render with correct gaps
- [ ] Colors match theme (dark background, black text)
- [ ] Text is readable on all segments
- [ ] Hover states are visible
- [ ] Press states provide feedback

### Platform Tests
- [ ] Works in Godot editor
- [ ] Works in desktop export
- [ ] **Works in web export** (critical)
- [ ] Touch interactions work on mobile web

### Integration Tests
- [ ] Menu pans with tree background
- [ ] RecenterButton works with radial menu
- [ ] No overlap with title label
- [ ] Zoom doesn't break layout

### Edge Cases
- [ ] Rapid clicking doesn't cause issues
- [ ] Resize/orientation change handled
- [ ] Empty button config doesn't crash

---

## 13. Styling Reference

### Colors (from theme.tres and app aesthetic)

```gdscript
# Background colors (dark, semi-transparent for world-space)
const BG_NORMAL = Color(0.15, 0.15, 0.18, 0.95)
const BG_HOVER = Color(0.25, 0.25, 0.35, 0.95)
const BG_PRESSED = Color(0.1, 0.1, 0.12, 1.0)
const BG_DISABLED = Color(0.15, 0.15, 0.15, 0.5)

# Text colors
const TEXT_COLOR = Color(0, 0, 0, 1)  # Black (matching theme Button font)
const TEXT_DISABLED = Color(0.5, 0.5, 0.5, 0.5)

# Border/accent
const BORDER_COLOR = Color(0.4, 0.4, 0.5, 0.8)
```

### Font

```gdscript
# Load Fraunces font for consistency with app
var font = load("res://resources/fonts/Fraunces/Fraunces-VariableFont_SOFT,WONK,opsz,wght.ttf")

# Or use theme-provided font
var font = ThemeDB.fallback_font
```

---

## 14. Dependencies & Prerequisites

### Required Existing Components
- `PaperCameraScene` - Camera/pan/zoom system
- `WorldSpaceUI` - Container for world-space positioning
- `NavigationManager` - Scene navigation autoload
- `theme.tres` - App theme with Fraunces font

### No External Dependencies
This implementation uses only built-in Godot features:
- `Control._draw()` for custom rendering
- `Control._has_point()` for hit detection
- `Control._gui_input()` for input handling
- `draw_polygon()`, `draw_arc()`, `draw_circle()`, `draw_string()` drawing primitives

---

## 15. Future Enhancements (Out of Scope)

1. **Submenu support** - Ring buttons could expand into sub-rings
2. **Icon support** - Add icons alongside or instead of text
3. **Gamepad support** - Navigate with D-pad/stick
4. **Keyboard shortcuts** - Number keys for quick access
5. **Context-aware buttons** - Different buttons based on state
6. **Haptic feedback** - Vibration on mobile devices

---

## Appendix A: Complete RadialButtonRing Implementation

```gdscript
extends Control
class_name RadialButtonRing

## Draws and handles arc-segment buttons in a ring formation.

signal segment_pressed(index: int, button_id: String)
signal segment_hovered(index: int, button_id: String)
signal segment_unhovered()

# =============================================================================
# Export Variables
# =============================================================================

@export_group("Ring Geometry")
@export var inner_radius: float = 150.0
@export var outer_radius: float = 300.0
@export var gap_angle: float = 0.08
@export var start_angle: float = -PI / 2

@export_group("Colors")
@export var normal_color: Color = Color(0.2, 0.2, 0.25, 0.85)
@export var hover_color: Color = Color(0.3, 0.3, 0.4, 0.95)
@export var pressed_color: Color = Color(0.1, 0.1, 0.15, 1.0)
@export var disabled_color: Color = Color(0.15, 0.15, 0.15, 0.5)

@export_group("Text")
@export var text_color: Color = Color.BLACK
@export var font_size: int = 32
@export var font: Font = null

# =============================================================================
# Internal State
# =============================================================================

var _buttons: Array[Dictionary] = []
var _segment_angles: Array[Dictionary] = []
var _hovered_index: int = -1
var _pressed_index: int = -1

# =============================================================================
# Public API
# =============================================================================

func setup_buttons(buttons: Array[Dictionary]) -> void:
    _buttons = buttons
    _compute_segment_angles()
    queue_redraw()


func add_button(config: Dictionary) -> void:
    _buttons.append(config)
    _compute_segment_angles()
    queue_redraw()


func clear_buttons() -> void:
    _buttons.clear()
    _segment_angles.clear()
    _hovered_index = -1
    _pressed_index = -1
    queue_redraw()


func get_button_count() -> int:
    return _buttons.size()

# =============================================================================
# Angle Computation
# =============================================================================

func _compute_segment_angles() -> void:
    _segment_angles.clear()
    var count := _buttons.size()
    if count == 0:
        return

    var total_gap := count * gap_angle
    var available_angle := TAU - total_gap
    var angle_per_segment := available_angle / count

    var current_angle := start_angle
    for i in range(count):
        var seg_start := current_angle + gap_angle / 2
        var seg_end := seg_start + angle_per_segment
        var seg_mid := (seg_start + seg_end) / 2

        _segment_angles.append({
            "start": seg_start,
            "end": seg_end,
            "mid": seg_mid
        })

        current_angle = seg_end + gap_angle / 2

# =============================================================================
# Drawing
# =============================================================================

func _draw() -> void:
    if _buttons.is_empty():
        return

    var center := size / 2

    for i in range(_buttons.size()):
        var btn := _buttons[i]
        if not btn.get("visible", true):
            continue

        var seg := _segment_angles[i]
        var color := _get_segment_color(i, btn)

        _draw_arc_segment(center, inner_radius, outer_radius,
                         seg.start, seg.end, color)

        _draw_segment_text(i, center, seg.mid, btn)


func _draw_arc_segment(center: Vector2, inner_r: float, outer_r: float,
                       angle_from: float, angle_to: float, color: Color) -> void:
    var nb_points := 32
    var points := PackedVector2Array()

    # Outer arc (clockwise)
    for i in range(nb_points + 1):
        var angle := angle_from + i * (angle_to - angle_from) / nb_points
        points.push_back(center + Vector2(cos(angle), sin(angle)) * outer_r)

    # Inner arc (counter-clockwise)
    for i in range(nb_points, -1, -1):
        var angle := angle_from + i * (angle_to - angle_from) / nb_points
        points.push_back(center + Vector2(cos(angle), sin(angle)) * inner_r)

    draw_polygon(points, PackedColorArray([color]))


func _draw_segment_text(index: int, center: Vector2, mid_angle: float,
                        btn: Dictionary) -> void:
    var text: String = btn.get("text", "")
    if text.is_empty():
        return

    var mid_radius := (inner_radius + outer_radius) / 2.0
    var pos := center + Vector2(cos(mid_angle), sin(mid_angle)) * mid_radius

    var draw_font: Font = font if font else ThemeDB.fallback_font
    var text_size := draw_font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER,
                                                -1, font_size)

    var text_pos := pos - Vector2(text_size.x / 2, -text_size.y / 4)
    draw_string(draw_font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER,
                -1, font_size, text_color)


func _get_segment_color(index: int, btn: Dictionary) -> Color:
    if btn.get("disabled", false):
        return disabled_color
    if index == _pressed_index:
        return pressed_color
    if index == _hovered_index:
        return hover_color
    return normal_color

# =============================================================================
# Input Handling
# =============================================================================

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            var seg := _get_segment_at_point(event.position)
            if event.pressed:
                if seg >= 0 and not _buttons[seg].get("disabled", false):
                    _pressed_index = seg
                    queue_redraw()
                    accept_event()
            else:
                if _pressed_index >= 0 and seg == _pressed_index:
                    var btn := _buttons[_pressed_index]
                    segment_pressed.emit(_pressed_index, btn.get("id", ""))
                _pressed_index = -1
                queue_redraw()
                accept_event()

    elif event is InputEventMouseMotion:
        var seg := _get_segment_at_point(event.position)
        if seg != _hovered_index:
            if seg >= 0 and not _buttons[seg].get("disabled", false):
                _hovered_index = seg
                var btn := _buttons[seg]
                segment_hovered.emit(seg, btn.get("id", ""))
            else:
                if _hovered_index >= 0:
                    segment_unhovered.emit()
                _hovered_index = -1
            queue_redraw()


func _get_segment_at_point(point: Vector2) -> int:
    var center := size / 2
    var local := point - center
    var distance := local.length()

    if distance < inner_radius or distance > outer_radius:
        return -1

    var angle := atan2(local.y, local.x)
    angle = fposmod(angle, TAU)

    for i in range(_segment_angles.size()):
        var seg := _segment_angles[i]
        var seg_start := fposmod(seg.start, TAU)
        var seg_end := fposmod(seg.end, TAU)

        if seg_start <= seg_end:
            if angle >= seg_start and angle <= seg_end:
                return i
        else:
            if angle >= seg_start or angle <= seg_end:
                return i

    return -1


func _has_point(point: Vector2) -> bool:
    return _get_segment_at_point(point) >= 0
```

---

## Appendix B: Key References

### Official Godot Documentation
- [Custom drawing in 2D](https://docs.godotengine.org/en/stable/tutorials/2d/custom_drawing_in_2d.html)
- [Custom GUI controls](https://docs.godotengine.org/en/stable/tutorials/ui/custom_gui_controls.html)
- [Control Class](https://docs.godotengine.org/en/stable/classes/class_control.html)

### Tutorials & Examples
- [Radial Popup Menu - KidsCanCode Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/ui/radial_menu/index.html)

### Existing Implementations (Reference Only)
- [jesuisse/godot-radial-menu-control](https://github.com/jesuisse/godot-radial-menu-control) - Feature-complete radial menu addon
- [tavurth/godot-radial-menu](https://github.com/tavurth/godot-radial-menu) - Shader-based approach

### BiologiDex Codebase
- `CLAUDE.md` - Project conventions and critical patterns
- `radial_button_research.md` - Initial research on approaches
- `features/tree_visualization/tree_visualization.gd` - Composition pattern reference
- `features/ui/components/recenter_button/recenter_button.gd` - Button component pattern
