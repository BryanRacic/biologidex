@tool
"""
TreeDexImage - Displays a dex record image in the taxonomic tree.
Wrapper for the reusable DexRecordImage component.
"""
extends Node2D
class_name TreeDexImage

const DexRecordImageScene = preload("res://features/ui/components/dex_record_image/dex_record_image.tscn")

# Configurable size (in world units - same space as node positions)
const DEFAULT_IMAGE_SIZE: float = 2000.0  # Base size in world units (200 avoids MIN_FONT clamp)

# DexRecordImage component instance
var record_image: DexRecordImage = null

# State
var _creation_index: int = -1
var _user_id: String = "self"
var _is_active: bool = false
var _target_size: float = DEFAULT_IMAGE_SIZE
var _current_ratio: float = 1.0  # Current aspect ratio (width/height), updated when image loads


func _ready() -> void:
	_setup_record_image()


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


func activate(world_position: Vector2, creation_index: int, user_id: String, entry_data: Dictionary, size: float = DEFAULT_IMAGE_SIZE) -> void:
	"""Activate this image at a world position."""
	position = world_position
	_creation_index = creation_index
	_user_id = user_id
	_target_size = size
	_is_active = true
	visible = true

	_apply_scale()

	# Use DexRecordImage component for display and image loading
	record_image.set_entry_data(entry_data, user_id)

	if Engine.is_editor_hint():
		record_image.set_placeholder()
	else:
		record_image.load_image_from_entry()


func _on_image_loaded(success: bool) -> void:
	"""Handle image load completion from DexRecordImage component."""
	if not is_instance_valid(self) or not _is_active:
		return

	if success:
		# Get aspect ratio from the component and update our local tracking
		_current_ratio = record_image.ratio
		_apply_scale()  # Re-apply scale with new aspect ratio


func deactivate() -> void:
	"""Deactivate and hide this image (returns to pool)."""
	_is_active = false
	_creation_index = -1
	_user_id = "self"
	_current_ratio = 1.0  # Reset to default square ratio
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
