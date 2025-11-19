extends Node
class_name APIClient

## APIClient - High-level API client with authentication, retry, and queue management
## Provides common functionality for all API services

const HTTPClientCore = preload("res://api/core/http_client.gd")
const APIConfig = preload("res://api/core/api_config.gd")
const APITypes = preload("res://api/core/api_types.gd")

var http_client
var config

# Request queue
var request_queue: Array = []
var active_requests: int = 0

func _init(client, cfg) -> void:
	http_client = client
	config = cfg

## Make authenticated GET request
func request_get(
	endpoint: String,
	success_callback: Callable,
	error_callback: Callable,
	req_config: APITypes.RequestConfig = null
) -> void:
	if req_config == null:
		req_config = APITypes.RequestConfig.new()

	var url = config.build_url(endpoint)
	var headers = []

	# Add auth header if required
	if req_config.requires_auth:
		var token = TokenManager.get_access_token()
		if token:
			headers.append("Authorization: Bearer %s" % token)

	_queue_request(
		HTTPClient.METHOD_GET,
		url,
		PackedStringArray(headers),
		"",
		req_config,
		success_callback,
		error_callback
	)

## Make authenticated POST request with JSON body
func post(
	endpoint: String,
	data: Dictionary,
	success_callback: Callable,
	error_callback: Callable,
	req_config: APITypes.RequestConfig = null
) -> void:
	if req_config == null:
		req_config = APITypes.RequestConfig.new()

	var url = config.build_url(endpoint)
	var headers = ["Content-Type: application/json"]

	# Add auth header if required
	if req_config.requires_auth:
		var token = TokenManager.get_access_token()
		if token:
			headers.append("Authorization: Bearer %s" % token)

	_queue_json_request(
		HTTPClient.METHOD_POST,
		url,
		data,
		PackedStringArray(headers),
		req_config,
		success_callback,
		error_callback
	)

## Make authenticated PUT request with JSON body
func put(
	endpoint: String,
	data: Dictionary,
	success_callback: Callable,
	error_callback: Callable,
	req_config: APITypes.RequestConfig = null
) -> void:
	if req_config == null:
		req_config = APITypes.RequestConfig.new()

	var url = config.build_url(endpoint)
	var headers = ["Content-Type: application/json"]

	# Add auth header if required
	if req_config.requires_auth:
		var token = TokenManager.get_access_token()
		if token:
			headers.append("Authorization: Bearer %s" % token)

	_queue_json_request(
		HTTPClient.METHOD_PUT,
		url,
		data,
		PackedStringArray(headers),
		req_config,
		success_callback,
		error_callback
	)

## Make authenticated DELETE request
func delete(
	endpoint: String,
	success_callback: Callable,
	error_callback: Callable,
	req_config: APITypes.RequestConfig = null
) -> void:
	if req_config == null:
		req_config = APITypes.RequestConfig.new()

	var url = config.build_url(endpoint)
	var headers = []

	# Add auth header if required
	if req_config.requires_auth:
		var token = TokenManager.get_access_token()
		if token:
			headers.append("Authorization: Bearer %s" % token)

	_queue_request(
		HTTPClient.METHOD_DELETE,
		url,
		PackedStringArray(headers),
		"",
		req_config,
		success_callback,
		error_callback
	)

## Make multipart/form-data request (for file uploads)
func post_multipart(
	endpoint: String,
	fields: Array,
	success_callback: Callable,
	error_callback: Callable,
	req_config: APITypes.RequestConfig = null
) -> void:
	if req_config == null:
		req_config = APITypes.RequestConfig.new()
		req_config.timeout = config.UPLOAD_TIMEOUT

	var url = config.build_url(endpoint)
	const boundary = "GodotBiologiDexBoundary"

	var headers = [
		"Content-Type: multipart/form-data; boundary=%s" % boundary
	]

	# Add auth header if required
	if req_config.requires_auth:
		var token = TokenManager.get_access_token()
		if token:
			headers.append("Authorization: Bearer %s" % token)

	# Build multipart body
	var body = http_client.build_multipart_body_with_fields(boundary, fields)

	_queue_request(
		HTTPClient.METHOD_POST,
		url,
		PackedStringArray(headers),
		body,
		req_config,
		success_callback,
		error_callback
	)

## Queue a request for execution
func _queue_request(
	method: HTTPClient.Method,
	url: String,
	headers: PackedStringArray,
	body: Variant,
	req_config: APITypes.RequestConfig,
	success_callback: Callable,
	error_callback: Callable
) -> void:
	var queued_request = APITypes.QueuedRequest.new(
		method,
		url,
		headers,
		body,
		req_config,
		success_callback,
		error_callback
	)

	request_queue.append(queued_request)
	_process_queue()

## Queue a JSON request
func _queue_json_request(
	method: HTTPClient.Method,
	url: String,
	data: Dictionary,
	headers: PackedStringArray,
	req_config: APITypes.RequestConfig,
	success_callback: Callable,
	error_callback: Callable
) -> void:
	var body = JSON.stringify(data)

	var queued_request = APITypes.QueuedRequest.new(
		method,
		url,
		headers,
		body,
		req_config,
		success_callback,
		error_callback
	)

	request_queue.append(queued_request)
	_process_queue()

## Process the request queue
func _process_queue() -> void:
	while active_requests < config.MAX_CONCURRENT_REQUESTS and request_queue.size() > 0:
		# Sort by priority (higher priority first)
		request_queue.sort_custom(func(a, b): return a.config.priority > b.config.priority)

		var request = request_queue.pop_front()
		_execute_request(request)

## Execute a queued request
func _execute_request(request: APITypes.QueuedRequest) -> void:
	active_requests += 1

	# Wrap callbacks to handle retry and queue processing
	# Use bind() to pass the request object to the callback methods
	var success_wrapper = _on_request_success.bind(request)
	var error_wrapper = _on_request_error.bind(request)

	# Execute based on body type
	if request.body is PackedByteArray:
		# Raw request (multipart)
		http_client.make_raw_request(
			request.method,
			request.url,
			request.headers,
			request.body,
			success_wrapper,
			error_wrapper
		)
	elif request.body is String and not request.body.is_empty():
		# JSON request - parse the body back to dictionary for make_json_request
		var json = JSON.new()
		var parse_result = json.parse(request.body)
		var data = json.data if parse_result == OK else {}

		http_client.make_json_request(
			request.method,
			request.url,
			data,
			success_wrapper,
			error_wrapper,
			Array(request.headers).filter(func(h): return not h.begins_with("Content-Type:"))
		)
	else:
		# GET or DELETE request
		http_client.http_get(request.url, success_wrapper, error_wrapper, Array(request.headers))

## Handle successful request completion
func _on_request_success(data: Dictionary, request: APITypes.QueuedRequest) -> void:
	active_requests -= 1
	request.success_callback.call(data)
	_process_queue()

## Handle request error with retry logic
func _on_request_error(error: APITypes.APIError, request: APITypes.QueuedRequest) -> void:
	active_requests -= 1

	# Don't retry auth errors (401/403) - they won't succeed
	var should_retry = (
		request.config.retry_on_failure
		and request.attempt < request.config.max_retries
		and not error.is_auth_error()
	)

	if should_retry:
		# Retry with exponential backoff
		request.attempt += 1
		var delay = config.get_retry_delay(request.attempt)
		print("[APIClient] Retrying request (attempt %d/%d) after %.2fs" % [request.attempt, request.config.max_retries, delay])

		# Re-queue after delay
		_retry_request_after_delay(request, delay)
	else:
		# Max retries reached, retry disabled, or auth error
		request.error_callback.call(error)
		_process_queue()

## Retry a request after a delay
func _retry_request_after_delay(request: APITypes.QueuedRequest, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	request_queue.append(request)
	_process_queue()

## Get number of pending requests
func get_pending_count() -> int:
	return request_queue.size()

## Get number of active requests
func get_active_count() -> int:
	return active_requests

## Clear all pending requests
func clear_queue() -> void:
	request_queue.clear()