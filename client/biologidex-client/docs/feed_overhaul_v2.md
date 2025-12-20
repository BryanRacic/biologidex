# Feed Overhaul v2: Unified Camera Architecture

## Executive Summary

This document outlines a comprehensive migration of the dex feed system from **screen-space manual positioning** to **world-space automatic positioning**, matching the tree visualization architecture exactly. This eliminates code duplication, simplifies coordinate handling, and provides a consistent user experience across both features.

### Problem Statement

The current feed implementation uses a fundamentally different approach than the tree visualization:

| Aspect | Tree (World-Space) | Carousel (Screen-Space) |
|--------|-------------------|-------------------------|
| **Content nodes** | Node2D children of content_container | Control nodes positioned manually |
| **Position updates** | Automatic via Camera2D | Manual in `_position_active_images()` |
| **Coordinate math** | None (camera handles it) | Complex scroll_offset/scale transforms |
| **Navigation arrows** | Node2D in tree-local space | Control in screen pixels |
| **Complexity** | Low | High |

**Best practice from game development**: Objects should be in world space, and screen space is just a convenience for display. The current carousel inverts this - it manually computes screen positions based on scroll offset, when it should position objects in world space and let the camera handle the transformation.

---

## Key Insight: Camera2D Already Does This

When content is added as a child of PaperCameraScene's `content_container`:
1. Content position is set **once** in world space
2. Camera.position changes move the viewport (scroll_offset)
3. Camera.zoom scales the view
4. **Content automatically appears in correct screen position** - no manual math needed

The current `FeedCarouselRenderer._position_active_images()` reimplements what Camera2D does natively:
```gdscript
# Current approach - 25+ lines of manual coordinate conversion
var screen_center := (content_pos - _scroll_offset) * _current_scale + viewport_center
var scaled_width := entry_width * _current_scale
# ... position each image every frame

# World-space approach - set position once
image.position = Vector2(0, entry_y)  # Done. Camera handles the rest.
```

---

## Architecture Comparison

### Current Screen-Space Architecture

```
DexFeed (scene root)
├── PaperCameraScene
│   ├── Camera2D (used for scroll limits only)
│   └── WorldContent/ContentContainer (UNUSED for feed content!)
├── CarouselContainer (Control)
│   └── FeedCarouselRenderer (Control)
│       └── Pool of DexRecordImage (Control nodes)
│           ├── Positioned in SCREEN SPACE manually
│           ├── Size/scale recalculated every scroll
│           └── Coordinate math done every frame
└── NavigationArrows (Control layer)
    └── Fixed screen positions
```

### Proposed World-Space Architecture

```
DexFeed (scene root)
├── PaperCameraScene
│   ├── Camera2D (handles all panning/zooming)
│   └── WorldContent/ContentContainer
│       └── FeedVisualization (Node2D) ← NEW
│           ├── ImagesLayer (Node2D)
│           │   └── Pool of WorldSpaceImage (Node2D)
│           │       ├── Positioned in WORLD SPACE once
│           │       ├── Size set once, camera zoom scales visually
│           │       └── No per-frame coordinate math
│           └── ArrowsLayer (Node2D)
│               └── World-space arrows (like tree)
└── DexFeedUILayer (CanvasLayer, layer=10)
    └── Screen-space UI (back button, filters, etc.)
```

---

## Detailed Technical Changes

### Phase 1: Create FeedViewState (Shared State Pattern)

Create a shared view state object following the TreeViewState pattern. This eliminates redundant view state tracking across components.

**File: `features/dex_feed/feed_view_state.gd`**

```gdscript
class_name FeedViewState
extends RefCounted

## FeedViewState - Shared view state for feed coordinate conversions.
##
## COORDINATE SPACES:
## - Screen space: Pixels, origin top-left (0,0). Used for UI, input events.
## - World space: World units, scene origin. Camera.position is in world space.
## - Feed-local space: World units, feed origin (0,0 at top). Entry positions.
##
## For feed: tree_scale is always 1.0 (no separate content scaling like tree)

signal view_changed()

# =============================================================================
# View Parameters
# =============================================================================

## Camera scroll offset in WORLD SPACE (position at viewport center)
var scroll_offset: Vector2 = Vector2.ZERO:
    set(value):
        if scroll_offset != value:
            scroll_offset = value
            view_changed.emit()

## Camera zoom scale (1.0 = normal)
var current_scale: float = 1.0:
    set(value):
        if absf(current_scale - value) > 0.001:
            current_scale = value
            view_changed.emit()

## Viewport center in SCREEN SPACE
var viewport_center: Vector2 = Vector2(640, 360)

## Viewport size in SCREEN SPACE
var viewport_size: Vector2 = Vector2(1280, 720)

# =============================================================================
# Coordinate Conversions
# =============================================================================

## Convert FEED-LOCAL position to SCREEN coordinates.
func feed_local_to_screen(feed_pos: Vector2) -> Vector2:
    return (feed_pos - scroll_offset) * current_scale + viewport_center

## Convert SCREEN position to FEED-LOCAL coordinates.
func screen_to_feed_local(screen_pos: Vector2) -> Vector2:
    return (screen_pos - viewport_center) / current_scale + scroll_offset

## Get view rectangle in FEED-LOCAL coordinates.
func get_view_rect(margin_screen: float = 0.0) -> Rect2:
    var margin_local: float = margin_screen / current_scale
    var half_size: Vector2 = (viewport_size / 2.0) / current_scale + Vector2(margin_local, margin_local)
    var center: Vector2 = scroll_offset
    return Rect2(center - half_size, half_size * 2)

## Get the feed-local Y position at viewport center
func get_center_y() -> float:
    return scroll_offset.y

## Batch update (reduces signal emissions)
func update(new_scroll: Vector2, new_scale: float, new_center: Vector2, new_size: Vector2) -> void:
    var changed := false
    if scroll_offset != new_scroll:
        scroll_offset = new_scroll
        changed = true
    if absf(current_scale - new_scale) > 0.001:
        current_scale = new_scale
        changed = true
    viewport_center = new_center
    viewport_size = new_size
    if changed:
        view_changed.emit()
```

---

### Phase 2: Create WorldSpaceImage Component

Replace Control-based DexRecordImage pooling with Node2D-based world-space images.

**File: `features/dex_feed/world_space_image.gd`**

```gdscript
class_name WorldSpaceImage
extends Node2D

## WorldSpaceImage - A poolable world-space image for the feed.
##
## Uses Sprite2D for rendering (Node2D-based, not Control).
## Positioned in FEED-LOCAL space (Y = 0 at top, increasing downward).
## Camera movement automatically handles screen positioning.

signal image_loaded(success: bool)
signal image_pressed

# =============================================================================
# Components
# =============================================================================

var _sprite: Sprite2D = null
var _texture_rect_size: Vector2 = Vector2.ZERO  # Stored for hit detection

# =============================================================================
# State
# =============================================================================

var _entry_data: Dictionary = {}
var _is_active: bool = false
var _target_size: Vector2 = Vector2.ZERO  # Desired display size in world units

# =============================================================================
# Initialization
# =============================================================================

func _ready() -> void:
    _sprite = Sprite2D.new()
    _sprite.name = "Sprite"
    add_child(_sprite)
    visible = false

# =============================================================================
# Public API
# =============================================================================

## Activate this image with entry data and position.
## position: Center position in FEED-LOCAL space
## size: Display size in WORLD UNITS (not pixels)
## rotation_deg: Rotation in degrees
func activate(entry: Dictionary, pos: Vector2, target_size: Vector2, rotation_deg: float) -> void:
    _entry_data = entry
    _is_active = true
    _target_size = target_size

    position = pos
    rotation_degrees = rotation_deg
    visible = true

    # Load image from entry
    _load_image_from_entry()

## Deactivate and return to pool
func deactivate() -> void:
    _is_active = false
    visible = false
    _entry_data = {}
    _sprite.texture = null

## Check if a world-space point hits this image
func contains_point(world_pos: Vector2) -> bool:
    if not _is_active or _target_size == Vector2.ZERO:
        return false

    # Transform point to local space (accounting for rotation)
    var local_pos: Vector2 = to_local(world_pos)
    var half_size: Vector2 = _target_size / 2.0

    return absf(local_pos.x) <= half_size.x and absf(local_pos.y) <= half_size.y

func is_active() -> bool:
    return _is_active

func get_entry_data() -> Dictionary:
    return _entry_data

# =============================================================================
# Image Loading
# =============================================================================

func _load_image_from_entry() -> void:
    var image_path: String = _entry_data.get("cached_image_path", "")

    if image_path.is_empty():
        # Try URL-based loading
        var url: String = _entry_data.get("dex_compatible_url", "")
        if not url.is_empty():
            _load_from_url(url)
        else:
            image_loaded.emit(false)
        return

    # Load from cached file
    if FileAccess.file_exists(image_path):
        var image := Image.load_from_file(image_path)
        if image:
            var texture := ImageTexture.create_from_image(image)
            _apply_texture(texture)
            image_loaded.emit(true)
            return

    image_loaded.emit(false)

func _load_from_url(url: String) -> void:
    # Use HTTPRequest for async loading
    var http := HTTPRequest.new()
    add_child(http)
    http.request_completed.connect(_on_http_completed.bind(http))
    http.request(url)

func _on_http_completed(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
    http.queue_free()

    if result != HTTPRequest.RESULT_SUCCESS:
        image_loaded.emit(false)
        return

    var image := Image.new()
    var err := image.load_png_from_buffer(body)
    if err != OK:
        err = image.load_jpg_from_buffer(body)

    if err == OK:
        var texture := ImageTexture.create_from_image(image)
        _apply_texture(texture)
        image_loaded.emit(true)
    else:
        image_loaded.emit(false)

func _apply_texture(texture: Texture2D) -> void:
    _sprite.texture = texture

    # Scale sprite to fit target size while maintaining aspect ratio
    if texture and _target_size != Vector2.ZERO:
        var tex_size: Vector2 = texture.get_size()
        var scale_x: float = _target_size.x / tex_size.x
        var scale_y: float = _target_size.y / tex_size.y
        var uniform_scale: float = minf(scale_x, scale_y)
        _sprite.scale = Vector2(uniform_scale, uniform_scale)
```

---

### Phase 3: Create FeedVisualization (Main Component)

This is the feed equivalent of TreeVisualization - a self-contained Node2D component that manages all feed rendering.

**File: `features/dex_feed/feed_visualization.gd`**

```gdscript
class_name FeedVisualization
extends Node2D

## FeedVisualization - Reusable component for dex feed rendering.
##
## Uses world-space positioning like TreeVisualization.
## Content added to this node moves automatically with camera panning.
##
## COORDINATE SPACES:
## - All entry positions are in FEED-LOCAL space (Y=0 at top)
## - Camera scroll_offset determines which part is visible
## - No manual screen-space calculations needed

const WorldSpaceImageClass = preload("res://features/dex_feed/world_space_image.gd")
const FeedViewStateClass = preload("res://features/dex_feed/feed_view_state.gd")
const FeedNavigationArrowsLayerClass = preload("res://features/dex_feed/feed_arrows_layer.gd")
const FeedConfigClass = preload("res://features/dex_feed/feed_config.gd")

# =============================================================================
# Signals
# =============================================================================

signal entry_pressed(entry: Dictionary)
signal layout_calculated(total_height: float)
signal loading_started()
signal loading_finished()

# =============================================================================
# Export Variables
# =============================================================================

@export_group("Layout")
## Minimum vertical spacing between images (world units)
@export var min_spacing: float = 120.0
## Maximum random additional spacing
@export var max_random_spacing: float = 80.0
## Maximum horizontal offset as fraction of viewport width
@export var max_horizontal_offset: float = 0.1
## Maximum rotation in degrees
@export var max_rotation: float = 8.0

@export_group("Image Sizing")
## Base image width as fraction of viewport (0.5 = 50% of viewport width)
@export var base_width_fraction: float = 0.85
## Maximum height as fraction of viewport
@export var max_height_fraction: float = 0.6

@export_group("Navigation")
## Enable navigation arrows
@export var navigation_arrows_enabled: bool = true

# =============================================================================
# Internal State
# =============================================================================

# Layers (created dynamically for web export compatibility)
var _images_layer: Node2D = null
var _arrows_layer = null  # FeedNavigationArrowsLayer

# Pool management
var _image_pool: Array = []  # Array of WorldSpaceImage
var _free_images: Array[int] = []  # Free list indices
var _active_images: Dictionary = {}  # {entry_index: pool_index}
const POOL_SIZE: int = 8  # Only need enough for visible + buffer

# Data
var _entries: Array[Dictionary] = []
var _entry_layout: Array[Dictionary] = []  # [{y: float, height: float, width: float, x_offset: float, rotation: float}]
var _total_height: float = 0.0

# References
var _paper_camera: PaperCameraScene = null
var _view_state: FeedViewState = null
var _config: FeedConfig = null

# =============================================================================
# Public API
# =============================================================================

## Setup the feed visualization with a paper camera.
## Call after adding to content_container.
func setup(paper_camera: PaperCameraScene) -> void:
    _paper_camera = paper_camera

    # Create shared state
    _view_state = FeedViewStateClass.new()
    _config = FeedConfigClass.create_default()

    # Create layers
    _setup_layers()

    # Setup image pool
    _setup_image_pool()

    # Connect to camera
    _paper_camera.view_changed.connect(_on_view_changed)
    _paper_camera.tap_detected.connect(_on_tap_detected)

    print("[FeedVisualization] Setup complete")

## Set entries to display
func set_entries(entries: Array[Dictionary]) -> void:
    _entries = entries
    _clear_active_images()
    _compute_layout()
    _update_visible_images()

## Get total scrollable height
func get_total_height() -> float:
    return _total_height

## Get entry position for navigation
func get_entry_center_y(index: int) -> float:
    if index >= 0 and index < _entry_layout.size():
        var layout: Dictionary = _entry_layout[index]
        return layout.y + layout.height / 2.0
    return 0.0

## Get currently visible entry indices
func get_visible_indices() -> Array[int]:
    var indices: Array[int] = []
    for entry_idx in _active_images:
        indices.append(entry_idx)
    indices.sort()
    return indices

## Clear all entries
func clear() -> void:
    _clear_active_images()
    _entries.clear()
    _entry_layout.clear()
    _total_height = 0.0
    if _arrows_layer:
        _arrows_layer.clear()

# =============================================================================
# Initialization
# =============================================================================

func _setup_layers() -> void:
    """Create layers dynamically (web export compatible)."""
    _images_layer = Node2D.new()
    _images_layer.name = "ImagesLayer"
    add_child(_images_layer)

    _arrows_layer = FeedNavigationArrowsLayerClass.new()
    _arrows_layer.name = "ArrowsLayer"
    _arrows_layer.z_index = 1
    _arrows_layer.config = _config
    _arrows_layer.view_state = _view_state
    _arrows_layer.visible = navigation_arrows_enabled
    add_child(_arrows_layer)

    _arrows_layer.navigate_to_entry.connect(_on_arrow_navigation)

func _setup_image_pool() -> void:
    """Pre-create pool of world-space images."""
    for i in range(POOL_SIZE):
        var img: WorldSpaceImage = WorldSpaceImageClass.new()
        img.name = "PooledImage_%d" % i
        _images_layer.add_child(img)
        _image_pool.append(img)
        _free_images.append(i)

        img.image_loaded.connect(_on_image_loaded.bind(i))
        img.image_pressed.connect(_on_image_pressed.bind(i))

# =============================================================================
# Layout Computation
# =============================================================================

func _compute_layout() -> void:
    """Compute world-space positions for all entries."""
    _entry_layout.clear()

    if _entries.is_empty():
        _total_height = 0.0
        layout_calculated.emit(0.0)
        return

    # Get viewport dimensions for sizing
    var viewport_size: Vector2 = Vector2(1280, 720)
    if is_inside_tree():
        viewport_size = get_viewport_rect().size

    var max_width: float = viewport_size.x * base_width_fraction
    var max_height: float = viewport_size.y * max_height_fraction

    var current_y: float = min_spacing  # Start with padding

    for i in range(_entries.size()):
        # Calculate entry dimensions (maintaining aspect ratio)
        var entry_size: Vector2 = _calculate_entry_size(i, max_width, max_height)

        # Random variations
        var x_offset: float = randf_range(-max_horizontal_offset, max_horizontal_offset) * viewport_size.x
        var rotation_deg: float = randf_range(-max_rotation, max_rotation)
        var extra_spacing: float = randf() * max_random_spacing

        _entry_layout.append({
            "y": current_y,
            "height": entry_size.y,
            "width": entry_size.x,
            "x_offset": x_offset,
            "rotation": rotation_deg
        })

        current_y += entry_size.y + min_spacing + extra_spacing

    _total_height = current_y

    # Update arrows with layout data
    if _arrows_layer:
        var positions: Array[float] = []
        for layout in _entry_layout:
            positions.append(layout.y)
        _arrows_layer.set_entries_data(_entries.size(), positions)

    layout_calculated.emit(_total_height)

func _calculate_entry_size(index: int, max_width: float, max_height: float) -> Vector2:
    """Calculate constrained size for entry (maintains aspect ratio)."""
    # Default aspect ratio (4:3) - will be updated when image loads
    var aspect_ratio: float = 1.33

    # Try width-constrained first
    var width: float = max_width
    var height: float = width / aspect_ratio

    # If too tall, constrain by height
    if height > max_height:
        height = max_height
        width = height * aspect_ratio

    return Vector2(width, height)

# =============================================================================
# Visibility & Pooling
# =============================================================================

func _update_visible_images() -> void:
    """Update which images are active based on viewport."""
    if _entries.is_empty() or not _view_state:
        return

    # Get visible range with buffer
    var view_rect: Rect2 = _view_state.get_view_rect(200.0)
    var view_top: float = view_rect.position.y
    var view_bottom: float = view_rect.position.y + view_rect.size.y

    # Find visible entries
    var visible_entries: Array[int] = []
    for i in range(_entry_layout.size()):
        var layout: Dictionary = _entry_layout[i]
        var entry_top: float = layout.y
        var entry_bottom: float = layout.y + layout.height

        if entry_bottom >= view_top and entry_top <= view_bottom:
            visible_entries.append(i)

    # Deactivate entries no longer visible
    var to_remove: Array[int] = []
    for entry_idx in _active_images:
        if entry_idx not in visible_entries:
            to_remove.append(entry_idx)

    for entry_idx in to_remove:
        var pool_idx: int = _active_images[entry_idx]
        _release_image(pool_idx)
        _active_images.erase(entry_idx)

    # Activate newly visible entries
    for entry_idx in visible_entries:
        if not _active_images.has(entry_idx):
            _activate_entry(entry_idx)

    # Update arrows
    if _arrows_layer:
        _arrows_layer.set_visible_indices(visible_entries)

func _activate_entry(entry_idx: int) -> void:
    """Activate a pooled image for an entry."""
    if _free_images.is_empty():
        return  # Pool exhausted

    var pool_idx: int = _free_images.pop_back()
    var img: WorldSpaceImage = _image_pool[pool_idx]
    var layout: Dictionary = _entry_layout[entry_idx]
    var entry: Dictionary = _entries[entry_idx]

    # Position is center of image in feed-local space
    var center_x: float = layout.x_offset
    var center_y: float = layout.y + layout.height / 2.0
    var pos := Vector2(center_x, center_y)
    var size := Vector2(layout.width, layout.height)

    img.activate(entry, pos, size, layout.rotation)
    _active_images[entry_idx] = pool_idx

func _release_image(pool_idx: int) -> void:
    """Return image to pool."""
    if pool_idx >= 0 and pool_idx < _image_pool.size():
        _image_pool[pool_idx].deactivate()
        _free_images.append(pool_idx)

func _clear_active_images() -> void:
    """Deactivate all images."""
    for entry_idx in _active_images:
        var pool_idx: int = _active_images[entry_idx]
        if pool_idx >= 0 and pool_idx < _image_pool.size():
            _image_pool[pool_idx].deactivate()
            _free_images.append(pool_idx)
    _active_images.clear()

# =============================================================================
# Event Handlers
# =============================================================================

func _on_view_changed(cam_position: Vector2, zoom: float) -> void:
    """Handle camera view changes."""
    var viewport_size: Vector2 = Vector2(1280, 720)
    var viewport_center: Vector2 = viewport_size / 2.0

    if is_inside_tree():
        viewport_size = get_viewport_rect().size
        viewport_center = viewport_size / 2.0

    _view_state.update(cam_position, zoom, viewport_center, viewport_size)
    _update_visible_images()

func _on_tap_detected(world_pos: Vector2) -> void:
    """Handle tap - check if an entry was tapped."""
    for entry_idx in _active_images:
        var pool_idx: int = _active_images[entry_idx]
        var img: WorldSpaceImage = _image_pool[pool_idx]

        if img.contains_point(world_pos):
            entry_pressed.emit(img.get_entry_data())
            return

func _on_image_loaded(success: bool, pool_idx: int) -> void:
    """Handle image load completion."""
    # Could update layout if aspect ratio differs significantly
    pass

func _on_image_pressed(pool_idx: int) -> void:
    """Handle direct image press."""
    for entry_idx in _active_images:
        if _active_images[entry_idx] == pool_idx:
            entry_pressed.emit(_entries[entry_idx])
            return

func _on_arrow_navigation(entry_idx: int) -> void:
    """Handle arrow navigation - emit world position for camera to pan to."""
    var center_y: float = get_entry_center_y(entry_idx)
    # Parent scene handles actual navigation via PaperCameraScene.scroll_to()

# =============================================================================
# Cleanup
# =============================================================================

func _exit_tree() -> void:
    if _paper_camera:
        if _paper_camera.view_changed.is_connected(_on_view_changed):
            _paper_camera.view_changed.disconnect(_on_view_changed)
        if _paper_camera.tap_detected.is_connected(_on_tap_detected):
            _paper_camera.tap_detected.disconnect(_on_tap_detected)
```

---

### Phase 4: Create Feed Arrows Layer (Node2D-based)

Migrate from Control-based arrows to Node2D-based, matching the tree navigation arrows pattern.

**File: `features/dex_feed/feed_arrows_layer.gd`**

```gdscript
class_name FeedArrowsLayer
extends Node2D

## FeedArrowsLayer - Navigation arrows for feed (Node2D-based like tree).
##
## Positioned in FEED-LOCAL space. Uses _input() for click detection
## instead of Control gui_input (more reliable across coordinate spaces).

const FeedNavigationArrowClass = preload("res://features/dex_feed/feed_arrow.gd")
const FeedConfigClass = preload("res://features/dex_feed/feed_config.gd")
const FeedViewStateClass = preload("res://features/dex_feed/feed_view_state.gd")

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

var view_state: FeedViewState = null:
    set(value):
        if view_state and view_state.view_changed.is_connected(_on_view_changed):
            view_state.view_changed.disconnect(_on_view_changed)
        view_state = value
        if view_state:
            view_state.view_changed.connect(_on_view_changed)
            _visibility_dirty = true

# =============================================================================
# State
# =============================================================================

var _up_arrow: FeedArrow = null
var _down_arrow: FeedArrow = null

var _visible_indices: Array[int] = []
var _total_entries: int = 0
var _entry_positions: Array[float] = []

var _visibility_dirty: bool = false
const MIN_UPDATE_INTERVAL: float = 0.05

var _last_update_time: float = 0.0

# =============================================================================
# Initialization
# =============================================================================

func _ready() -> void:
    if not config:
        config = FeedConfigClass.create_default()
    if not view_state:
        view_state = FeedViewStateClass.new()

    _setup_arrows()

func _setup_arrows() -> void:
    _up_arrow = FeedNavigationArrowClass.new()
    _up_arrow.name = "UpArrow"
    _up_arrow.direction = FeedArrow.Direction.UP
    add_child(_up_arrow)

    _down_arrow = FeedNavigationArrowClass.new()
    _down_arrow.name = "DownArrow"
    _down_arrow.direction = FeedArrow.Direction.DOWN
    add_child(_down_arrow)

# =============================================================================
# Input Handling (like tree arrows)
# =============================================================================

func _input(event: InputEvent) -> void:
    if not visible or not view_state:
        return

    var screen_pos: Vector2 = Vector2.ZERO
    var is_click := false

    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            screen_pos = event.position
            is_click = true
    elif event is InputEventScreenTouch:
        if event.pressed:
            screen_pos = event.position
            is_click = true

    if is_click:
        var local_pos: Vector2 = view_state.screen_to_feed_local(screen_pos)

        if _up_arrow.visible and _up_arrow.contains_point(local_pos):
            _navigate_up()
            get_viewport().set_input_as_handled()
        elif _down_arrow.visible and _down_arrow.contains_point(local_pos):
            _navigate_down()
            get_viewport().set_input_as_handled()

# =============================================================================
# Public API
# =============================================================================

func set_entries_data(total: int, positions: Array[float]) -> void:
    _total_entries = total
    _entry_positions = positions
    _visibility_dirty = true

func set_visible_indices(indices: Array[int]) -> void:
    _visible_indices = indices
    _visibility_dirty = true

func clear() -> void:
    _up_arrow.deactivate()
    _down_arrow.deactivate()
    _visible_indices.clear()
    _total_entries = 0
    _entry_positions.clear()

# =============================================================================
# Visibility Logic
# =============================================================================

func _process(_delta: float) -> void:
    if _visibility_dirty:
        _update_arrows()

func _update_arrows() -> void:
    if not _visibility_dirty:
        return

    var current_time := Time.get_ticks_msec() / 1000.0
    if current_time - _last_update_time < MIN_UPDATE_INTERVAL:
        return

    _visibility_dirty = false
    _last_update_time = current_time

    if _total_entries == 0 or _visible_indices.is_empty() or not view_state:
        _up_arrow.deactivate()
        _down_arrow.deactivate()
        return

    var min_visible: int = _visible_indices.min() as int
    var max_visible: int = _visible_indices.max() as int

    # Position arrows in feed-local space
    # They should appear at fixed screen positions, so we calculate
    # the feed-local position that corresponds to those screen positions
    var arrow_size: float = config.size if config else 48.0
    var edge_distance: float = config.arrow_edge_distance if config else 20.0

    # Calculate screen positions we want
    var viewport_size: Vector2 = view_state.viewport_size
    var screen_x: float = viewport_size.x - edge_distance - arrow_size / 2.0
    var up_screen_y: float = viewport_size.y * 0.25
    var down_screen_y: float = viewport_size.y * 0.75

    # Convert to feed-local
    var up_local: Vector2 = view_state.screen_to_feed_local(Vector2(screen_x, up_screen_y))
    var down_local: Vector2 = view_state.screen_to_feed_local(Vector2(screen_x, down_screen_y))

    # Scale arrow size inversely with zoom so it appears constant on screen
    var screen_arrow_size: float = arrow_size / view_state.current_scale

    if min_visible > 0:
        _up_arrow.activate(up_local, screen_arrow_size)
    else:
        _up_arrow.deactivate()

    if max_visible < _total_entries - 1:
        _down_arrow.activate(down_local, screen_arrow_size)
    else:
        _down_arrow.deactivate()

func _navigate_up() -> void:
    if _visible_indices.is_empty():
        return
    var min_visible: int = _visible_indices.min() as int
    var target: int = maxi(0, min_visible - 1)
    navigate_to_entry.emit(target)

func _navigate_down() -> void:
    if _visible_indices.is_empty():
        return
    var min_visible: int = _visible_indices.min() as int
    var target: int = mini(_total_entries - 1, min_visible + 1)
    navigate_to_entry.emit(target)

func _on_config_changed() -> void:
    _visibility_dirty = true

func _on_view_changed() -> void:
    _visibility_dirty = true
```

---

### Phase 5: Create Feed Arrow Component (Node2D-based)

**File: `features/dex_feed/feed_arrow.gd`**

```gdscript
class_name FeedArrow
extends Node2D

## FeedArrow - Single navigation arrow (Node2D-based).
##
## Positioned in FEED-LOCAL space. Arrow appears at fixed screen
## position by recalculating feed-local position on each view change.

enum Direction { UP, DOWN }

var direction: Direction = Direction.DOWN

var _sprite: Sprite2D = null
var _is_active: bool = false
var _size: float = 48.0

static var _arrow_up_texture: Texture2D = null
static var _arrow_down_texture: Texture2D = null

func _ready() -> void:
    if not _arrow_up_texture:
        _arrow_up_texture = load("res://resources/icons/kenny_board-game-icons/arrow_up.svg")
    if not _arrow_down_texture:
        _arrow_down_texture = load("res://resources/icons/kenny_board-game-icons/arrow_down.svg")

    _sprite = Sprite2D.new()
    _sprite.name = "Sprite"
    add_child(_sprite)

    visible = false

func activate(pos: Vector2, arrow_size: float) -> void:
    _is_active = true
    _size = arrow_size
    position = pos
    visible = true

    _sprite.texture = _arrow_up_texture if direction == Direction.UP else _arrow_down_texture

    # Scale sprite to match desired size
    if _sprite.texture:
        var tex_size: float = _sprite.texture.get_size().x
        var scale_val: float = arrow_size / tex_size
        _sprite.scale = Vector2(scale_val, scale_val)

func deactivate() -> void:
    _is_active = false
    visible = false

func contains_point(local_pos: Vector2) -> bool:
    if not _is_active:
        return false

    var half_size: float = _size / 2.0
    var dist: float = position.distance_to(local_pos)
    return dist <= half_size

func is_active() -> bool:
    return _is_active
```

---

### Phase 6: Update DexFeed Scene

**Modified `scenes/dex_feed/dex_feed.gd`**

```gdscript
extends BaseSceneNode

## Dex Feed - Display friends' dex entries using world-space positioning.
## Uses PaperCameraScene with FeedVisualization (like Home uses TreeVisualization).

const FeedVisualizationClass = preload("res://features/dex_feed/feed_visualization.gd")

# State
enum FeedState { IDLE, LOADING, SCROLLING, ERROR }
var _state: FeedState = FeedState.IDLE
var feed_entries: Array[Dictionary] = []
var displayed_entries: Array[Dictionary] = []
var current_filter: String = "all"
var selected_friend_id: String = ""

# Components
@onready var _paper_camera: PaperCameraScene = get_node("%PaperCameraScene")
var _feed_visualization: FeedVisualization = null

# UI (screen-space layer - sibling to PaperCameraScene per web export pattern)
@onready var refresh_button: Button = get_node("%RefreshButton")
@onready var filter_all_button: Button = get_node("%AllButton")
@onready var filter_dropdown: OptionButton = get_node("%FriendsDropdown")
@onready var _empty_state_label: Label = get_node("%EmptyStateLabel")
@onready var _feed_status_label: Label = get_node("%StatusLabel")
@onready var loading_overlay: Control = get_node("%LoadingOverlay")

signal feed_loaded(entry_count: int)

func _on_scene_ready() -> void:
    scene_name = "DexFeed"

    _setup_ui()
    _setup_feed_visualization()
    _connect_sync_signals()
    _initialize_feed()

func _setup_feed_visualization() -> void:
    """Setup FeedVisualization in world-space (like TreeVisualization)."""

    # Create FeedVisualization dynamically (web export compatible)
    _feed_visualization = FeedVisualizationClass.new()
    _feed_visualization.name = "FeedVisualization"

    # Add to PaperCameraScene content container (world-space)
    _paper_camera.content_container.add_child(_feed_visualization)

    # Setup with camera reference
    _feed_visualization.setup(_paper_camera)

    # Connect signals
    _feed_visualization.entry_pressed.connect(_on_view_in_dex)
    _feed_visualization.layout_calculated.connect(_on_layout_calculated)

    print("[DexFeed] FeedVisualization setup complete")

func _on_layout_calculated(total_height: float) -> void:
    """Update scroll limits based on content height."""
    var viewport_size: Vector2 = get_viewport_rect().size
    var max_scroll_y: float = maxf(0.0, total_height - viewport_size.y / 2.0)

    # Horizontal limits (slight wobble allowed)
    var horizontal_max: float = viewport_size.x * 0.3

    _paper_camera.set_scroll_limits(
        Vector2(-horizontal_max, 0.0),
        Vector2(horizontal_max, max_scroll_y)
    )

func _display_feed() -> void:
    """Display entries using FeedVisualization."""
    displayed_entries = _apply_filters(feed_entries)

    if displayed_entries.is_empty():
        _show_empty_state(true, "No entries to display.")
        _feed_visualization.clear()
        _paper_camera.reset()
        return

    _show_empty_state(false)

    # Set entries - FeedVisualization handles the rest
    _feed_visualization.set_entries(displayed_entries)

    # Scroll to top
    _paper_camera.scroll_to(Vector2.ZERO, false)

    _show_status("%d entries" % displayed_entries.size(), true)
    feed_loaded.emit(displayed_entries.size())

# ... rest of existing code (filtering, sync handlers, etc.) unchanged ...
```

---

## Code Reuse Analysis

### What Gets Eliminated

| Component | Current Lines | After Migration | Savings |
|-----------|--------------|-----------------|---------|
| Manual positioning in `_position_active_images()` | ~40 lines | 0 | 100% |
| Screen-space coordinate math | ~30 lines | ~5 (minimal view state) | 83% |
| Control-based arrows layer | 243 lines | Reuses Node2D pattern | ~50% |
| `FeedCarouselRenderer` scroll handling | ~50 lines | 0 | 100% |

### What Gets Reused

1. **PaperCameraScene** - Already shared, now used properly for world-space content
2. **NavigationArrowConfigBase** - Shared base class already exists
3. **FeedConfig** - Minimal changes needed
4. **Object pooling pattern** - Same pattern, different base class (Node2D vs Control)
5. **Visibility throttling** - Same dirty flag + MIN_UPDATE_INTERVAL pattern

### Shared Patterns Extracted

The following patterns are now consistent between tree and feed:

| Pattern | Tree | Feed |
|---------|------|------|
| View state | TreeViewState | FeedViewState |
| Main visualization | TreeVisualization | FeedVisualization |
| Arrows layer | TreeNavigationArrowsLayer | FeedArrowsLayer |
| Arrow component | TreeNavigationArrow | FeedArrow |
| Config | TreeArrowConfig | FeedConfig |
| Input handling | `_input()` with hit detection | `_input()` with hit detection |

---

## File Structure

```
client/biologidex-client/features/
├── dex_feed/
│   ├── feed_visualization.gd       # NEW: Main component (like TreeVisualization)
│   ├── feed_view_state.gd          # NEW: Shared view state
│   ├── world_space_image.gd        # NEW: Node2D-based pooled image
│   ├── feed_arrows_layer.gd        # NEW: Node2D-based arrows layer
│   ├── feed_arrow.gd               # NEW: Node2D-based single arrow
│   ├── feed_config.gd              # EXISTING: Minimal changes
│   ├── feed_carousel_renderer.gd   # DEPRECATED: Remove after migration
│   ├── feed_navigation_arrow.gd    # DEPRECATED: Remove after migration
│   └── feed_navigation_arrows_layer.gd  # DEPRECATED: Remove after migration
```

---

## Migration Sequence

### Step 1: Create New Components (Non-Breaking)
1. Create `feed_view_state.gd`
2. Create `world_space_image.gd`
3. Create `feed_arrow.gd`
4. Create `feed_arrows_layer.gd`
5. Create `feed_visualization.gd`

### Step 2: Update DexFeed Scene
1. Modify `dex_feed.gd` to use `FeedVisualization`
2. Remove carousel container from scene tree (if in .tscn)
3. Test basic functionality

### Step 3: Test & Validate
1. Verify scrolling works correctly
2. Verify image loading and pooling
3. Verify navigation arrows work
4. Verify tap detection on images
5. Web export testing (critical!)

### Step 4: Cleanup
1. Remove deprecated files (`feed_carousel_renderer.gd`, old arrows)
2. Update any imports/references
3. Final testing pass

---

## Best Practices Applied

### 1. World-Space Content (Industry Standard)
> "Your objects should be in world space, not screen space. Screen space is just a convenience for the player."
> — [GameDev.net Forum](https://gamedev.net/forums/topic/525538-2d-screens-vs-continuous-scrolling/)

Objects positioned in world space; camera handles screen projection automatically.

### 2. Object Pooling with Free List
> "When the pool is initialized, it creates the entire collection of objects up front... objects can be freely created and destroyed without needing to allocate memory."
> — [Game Programming Patterns](https://gameprogrammingpatterns.com/object-pool.html)

Pre-allocated pool with O(1) allocation via free list indices.

### 3. Camera2D Native Behavior
> "The Camera2D's position property controls the camera's offset. Elements in world space move automatically with camera changes."
> — [Godot Documentation](https://docs.godotengine.org/en/stable/classes/class_camera2d.html)

Leveraging Camera2D instead of reimplementing its behavior.

### 4. Coordinate Space Documentation
Per CLAUDE.md conventions, all Vector2 variables document their coordinate space.

### 5. Web Export Compatibility
- Layers created programmatically (no children in .tscn)
- UI as sibling CanvasLayer
- Guards for `is_inside_tree()` before viewport queries

---

## References

- [Godot Camera2D Documentation](https://docs.godotengine.org/en/stable/classes/class_camera2d.html)
- [Viewport and Canvas Transforms](https://docs.godotengine.org/en/stable/tutorials/2d/2d_transforms.html)
- [Object Pool Pattern](https://gameprogrammingpatterns.com/object-pool.html)
- [GameDev.net: World Space vs Screen Space](https://gamedev.net/forums/topic/525538-2d-screens-vs-continuous-scrolling/)
- [Medium: Object Pooling in Game Development](https://medium.com/@dilupa.sheh02/object-pooling-in-game-development-the-complete-guide-1786694fcb80)
- Existing codebase: `features/tree_visualization/tree_visualization.gd`
- Existing codebase: `features/camera_system/paper_camera_scene.gd`
