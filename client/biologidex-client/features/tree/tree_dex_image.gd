@tool
"""
TreeDexImage - Displays a dex record image in the taxonomic tree.
Wrapper for the reusable dex_record_image.tscn scene.
Uses DexImageLoader for unified cache/download handling.
"""
extends Node2D
class_name TreeDexImage

const DexRecordImageScene = preload("res://features/ui/components/dex_record_image/dex_record_image.tscn")

# Configurable size (in world units - same space as node positions)
const DEFAULT_IMAGE_SIZE: float = 80.0  # Base size in world units
const CONTROL_BASE_SIZE: float = 200.0  # Base pixel size for the Control before scaling

# Nodes - record_image root is now AspectRatioContainer
var record_image: AspectRatioContainer = null
var bordered_container: PanelContainer = null
var bordered_image: TextureRect = null
var record_label: Label = null
var simple_image: TextureRect = null

# State
var _creation_index: int = -1
var _user_id: String = "self"
var _is_active: bool = false
var _target_size: float = DEFAULT_IMAGE_SIZE
var _current_ratio: float = 1.0  # Current aspect ratio (width/height), updated when image loads
var _entry_data: Dictionary = {}


func _ready() -> void:
	_setup_record_image()


func _setup_record_image() -> void:
	"""Instance the reusable dex_record_image scene."""
	record_image = DexRecordImageScene.instantiate()
	record_image.name = "RecordImage"
	add_child(record_image)

	# Root is now AspectRatioContainer, so bordered_container is ImageBorder PanelContainer
	bordered_container = record_image.find_child("ImageBorder", true, false)
	bordered_image = record_image.find_child("BorderedImage", true, false)
	record_label = record_image.find_child("RecordLabel", true, false)
	simple_image = record_image.find_child("SimpleImage", true, false)

	# Hide simple image (we use bordered version)
	if simple_image:
		simple_image.visible = false

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
	# SubViewportContainer handles proportional scaling of content internally
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
	"""Activate this image at a world position.
	Uses DexImageLoader for unified cache/download handling."""
	position = world_position
	_creation_index = creation_index
	_user_id = user_id
	_entry_data = entry_data
	_target_size = size
	_is_active = true
	visible = true

	_apply_scale()
	_update_label()
	_load_image()


func _update_label() -> void:
	"""Update the record label with entry data."""
	if not record_label:
		return

	var scientific: String = _entry_data.get("scientific_name", "")
	var common: String = _entry_data.get("common_name", "")
	var owner: String = _entry_data.get("owner_username", "")
	var catch_date: String = _entry_data.get("catch_date", _entry_data.get("updated_at", ""))

	# Format species name
	var species_line := scientific if not scientific.is_empty() else "Unknown"
	if not common.is_empty():
		species_line += " - %s" % common

	# Format username
	var username_line := owner if not owner.is_empty() else ""

	# Format date
	var date_line := ""
	if not catch_date.is_empty():
		var date_parts := catch_date.split("T")
		if date_parts.size() > 0:
			date_line = date_parts[0]

	record_label.text = species_line + "\n" + username_line + "\n" + date_line


func _load_image() -> void:
	"""Load image using DexImageLoader service."""
	if Engine.is_editor_hint():
		_set_placeholder_image()
		return

	var loader = get_node_or_null("/root/DexImageLoader")
	if loader:
		loader.load_image(_entry_data, _user_id, _on_image_loaded, self)
	else:
		_set_placeholder_image()


func _on_image_loaded(result) -> void:
	"""Handle image load result from DexImageLoader."""
	if not is_instance_valid(self) or not _is_active:
		return

	if result.success:
		_set_texture(result.texture, result.image.get_width(), result.image.get_height())
		# Update entry data with cached path
		if not result.cached_path.is_empty():
			_entry_data["cached_image_path"] = result.cached_path
	else:
		_set_placeholder_image()


func _set_texture(texture: Texture2D, width: float, height: float) -> void:
	"""Set the image texture and update aspect ratio."""
	if bordered_image:
		bordered_image.texture = texture

	if height > 0:
		_current_ratio = width / height
		_apply_scale()  # Re-apply scale with new aspect ratio


func _set_placeholder_image() -> void:
	"""Set a placeholder image when real image is unavailable."""
	if Engine.is_editor_hint():
		var placeholder := Image.create(256, 256, false, Image.FORMAT_RGB8)
		placeholder.fill(Color(0.3, 0.3, 0.3))
		var texture := ImageTexture.create_from_image(placeholder)
		_set_texture(texture, 256, 256)
	else:
		var loader = get_node_or_null("/root/DexImageLoader")
		if loader:
			_set_texture(loader.create_placeholder(256, Color(0.3, 0.3, 0.3)), 256, 256)
		else:
			var placeholder := Image.create(256, 256, false, Image.FORMAT_RGB8)
			placeholder.fill(Color(0.3, 0.3, 0.3))
			var texture := ImageTexture.create_from_image(placeholder)
			_set_texture(texture, 256, 256)


func deactivate() -> void:
	"""Deactivate and hide this image (returns to pool)."""
	_is_active = false
	_creation_index = -1
	_user_id = "self"
	_current_ratio = 1.0  # Reset to default square ratio
	_entry_data.clear()
	visible = false

	# Clear texture to free memory
	if bordered_image:
		bordered_image.texture = null


func is_active() -> bool:
	"""Check if this image is currently in use."""
	return _is_active


func get_creation_index() -> int:
	"""Get the creation index this image represents."""
	return _creation_index


func get_user_id() -> String:
	"""Get the user ID this image represents."""
	return _user_id
