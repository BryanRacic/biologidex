class_name WorldSpaceImage
extends Node2D

## WorldSpaceImage - Displays a dex record image in the feed.
## Wrapper for the reusable DexRecordImage component (same pattern as TreeDexImage).
## Positioned in FEED-LOCAL space (Y = 0 at top, increasing downward).

const DexRecordImageScene = preload("res://features/ui/components/dex_record_image/dex_record_image.tscn")

signal image_loaded(success: bool)

# =============================================================================
# State
# =============================================================================

## DexRecordImage component instance
var record_image: DexRecordImage = null

var _entry_data: Dictionary = {}
var _is_active: bool = false
var _target_size: Vector2 = Vector2.ZERO  # Target size in world units
var _current_ratio: float = 1.33  # Current aspect ratio (width/height), default 4:3
var _http_request: HTTPRequest = null

# =============================================================================
# Initialization
# =============================================================================

func _ready() -> void:
	_setup_record_image()


func _setup_record_image() -> void:
	"""Instance the reusable DexRecordImage component."""
	record_image = DexRecordImageScene.instantiate()
	record_image.name = "RecordImage"
	add_child(record_image)

	# Connect image loaded signal
	record_image.image_loaded.connect(_on_image_loaded)

	# Show bordered mode
	record_image.show_bordered()

	# Enable mouse passthrough so pan/zoom works over images
	record_image.set_mouse_passthrough(true)

	visible = false


# =============================================================================
# Public API
# =============================================================================

## Activate this image with entry data and position.
## pos: Center position in FEED-LOCAL space
## target_size: Display size in WORLD UNITS
## rotation_deg: Rotation in degrees
func activate(entry: Dictionary, pos: Vector2, target_size: Vector2, rotation_deg: float) -> void:
	_entry_data = entry
	_is_active = true
	_target_size = target_size

	# Set Node2D position and rotation
	position = pos
	rotation_degrees = rotation_deg
	visible = true

	# Apply size
	_apply_size()

	# Set entry data on DexRecordImage
	var user_id: String = entry.get("owner_id", "")
	record_image.set_entry_data(entry, user_id)

	# Start loading the image
	_load_image()


## Deactivate and return to pool
func deactivate() -> void:
	_is_active = false
	_entry_data = {}
	_current_ratio = 1.33  # Reset to default
	visible = false

	# Clear texture to free memory
	if record_image:
		record_image.clear_texture()

	# Cancel any pending HTTP request
	if _http_request and is_instance_valid(_http_request):
		_http_request.cancel_request()
		_http_request.queue_free()
		_http_request = null


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


func get_target_size() -> Vector2:
	return _target_size


# =============================================================================
# Sizing (same pattern as TreeDexImage)
# =============================================================================

func _apply_size() -> void:
	"""Apply size to DexRecordImage container."""
	if not record_image:
		return

	# Set container size directly to target world size
	# DexRecordImage applies proportional sizing (borders, fonts) based on this
	record_image.size = _target_size
	record_image.ratio = _current_ratio
	record_image.scale = Vector2.ONE

	# Center the control on this node's position
	record_image.position = -record_image.size / 2.0


# =============================================================================
# Image Loading
# =============================================================================

func _load_image() -> void:
	"""Load image using DexRecordImage's built-in loading."""
	if not record_image:
		return

	# Try cached path first (faster)
	var cached_path: String = _entry_data.get("cached_image_path", "")
	if not cached_path.is_empty() and FileAccess.file_exists(cached_path):
		record_image.load_image_from_entry()
		return

	# Try URL-based loading
	var url: String = _entry_data.get("dex_compatible_url", "")
	if not url.is_empty():
		_load_from_url(url)
	else:
		# Use DexRecordImage's default loading (may use its own URL resolution)
		record_image.load_image_from_entry()


func _load_from_url(url: String) -> void:
	"""Load image from URL and set on DexRecordImage."""
	# Clean up any existing request
	if _http_request and is_instance_valid(_http_request):
		_http_request.cancel_request()
		_http_request.queue_free()

	_http_request = HTTPRequest.new()
	_http_request.accept_gzip = false  # Required for web export
	add_child(_http_request)
	_http_request.request_completed.connect(_on_http_completed)

	var error := _http_request.request(url)
	if error != OK:
		record_image.set_placeholder()
		image_loaded.emit(false)


func _on_http_completed(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Handle HTTP request completion."""
	# Clean up request node
	if _http_request and is_instance_valid(_http_request):
		_http_request.queue_free()
		_http_request = null

	if not _is_active:
		return

	if result != HTTPRequest.RESULT_SUCCESS or body.is_empty():
		record_image.set_placeholder()
		image_loaded.emit(false)
		return

	# Try to load as PNG first, then JPEG
	var image := Image.new()
	var err := image.load_png_from_buffer(body)
	if err != OK:
		err = image.load_jpg_from_buffer(body)

	if err == OK:
		var texture := ImageTexture.create_from_image(image)
		record_image.set_texture(texture)
		record_image.update_aspect_ratio(float(image.get_width()), float(image.get_height()))

		# Update our ratio and re-apply size
		_current_ratio = record_image.ratio
		_apply_size()

		image_loaded.emit(true)
	else:
		record_image.set_placeholder()
		image_loaded.emit(false)


func _on_image_loaded(success: bool) -> void:
	"""Handle image load completion from DexRecordImage component."""
	if not is_instance_valid(self) or not _is_active:
		return

	if success:
		# Update aspect ratio from loaded image
		_current_ratio = record_image.ratio
		_apply_size()

	image_loaded.emit(success)
