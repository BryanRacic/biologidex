class_name ImageLoader extends Node

## Asynchronous image loading utility
## Loads images in background without blocking UI

signal image_loaded(key: String, texture: ImageTexture)
signal image_load_failed(key: String, error: String)
signal load_progress(key: String, progress: float)

# Dependencies
var http_pool: HTTPRequestPool
var image_cache: ImageCache

# Private variables
var _loading_queue: Array[Dictionary] = []
var _active_loads: Dictionary = {}
var _max_concurrent_loads: int = 3

func _init(p_http_pool: HTTPRequestPool = null, p_image_cache: ImageCache = null) -> void:
	http_pool = p_http_pool
	image_cache = p_image_cache

func _ready() -> void:
	# Process queue periodically
	var timer: Timer = Timer.new()
	timer.wait_time = 0.1
	timer.timeout.connect(_process_queue)
	add_child(timer)
	timer.start()

## Load image from URL with caching
func load_image(key: String, url: String, use_cache: bool = true) -> void:
	# Check cache first
	if use_cache and image_cache != null:
		var cached_texture: ImageTexture = image_cache.get_image(key, url, false)
		if cached_texture != null:
			# Emit on next frame to maintain async behavior
			_emit_cached_result(key, cached_texture)
			return

	# Add to queue
	_loading_queue.append({
		"key": key,
		"url": url,
		"use_cache": use_cache
	})

## Load image from file path
func load_image_from_file(key: String, file_path: String) -> void:
	# Load in background using thread (if available)
	_load_file_async(key, file_path)

## Cancel loading for a specific key
func cancel_load(key: String) -> void:
	# Remove from queue
	for i in range(_loading_queue.size() - 1, -1, -1):
		if _loading_queue[i]["key"] == key:
			_loading_queue.remove_at(i)

	# Cancel active load
	if key in _active_loads:
		var load_info: Dictionary = _active_loads[key]
		if load_info.has("http_request"):
			var request: HTTPRequest = load_info["http_request"]
			request.cancel_request()
			if http_pool != null:
				http_pool.release(request)
		_active_loads.erase(key)

## Cancel all loads
func cancel_all() -> void:
	_loading_queue.clear()

	for key in _active_loads.keys():
		var load_info: Dictionary = _active_loads[key]
		if load_info.has("http_request"):
			var request: HTTPRequest = load_info["http_request"]
			request.cancel_request()
			if http_pool != null:
				http_pool.release(request)

	_active_loads.clear()

## Get number of pending loads
func get_pending_count() -> int:
	return _loading_queue.size() + _active_loads.size()

## Check if a key is currently loading
func is_loading(key: String) -> bool:
	# Check queue
	for item in _loading_queue:
		if item["key"] == key:
			return true

	# Check active
	return key in _active_loads

## Process loading queue
func _process_queue() -> void:
	# Start new loads if we have capacity
	while _active_loads.size() < _max_concurrent_loads and not _loading_queue.is_empty():
		var load_info: Dictionary = _loading_queue.pop_front()
		_start_load(load_info)

## Start loading an image
func _start_load(load_info: Dictionary) -> void:
	var key: String = load_info["key"]
	var url: String = load_info["url"]

	# Acquire HTTP request from pool
	var http_request: HTTPRequest = null
	if http_pool != null:
		http_request = http_pool.acquire()
	else:
		http_request = HTTPRequest.new()
		add_child(http_request)

	if http_request == null:
		push_error("ImageLoader: Failed to acquire HTTP request")
		image_load_failed.emit(key, "Failed to acquire HTTP request")
		return

	# Track active load
	_active_loads[key] = {
		"key": key,
		"url": url,
		"use_cache": load_info["use_cache"],
		"http_request": http_request,
		"start_time": Time.get_ticks_msec()
	}

	# Connect signals
	http_request.request_completed.connect(_on_load_completed.bind(key))

	# Start request
	var error: int = http_request.request(url)
	if error != OK:
		push_error("ImageLoader: Failed to start request for %s (Error: %d)" % [key, error])
		_handle_load_failure(key, "Failed to start request")

## Handle load completion
func _on_load_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, key: String) -> void:
	if not key in _active_loads:
		return

	var load_info: Dictionary = _active_loads[key]
	var http_request: HTTPRequest = load_info["http_request"]

	# Clean up
	_active_loads.erase(key)
	if http_pool != null:
		http_pool.release(http_request)
	else:
		http_request.queue_free()

	# Check for errors
	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_load_failure(key, "HTTP request failed (Result: %d)" % result)
		return

	if response_code != 200:
		_handle_load_failure(key, "HTTP response error (Code: %d)" % response_code)
		return

	# Load image from buffer
	var image: Image = ImageProcessor.load_image_from_buffer(body)
	if image == null:
		_handle_load_failure(key, "Failed to parse image data")
		return

	# Create texture
	var texture: ImageTexture = ImageTexture.create_from_image(image)

	# Cache if enabled
	if load_info["use_cache"] and image_cache != null:
		image_cache.cache_image(key, image, true)

	# Emit success
	image_loaded.emit(key, texture)

## Handle load failure
func _handle_load_failure(key: String, error_msg: String) -> void:
	if key in _active_loads:
		var load_info: Dictionary = _active_loads[key]
		if load_info.has("http_request"):
			var http_request: HTTPRequest = load_info["http_request"]
			if http_pool != null:
				http_pool.release(http_request)
			else:
				http_request.queue_free()
		_active_loads.erase(key)

	push_error("ImageLoader: %s" % error_msg)
	image_load_failed.emit(key, error_msg)

## Load image from file asynchronously
func _load_file_async(key: String, file_path: String) -> void:
	# For now, load synchronously (Godot doesn't support threaded file loading easily)
	# In production, you might use WorkerThreadPool or custom threading
	var image: Image = ImageProcessor.load_image(file_path)

	if image == null:
		_handle_load_failure(key, "Failed to load file: %s" % file_path)
		return

	var texture: ImageTexture = ImageTexture.create_from_image(image)
	image_loaded.emit(key, texture)

## Emit cached result on next frame
func _emit_cached_result(key: String, texture: ImageTexture) -> void:
	await get_tree().process_frame
	image_loaded.emit(key, texture)

func _exit_tree() -> void:
	cancel_all()
