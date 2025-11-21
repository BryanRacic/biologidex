class_name ImageCache extends Node

## Specialized caching for images with both memory and disk layers
## Automatically manages thumbnails and full-resolution images

signal image_loaded(key: String, texture: ImageTexture)
signal image_load_failed(key: String, error: String)
signal thumbnail_generated(key: String)

# Constants
const THUMBNAIL_SIZE := 256
const MEMORY_CACHE_SIZE := 50  # Number of images in memory
const DISK_CACHE_SIZE_MB := 200.0  # Disk cache size

# Cache layers
var memory_cache: MemoryCache
var disk_cache: DiskCache

# Private variables
var _pending_loads: Dictionary = {}
var _thumbnail_cache: MemoryCache

func _init() -> void:
	memory_cache = MemoryCache.new(MEMORY_CACHE_SIZE, 100.0)  # 100MB memory cache
	disk_cache = DiskCache.new("user://image_cache/", DISK_CACHE_SIZE_MB)
	_thumbnail_cache = MemoryCache.new(MEMORY_CACHE_SIZE * 2, 50.0)  # More thumbnails

func _ready() -> void:
	# Cleanup expired items periodically
	var timer: Timer = Timer.new()
	timer.wait_time = 60.0  # Every minute
	timer.timeout.connect(_on_cleanup_timer)
	add_child(timer)
	timer.start()

## Get image texture from cache or load from URL
func get_image(key: String, url: String = "", use_thumbnail: bool = false) -> ImageTexture:
	var cache_key: String = _make_cache_key(key, use_thumbnail)

	# Try memory cache first (fastest)
	var cached_data: Variant = null
	if use_thumbnail:
		cached_data = _thumbnail_cache.get_cached(cache_key)
	else:
		cached_data = memory_cache.get_cached(cache_key)

	if cached_data != null:
		return _texture_from_cached_data(cached_data)

	# Try disk cache (slower but persistent)
	cached_data = disk_cache.get_cached(cache_key)
	if cached_data != null:
		var texture: ImageTexture = _texture_from_cached_data(cached_data)
		if texture != null:
			# Promote to memory cache
			_cache_in_memory(cache_key, cached_data, use_thumbnail)
			return texture

	# Not in cache, load from URL if provided
	if url != "":
		load_image_async(key, url, use_thumbnail)

	return null

## Load image asynchronously from URL
func load_image_async(key: String, url: String, generate_thumbnail: bool = true) -> void:
	var cache_key: String = _make_cache_key(key, false)

	# Don't load if already pending
	if cache_key in _pending_loads:
		return

	var http_request: HTTPRequest = HTTPRequest.new()
	add_child(http_request)

	_pending_loads[cache_key] = {
		"key": key,
		"url": url,
		"generate_thumbnail": generate_thumbnail,
		"request": http_request
	}

	http_request.request_completed.connect(_on_image_request_completed.bind(cache_key))
	var error: int = http_request.request(url)

	if error != OK:
		push_error("ImageCache: Failed to start image request: %s (Error: %d)" % [url, error])
		_pending_loads.erase(cache_key)
		http_request.queue_free()
		image_load_failed.emit(key, "Failed to start request")

## Store image in cache
func cache_image(key: String, image: Image, generate_thumbnail: bool = true) -> void:
	if image == null:
		return

	# Cache full image
	var cache_key: String = _make_cache_key(key, false)
	var image_data: Dictionary = _serialize_image(image)

	_cache_in_memory(cache_key, image_data, false)
	disk_cache.set_cached(cache_key, image_data, 86400 * 7)  # 7 days

	# Generate and cache thumbnail
	if generate_thumbnail:
		var thumbnail: Image = _generate_thumbnail(image)
		var thumb_key: String = _make_cache_key(key, true)
		var thumb_data: Dictionary = _serialize_image(thumbnail)

		_cache_in_memory(thumb_key, thumb_data, true)
		disk_cache.set_cached(thumb_key, thumb_data, 86400 * 7)
		thumbnail_generated.emit(key)

## Check if image exists in cache
func has_image(key: String, use_thumbnail: bool = false) -> bool:
	var cache_key: String = _make_cache_key(key, use_thumbnail)

	if use_thumbnail:
		return _thumbnail_cache.has_cached(cache_key)
	else:
		return memory_cache.has_cached(cache_key) or disk_cache.has_cached(cache_key)

## Remove image from cache
func remove_image(key: String) -> void:
	var full_key: String = _make_cache_key(key, false)
	var thumb_key: String = _make_cache_key(key, true)

	memory_cache.remove_cached(full_key)
	disk_cache.remove_cached(full_key)
	_thumbnail_cache.remove_cached(thumb_key)
	disk_cache.remove_cached(thumb_key)

## Clear all caches
func clear_all() -> void:
	memory_cache.clear()
	disk_cache.clear()
	_thumbnail_cache.clear()
	_pending_loads.clear()

## Get cache statistics
func get_stats() -> Dictionary:
	return {
		"memory": memory_cache.get_stats(),
		"disk": disk_cache.get_stats(),
		"thumbnails": _thumbnail_cache.get_stats(),
		"pending_loads": _pending_loads.size()
	}

## Make cache key with thumbnail suffix
func _make_cache_key(key: String, is_thumbnail: bool) -> String:
	return key + ("_thumb" if is_thumbnail else "")

## Serialize image to cacheable format
func _serialize_image(image: Image) -> Dictionary:
	return {
		"width": image.get_width(),
		"height": image.get_height(),
		"format": image.get_format(),
		"data": Marshalls.raw_to_base64(image.get_data())
	}

## Deserialize image from cached data
func _deserialize_image(data: Dictionary) -> Image:
	if not data.has("width") or not data.has("height") or not data.has("format") or not data.has("data"):
		return null

	var image: Image = Image.create_from_data(
		data["width"],
		data["height"],
		false,
		data["format"],
		Marshalls.base64_to_raw(data["data"])
	)
	return image

## Create texture from cached data
func _texture_from_cached_data(cached_data: Variant) -> ImageTexture:
	if cached_data is Dictionary:
		var image: Image = _deserialize_image(cached_data)
		if image != null:
			return ImageTexture.create_from_image(image)
	return null

## Cache data in appropriate memory cache
func _cache_in_memory(cache_key: String, data: Dictionary, is_thumbnail: bool) -> void:
	if is_thumbnail:
		_thumbnail_cache.set_cached(cache_key, data, 3600)  # 1 hour
	else:
		memory_cache.set_cached(cache_key, data, 3600)  # 1 hour

## Generate thumbnail from full image
func _generate_thumbnail(image: Image) -> Image:
	var thumbnail: Image = image.duplicate()
	var original_size: Vector2i = Vector2i(thumbnail.get_width(), thumbnail.get_height())

	# Calculate thumbnail size maintaining aspect ratio
	var scale_factor: float = THUMBNAIL_SIZE / float(maxi(original_size.x, original_size.y))
	var new_size: Vector2i = Vector2i(
		int(original_size.x * scale_factor),
		int(original_size.y * scale_factor)
	)

	thumbnail.resize(new_size.x, new_size.y, Image.INTERPOLATE_LANCZOS)
	return thumbnail

## Handle image request completion
func _on_image_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, cache_key: String) -> void:
	if not cache_key in _pending_loads:
		return

	var load_info: Dictionary = _pending_loads[cache_key]
	var key: String = load_info["key"]
	var http_request: HTTPRequest = load_info["request"]

	_pending_loads.erase(cache_key)
	http_request.queue_free()

	# Check for errors
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("ImageCache: HTTP request failed for %s (Result: %d)" % [key, result])
		image_load_failed.emit(key, "HTTP request failed")
		return

	if response_code != 200:
		push_error("ImageCache: HTTP response error for %s (Code: %d)" % [key, response_code])
		image_load_failed.emit(key, "HTTP response code %d" % response_code)
		return

	# Load image from body
	var image: Image = Image.new()
	var load_error: int = OK

	# Try different image formats
	if body.size() > 0:
		# Try PNG first
		load_error = image.load_png_from_buffer(body)
		if load_error != OK:
			# Try JPG
			load_error = image.load_jpg_from_buffer(body)
		if load_error != OK:
			# Try WebP
			load_error = image.load_webp_from_buffer(body)

	if load_error != OK or body.size() == 0:
		push_error("ImageCache: Failed to load image data for %s" % key)
		image_load_failed.emit(key, "Failed to load image data")
		return

	# Cache the image
	cache_image(key, image, load_info["generate_thumbnail"])

	# Create texture and emit signal
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	image_loaded.emit(key, texture)

## Periodic cleanup of expired items
func _on_cleanup_timer() -> void:
	memory_cache.cleanup_expired()
	_thumbnail_cache.cleanup_expired()
	# Disk cache cleanup is less frequent and can be done on demand

func _exit_tree() -> void:
	# Cancel pending requests
	for cache_key in _pending_loads.keys():
		var load_info: Dictionary = _pending_loads[cache_key]
		if load_info.has("request"):
			var request: HTTPRequest = load_info["request"]
			request.cancel_request()
			request.queue_free()
	_pending_loads.clear()
