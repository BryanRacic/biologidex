class_name FeedVisualization
extends Node2D

## FeedVisualization - Reusable component for dex feed rendering.
##
## Uses world-space positioning like TreeVisualization.
## Content added to this node moves automatically with camera panning.
##
## COORDINATE SPACES:
## - All entry positions are in FEED-LOCAL space (Y=0 at top, increasing downward)
## - Camera scroll_offset determines which part is visible
## - No manual screen-space calculations needed for content positioning
##
## ARCHITECTURE:
## - FeedVisualization is added to PaperCameraScene.content_container
## - It manages WorldSpaceImage pool for efficient rendering
## - FeedArrowsLayer provides navigation arrows
## - FeedViewState provides shared view state for coordinate conversions

const WorldSpaceImageClass = preload("res://features/dex_feed/world_space_image.gd")
const FeedViewStateClass = preload("res://features/dex_feed/feed_view_state.gd")
const FeedArrowsLayerClass = preload("res://features/dex_feed/feed_arrows_layer.gd")
const FeedConfigClass = preload("res://features/dex_feed/feed_config.gd")

# =============================================================================
# Signals
# =============================================================================

## Emitted when an entry is pressed/tapped
signal entry_pressed(entry: Dictionary)

## Emitted after layout is calculated (provides total content height)
signal layout_calculated(total_height: float)

## Emitted when loading starts
signal loading_started()

## Emitted when loading finishes
signal loading_finished()

# =============================================================================
# Internal Layers (created dynamically for web export compatibility)
# =============================================================================

var _images_layer: Node2D = null
var _arrows_layer: FeedArrowsLayer = null

# =============================================================================
# Pool Management
# =============================================================================

## Pool of WorldSpaceImage instances
var _image_pool: Array = []  # Array[WorldSpaceImage]

## Free list indices (available slots in pool)
var _free_images: Array[int] = []

## Active assignments: {entry_index: pool_index}
var _active_images: Dictionary = {}

# =============================================================================
# Data
# =============================================================================

## Entry data array
var _entries: Array[Dictionary] = []

## Layout data for each entry: {y, height, width, x_offset, rotation}
var _entry_layout: Array[Dictionary] = []

## Random values for each entry (cached for consistency)
var _entry_randoms: Array[Dictionary] = []

## Total content height in feed-local units
var _total_height: float = 0.0

# =============================================================================
# References
# =============================================================================

var _paper_camera: PaperCameraScene = null
var _view_state: FeedViewState = null
var _config: FeedConfig = null

# =============================================================================
# Configuration (set before calling setup())
# =============================================================================

## Enable navigation arrows
var navigation_arrows_enabled: bool = true

# =============================================================================
# Public API
# =============================================================================

## Setup the feed visualization with a paper camera.
## Call after adding to content_container.
func setup(paper_camera: PaperCameraScene) -> void:
	_paper_camera = paper_camera

	# Create shared state objects
	_view_state = FeedViewStateClass.new()
	_config = FeedConfigClass.create_default()

	# Initialize viewport and scale from current camera state
	if is_inside_tree():
		var viewport_size := get_viewport_rect().size
		_view_state.viewport_size = viewport_size
		_view_state.viewport_center = viewport_size / 2.0
		# Get initial zoom from camera to avoid stale state before first view_changed signal
		_view_state.current_scale = _paper_camera.get_current_zoom()
		_view_state.scroll_offset = _paper_camera.get_camera_position()

	# Create layers (dynamically for web export compatibility)
	_setup_layers()

	# Setup image pool
	_setup_image_pool()

	# Connect to camera signals
	_paper_camera.view_changed.connect(_on_view_changed)
	_paper_camera.tap_detected.connect(_on_tap_detected)

	# Emit initial view state so arrows get positioned correctly
	_view_state.view_changed.emit()

	print("[FeedVisualization] Setup complete with pool size: %d, initial zoom: %.2f" % [_config.pool_size, _view_state.current_scale])


## Set entries to display.
## entries: Array of entry dictionaries
func set_entries(entries: Array[Dictionary]) -> void:
	_entries = entries

	# Clear current state
	_clear_active_images()
	_entry_layout.clear()
	_entry_randoms.clear()

	if _entries.is_empty():
		_total_height = 0.0
		layout_calculated.emit(0.0)
		if _arrows_layer:
			_arrows_layer.clear()
		return

	# Generate random values for organic look
	_generate_random_values()

	# Compute layout
	_compute_layout()

	# Update visible images
	_update_visible_images()


## Get total scrollable height
func get_total_height() -> float:
	return _total_height


## Get entry center Y position (for navigation)
func get_entry_center_y(index: int) -> float:
	if index >= 0 and index < _entry_layout.size():
		var layout: Dictionary = _entry_layout[index]
		var height: float = layout.get("height", 0.0)
		var y: float = layout.get("y", 0.0)
		return y + height / 2.0
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
	_entry_randoms.clear()
	_total_height = 0.0
	if _arrows_layer:
		_arrows_layer.clear()


## Get the configuration object
func get_config() -> FeedConfig:
	return _config


## Get the view state object
func get_view_state() -> FeedViewState:
	return _view_state


# =============================================================================
# Initialization
# =============================================================================

func _setup_layers() -> void:
	"""Create layers dynamically (web export compatible)."""
	# Images layer
	_images_layer = Node2D.new()
	_images_layer.name = "ImagesLayer"
	add_child(_images_layer)

	# Arrows layer (on top)
	_arrows_layer = FeedArrowsLayerClass.new()
	_arrows_layer.name = "ArrowsLayer"
	_arrows_layer.z_index = 1
	_arrows_layer.config = _config
	_arrows_layer.view_state = _view_state
	_arrows_layer.visible = navigation_arrows_enabled
	add_child(_arrows_layer)

	# Connect arrow navigation signal
	_arrows_layer.navigate_to_entry.connect(_on_arrow_navigation)


func _setup_image_pool() -> void:
	"""Pre-create pool of world-space images."""
	var pool_size: int = _config.pool_size

	for i in range(pool_size):
		var img: WorldSpaceImage = WorldSpaceImageClass.new()
		img.name = "PooledImage_%d" % i
		_images_layer.add_child(img)
		_image_pool.append(img)
		_free_images.append(i)

		# Connect signals
		img.image_loaded.connect(_on_image_loaded.bind(i))


# =============================================================================
# Random Value Generation (for organic scrapbook look)
# =============================================================================

func _generate_random_values() -> void:
	"""Generate and cache random values for each entry."""
	_entry_randoms.clear()

	for i in range(_entries.size()):
		_entry_randoms.append({
			# Additional spacing after this entry
			"spacing": randf() * _config.max_random_spacing,
			# X offset as ratio of viewport width
			"x_offset": randf_range(-_config.max_horizontal_offset, _config.max_horizontal_offset),
			# Rotation in degrees
			"rotation": randf_range(-_config.max_rotation, _config.max_rotation)
		})


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
		_view_state.viewport_size = viewport_size
		_view_state.viewport_center = viewport_size / 2.0

	# Convert viewport fractions to WORLD UNITS (must account for camera zoom)
	# At zoom 2.0, things appear 2x bigger, so world sizes are viewport / zoom
	var current_zoom: float = _view_state.current_scale if _view_state else 1.0
	var max_width: float = (viewport_size.x * _config.base_width_fraction) / current_zoom
	var max_height: float = (viewport_size.y * _config.max_height_fraction) / current_zoom

	var current_y: float = 0.0  # No initial padding - first image starts at top

	for i in range(_entries.size()):
		# Calculate entry dimensions (maintaining aspect ratio)
		var entry_size: Vector2 = _calculate_entry_size(i, max_width, max_height)

		# Get random values
		var rand_data: Dictionary = _entry_randoms[i] if i < _entry_randoms.size() else {}
		# X offset also needs zoom conversion (viewport pixels -> world units)
		var x_offset: float = (rand_data.get("x_offset", 0.0) * viewport_size.x) / current_zoom
		var rotation_deg: float = rand_data.get("rotation", 0.0)
		var extra_spacing: float = rand_data.get("spacing", 0.0)

		# Store layout data
		_entry_layout.append({
			"y": current_y,
			"height": entry_size.y,
			"width": entry_size.x,
			"x_offset": x_offset,
			"rotation": rotation_deg
		})

		current_y += entry_size.y + _config.min_spacing + extra_spacing

	_total_height = current_y

	# Update arrows with layout data
	if _arrows_layer:
		var positions: Array[float] = []
		for layout in _entry_layout:
			positions.append(layout.y as float)
		_arrows_layer.set_entries_data(_entries.size(), positions)

	layout_calculated.emit(_total_height)


func _calculate_entry_size(_index: int, max_width: float, max_height: float) -> Vector2:
	"""Calculate constrained size for entry (maintains aspect ratio)."""
	# Use default aspect ratio (will be updated when image loads)
	var aspect_ratio: float = _config.default_aspect_ratio

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
	var view_rect: Rect2 = _view_state.get_view_rect(_config.visibility_buffer)
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

	var pool_idx: int = _free_images.pop_back() as int
	var img: WorldSpaceImage = _image_pool[pool_idx]
	var layout: Dictionary = _entry_layout[entry_idx]
	var entry: Dictionary = _entries[entry_idx]

	# Position is center of image in feed-local space
	var center_x: float = layout.x_offset
	var center_y: float = layout.y + layout.height / 2.0
	var pos := Vector2(center_x, center_y)
	var size_val := Vector2(layout.width, layout.height)
	var rotation_deg: float = layout.rotation

	img.activate(entry, pos, size_val, rotation_deg)
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
	# Update view state
	var viewport_size: Vector2 = Vector2(1280, 720)
	if is_inside_tree():
		viewport_size = get_viewport_rect().size

	_view_state.update(cam_position, zoom, viewport_size / 2.0, viewport_size)

	# Update visible images
	_update_visible_images()


func _on_tap_detected(world_pos: Vector2) -> void:
	"""Handle tap - check if an entry was tapped."""
	for entry_idx in _active_images:
		var pool_idx: int = _active_images[entry_idx]
		var img: WorldSpaceImage = _image_pool[pool_idx]

		if img.contains_point(world_pos):
			entry_pressed.emit(img.get_entry_data())
			return


func _on_image_loaded(_success: bool, _pool_idx: int) -> void:
	"""Handle image load completion."""
	# Could update layout if aspect ratio differs significantly
	pass


func _on_arrow_navigation(entry_idx: int) -> void:
	"""Handle arrow navigation request."""
	if entry_idx < 0 or entry_idx >= _entry_layout.size():
		return

	var center_y: float = get_entry_center_y(entry_idx)

	# Scroll to center this entry vertically
	# Parent scene should call paper_camera.scroll_to()
	if _paper_camera:
		var current_x: float = _paper_camera.get_camera_position().x
		_paper_camera.scroll_to(Vector2(current_x, center_y), true)


# =============================================================================
# Cleanup
# =============================================================================

func _exit_tree() -> void:
	# Disconnect camera signals
	if _paper_camera:
		if _paper_camera.view_changed.is_connected(_on_view_changed):
			_paper_camera.view_changed.disconnect(_on_view_changed)
		if _paper_camera.tap_detected.is_connected(_on_tap_detected):
			_paper_camera.tap_detected.disconnect(_on_tap_detected)
