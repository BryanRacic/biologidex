class_name DexRecordImage
extends AspectRatioContainer
## DexRecordImage - Reusable component for displaying dex entry images with labels.
## Provides unified API for image loading, label formatting, and display modes.

# Internal node references (resolved in _ready)
var _bordered_container: PanelContainer
var _bordered_image: TextureRect
var _record_label: Label
var _simple_image: TextureRect

# Entry data storage
var _entry_data: Dictionary = {}
var _user_id: String = ""

# Signals
signal image_loaded(success: bool)
signal image_load_failed


func _ready() -> void:
	_bordered_container = find_child("ImageBorder", true, false)
	_bordered_image = find_child("BorderedImage", true, false)
	_record_label = find_child("RecordLabel", true, false)
	_simple_image = find_child("SimpleImage", true, false)


# =============================================================================
# Public API - Entry Data
# =============================================================================

func set_entry_data(data: Dictionary, user_id: String = "") -> void:
	"""Set entry data and update label. Call load_image() separately to load the image."""
	_entry_data = data
	_user_id = user_id
	_update_label_from_entry()


func get_entry_data() -> Dictionary:
	"""Get the current entry data."""
	return _entry_data


func get_user_id() -> String:
	"""Get the current user ID."""
	return _user_id


# =============================================================================
# Public API - Image Loading
# =============================================================================

func load_image_from_entry() -> void:
	"""Load image using DexImageLoader service based on current entry data."""
	if _entry_data.is_empty():
		_set_placeholder()
		return

	var loader = _get_image_loader()
	if loader:
		loader.load_image(_entry_data, _user_id, _on_image_loaded, self)
	else:
		_set_placeholder()


func set_texture(texture: Texture2D) -> void:
	"""Directly set texture on the bordered image."""
	if _bordered_image:
		_bordered_image.texture = texture


func set_simple_texture(texture: Texture2D) -> void:
	"""Directly set texture on the simple image (for preview mode)."""
	if _simple_image:
		_simple_image.texture = texture


func get_simple_texture() -> Texture2D:
	"""Get the current simple image texture."""
	if _simple_image:
		return _simple_image.texture
	return null


func update_aspect_ratio(width: float, height: float) -> void:
	"""Update container aspect ratio from image dimensions."""
	if height > 0:
		ratio = width / height


func clear_texture() -> void:
	"""Clear textures from both image displays."""
	if _bordered_image:
		_bordered_image.texture = null
	if _simple_image:
		_simple_image.texture = null


# =============================================================================
# Public API - Display Modes
# =============================================================================

func show_bordered() -> void:
	"""Show bordered card mode with label, hide simple preview."""
	if _simple_image:
		_simple_image.visible = false
	if _bordered_container:
		_bordered_container.visible = true


func show_simple() -> void:
	"""Show simple preview mode, hide bordered card."""
	if _simple_image:
		_simple_image.visible = true
	if _bordered_container:
		_bordered_container.visible = false


func copy_simple_to_bordered() -> void:
	"""Copy simple image texture to bordered image."""
	if _simple_image and _bordered_image and _simple_image.texture:
		_bordered_image.texture = _simple_image.texture


# =============================================================================
# Public API - Label
# =============================================================================

func set_label_text(species_line: String, username_line: String, date_line: String) -> void:
	"""Set label text with explicit values (for camera scene with live data)."""
	if _record_label:
		_record_label.text = species_line + "\n" + username_line + "\n" + date_line


func update_label_from_data(scientific_name: String, common_name: String, username: String, catch_date: String) -> void:
	"""Update label from individual data fields."""
	if not _record_label:
		return

	var species_line := _format_species_line(scientific_name, common_name)
	var username_line := username if not username.is_empty() else "Unknown User"
	var date_line := _format_date(catch_date)

	_record_label.text = species_line + "\n" + username_line + "\n" + date_line


# =============================================================================
# Public API - Node Access (for special cases like rotation)
# =============================================================================

func get_simple_image() -> TextureRect:
	"""Get direct access to simple image TextureRect (for rotation, etc.)."""
	return _simple_image


func get_bordered_image() -> TextureRect:
	"""Get direct access to bordered image TextureRect."""
	return _bordered_image


func get_record_label() -> Label:
	"""Get direct access to record label."""
	return _record_label


func get_bordered_container() -> PanelContainer:
	"""Get direct access to bordered container."""
	return _bordered_container


# =============================================================================
# Public API - Placeholder
# =============================================================================

func set_placeholder(size: int = 256, color: Color = Color(0.3, 0.3, 0.3)) -> void:
	"""Set a placeholder image."""
	_set_placeholder(size, color)


# =============================================================================
# Private - Label Formatting
# =============================================================================

func _update_label_from_entry() -> void:
	"""Update label from current entry data."""
	if not _record_label:
		return

	var scientific: String = _entry_data.get("scientific_name", "")
	var common: String = _entry_data.get("common_name", "")
	var owner: String = _entry_data.get("owner_username", "")
	var catch_date: String = _entry_data.get("catch_date", _entry_data.get("updated_at", ""))

	var species_line := _format_species_line(scientific, common)
	var username_line := owner if not owner.is_empty() else "Unknown User"
	var date_line := _format_date(catch_date)

	_record_label.text = species_line + "\n" + username_line + "\n" + date_line


func _format_species_line(scientific: String, common: String) -> String:
	"""Format species line: 'Scientific name - common name'"""
	var line := scientific if not scientific.is_empty() else "Unknown"
	if not common.is_empty():
		if scientific.is_empty():
			line = common
		else:
			line += " - " + common
	return line


func _format_date(iso_date: String) -> String:
	"""Extract date portion from ISO format timestamp."""
	if iso_date.is_empty():
		return ""
	var date_parts := iso_date.split("T")
	if date_parts.size() > 0:
		return date_parts[0]
	return ""


# =============================================================================
# Private - Image Loading
# =============================================================================

func _get_image_loader():
	"""Get DexImageLoader singleton."""
	return get_node_or_null("/root/DexImageLoader")


func _on_image_loaded(result) -> void:
	"""Handle image load result from DexImageLoader."""
	if not is_instance_valid(self):
		return

	if result.success:
		set_texture(result.texture)
		update_aspect_ratio(float(result.image.get_width()), float(result.image.get_height()))
		show_bordered()

		# Update entry data with cached path
		if not result.cached_path.is_empty():
			_entry_data["cached_image_path"] = result.cached_path

		image_loaded.emit(true)
	else:
		_set_placeholder()
		image_load_failed.emit()
		image_loaded.emit(false)


func _set_placeholder(size: int = 256, color: Color = Color(0.3, 0.3, 0.3)) -> void:
	"""Set a placeholder image when real image is unavailable."""
	var loader = _get_image_loader()
	if loader:
		set_texture(loader.create_placeholder(size, color))
	else:
		# Fallback if loader unavailable
		var placeholder := Image.create(size, size, false, Image.FORMAT_RGB8)
		placeholder.fill(color)
		var texture := ImageTexture.create_from_image(placeholder)
		set_texture(texture)

	ratio = 1.0
	show_bordered()
