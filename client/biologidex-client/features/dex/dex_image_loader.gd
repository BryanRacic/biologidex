extends Node
## DexImageLoader - Centralized image loading service for dex entries
## Handles cache-first loading, HTTP downloading, and DexDatabase caching.
## Used by FeedListItem, TreeDexImage, and other dex display components.

## Result passed to callbacks
class LoadResult:
	var success: bool = false
	var texture: ImageTexture = null
	var image: Image = null
	var cached_path: String = ""
	var error: String = ""

	static func ok(tex: ImageTexture, img: Image, path: String) -> LoadResult:
		var r := LoadResult.new()
		r.success = true
		r.texture = tex
		r.image = img
		r.cached_path = path
		return r

	static func fail(err: String) -> LoadResult:
		var r := LoadResult.new()
		r.success = false
		r.error = err
		return r

## Active download requests: {request_id: {http_request, callback, user_id, image_url, entry_data}}
var _active_requests: Dictionary = {}
var _request_counter: int = 0

## Reference to DexDatabase (set in _ready)
var _dex_db: Node = null


func _ready() -> void:
	print("[DexImageLoader] Initializing...")
	_dex_db = get_node_or_null("/root/DexDatabase")
	if not _dex_db:
		push_warning("[DexImageLoader] DexDatabase not found - caching will be disabled")


## Load image for a dex entry with cache-first strategy.
## Calls callback(LoadResult) when complete.
##
## entry_data should contain:
##   - cached_image_path: String (local file path, if available)
##   - dex_compatible_url: String (remote URL, if available)
##   - creation_index: int (for updating DB record after caching)
##
## user_id: The user who owns this entry ("self" for current user, or friend's user_id)
## callback: func(result: LoadResult) - called when loading completes
## parent_node: Node to attach HTTPRequest to (for lifecycle management)
func load_image(entry_data: Dictionary, user_id: String, callback: Callable, parent_node: Node = null) -> void:
	var cached_path: String = entry_data.get("cached_image_path", "")
	var image_url: String = entry_data.get("dex_compatible_url", "")

	# Priority 1: Check local cache
	if not cached_path.is_empty() and FileAccess.file_exists(cached_path):
		_load_from_cache(cached_path, callback)
		return

	# Priority 2: Download from URL
	if not image_url.is_empty():
		_download_image(image_url, user_id, entry_data, callback, parent_node)
		return

	# No image available
	callback.call(LoadResult.fail("No cached path or URL available"))


## Load image directly from local file path
func load_from_path(path: String, callback: Callable) -> void:
	_load_from_cache(path, callback)


## Create a placeholder texture (gray)
static func create_placeholder(size: int = 256, color: Color = Color(0.3, 0.3, 0.3)) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


## Internal: Load from local cache file
func _load_from_cache(path: String, callback: Callable) -> void:
	var image := Image.load_from_file(path)
	if image:
		var texture := ImageTexture.create_from_image(image)
		callback.call(LoadResult.ok(texture, image, path))
	else:
		callback.call(LoadResult.fail("Failed to load image from: %s" % path))


## Internal: Download image from URL
func _download_image(url: String, user_id: String, entry_data: Dictionary, callback: Callable, parent_node: Node) -> void:
	# Use parent_node if provided, otherwise use self
	var request_parent: Node = parent_node if parent_node else self

	var http_request := HTTPRequest.new()
	request_parent.add_child(http_request)
	http_request.accept_gzip = false  # Important for web export

	var request_id := _request_counter
	_request_counter += 1

	_active_requests[request_id] = {
		"http_request": http_request,
		"callback": callback,
		"user_id": user_id,
		"image_url": url,
		"entry_data": entry_data
	}

	http_request.request_completed.connect(_on_download_completed.bind(request_id))

	var error := http_request.request(url)
	if error != OK:
		_cleanup_request(request_id)
		callback.call(LoadResult.fail("Failed to start download: %d" % error))


## Internal: Handle download completion
func _on_download_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, request_id: int) -> void:
	if not _active_requests.has(request_id):
		return

	var request_data: Dictionary = _active_requests[request_id]
	var callback: Callable = request_data.get("callback")
	var user_id: String = request_data.get("user_id", "self")
	var image_url: String = request_data.get("image_url", "")
	var entry_data: Dictionary = request_data.get("entry_data", {})

	_cleanup_request(request_id)

	# Check for valid callback
	if not callback.is_valid():
		return

	# Check response
	if response_code != 200:
		callback.call(LoadResult.fail("Download failed with code: %d" % response_code))
		return

	if body.size() == 0:
		callback.call(LoadResult.fail("Downloaded image is empty"))
		return

	# Load image from buffer
	var image := Image.new()
	var load_error := image.load_png_from_buffer(body)

	if load_error != OK:
		# Try JPEG if PNG fails
		load_error = image.load_jpg_from_buffer(body)
		if load_error != OK:
			callback.call(LoadResult.fail("Failed to decode image: %d" % load_error))
			return

	# Create texture
	var texture := ImageTexture.create_from_image(image)

	# Cache the image
	var cached_path := _cache_image(image_url, body, user_id, entry_data)

	callback.call(LoadResult.ok(texture, image, cached_path))


## Internal: Cache downloaded image to DexDatabase
func _cache_image(image_url: String, body: PackedByteArray, user_id: String, entry_data: Dictionary) -> String:
	if not _dex_db:
		return ""

	var cached_path: String = _dex_db.cache_image(image_url, body, user_id)
	if cached_path.is_empty():
		return ""

	# Update the DexDatabase record with cached path
	var creation_index: int = entry_data.get("creation_index", -1)
	if creation_index >= 0:
		var record: Dictionary = _dex_db.get_record_for_user(creation_index, user_id)
		if not record.is_empty():
			record["cached_image_path"] = cached_path
			_dex_db.add_record_from_dict(record, user_id)

	return cached_path


## Internal: Cleanup a request
func _cleanup_request(request_id: int) -> void:
	if not _active_requests.has(request_id):
		return

	var request_data: Dictionary = _active_requests[request_id]
	var http_request: HTTPRequest = request_data.get("http_request")

	if http_request and is_instance_valid(http_request):
		http_request.queue_free()

	_active_requests.erase(request_id)


## Cancel all pending requests
func cancel_all() -> void:
	for request_id in _active_requests.keys():
		_cleanup_request(request_id)


## Get entry data for a dex entry, checking DexDatabase with fallback to provided data.
## Useful for tree nodes that may not have full entry data.
func get_entry_data_for_user(creation_index: int, user_id: String, fallback_data: Dictionary = {}) -> Dictionary:
	if not _dex_db:
		return fallback_data

	var db_record: Dictionary = _dex_db.get_record_for_user(creation_index, user_id)

	if db_record.is_empty():
		return fallback_data

	# Merge DB record with fallback, preferring DB values
	var result := fallback_data.duplicate()
	for key in db_record:
		if not db_record[key] is String or not db_record[key].is_empty():
			result[key] = db_record[key]

	return result
