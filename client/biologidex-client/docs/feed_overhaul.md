# Feed Overhaul Implementation Plan

## Executive Summary

This document outlines a comprehensive plan to overhaul the dex feed implementation to:
1. **Fix image sizing** - Ensure dex record images always fit within the viewport with configurable margins
2. **Add navigation arrows** - Implement prev/next auto-panning with arrow buttons (similar to tree view)

**Design Philosophy**: Prioritize Godot's native container-based sizing patterns over manual scale manipulation. Use composition and signal-based communication for clean architecture.

---

## Problem Analysis

### Issue 1: Images Exceed Viewport Bounds

**Current Behavior** (`feed_carousel_renderer.gd:218-227`):
```gdscript
func _get_base_item_width() -> float:
    return _container_width * 0.9  # 90% of container width

func _get_base_item_height() -> float:
    return _get_base_item_width() / DEFAULT_ASPECT_RATIO  # 1.33 (4:3)
```

**Problems**:
1. Uses fixed 4:3 aspect ratio for layout calculation
2. Actual images can be portrait (3:2, 9:16) or ultra-wide
3. Height is calculated from width only - never considers viewport height constraint
4. On narrow/tall viewports, images can extend far beyond visible area

**Example**: A 9:16 portrait image on a 720x1280 viewport:
- Current: width = 648px (90% of 720), height = 487px (648/1.33)
- Image loads with actual 9:16 ratio, AspectRatioContainer adjusts to 648x1152px
- Image extends 432px beyond viewport bottom

### Issue 2: No Navigation Arrows

The tree visualization has navigation arrows that allow quick traversal to connected nodes. The feed lacks equivalent functionality for navigating between entries, forcing users to scroll manually.

---

## Solution Overview

### Sizing Solution: Dual-Constraint Fit Algorithm

Calculate maximum dimensions that fit within viewport bounds, respecting both width AND height:

```
max_width = viewport_width - (2 * horizontal_margin)
max_height = viewport_height - (2 * vertical_margin)

# For each image with actual aspect ratio:
scale_by_width = max_width / image_width
scale_by_height = max_height / image_height
actual_scale = min(scale_by_width, scale_by_height)

final_width = image_width * actual_scale
final_height = image_height * actual_scale
```

### Navigation Solution: FeedNavigationArrows

Create a simplified arrow system for the feed:
- Two arrows (up/down) fixed on the right side of screen
- Arrows visible when entries exist above/below current view
- Click triggers animated pan to center on prev/next entry
- Follow TreeNavigationArrows pattern for pooling and input handling

---

## Detailed Implementation Plan

### Phase 0: Shared Arrow Configuration Base (DRY Refactor)

Before creating FeedConfig, extract common arrow properties shared between tree and feed navigation into a base class. This follows DRY principles while acknowledging that most logic is context-specific.

**Analysis**: TreeArrowConfig and FeedConfig share only 3 properties (~30 lines):
- `size` (arrow icon size)
- `opacity` (0.0-1.0)
- `color` (tint color)

The remaining properties are domain-specific (tree: edge fractions, diff circle padding; feed: margins, spacing).

**Create `navigation_arrow_config_base.gd`**

```gdscript
## File: features/ui/components/navigation_arrow_config_base.gd
class_name NavigationArrowConfigBase
extends RefCounted

## Base configuration for navigation arrows.
## Provides common appearance settings shared between Tree and Feed arrows.
## Subclasses add domain-specific properties.
##
## Uses signal-based invalidation pattern for reactive updates.

signal config_changed

# =============================================================================
# Arrow Appearance (shared across all navigation arrow types)
# =============================================================================

## Size of arrow buttons (pixels for UI, tree-local units for tree)
var size: float = 48.0:
    set(value):
        if abs(size - value) > 0.1:
            size = value
            config_changed.emit()

## Opacity of arrow buttons (0.0 - 1.0)
var opacity: float = 0.75:
    set(value):
        value = clampf(value, 0.0, 1.0)
        if abs(opacity - value) > 0.01:
            opacity = value
            config_changed.emit()

## Color tint for arrows (modulate)
var color: Color = Color(0.2, 0.2, 0.2, 1.0):
    set(value):
        if color != value:
            color = value
            config_changed.emit()
```

**Update `arrow_config.gd`** (TreeArrowConfig)

```gdscript
## File: features/tree_visualization/arrow_config.gd
class_name TreeArrowConfig
extends NavigationArrowConfigBase

## Tree-specific arrow configuration.
## Extends base with edge placement, diff circle, and pool settings.

# Override default size for tree (tree-local units, smaller default)
func _init() -> void:
    size = 30.0  # Tree-local units (differs from feed's 48px)
    color = Color(0, 0, 0, 1.0)  # Black for tree

# =============================================================================
# Tree-Specific Properties
# =============================================================================

## Base distance from node center to place arrow (tree-local units)
var distance_from_node: float = 60.0:
    set(value):
        if abs(distance_from_node - value) > 0.1:
            distance_from_node = value
            config_changed.emit()

## Extra offset when placing arrows near nodes with dex images
var dex_image_offset: float = 500.0:
    set(value):
        if abs(dex_image_offset - value) > 0.1:
            dex_image_offset = value
            config_changed.emit()

## Minimum edge length to show arrows (shorter edges get no arrows)
var min_edge_length: float = 120.0:
    set(value):
        if abs(min_edge_length - value) > 0.1:
            min_edge_length = value
            config_changed.emit()

## Maximum portion of edge length for arrow placement (0.0 - 1.0)
var max_edge_fraction: float = 0.4:
    set(value):
        value = clampf(value, 0.1, 0.9)
        if abs(max_edge_fraction - value) > 0.01:
            max_edge_fraction = value
            config_changed.emit()

## Extra padding beyond diff circle radius for arrow placement
var diff_circle_padding: float = 30.0:
    set(value):
        if abs(diff_circle_padding - value) > 0.1:
            diff_circle_padding = value
            config_changed.emit()

## Maximum number of arrows in the object pool
var pool_size: int = 50:
    set(value):
        value = clampi(value, 10, 500)
        if pool_size != value:
            pool_size = value
            config_changed.emit()

# =============================================================================
# Factory Methods
# =============================================================================

static func create_default() -> TreeArrowConfig:
    return TreeArrowConfig.new()
```

---

### Phase 1: Feed Sizing Configuration

**Create `feed_config.gd`** - Centralized configuration for feed behavior

```gdscript
## File: features/dex_feed/feed_config.gd
class_name FeedConfig
extends NavigationArrowConfigBase

## Configuration for feed layout and navigation.
## Extends NavigationArrowConfigBase with feed-specific settings.
##
## Inherits from base: size, opacity, color (with config_changed signal)

# =============================================================================
# Margin Configuration (SCREEN PIXELS)
# =============================================================================

## Horizontal margin from viewport edges (pixels)
var margin_horizontal: float = 40.0:
    set(value):
        margin_horizontal = value
        config_changed.emit()

## Vertical margin from viewport edges (pixels)
var margin_vertical: float = 80.0:
    set(value):
        margin_vertical = value
        config_changed.emit()

## Minimum spacing between images (pixels, content space)
var min_spacing: float = 100.0:
    set(value):
        min_spacing = value
        config_changed.emit()

## Maximum random additional spacing (pixels)
var max_random_spacing: float = 60.0

# =============================================================================
# Size Constraints
# =============================================================================

## Maximum image width as fraction of available width (0.0-1.0)
var max_width_fraction: float = 0.95:
    set(value):
        max_width_fraction = clampf(value, 0.5, 1.0)
        config_changed.emit()

## Maximum image height as fraction of available height (0.0-1.0)
var max_height_fraction: float = 0.85:
    set(value):
        max_height_fraction = clampf(value, 0.5, 1.0)
        config_changed.emit()

# =============================================================================
# Feed-Specific Arrow Configuration
# =============================================================================

## Distance from right edge of screen (pixels)
var arrow_edge_distance: float = 20.0:
    set(value):
        arrow_edge_distance = value
        config_changed.emit()

## Animation duration for auto-pan (seconds)
var pan_duration: float = 0.4:
    set(value):
        pan_duration = value
        config_changed.emit()

# =============================================================================
# Factory Method
# =============================================================================

static func create_default() -> FeedConfig:
    return FeedConfig.new()
```

**Rationale**:
- Extends NavigationArrowConfigBase for shared arrow properties (size, opacity, color)
- Adds feed-specific properties (margins, spacing, size constraints)
- Signal-based invalidation inherited from base class
- Separates concerns while avoiding duplication

---

### Phase 2: Image Sizing Refactor

**Modify `feed_carousel_renderer.gd`** - Implement dual-constraint sizing

#### 2.1 Add Config Integration

```gdscript
# Add to class properties
var config: FeedConfig = null:
    set(value):
        if config and config.config_changed.is_connected(_on_config_changed):
            config.config_changed.disconnect(_on_config_changed)
        config = value
        if config:
            config.config_changed.connect(_on_config_changed)
            _layout_dirty = true

var _layout_dirty: bool = false

func _on_config_changed() -> void:
    _layout_dirty = true
    _compute_layout()
```

#### 2.2 Implement Viewport-Aware Sizing

**Replace `_get_base_item_height()` with dynamic calculation:**

```gdscript
## Maximum available width for images (SCREEN PIXELS)
## Accounts for horizontal margins from config.
func _get_max_available_width() -> float:
    var margin := config.margin_horizontal if config else 40.0
    return _container_width - (2.0 * margin)

## Maximum available height for images (SCREEN PIXELS)
## Accounts for vertical margins from config.
func _get_max_available_height() -> float:
    var margin := config.margin_vertical if config else 80.0
    return _container_height - (2.0 * margin)

## Calculate constrained dimensions for an image.
## Ensures image fits within viewport bounds while maintaining aspect ratio.
##
## Parameters:
## - actual_ratio: The image's actual width/height ratio (from loaded image)
##                 If 0 or negative, uses DEFAULT_ASPECT_RATIO (1.33)
##
## Returns: Vector2 with (width, height) in SCREEN PIXELS
func calculate_constrained_size(actual_ratio: float) -> Vector2:
    # Use default ratio if actual not yet known
    if actual_ratio <= 0:
        actual_ratio = DEFAULT_ASPECT_RATIO

    var max_width := _get_max_available_width()
    var max_height := _get_max_available_height()

    # Apply fraction limits from config
    var width_limit := max_width * (config.max_width_fraction if config else 0.95)
    var height_limit := max_height * (config.max_height_fraction if config else 0.85)

    # Calculate dimensions that fit within both constraints
    # Try fitting to width first
    var width_constrained_width := width_limit
    var width_constrained_height := width_limit / actual_ratio

    # Try fitting to height
    var height_constrained_height := height_limit
    var height_constrained_width := height_limit * actual_ratio

    # Use the smaller of the two options
    if width_constrained_height <= height_limit:
        return Vector2(width_constrained_width, width_constrained_height)
    else:
        return Vector2(height_constrained_width, height_constrained_height)
```

#### 2.3 Store Per-Entry Aspect Ratios

```gdscript
## Cached aspect ratios for loaded images {data_index: float}
## Updated when images load, used for accurate positioning
var _entry_aspect_ratios: Dictionary = {}

## Get aspect ratio for an entry (actual if loaded, default otherwise)
func _get_entry_aspect_ratio(index: int) -> float:
    if _entry_aspect_ratios.has(index):
        return _entry_aspect_ratios[index]
    return DEFAULT_ASPECT_RATIO

## Update entry height calculation to use constrained sizing
func _get_entry_height(index: int) -> float:
    var ratio := _get_entry_aspect_ratio(index)
    var size_mult := 1.0
    if index < _entry_randoms.size():
        size_mult = _entry_randoms[index].size_mult

    var constrained := calculate_constrained_size(ratio)
    return constrained.y * size_mult

func _get_entry_width(index: int) -> float:
    var ratio := _get_entry_aspect_ratio(index)
    var size_mult := 1.0
    if index < _entry_randoms.size():
        size_mult = _entry_randoms[index].size_mult

    var constrained := calculate_constrained_size(ratio)
    return constrained.x * size_mult
```

#### 2.4 Update Aspect Ratio on Image Load

```gdscript
func _on_image_loaded(success: bool, pool_idx: int) -> void:
    if not _active_assignments.has(pool_idx):
        return

    var data_idx: int = _active_assignments[pool_idx]

    if success:
        _loading_states[pool_idx] = SlotState.READY

        # Capture actual aspect ratio from loaded image
        var img: DexRecordImage = _image_pool[pool_idx]
        var actual_ratio: float = img.ratio  # AspectRatioContainer.ratio
        if actual_ratio > 0:
            var old_ratio: float = _entry_aspect_ratios.get(data_idx, DEFAULT_ASPECT_RATIO)
            _entry_aspect_ratios[data_idx] = actual_ratio

            # Re-layout if ratio changed significantly (affects positioning of later entries)
            if absf(actual_ratio - old_ratio) > 0.1:
                _compute_layout()

        image_ready.emit(data_idx)
    else:
        _loading_states[pool_idx] = SlotState.ERROR
```

#### 2.5 Update Image Positioning

Modify `_position_active_images()` to use constrained sizes:

```gdscript
func _position_active_images() -> void:
    var viewport_center := Vector2(_container_width, _container_height) / 2.0

    for pool_idx in _active_assignments:
        var data_idx: int = _active_assignments[pool_idx]
        var img: DexRecordImage = _image_pool[pool_idx]

        if data_idx >= _entry_positions.size():
            continue

        var entry_y: float = _entry_positions[data_idx]

        # Get constrained dimensions (respects viewport bounds)
        var entry_width := _get_entry_width(data_idx)
        var entry_height := _get_entry_height(data_idx)

        # Get random offset and rotation
        var x_offset_ratio := 0.0
        var rotation := 0.0
        if data_idx < _entry_randoms.size():
            x_offset_ratio = _entry_randoms[data_idx].x_offset
            rotation = _entry_randoms[data_idx].rotation

        # Content space positioning (Y=0 at top, X=0 at center)
        var content_x := x_offset_ratio * _container_width
        var content_y := entry_y + entry_height / 2.0
        var content_pos := Vector2(content_x, content_y)

        # Transform to screen space
        var screen_center := (content_pos - _scroll_offset) * _current_scale + viewport_center
        var scaled_width := entry_width * _current_scale
        var scaled_height := entry_height * _current_scale
        var screen_x := screen_center.x - scaled_width / 2.0
        var screen_y := screen_center.y - scaled_height / 2.0

        # Apply position and size
        img.position = Vector2(screen_x, screen_y)
        img.custom_minimum_size = Vector2(scaled_width, scaled_height)
        img.size = Vector2(scaled_width, scaled_height)

        # Apply rotation around center
        img.pivot_offset = Vector2(scaled_width / 2.0, scaled_height / 2.0)
        img.rotation_degrees = rotation
```

---

### Phase 3: Feed Navigation Arrows

#### 3.1 Create FeedNavigationArrow

**File: `features/dex_feed/feed_navigation_arrow.gd`**

```gdscript
class_name FeedNavigationArrow
extends Control

## FeedNavigationArrow - Single navigation arrow for feed traversal.
##
## Simpler than TreeNavigationArrow - fixed position, only up/down directions.
## Uses Control node for UI layer compatibility.
##
## COORDINATE SPACE: All positions are in SCREEN PIXELS.

signal pressed

# =============================================================================
# Configuration
# =============================================================================

enum Direction { UP, DOWN }

var direction: Direction = Direction.DOWN
var _is_active: bool = false

# Visual components
var _texture_rect: TextureRect = null
static var _arrow_up_texture: Texture2D = null
static var _arrow_down_texture: Texture2D = null

# =============================================================================
# Initialization
# =============================================================================

func _ready() -> void:
    # Load textures once (static cache)
    if not _arrow_up_texture:
        _arrow_up_texture = load("res://resources/icons/kenny_board-game-icons/arrow_up.svg")
    if not _arrow_down_texture:
        _arrow_down_texture = load("res://resources/icons/kenny_board-game-icons/arrow_down.svg")

    # Create TextureRect for rendering
    _texture_rect = TextureRect.new()
    _texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_texture_rect)

    # Configure for clickability
    mouse_filter = Control.MOUSE_FILTER_STOP
    gui_input.connect(_on_gui_input)

    visible = false
    _is_active = false

# =============================================================================
# Public API
# =============================================================================

func activate(dir: Direction, arrow_size: float, arrow_color: Color, arrow_opacity: float) -> void:
    """Activate arrow with given configuration."""
    direction = dir
    _is_active = true
    visible = true

    # Set appropriate texture
    _texture_rect.texture = _arrow_up_texture if dir == Direction.UP else _arrow_down_texture

    # Size and center the texture
    custom_minimum_size = Vector2(arrow_size, arrow_size)
    size = Vector2(arrow_size, arrow_size)
    _texture_rect.size = Vector2(arrow_size, arrow_size)

    # Apply styling
    modulate = arrow_color
    modulate.a = arrow_opacity


func deactivate() -> void:
    """Deactivate and hide arrow."""
    _is_active = false
    visible = false


func is_active() -> bool:
    return _is_active

# =============================================================================
# Input Handling
# =============================================================================

func _on_gui_input(event: InputEvent) -> void:
    """Handle input on this arrow."""
    if not _is_active:
        return

    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            pressed.emit()
            accept_event()

    elif event is InputEventScreenTouch:
        if event.pressed:
            pressed.emit()
            accept_event()
```

#### 3.2 Create FeedNavigationArrowsLayer

**File: `features/dex_feed/feed_navigation_arrows_layer.gd`**

```gdscript
class_name FeedNavigationArrowsLayer
extends Control

## FeedNavigationArrowsLayer - Manages up/down navigation arrows for the feed.
##
## Shows up arrow when entries exist above current view.
## Shows down arrow when entries exist below current view.
## Clicking navigates to center on prev/next entry.
##
## COORDINATE SPACE: All positions are in SCREEN PIXELS (UI layer).

const FeedNavigationArrowClass = preload("res://features/dex_feed/feed_navigation_arrow.gd")

signal navigate_to_entry(entry_index: int)

# =============================================================================
# Configuration
# =============================================================================

var config: FeedConfig = null:
    set(value):
        if config and config.config_changed.is_connected(_on_config_changed):
            config.config_changed.disconnect(_on_config_changed)
        config = value
        if config:
            config.config_changed.connect(_on_config_changed)
            _visibility_dirty = true

# =============================================================================
# State
# =============================================================================

var _up_arrow: FeedNavigationArrow = null
var _down_arrow: FeedNavigationArrow = null

## Currently visible entry indices (updated by parent)
var _visible_indices: Array[int] = []

## Total number of entries
var _total_entries: int = 0

## Entry Y positions in content space (for navigation target calculation)
var _entry_positions: Array[float] = []

## Visibility dirty flag for throttled updates
var _visibility_dirty: bool = false

const MIN_UPDATE_INTERVAL: float = 0.05  # 20 FPS for UI arrows (less frequent than tree)
var _last_update_time: float = 0.0

# =============================================================================
# Initialization
# =============================================================================

func _ready() -> void:
    if not config:
        config = FeedConfig.create_default()

    _setup_arrows()

    # Full rect anchoring for proper positioning
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE  # Pass through except on arrows


func _setup_arrows() -> void:
    """Create up and down arrow instances."""
    _up_arrow = FeedNavigationArrowClass.new()
    _up_arrow.name = "UpArrow"
    _up_arrow.pressed.connect(_on_up_pressed)
    add_child(_up_arrow)

    _down_arrow = FeedNavigationArrowClass.new()
    _down_arrow.name = "DownArrow"
    _down_arrow.pressed.connect(_on_down_pressed)
    add_child(_down_arrow)

# =============================================================================
# Public API
# =============================================================================

func set_entries_data(total: int, positions: Array[float]) -> void:
    """Update entries information for visibility calculation."""
    _total_entries = total
    _entry_positions = positions
    _visibility_dirty = true


func set_visible_indices(indices: Array[int]) -> void:
    """Update which entries are currently visible."""
    _visible_indices = indices
    _visibility_dirty = true


func update_arrows() -> void:
    """Update arrow visibility and positions."""
    if not _visibility_dirty:
        return

    var current_time := Time.get_ticks_msec() / 1000.0
    if current_time - _last_update_time < MIN_UPDATE_INTERVAL:
        return

    _visibility_dirty = false
    _last_update_time = current_time
    _update_visibility()


func clear() -> void:
    """Hide all arrows."""
    if _up_arrow:
        _up_arrow.deactivate()
    if _down_arrow:
        _down_arrow.deactivate()
    _visible_indices.clear()
    _total_entries = 0
    _entry_positions.clear()

# =============================================================================
# Update Loop
# =============================================================================

func _process(_delta: float) -> void:
    if _visibility_dirty:
        update_arrows()

# =============================================================================
# Visibility Logic
# =============================================================================

func _update_visibility() -> void:
    """Determine which arrows should be visible based on current view."""
    if _total_entries == 0 or _visible_indices.is_empty():
        _up_arrow.deactivate()
        _down_arrow.deactivate()
        return

    # Use inherited properties from NavigationArrowConfigBase
    var arrow_size := config.size if config else 48.0
    var edge_distance := config.arrow_edge_distance if config else 20.0
    var opacity := config.opacity if config else 0.75
    var color := config.color if config else Color(0.2, 0.2, 0.2, 1.0)

    # Find min and max visible indices
    var min_visible := _visible_indices.min()
    var max_visible := _visible_indices.max()

    # Calculate arrow positions (right side of screen, vertically centered-ish)
    var viewport_size := size
    var arrow_x := viewport_size.x - edge_distance - arrow_size
    var up_arrow_y := viewport_size.y * 0.25 - arrow_size / 2.0
    var down_arrow_y := viewport_size.y * 0.75 - arrow_size / 2.0

    # Show up arrow if there are entries above visible area
    if min_visible > 0:
        _up_arrow.activate(
            FeedNavigationArrow.Direction.UP,
            arrow_size, color, opacity
        )
        _up_arrow.position = Vector2(arrow_x, up_arrow_y)
    else:
        _up_arrow.deactivate()

    # Show down arrow if there are entries below visible area
    if max_visible < _total_entries - 1:
        _down_arrow.activate(
            FeedNavigationArrow.Direction.DOWN,
            arrow_size, color, opacity
        )
        _down_arrow.position = Vector2(arrow_x, down_arrow_y)
    else:
        _down_arrow.deactivate()

# =============================================================================
# Navigation Handlers
# =============================================================================

func _on_up_pressed() -> void:
    """Handle up arrow press - navigate to previous entry."""
    if _visible_indices.is_empty():
        return

    var min_visible: int = _visible_indices.min()
    var target_index := maxi(0, min_visible - 1)
    navigate_to_entry.emit(target_index)


func _on_down_pressed() -> void:
    """Handle down arrow press - navigate to next entry."""
    if _visible_indices.is_empty():
        return

    var max_visible: int = _visible_indices.max()
    var target_index := mini(_total_entries - 1, max_visible + 1)
    navigate_to_entry.emit(target_index)

# =============================================================================
# Config Handler
# =============================================================================

func _on_config_changed() -> void:
    _visibility_dirty = true
```

#### 3.3 Integrate into DexFeed

**Modify `dex_feed.gd`:**

```gdscript
# Add imports and variables
const FeedNavigationArrowsLayer = preload("res://features/dex_feed/feed_navigation_arrows_layer.gd")
const FeedConfig = preload("res://features/dex_feed/feed_config.gd")

var _feed_config: FeedConfig
var _arrows_layer: FeedNavigationArrowsLayer

# In _setup_carousel_components():
func _setup_carousel_components() -> void:
    await get_tree().process_frame

    var content_width := _content_area.size.x
    var content_height := _content_area.size.y
    assert(content_width > 0 and content_height > 0, "...")

    # Create shared config
    _feed_config = FeedConfig.create_default()

    # ... existing scroll limits setup ...

    # Create and configure carousel renderer
    _carousel_renderer = FeedCarouselRenderer.new()
    _carousel_renderer.name = "CarouselRenderer"
    _carousel_renderer.config = _feed_config  # NEW: Pass config
    _carousel_renderer.set_anchors_preset(Control.PRESET_FULL_RECT)
    _carousel_container.add_child(_carousel_renderer)
    _carousel_renderer.setup(content_width, content_height)

    # Create navigation arrows layer (as sibling in UI layer)
    _arrows_layer = FeedNavigationArrowsLayer.new()
    _arrows_layer.name = "NavigationArrows"
    _arrows_layer.config = _feed_config  # Shared config
    _content_area.add_child(_arrows_layer)

    # Connect signals
    _carousel_renderer.item_pressed.connect(_on_view_in_dex)
    _carousel_renderer.image_ready.connect(_on_image_ready)
    _carousel_renderer.layout_calculated.connect(_on_layout_calculated)
    _arrows_layer.navigate_to_entry.connect(_on_navigate_to_entry)

# Add navigation handler:
func _on_navigate_to_entry(entry_index: int) -> void:
    """Handle arrow navigation - animate pan to entry."""
    if entry_index < 0 or entry_index >= displayed_entries.size():
        return

    # Get entry Y position (center of entry)
    var entry_positions := _carousel_renderer.get_entry_positions()
    if entry_index >= entry_positions.size():
        return

    var entry_y: float = entry_positions[entry_index]
    var entry_height := _carousel_renderer.get_entry_height_at(entry_index)
    var target_y := entry_y + entry_height / 2.0

    # Pan to center on entry (animated)
    _paper_camera.scroll_to(Vector2(0.0, target_y), true)
    print("[DexFeed] Navigating to entry %d at Y=%.0f" % [entry_index, target_y])

# Update _on_view_changed to pass visible indices to arrows:
func _on_view_changed(cam_position: Vector2, zoom: float) -> void:
    if _carousel_renderer:
        _carousel_renderer.update_scroll(cam_position, zoom)

        # Update arrows with visible indices
        if _arrows_layer:
            var visible := _carousel_renderer.get_visible_indices()
            _arrows_layer.set_visible_indices(visible)

# Update _on_layout_calculated to pass positions to arrows:
func _on_layout_calculated(total_height: float) -> void:
    # ... existing code ...

    # Update arrows with entries data
    if _arrows_layer:
        var positions: Array[float] = []
        for p in _carousel_renderer.get_entry_positions():
            positions.append(p)
        _arrows_layer.set_entries_data(displayed_entries.size(), positions)
```

---

### Phase 4: Add Required Public Methods to FeedCarouselRenderer

```gdscript
# Add to feed_carousel_renderer.gd:

func get_entry_positions() -> Array:
    """Get Y positions of all entries (content space)."""
    return _entry_positions

func get_entry_height_at(index: int) -> float:
    """Get height of entry at specific index."""
    return _get_entry_height(index)

func get_visible_indices() -> Array[int]:
    """Get currently visible entry indices."""
    return _get_visible_indices()
```

---

## File Structure

```
client/biologidex-client/
├── features/
│   ├── ui/components/
│   │   └── navigation_arrow_config_base.gd  # NEW: Shared base config (DRY)
│   ├── dex_feed/
│   │   ├── feed_config.gd              # NEW: Feed config (extends base)
│   │   ├── feed_carousel_renderer.gd   # MODIFIED: Constrained sizing
│   │   ├── feed_navigation_arrow.gd    # NEW: Individual arrow
│   │   └── feed_navigation_arrows_layer.gd  # NEW: Arrows manager
│   └── tree_visualization/
│       └── arrow_config.gd             # MODIFIED: Extends base config
└── scenes/dex_feed/
    └── dex_feed.gd                     # MODIFIED: Integration
```

---

## Implementation Sequence

### Step 0: Create NavigationArrowConfigBase (15 min)
- Create `navigation_arrow_config_base.gd` with shared properties (size, opacity, color)
- Implement signal-based invalidation pattern
- Test that base class can be instantiated

### Step 1: Update TreeArrowConfig (20 min)
- Modify `arrow_config.gd` to extend NavigationArrowConfigBase
- Remove duplicate properties (now inherited)
- Override defaults in `_init()` for tree-specific values
- Verify tree navigation still works correctly

### Step 2: Create FeedConfig (20 min)
- Create `feed_config.gd` extending NavigationArrowConfigBase
- Add feed-specific properties (margins, spacing, size constraints)
- Implement signal-based invalidation for new properties

### Step 3: Refactor Image Sizing (1-2 hours)
- Add config integration to FeedCarouselRenderer
- Implement `calculate_constrained_size()` with dual-constraint algorithm
- Add aspect ratio caching and update-on-load
- Update `_get_entry_width/height` to use constrained sizing
- Update `_position_active_images()` for proper positioning

### Step 4: Create FeedNavigationArrow (45 min)
- Single arrow component with up/down variants
- Click handling with signal emission
- Static texture caching

### Step 5: Create FeedNavigationArrowsLayer (1 hour)
- Arrow management and visibility logic
- Position calculation based on viewport
- Signal emission for navigation

### Step 6: Integrate into DexFeed (45 min)
- Create and wire up config and arrows
- Connect signals
- Add navigation handler with animated pan

### Step 7: Testing & Polish (1 hour)
- Verify TreeArrowConfig refactor didn't break tree navigation
- Test with various aspect ratio images (portrait, landscape, square)
- Test on different viewport sizes
- Verify arrows appear/disappear correctly
- Test navigation animation smoothness
- Web export testing (critical)

---

## Best Practices Applied

### 1. DRY Principles (Judicious Application)
- **Extracted**: Common arrow config properties (size, opacity, color) into shared base
- **Not extracted**: Arrow components themselves (different base classes, coordinate spaces, input handling)
- **Rationale**: Only extract when implementations are truly identical; superficial similarity doesn't justify forced abstraction
- **Benefit**: ~30 lines saved, establishes reusable pattern for future navigation components

### 2. Container-Based Sizing (Godot Native)
- AspectRatioContainer maintains image proportions
- Constrained sizing respects both width AND height limits
- Margins defined in configuration, not hardcoded

### 3. Signal-Based Architecture
- Config changes propagate via signals
- Navigation triggers via signals, not direct calls
- Decoupled components

### 4. Coordinate Space Documentation
Per CLAUDE.md conventions:
- All positions documented with coordinate space
- Screen pixels for UI layer
- Content space for scroll calculations
- Conversions clearly named (`screen_to_*`, `*_to_world`)

### 5. Performance Patterns
- Object pooling for arrows (though simplified - only 2 needed)
- Dirty flag + throttling for visibility updates
- Static texture caching

### 6. Web Export Compatibility
- No children added to instanced scenes in .tscn
- UI as sibling CanvasLayer pattern
- Explicit node paths instead of `%UniqueNames` where needed
- Guard `is_inside_tree()` checks before viewport queries

---

## References

- [AspectRatioContainer - Godot Docs](https://docs.godotengine.org/en/stable/classes/class_aspectratiocontainer.html)
- [Using Containers - Godot Docs](https://docs.godotengine.org/en/stable/tutorials/ui/gui_containers.html)
- [GDQuest Container Overview](https://school.gdquest.com/courses/learn_2d_gamedev_godot_4/start_a_dialogue/all_the_containers)
- TreeNavigationArrows implementation: `features/tree_visualization/tree_navigation_arrow*.gd`
- TreeArrowConfig pattern: `features/tree_visualization/arrow_config.gd`
- PaperCameraScene: `features/camera_system/paper_camera_scene.gd`
