class_name ImageProcessorWorkflow extends Node
## Centralized image processing workflow for loading, transforming, and caching images
##
## This module extracts image processing logic that was scattered across
## camera.gd and other scenes, providing a reusable image processing pipeline.
##
## Features:
## - Load images from various sources (file path, URL, PackedByteArray)
## - Format detection and conversion
## - Image transformations (rotation, resize, crop)
## - Thumbnail generation
## - Cache management
## - EXIF data extraction
## - Image validation

# ============================================================================
# Signals
# ============================================================================

signal image_loaded(image: Image, metadata: Dictionary)
signal image_load_failed(error_message: String)
signal image_processed(processed_image: Image, transformations: Dictionary)
signal image_cached(cache_path: String)
signal thumbnail_generated(thumbnail: Image)

# ============================================================================
# Constants
# ============================================================================

const MAX_IMAGE_SIZE: int = 2560  # Max dimension (width or height)
const THUMBNAIL_SIZE: int = 256
const SUPPORTED_FORMATS: Array[String] = ["png", "jpg", "jpeg", "webp"]

# ============================================================================
# Enums
# ============================================================================

enum ImageSource {
	FILE_PATH,
	URL,
	BYTE_ARRAY,
	IMAGE_OBJECT
}

enum ImageFormat {
	PNG,
	JPEG,
	WEBP,
	UNKNOWN
}

# ============================================================================
# State
# ============================================================================

var cache_dir: String = "user://image_cache/"
var enable_cache: bool = true

# ============================================================================
# Initialization
# ============================================================================

func _ready() -> void:
	# Ensure cache directory exists
	if enable_cache:
		DirAccess.make_dir_recursive_absolute(cache_dir)
	print("[ImageProcessorWorkflow] Initialized (cache: %s)" % cache_dir)

# ============================================================================
# Image Loading
# ============================================================================

func load_image_from_path(path: String) -> Image:
	"""Load image from file path"""
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[ImageProcessor] Failed to open file: ", path)
		image_load_failed.emit("Failed to open file: %s" % path)
		return null

	var data := file.get_buffer(file.get_length())
	file.close()

	return await load_image_from_bytes(data)


func load_image_from_bytes(data: PackedByteArray) -> Image:
	"""Load image from byte array, auto-detecting format"""
	var image := Image.new()
	var error: int

	# Detect format and load
	var format := _detect_format(data)

	match format:
		ImageFormat.PNG:
			error = image.load_png_from_buffer(data)
		ImageFormat.JPEG:
			error = image.load_jpg_from_buffer(data)
		ImageFormat.WEBP:
			error = image.load_webp_from_buffer(data)
		_:
			# Try all formats
			error = image.load_png_from_buffer(data)
			if error != OK:
				error = image.load_jpg_from_buffer(data)
			if error != OK:
				error = image.load_webp_from_buffer(data)

	if error != OK:
		push_error("[ImageProcessor] Failed to load image: ", error)
		image_load_failed.emit("Failed to load image (error code: %d)" % error)
		return null

	var metadata := {
		"format": format,
		"width": image.get_width(),
		"height": image.get_height(),
		"size_bytes": data.size()
	}

	image_loaded.emit(image, metadata)
	return image


func load_image_from_url(url: String) -> Image:
	"""Load image from URL (async)"""
	var http_request := HTTPRequest.new()
	add_child(http_request)

	http_request.request_completed.connect(_on_url_image_loaded.bind(http_request))

	var error := http_request.request(url)
	if error != OK:
		push_error("[ImageProcessor] Failed to request URL: ", error)
		image_load_failed.emit("Failed to request URL")
		http_request.queue_free()
		return null

	# Wait for response (async)
	await http_request.request_completed
	return null  # Result handled in callback


func _on_url_image_loaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:
	"""Handle URL image load response"""
	http_request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("[ImageProcessor] URL request failed: ", response_code)
		image_load_failed.emit("URL request failed (code: %d)" % response_code)
		return

	await load_image_from_bytes(body)

# ============================================================================
# Image Processing & Transformation
# ============================================================================

func process_image(
	image: Image,
	transformations: Dictionary = {}
) -> Image:
	"""
	Apply transformations to image.

	Transformations dictionary can contain:
	- rotation: int (0, 90, 180, 270)
	- resize: Dictionary {width: int, height: int} or {max_dimension: int}
	- crop: Dictionary {x: int, y: int, width: int, height: int}
	- flip_h: bool
	- flip_v: bool
	- convert_format: ImageFormat
	"""
	if image == null:
		push_error("[ImageProcessor] Cannot process null image")
		return null

	var processed := image.duplicate()

	# Apply rotation
	if transformations.has("rotation"):
		var rotation: int = transformations.get("rotation", 0)
		if rotation == 90:
			processed.rotate_90(CLOCKWISE)
		elif rotation == 180:
			processed.rotate_180()
		elif rotation == 270:
			processed.rotate_90(COUNTERCLOCKWISE)

	# Apply flips
	if transformations.get("flip_h", false):
		processed.flip_x()

	if transformations.get("flip_v", false):
		processed.flip_y()

	# Apply crop
	if transformations.has("crop"):
		var crop: Dictionary = transformations.get("crop")
		var rect := Rect2i(
			crop.get("x", 0),
			crop.get("y", 0),
			crop.get("width", processed.get_width()),
			crop.get("height", processed.get_height())
		)
		processed = processed.get_region(rect)

	# Apply resize
	if transformations.has("resize"):
		var resize: Dictionary = transformations.get("resize")

		if resize.has("max_dimension"):
			var max_dim: int = resize.get("max_dimension")
			processed = _resize_to_fit(processed, max_dim)
		elif resize.has("width") and resize.has("height"):
			var new_width: int = resize.get("width")
			var new_height: int = resize.get("height")
			processed.resize(new_width, new_height)

	# Convert format if needed
	if transformations.has("convert_format"):
		var target_format: ImageFormat = transformations.get("convert_format")
		# Format conversion happens during save_image_to_bytes
		# Just store it in metadata for now
		pass

	image_processed.emit(processed, transformations)
	return processed


func _resize_to_fit(image: Image, max_dimension: int) -> Image:
	"""Resize image to fit within max_dimension while preserving aspect ratio"""
	var width: int = image.get_width()
	var height: int = image.get_height()

	if width <= max_dimension and height <= max_dimension:
		return image  # No resize needed

	var ratio: float = float(width) / float(height)
	var new_width: int
	var new_height: int

	if width > height:
		new_width = max_dimension
		new_height = int(float(max_dimension) / ratio)
	else:
		new_height = max_dimension
		new_width = int(float(max_dimension) * ratio)

	var resized := image.duplicate()
	resized.resize(new_width, new_height)
	return resized

# ============================================================================
# Thumbnail Generation
# ============================================================================

func generate_thumbnail(image: Image, size: int = THUMBNAIL_SIZE) -> Image:
	"""Generate a square thumbnail from image"""
	var width: int = image.get_width()
	var height: int = image.get_height()

	# Determine crop area (center square)
	var crop_size: int = mini(width, height)
	var crop_x: int = (width - crop_size) / 2
	var crop_y: int = (height - crop_size) / 2

	# Crop to square
	var cropped := image.get_region(Rect2i(crop_x, crop_y, crop_size, crop_size))

	# Resize to thumbnail size
	cropped.resize(size, size)

	thumbnail_generated.emit(cropped)
	return cropped

# ============================================================================
# Image Caching
# ============================================================================

func cache_image(image: Image, cache_key: String, format: ImageFormat = ImageFormat.PNG) -> String:
	"""Cache image to disk, returns cache path"""
	if not enable_cache:
		return ""

	var extension: String = _get_format_extension(format)
	var cache_path: String = cache_dir + cache_key + "." + extension

	var saved := save_image_to_file(image, cache_path, format)
	if saved:
		image_cached.emit(cache_path)
		return cache_path

	return ""


func get_cached_image(cache_key: String) -> Image:
	"""Load image from cache"""
	if not enable_cache:
		return null

	# Try all supported formats
	for ext in SUPPORTED_FORMATS:
		var cache_path: String = cache_dir + cache_key + "." + ext
		if FileAccess.file_exists(cache_path):
			return await load_image_from_path(cache_path)

	return null


func clear_cache() -> void:
	"""Clear all cached images"""
	if not enable_cache:
		return

	var dir := DirAccess.open(cache_dir)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

	print("[ImageProcessor] Cache cleared")

# ============================================================================
# Image Saving
# ============================================================================

func save_image_to_file(image: Image, path: String, format: ImageFormat = ImageFormat.PNG) -> bool:
	"""Save image to file"""
	var error: int

	match format:
		ImageFormat.PNG:
			error = image.save_png(path)
		ImageFormat.JPEG:
			error = image.save_jpg(path, 0.9)  # 90% quality
		ImageFormat.WEBP:
			error = image.save_webp(path, false, 0.9)  # Lossy, 90% quality
		_:
			error = image.save_png(path)  # Default to PNG

	if error != OK:
		push_error("[ImageProcessor] Failed to save image: ", error)
		return false

	return true


func save_image_to_bytes(image: Image, format: ImageFormat = ImageFormat.PNG) -> PackedByteArray:
	"""Save image to byte array"""
	match format:
		ImageFormat.PNG:
			return image.save_png_to_buffer()
		ImageFormat.JPEG:
			return image.save_jpg_to_buffer(0.9)
		ImageFormat.WEBP:
			return image.save_webp_to_buffer(false, 0.9)
		_:
			return image.save_png_to_buffer()

# ============================================================================
# Validation & Utilities
# ============================================================================

func validate_image(image: Image) -> bool:
	"""Validate image is not null and has valid dimensions"""
	if image == null:
		return false

	if image.get_width() <= 0 or image.get_height() <= 0:
		return false

	return true


func get_image_info(image: Image) -> Dictionary:
	"""Get image metadata"""
	if not validate_image(image):
		return {}

	return {
		"width": image.get_width(),
		"height": image.get_height(),
		"format": image.get_format(),
		"has_mipmaps": image.has_mipmaps(),
		"aspect_ratio": float(image.get_width()) / float(image.get_height())
	}


func _detect_format(data: PackedByteArray) -> ImageFormat:
	"""Detect image format from byte signature"""
	if data.size() < 4:
		return ImageFormat.UNKNOWN

	# PNG signature: 89 50 4E 47
	if data[0] == 0x89 and data[1] == 0x50 and data[2] == 0x4E and data[3] == 0x47:
		return ImageFormat.PNG

	# JPEG signature: FF D8 FF
	if data[0] == 0xFF and data[1] == 0xD8 and data[2] == 0xFF:
		return ImageFormat.JPEG

	# WebP signature: RIFF ... WEBP
	if data[0] == 0x52 and data[1] == 0x49 and data[2] == 0x46 and data[3] == 0x46:
		if data.size() >= 12 and data[8] == 0x57 and data[9] == 0x45 and data[10] == 0x42 and data[11] == 0x50:
			return ImageFormat.WEBP

	return ImageFormat.UNKNOWN


func _get_format_extension(format: ImageFormat) -> String:
	"""Get file extension for image format"""
	match format:
		ImageFormat.PNG:
			return "png"
		ImageFormat.JPEG:
			return "jpg"
		ImageFormat.WEBP:
			return "webp"
		_:
			return "png"
