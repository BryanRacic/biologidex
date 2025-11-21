class_name HTTPRequestPool extends Node

## Pool for HTTPRequest nodes to avoid repeated allocation/deallocation
## Improves performance by reusing request objects

signal pool_exhausted(active_count: int)

# Constants
const DEFAULT_POOL_SIZE := 10
const DEFAULT_MAX_SIZE := 20

# Configuration
var initial_pool_size: int = DEFAULT_POOL_SIZE
var max_pool_size: int = DEFAULT_MAX_SIZE

# Private variables
var _available_requests: Array[HTTPRequest] = []
var _active_requests: Dictionary = {}  # id -> HTTPRequest
var _request_counter: int = 0

func _init(p_initial_size: int = DEFAULT_POOL_SIZE, p_max_size: int = DEFAULT_MAX_SIZE) -> void:
	initial_pool_size = p_initial_size
	max_pool_size = p_max_size

func _ready() -> void:
	# Pre-create initial pool
	for i in range(initial_pool_size):
		var request: HTTPRequest = _create_request()
		_available_requests.append(request)

## Acquire an HTTPRequest from the pool
## Returns null if pool is exhausted and at max size
func acquire() -> HTTPRequest:
	var request: HTTPRequest = null

	# Try to get from available pool
	if not _available_requests.is_empty():
		request = _available_requests.pop_back()
	# Create new if under max size
	elif (_available_requests.size() + _active_requests.size()) < max_pool_size:
		request = _create_request()
	else:
		push_warning("HTTPRequestPool: Pool exhausted (active: %d)" % _active_requests.size())
		pool_exhausted.emit(_active_requests.size())
		return null

	# Track as active
	var request_id: String = _generate_request_id()
	_active_requests[request_id] = request
	request.set_meta("pool_id", request_id)

	return request

## Release an HTTPRequest back to the pool
func release(request: HTTPRequest) -> void:
	if request == null:
		return

	# Get pool ID
	var request_id: String = ""
	if request.has_meta("pool_id"):
		request_id = request.get_meta("pool_id")

	# Remove from active tracking
	if request_id != "" and request_id in _active_requests:
		_active_requests.erase(request_id)

	# Cancel any ongoing request
	request.cancel_request()

	# Reset request state
	_reset_request(request)

	# Return to pool or free if over initial size
	if _available_requests.size() < initial_pool_size:
		_available_requests.append(request)
	else:
		request.queue_free()

## Get pool statistics
func get_stats() -> Dictionary:
	return {
		"available": _available_requests.size(),
		"active": _active_requests.size(),
		"total": _available_requests.size() + _active_requests.size(),
		"max_size": max_pool_size
	}

## Clear all requests and reset pool
func clear() -> void:
	# Free active requests
	for request_id in _active_requests.keys():
		var request: HTTPRequest = _active_requests[request_id]
		request.cancel_request()
		request.queue_free()
	_active_requests.clear()

	# Free available requests
	for request in _available_requests:
		request.queue_free()
	_available_requests.clear()

	# Recreate initial pool
	for i in range(initial_pool_size):
		var request: HTTPRequest = _create_request()
		_available_requests.append(request)

## Create a new HTTPRequest node
func _create_request() -> HTTPRequest:
	var request: HTTPRequest = HTTPRequest.new()
	add_child(request)

	# Configure for best compatibility
	request.use_threads = false  # Important for web exports
	request.accept_gzip = false  # Avoid double decompression
	request.timeout = 30.0  # 30 second timeout

	return request

## Reset request to clean state
func _reset_request(request: HTTPRequest) -> void:
	# Disconnect all signals
	for connection in request.request_completed.get_connections():
		request.request_completed.disconnect(connection["callable"])

	# Clear metadata except pool_id
	var pool_id: String = ""
	if request.has_meta("pool_id"):
		pool_id = request.get_meta("pool_id")

	# Clear all metadata
	for meta_key in request.get_meta_list():
		request.remove_meta(meta_key)

	# Restore pool_id
	if pool_id != "":
		request.set_meta("pool_id", pool_id)

## Generate unique request ID
func _generate_request_id() -> String:
	_request_counter += 1
	return "req_%d_%d" % [Time.get_ticks_msec(), _request_counter]

func _exit_tree() -> void:
	clear()
