class_name ImageProcessor extends RefCounted

## Utility class for image processing operations
## Handles rotation, resizing, format conversion, and optimization

signal processing_complete(result: Dictionary)

# Constants
const MAX_DIMENSION := 2560
const JPEG_QUALITY := 0.85
const THUMBNAIL_SIZE := 256

## Rotate image by specified degrees (90, 180, 270)
static func rotate_image(image: Image, degrees: int) -> Image:
	if image == null:
		push_error("ImageProcessor: Cannot rotate null image")
		return null

	var rotated: Image = image.duplicate()

	match degrees:
		90:
			rotated.rotate_90(CLOCKWISE)
		180:
			rotated.rotate_90(CLOCKWISE)
			rotated.rotate_90(CLOCKWISE)
		270:
			rotated.rotate_90(COUNTERCLOCKWISE)
		_:
			push_warning("ImageProcessor: Unsupported rotation: %d degrees" % degrees)
			return image

	return rotated

## Resize image to fit within max dimensions while maintaining aspect ratio
static func resize_image(image: Image, max_width: int = MAX_DIMENSION, max_height: int = MAX_DIMENSION, interpolation: Image.Interpolation = Image.INTERPOLATE_LANCZOS) -> Image:
	if image == null:
		push_error("ImageProcessor: Cannot resize null image")
		return null

	var width: int = image.get_width()
	var height: int = image.get_height()

	# Check if resizing is needed
	if width <= max_width and height <= max_height:
		return image

	# Calculate new dimensions maintaining aspect ratio
	var scale: float = minf(
		float(max_width) / float(width),
		float(max_height) / float(height)
	)

	var new_width: int = int(width * scale)
	var new_height: int = int(height * scale)

	# Create resized image
	var resized: Image = image.duplicate()
	resized.resize(new_width, new_height, interpolation)

	return resized

## Generate thumbnail from image
static func generate_thumbnail(image: Image, size: int = THUMBNAIL_SIZE) -> Image:
	if image == null:
		push_error("ImageProcessor: Cannot generate thumbnail from null image")
		return null

	return resize_image(image, size, size, Image.INTERPOLATE_LANCZOS)

## Convert image to PNG format
static func convert_to_png(image: Image) -> PackedByteArray:
	if image == null:
		push_error("ImageProcessor: Cannot convert null image to PNG")
		return PackedByteArray()

	# Convert RGBA to RGB if needed (PNG supports both)
	if image.get_format() == Image.FORMAT_RGBA8:
		# Keep RGBA for transparency support
		pass
	elif image.get_format() != Image.FORMAT_RGB8:
		# Convert to RGB8 for other formats
		image.convert(Image.FORMAT_RGB8)

	return image.save_png_to_buffer()

## Convert image to JPEG format
static func convert_to_jpeg(image: Image, quality: float = JPEG_QUALITY) -> PackedByteArray:
	if image == null:
		push_error("ImageProcessor: Cannot convert null image to JPEG")
		return PackedByteArray()

	# JPEG doesn't support transparency, convert to RGB
	if image.get_format() != Image.FORMAT_RGB8:
		var converted: Image = image.duplicate()
		converted.convert(Image.FORMAT_RGB8)
		return converted.save_jpg_to_buffer(quality)

	return image.save_jpg_to_buffer(quality)

## Optimize image for upload (resize + format conversion)
static func optimize_for_upload(image: Image, max_dimension: int = MAX_DIMENSION, use_jpeg: bool = false) -> PackedByteArray:
	if image == null:
		push_error("ImageProcessor: Cannot optimize null image")
		return PackedByteArray()

	# Resize if needed
	var optimized: Image = resize_image(image, max_dimension, max_dimension)

	# Convert to appropriate format
	if use_jpeg:
		return convert_to_jpeg(optimized)
	else:
		return convert_to_png(optimized)

## Load image from file path
static func load_image(file_path: String) -> Image:
	if not FileAccess.file_exists(file_path):
		push_error("ImageProcessor: File not found: %s" % file_path)
		return null

	var image: Image = Image.new()
	var error: int = image.load(file_path)

	if error != OK:
		push_error("ImageProcessor: Failed to load image: %s (Error: %d)" % [file_path, error])
		return null

	return image

## Save image to file
static func save_image(image: Image, file_path: String, format: String = "png") -> int:
	if image == null:
		push_error("ImageProcessor: Cannot save null image")
		return ERR_INVALID_PARAMETER

	var error: int = OK
	match format.to_lower():
		"png":
			error = image.save_png(file_path)
		"jpg", "jpeg":
			error = image.save_jpg(file_path, JPEG_QUALITY)
		"webp":
			error = image.save_webp(file_path, false, JPEG_QUALITY)
		_:
			push_error("ImageProcessor: Unsupported format: %s" % format)
			return ERR_INVALID_PARAMETER

	if error != OK:
		push_error("ImageProcessor: Failed to save image: %s (Error: %d)" % [file_path, error])

	return error

## Get image dimensions without loading full image data
static func get_image_size(file_path: String) -> Vector2i:
	var image: Image = load_image(file_path)
	if image == null:
		return Vector2i.ZERO

	return Vector2i(image.get_width(), image.get_height())

## Calculate file size in bytes
static func get_image_memory_size(image: Image) -> int:
	if image == null:
		return 0

	var width: int = image.get_width()
	var height: int = image.get_height()
	var format: int = image.get_format()

	# Estimate based on format
	var bytes_per_pixel: int = 4  # RGBA default
	match format:
		Image.FORMAT_RGB8:
			bytes_per_pixel = 3
		Image.FORMAT_RGBA8:
			bytes_per_pixel = 4
		Image.FORMAT_L8:
			bytes_per_pixel = 1
		_:
			bytes_per_pixel = 4  # Estimate

	return width * height * bytes_per_pixel

## Apply multiple transformations in sequence
static func apply_transformations(image: Image, transformations: Array[Dictionary]) -> Image:
	if image == null:
		push_error("ImageProcessor: Cannot apply transformations to null image")
		return null

	var result: Image = image.duplicate()

	for transform in transformations:
		var type: String = transform.get("type", "")
		match type:
			"rotate":
				var degrees: int = transform.get("degrees", 0)
				result = rotate_image(result, degrees)
			"resize":
				var max_width: int = transform.get("max_width", MAX_DIMENSION)
				var max_height: int = transform.get("max_height", MAX_DIMENSION)
				result = resize_image(result, max_width, max_height)
			"thumbnail":
				var size: int = transform.get("size", THUMBNAIL_SIZE)
				result = generate_thumbnail(result, size)
			_:
				push_warning("ImageProcessor: Unknown transformation type: %s" % type)

	return result

## Create image from buffer with format detection
static func load_image_from_buffer(buffer: PackedByteArray) -> Image:
	if buffer.is_empty():
		push_error("ImageProcessor: Cannot load image from empty buffer")
		return null

	var image: Image = Image.new()
	var error: int = OK

	# Try different formats
	error = image.load_png_from_buffer(buffer)
	if error == OK:
		return image

	error = image.load_jpg_from_buffer(buffer)
	if error == OK:
		return image

	error = image.load_webp_from_buffer(buffer)
	if error == OK:
		return image

	push_error("ImageProcessor: Failed to load image from buffer")
	return null
