@tool
"""
TreeDexImage - Displays a dex record image in the taxonomic tree.
Wrapper for the reusable dex_record_image.tscn scene.
Handles image caching/downloading and positioning in world space.
"""
extends Node2D
class_name TreeDexImage

const DexRecordImageScene = preload("res://features/ui/components/dex_record_image/dex_record_image.tscn")

# Configurable size (in world units - same space as node positions)
const DEFAULT_IMAGE_SIZE: float = 80.0  # Base size in world units
const CONTROL_BASE_SIZE: float = 200.0  # Base pixel size for the Control before scaling

# Nodes
var record_image: Control = null
var bordered_container: AspectRatioContainer = null
var bordered_image: TextureRect = null
var record_label: Label = null
var simple_image: TextureRect = null

# State
var _creation_index: int = -1
var _user_id: String = "self"
var _is_active: bool = false
var _target_size: float = DEFAULT_IMAGE_SIZE
var _is_downloading: bool = false
var _entry_data: Dictionary = {}

# HTTP request for downloading
var _http_request: HTTPRequest = null


func _ready() -> void:
	_setup_record_image()


func _setup_record_image() -> void:
	"""Instance the reusable dex_record_image scene."""
	record_image = DexRecordImageScene.instantiate()
	record_image.name = "RecordImage"
	add_child(record_image)

	# Use find_child for robust node finding (handles scene structure changes)
	bordered_container = record_image.find_child("ImageBorderAspectRatio", true, false)
	bordered_image = record_image.find_child("BorderedImage", true, false)
	record_label = record_image.find_child("RecordLabel", true, false)
	simple_image = record_image.find_child("SimpleImage", true, false)

	print("[TreeDexImage] Setup - bordered_container: %s, bordered_image: %s, record_label: %s, simple_image: %s" % [
		bordered_container != null, bordered_image != null, record_label != null, simple_image != null
	])

	# Hide simple image (we use bordered version)
	if simple_image:
		simple_image.visible = false

	# Set fixed size for Control (since we're in Node2D, anchors don't work)
	record_image.size = Vector2(CONTROL_BASE_SIZE, CONTROL_BASE_SIZE)

	# Center the control on this node's position
	record_image.position = -record_image.size / 2.0

	# Apply initial scale
	_apply_scale()


func _apply_scale() -> void:
	"""Apply scale to match target world size."""
	if not record_image:
		return

	# Scale the control to match target world units
	var scale_factor = _target_size / CONTROL_BASE_SIZE
	record_image.scale = Vector2(scale_factor, scale_factor)

	# Re-center after scaling
	record_image.position = -record_image.size * scale_factor / 2.0


func set_image_size(size: float) -> void:
	"""Set the target size for this image in world units."""
	_target_size = size
	_apply_scale()


func activate(world_position: Vector2, creation_index: int, user_id: String, entry_data: Dictionary, size: float = DEFAULT_IMAGE_SIZE) -> void:
	"""Activate this image at a world position.
	Checks cache and downloads if necessary."""
	print("[TreeDexImage] Activating #%d at %s" % [creation_index, world_position])
	print("[TreeDexImage] Entry data: cached_path='%s', url='%s'" % [
		entry_data.get("cached_image_path", ""),
		entry_data.get("dex_compatible_url", "")
	])

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
	"""Load image from cache or download if necessary."""
	var cached_path: String = _entry_data.get("cached_image_path", "")

	# Try cache first
	if not cached_path.is_empty() and FileAccess.file_exists(cached_path):
		print("[TreeDexImage] Loading from cache: %s" % cached_path)
		_load_image_from_path(cached_path)
		return

	# Try to download
	var image_url: String = _entry_data.get("dex_compatible_url", "")
	if not image_url.is_empty():
		print("[TreeDexImage] Downloading from: %s" % image_url)
		_download_image(image_url)
	else:
		print("[TreeDexImage] No cached path or URL, using placeholder")
		_set_placeholder_image()


func _load_image_from_path(path: String) -> void:
	"""Load image from local file path."""
	var image := Image.load_from_file(path)
	if image:
		print("[TreeDexImage] Loaded image %dx%d from %s" % [image.get_width(), image.get_height(), path])
		var texture := ImageTexture.create_from_image(image)
		_set_texture(texture, image.get_width(), image.get_height())
	else:
		print("[TreeDexImage] Failed to load image from: %s" % path)
		_set_placeholder_image()


func _download_image(url: String) -> void:
	"""Download image from server and cache it."""
	if _is_downloading:
		return

	_is_downloading = true

	# Clean up old request if exists
	if _http_request:
		_http_request.queue_free()

	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.accept_gzip = false  # Important for web export
	_http_request.request_completed.connect(_on_image_downloaded)

	var error := _http_request.request(url)
	if error != OK:
		print("[TreeDexImage] Failed to start download: ", error)
		_is_downloading = false
		_http_request.queue_free()
		_http_request = null
		_set_placeholder_image()


func _on_image_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Handle image download completion."""
	_is_downloading = false

	if _http_request:
		_http_request.queue_free()
		_http_request = null

	if response_code != 200 or body.size() == 0:
		_set_placeholder_image()
		return

	# Load image from buffer
	var image := Image.new()
	var load_error := image.load_png_from_buffer(body)

	if load_error != OK:
		_set_placeholder_image()
		return

	# Display the image
	var texture := ImageTexture.create_from_image(image)
	_set_texture(texture, image.get_width(), image.get_height())

	# Cache the image
	_cache_downloaded_image(body)


func _cache_downloaded_image(body: PackedByteArray) -> void:
	"""Cache the downloaded image to DexDatabase."""
	var dex_db = get_node_or_null("/root/DexDatabase")
	if not dex_db:
		return

	var image_url: String = _entry_data.get("dex_compatible_url", "")
	if image_url.is_empty():
		return

	var cached_path: String = dex_db.cache_image(image_url, body, _user_id)
	_entry_data["cached_image_path"] = cached_path

	# Update the DexDatabase record
	if _creation_index >= 0:
		var record: Dictionary = dex_db.get_record_for_user(_creation_index, _user_id)
		if not record.is_empty():
			record["cached_image_path"] = cached_path
			dex_db.add_record_from_dict(record, _user_id)


func _set_texture(texture: Texture2D, width: float, height: float) -> void:
	"""Set the image texture and update aspect ratio."""
	print("[TreeDexImage] Setting texture %dx%d, bordered_image=%s" % [int(width), int(height), bordered_image != null])
	if bordered_image:
		bordered_image.texture = texture
		print("[TreeDexImage] Texture assigned to bordered_image")
	else:
		print("[TreeDexImage] ERROR: bordered_image is null!")

	if bordered_container and height > 0:
		bordered_container.ratio = width / height


func _set_placeholder_image() -> void:
	"""Set a placeholder image when real image is unavailable."""
	var placeholder := Image.create(256, 256, false, Image.FORMAT_RGB8)
	placeholder.fill(Color(0.3, 0.3, 0.3))
	var texture := ImageTexture.create_from_image(placeholder)
	_set_texture(texture, 256, 256)


func deactivate() -> void:
	"""Deactivate and hide this image (returns to pool)."""
	_is_active = false
	_creation_index = -1
	_user_id = "self"
	_entry_data.clear()
	visible = false

	# Cancel any pending download
	if _is_downloading and _http_request:
		_http_request.cancel_request()
		_http_request.queue_free()
		_http_request = null
		_is_downloading = false

	# Clear texture to free memory
	if bordered_image:
		bordered_image.texture = null


func is_active() -> bool:
	"""Check if this image is currently in use."""
	return _is_active


func get_creation_index() -> int:
	"""Get the creation index this image represents."""
	return _creation_index
