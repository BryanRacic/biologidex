@tool
"""
TreeDexImage - Displays a dex record image in the taxonomic tree.
Wrapper for the reusable DexRecordImage component.
Supports native visibility detection and lazy loading via VisibleOnScreenNotifier2D.
"""
extends Node2D
class_name TreeDexImage

const DexRecordImageScene = preload("res://features/ui/components/dex_record_image/dex_record_image.tscn")

# Configurable size (in world units - same space as node positions)
const DEFAULT_IMAGE_SIZE: float = 2000.0  # Base size in world units (200 avoids MIN_FONT clamp)
const PRELOAD_MARGIN: float = 500.0  # World units - start loading before fully visible

# Load state enum for tracking image loading lifecycle
enum LoadState {
	IDLE,           # Not loaded, not loading
	QUEUED,         # In the loading queue
	LOADING,        # Currently loading (HTTP in progress)
	LOADED,         # Image loaded successfully
	FAILED          # Load failed
}

# Signals for tree_renderer to subscribe to
signal visibility_entered
signal visibility_exited
signal load_state_changed(new_state: int)

# DexRecordImage component instance
var record_image: DexRecordImage = null

# Visibility notifier for native engine detection
var _visibility_notifier: VisibleOnScreenNotifier2D = null

# State
var _creation_index: int = -1
var _user_id: String = "self"
var _is_active: bool = false
var _target_size: float = DEFAULT_IMAGE_SIZE
var _current_ratio: float = 1.0  # Current aspect ratio (width/height), updated when image loads
var _image_load_state: int = LoadState.IDLE  # Track loading state


func _ready() -> void:
	_setup_record_image()
	_setup_visibility_notifier()


func _setup_visibility_notifier() -> void:
	"""Create VisibleOnScreenNotifier2D for native visibility detection."""
	_visibility_notifier = VisibleOnScreenNotifier2D.new()
	_visibility_notifier.name = "VisibilityNotifier"
	add_child(_visibility_notifier)

	# Connect signals
	_visibility_notifier.screen_entered.connect(_on_screen_entered)
	_visibility_notifier.screen_exited.connect(_on_screen_exited)

	# Initial rect will be set when activate() is called with size


func _on_screen_entered() -> void:
	"""Called by engine when notifier rect enters viewport."""
	visibility_entered.emit()

	# Request image load if not already loaded/loading
	if _image_load_state == LoadState.IDLE:
		_request_image_load()


func _on_screen_exited() -> void:
	"""Called by engine when notifier rect completely exits viewport."""
	visibility_exited.emit()
	# Note: We don't unload here - that's managed by the pool
	# This signal is informational for the renderer


func _request_image_load() -> void:
	"""Request to be added to the loading queue."""
	if _image_load_state != LoadState.IDLE:
		return
	_set_load_state(LoadState.QUEUED)


func _set_load_state(new_state: int) -> void:
	"""Update load state and emit signal."""
	if _image_load_state == new_state:
		return
	_image_load_state = new_state
	load_state_changed.emit(new_state)


func _setup_record_image() -> void:
	"""Instance the reusable DexRecordImage component."""
	record_image = DexRecordImageScene.instantiate()
	record_image.name = "RecordImage"
	add_child(record_image)

	# Connect image loaded signal
	record_image.image_loaded.connect(_on_image_loaded)

	# Show bordered mode (we don't use simple preview in tree)
	record_image.show_bordered()

	# Enable mouse passthrough so pan/zoom works over images in tree view
	record_image.set_mouse_passthrough(true)

	# Apply initial scale (will set size based on current ratio)
	_apply_scale()


func _apply_scale() -> void:
	"""Apply scale to match target world size."""
	if not record_image:
		return

	# Calculate container size based on aspect ratio
	# target_size is the largest dimension (width for landscape, height for portrait)
	var container_width: float
	var container_height: float

	if _current_ratio >= 1.0:
		# Landscape or square: width is the largest dimension
		container_width = _target_size
		container_height = _target_size / _current_ratio
	else:
		# Portrait: height is the largest dimension
		container_height = _target_size
		container_width = _target_size * _current_ratio

	# Set container size directly to target world size
	# DexRecordImage applies proportional sizing based on this size
	record_image.size = Vector2(container_width, container_height)
	record_image.ratio = _current_ratio
	record_image.scale = Vector2.ONE  # No additional scaling needed

	# Center the control on this node's position
	record_image.position = -record_image.size / 2.0


func set_image_size(size: float) -> void:
	"""Set the target size for this image in world units."""
	_target_size = size
	_apply_scale()
	_update_notifier_rect()


func _update_notifier_rect() -> void:
	"""Update visibility notifier rect based on current size and preload margin."""
	if not _visibility_notifier:
		return

	# Calculate rect centered on this node with preload margin
	var half_size := _target_size / 2.0
	var margin := PRELOAD_MARGIN

	# Rect2 is (position, size) - position is relative to this node
	_visibility_notifier.rect = Rect2(
		Vector2(-half_size - margin, -half_size - margin),
		Vector2(_target_size + margin * 2, _target_size + margin * 2)
	)


func activate(world_position: Vector2, creation_index: int, user_id: String, entry_data: Dictionary, size: float = DEFAULT_IMAGE_SIZE) -> void:
	"""Activate this image at a world position. Does NOT auto-load - use start_load()."""
	position = world_position
	_creation_index = creation_index
	_user_id = user_id
	_target_size = size
	_is_active = true
	_image_load_state = LoadState.IDLE  # Reset state
	visible = true

	_apply_scale()
	_update_notifier_rect()

	# Store entry data but don't load yet
	record_image.set_entry_data(entry_data, user_id)

	if Engine.is_editor_hint():
		record_image.set_placeholder()
		_set_load_state(LoadState.LOADED)


func start_load() -> void:
	"""Actually start loading the image (called by loading queue)."""
	if _image_load_state == LoadState.LOADING or _image_load_state == LoadState.LOADED:
		return

	_set_load_state(LoadState.LOADING)
	record_image.load_image_from_entry()


func _on_image_loaded(success: bool) -> void:
	"""Handle image load completion from DexRecordImage component."""
	if not is_instance_valid(self) or not _is_active:
		return

	if success:
		_set_load_state(LoadState.LOADED)
		# Get aspect ratio from the component and update our local tracking
		_current_ratio = record_image.ratio
		_apply_scale()  # Re-apply scale with new aspect ratio
	else:
		_set_load_state(LoadState.FAILED)


func deactivate() -> void:
	"""Deactivate and hide this image (returns to pool)."""
	_is_active = false
	_creation_index = -1
	_user_id = "self"
	_current_ratio = 1.0  # Reset to default square ratio
	_image_load_state = LoadState.IDLE  # Reset load state
	visible = false

	# Clear texture to free memory
	if record_image:
		record_image.clear_texture()


func is_active() -> bool:
	"""Check if this image is currently in use."""
	return _is_active


func get_creation_index() -> int:
	"""Get the creation index this image represents."""
	return _creation_index


func get_user_id() -> String:
	"""Get the user ID this image represents."""
	return _user_id


func is_on_screen() -> bool:
	"""Check if currently visible on screen (via notifier)."""
	if _visibility_notifier:
		return _visibility_notifier.is_on_screen()
	return false


func is_loading() -> bool:
	"""Check if currently loading."""
	return _image_load_state == LoadState.LOADING


func is_loaded() -> bool:
	"""Check if image is loaded."""
	return _image_load_state == LoadState.LOADED


func is_queued() -> bool:
	"""Check if waiting in queue."""
	return _image_load_state == LoadState.QUEUED


func get_load_state() -> int:
	"""Get current load state."""
	return _image_load_state


# Static accessors for LoadState enum (for external use)
static func get_load_state_idle() -> int:
	return LoadState.IDLE


static func get_load_state_queued() -> int:
	return LoadState.QUEUED


static func get_load_state_loading() -> int:
	return LoadState.LOADING


static func get_load_state_loaded() -> int:
	return LoadState.LOADED
