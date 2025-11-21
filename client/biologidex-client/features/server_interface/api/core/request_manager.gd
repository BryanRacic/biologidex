class_name RequestManager extends Node

## Manages HTTP requests with pooling, cancellation, retry, and deduplication
## Provides a clean interface for making API calls with advanced features

signal request_started(request_id: String)
signal request_completed(request_id: String, result: Dictionary)
signal request_failed(request_id: String, error: String)
signal request_cancelled(request_id: String)

# Configuration
const MAX_RETRIES := 3
const RETRY_DELAY_MS := 1000  # Base delay for exponential backoff
const REQUEST_TIMEOUT := 30.0

# Dependencies
var http_pool: HTTPRequestPool
var http_cache: Variant  # Will be set if caching is enabled

# Private variables
var _active_requests: Dictionary = {}  # request_id -> RequestContext
var _pending_requests: Dictionary = {}  # url+method -> Array of request_ids (deduplication)
var _request_counter: int = 0

func _init(p_http_pool: HTTPRequestPool = null, p_http_cache: Variant = null) -> void:
	http_pool = p_http_pool if p_http_pool != null else HTTPRequestPool.new()
	http_cache = p_http_cache

func _ready() -> void:
	if http_pool.get_parent() == null:
		add_child(http_pool)

## Execute an HTTP request with retry and caching support
func execute_request(
	url: String,
	method: int = HTTPClient.METHOD_GET,
	headers: PackedStringArray = PackedStringArray(),
	body: String = "",
	enable_cache: bool = false,
	cache_max_age: int = 300
) -> String:
	# Check cache first (for GET requests only)
	if enable_cache and method == HTTPClient.METHOD_GET and http_cache != null:
		var cached_response: Variant = http_cache.get_cached_response(url, cache_max_age)
		if cached_response != null:
			# Return immediately with cached data
			var request_id: String = _generate_request_id()
			_emit_cached_response(request_id, cached_response)
			return request_id

	# Check for duplicate pending requests (deduplication)
	var dedup_key: String = _make_dedup_key(url, method)
	if dedup_key in _pending_requests:
		# Piggyback on existing request
		var request_id: String = _generate_request_id()
		_pending_requests[dedup_key].append(request_id)
		return request_id

	# Acquire request from pool
	var http_request: HTTPRequest = http_pool.acquire()
	if http_request == null:
		# Pool exhausted, fail immediately
		var request_id: String = _generate_request_id()
		_emit_failed_response(request_id, "HTTP request pool exhausted")
		return request_id

	# Create request context
	var request_id: String = _generate_request_id()
	var context: Dictionary = {
		"id": request_id,
		"url": url,
		"method": method,
		"headers": headers,
		"body": body,
		"http_request": http_request,
		"retry_count": 0,
		"enable_cache": enable_cache,
		"cache_max_age": cache_max_age,
		"start_time": Time.get_ticks_msec()
	}

	_active_requests[request_id] = context
	_pending_requests[dedup_key] = [request_id]

	# Connect signals
	http_request.request_completed.connect(_on_request_completed.bind(request_id))

	# Start request
	var error: int = http_request.request(url, headers, method, body)
	if error != OK:
		_handle_request_failure(request_id, "Failed to start request (Error: %d)" % error)
		return request_id

	request_started.emit(request_id)
	return request_id

## Cancel an active request
func cancel_request(request_id: String) -> void:
	if not request_id in _active_requests:
		return

	var context: Dictionary = _active_requests[request_id]
	var http_request: HTTPRequest = context["http_request"]

	# Cancel HTTP request
	http_request.cancel_request()

	# Cleanup
	_cleanup_request(request_id)
	request_cancelled.emit(request_id)

## Cancel all active requests
func cancel_all_requests() -> void:
	var request_ids: Array = _active_requests.keys()
	for request_id in request_ids:
		cancel_request(request_id)

## Get active request count
func get_active_request_count() -> int:
	return _active_requests.size()

## Check if a request is active
func is_request_active(request_id: String) -> bool:
	return request_id in _active_requests

## Handle request completion
func _on_request_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray,
	request_id: String
) -> void:
	if not request_id in _active_requests:
		return

	var context: Dictionary = _active_requests[request_id]

	# Check for retry-able errors
	if _should_retry(result, response_code, context):
		_retry_request(request_id)
		return

	# Check for success
	if result == HTTPRequest.RESULT_SUCCESS and (response_code >= 200 and response_code < 300):
		_handle_request_success(request_id, response_code, headers, body)
	else:
		_handle_request_failure(
			request_id,
			"Request failed (Result: %d, Code: %d)" % [result, response_code]
		)

## Handle successful request
func _handle_request_success(
	request_id: String,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if not request_id in _active_requests:
		return

	var context: Dictionary = _active_requests[request_id]
	var url: String = context["url"]
	var method: int = context["method"]

	# Parse response body
	var body_string: String = body.get_string_from_utf8()
	var response_data: Variant = null

	# Try to parse as JSON
	if body_string.length() > 0:
		var json: JSON = JSON.new()
		if json.parse(body_string) == OK:
			response_data = json.data
		else:
			response_data = body_string

	# Create response
	var response: Dictionary = {
		"code": response_code,
		"headers": headers,
		"body": response_data,
		"raw_body": body,
		"duration_ms": Time.get_ticks_msec() - context["start_time"]
	}

	# Cache response if enabled
	if context["enable_cache"] and method == HTTPClient.METHOD_GET and http_cache != null:
		http_cache.cache_response(url, response, context["cache_max_age"])

	# Handle deduplication - notify all waiting requests
	var dedup_key: String = _make_dedup_key(url, method)
	if dedup_key in _pending_requests:
		for waiting_id in _pending_requests[dedup_key]:
			request_completed.emit(waiting_id, response)

		_pending_requests.erase(dedup_key)

	# Cleanup
	_cleanup_request(request_id)

## Handle request failure
func _handle_request_failure(request_id: String, error_message: String) -> void:
	if not request_id in _active_requests:
		return

	var context: Dictionary = _active_requests[request_id]
	var url: String = context["url"]
	var method: int = context["method"]

	# Handle deduplication - notify all waiting requests
	var dedup_key: String = _make_dedup_key(url, method)
	if dedup_key in _pending_requests:
		for waiting_id in _pending_requests[dedup_key]:
			request_failed.emit(waiting_id, error_message)

		_pending_requests.erase(dedup_key)

	# Cleanup
	_cleanup_request(request_id)

## Retry a failed request with exponential backoff
func _retry_request(request_id: String) -> void:
	if not request_id in _active_requests:
		return

	var context: Dictionary = _active_requests[request_id]
	context["retry_count"] += 1

	# Calculate backoff delay
	var delay_ms: int = RETRY_DELAY_MS * (1 << (context["retry_count"] - 1))

	# Wait before retrying
	await get_tree().create_timer(delay_ms / 1000.0).timeout

	# Check if still active (might have been cancelled)
	if not request_id in _active_requests:
		return

	# Retry request
	var http_request: HTTPRequest = context["http_request"]
	var error: int = http_request.request(
		context["url"],
		context["headers"],
		context["method"],
		context["body"]
	)

	if error != OK:
		_handle_request_failure(request_id, "Retry failed (Error: %d)" % error)

## Check if request should be retried
func _should_retry(result: int, response_code: int, context: Dictionary) -> bool:
	# Don't retry if max retries reached
	if context["retry_count"] >= MAX_RETRIES:
		return false

	# Retry on network errors
	if result != HTTPRequest.RESULT_SUCCESS:
		return true

	# Retry on specific HTTP codes
	if response_code in [408, 429, 500, 502, 503, 504]:
		return true

	return false

## Cleanup request resources
func _cleanup_request(request_id: String) -> void:
	if not request_id in _active_requests:
		return

	var context: Dictionary = _active_requests[request_id]
	var http_request: HTTPRequest = context["http_request"]

	# Disconnect signals
	if http_request.request_completed.is_connected(_on_request_completed):
		for connection in http_request.request_completed.get_connections():
			if connection["callable"].get_method() == "_on_request_completed":
				http_request.request_completed.disconnect(connection["callable"])

	# Return to pool
	http_pool.release(http_request)

	# Remove from active
	_active_requests.erase(request_id)

## Generate unique request ID
func _generate_request_id() -> String:
	_request_counter += 1
	return "req_%d_%d" % [Time.get_ticks_msec(), _request_counter]

## Create deduplication key
func _make_dedup_key(url: String, method: int) -> String:
	return "%d:%s" % [method, url]

## Emit cached response
func _emit_cached_response(request_id: String, cached_response: Dictionary) -> void:
	# Emit on next frame to maintain async behavior
	await get_tree().process_frame
	request_completed.emit(request_id, cached_response)

## Emit failed response
func _emit_failed_response(request_id: String, error: String) -> void:
	await get_tree().process_frame
	request_failed.emit(request_id, error)

func _exit_tree() -> void:
	cancel_all_requests()
