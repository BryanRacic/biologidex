extends BaseService
class_name TreeService

## TreeService - Taxonomic tree API operations

const TreeDataModels = preload("res://tree_data_models.gd")

signal tree_loaded(tree_data: TreeDataModels.TreeData)
signal tree_load_failed(error: APITypes.APIError)
signal chunk_loaded(chunk_id: Vector2i, chunk_data: Dictionary)
signal chunk_load_failed(chunk_id: Vector2i, error: APITypes.APIError)
signal search_results_received(results: Array)
signal search_failed(error: APITypes.APIError)
signal cache_invalidated()
signal friends_list_received(friends: Array)

## Fetch complete tree data from server
## friend_ids should be an array of UUID strings (not integers)
func fetch_tree(
	mode: APITypes.TreeMode = APITypes.TreeMode.FRIENDS,
	friend_ids: Array = [],
	use_cache: bool = true,
	callback: Callable = Callable()
) -> void:
	var mode_str = APITypes.get_tree_mode_string(mode)
	_log("Fetching tree (mode: %s)" % mode_str)

	# Build query params
	var params = {
		"mode": mode_str,
		"use_cache": "true" if use_cache else "false"
	}

	# Add friend_ids for selected mode (expects UUID strings)
	if mode == APITypes.TreeMode.SELECTED and friend_ids.size() > 0:
		var friend_ids_str = ",".join(friend_ids.map(func(id): return str(id)))
		params["friend_ids"] = friend_ids_str

	# Build URL with query params
	var url = _build_url_with_params(config.ENDPOINTS_TREE["tree"], params)

	var req_config = _create_request_config()

	var context = {"callback": callback}

	api_client.request_get(
		url,
		_on_fetch_tree_success.bind(context),
		_on_fetch_tree_error.bind(context),
		req_config
	)

func _on_fetch_tree_success(response: Dictionary, context: Dictionary) -> void:
	_log("Tree data received")
	_log("Nodes: %d" % response.get("nodes", []).size())
	_log("Edges: %d" % response.get("edges", []).size())

	# Parse response into TreeData object
	var tree_data = TreeDataModels.TreeData.new(response)
	tree_loaded.emit(tree_data)

	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_fetch_tree_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "fetch_tree")
	tree_load_failed.emit(error)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Fetch specific chunk from server
func fetch_chunk(
	chunk_x: int,
	chunk_y: int,
	mode: APITypes.TreeMode = APITypes.TreeMode.FRIENDS,
	friend_ids: Array[int] = [],
	callback: Callable = Callable()
) -> void:
	var chunk_id = Vector2i(chunk_x, chunk_y)
	_log("Fetching chunk %s" % chunk_id)

	# Build query params
	var mode_str = APITypes.get_tree_mode_string(mode)
	var params = {"mode": mode_str}

	if mode == APITypes.TreeMode.SELECTED and friend_ids.size() > 0:
		var friend_ids_str = ",".join(friend_ids.map(func(id): return str(id)))
		params["friend_ids"] = friend_ids_str

	# Build URL - note: endpoint already has format specifiers
	var endpoint = config.ENDPOINTS_TREE["chunk"] % [chunk_x, chunk_y]
	var url = _build_url_with_params(endpoint, params)

	var req_config = _create_request_config()

	var context = {"chunk_id": chunk_id, "callback": callback}

	api_client.request_get(
		url,
		_on_fetch_chunk_success.bind(context),
		_on_fetch_chunk_error.bind(context),
		req_config
	)

func _on_fetch_chunk_success(response: Dictionary, context: Dictionary) -> void:
	_log("Chunk %s received" % context.chunk_id)
	chunk_loaded.emit(context.chunk_id, response)
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_fetch_chunk_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "fetch_chunk")
	chunk_load_failed.emit(context.chunk_id, error)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Search within current tree scope
func search_tree(
	query: String,
	mode: APITypes.TreeMode = APITypes.TreeMode.FRIENDS,
	friend_ids: Array[int] = [],
	limit: int = 50,
	callback: Callable = Callable()
) -> void:
	if query.strip_edges().is_empty():
		push_error("[TreeService] Search query cannot be empty")
		var error = APITypes.APIError.new(400, "Query cannot be empty", "Query cannot be empty")
		search_failed.emit(error)
		if callback:
			callback.call({"error": "Query cannot be empty"}, 400)
		return

	_log("Searching for: %s" % query)

	# Build query params
	var mode_str = APITypes.get_tree_mode_string(mode)
	var params = {
		"q": query,
		"mode": mode_str,
		"limit": str(limit)
	}

	if mode == APITypes.TreeMode.SELECTED and friend_ids.size() > 0:
		var friend_ids_str = ",".join(friend_ids.map(func(id): return str(id)))
		params["friend_ids"] = friend_ids_str

	# Build URL
	var url = _build_url_with_params(config.ENDPOINTS_TREE["search"], params)

	var req_config = _create_request_config()

	var context = {"callback": callback}

	api_client.request_get(
		url,
		_on_search_tree_success.bind(context),
		_on_search_tree_error.bind(context),
		req_config
	)

func _on_search_tree_success(response: Dictionary, context: Dictionary) -> void:
	var results = response.get("results", [])
	_log("Search returned %d results" % results.size())
	search_results_received.emit(results)
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_search_tree_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "search_tree")
	search_failed.emit(error)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Invalidate tree cache on server
func invalidate_cache(scope: String = "user", callback: Callable = Callable()) -> void:
	_log("Invalidating cache (scope: %s)" % scope)

	var data = {"scope": scope}

	var req_config = _create_request_config()

	var context = {"callback": callback}

	api_client.post(
		config.ENDPOINTS_TREE["invalidate"],
		data,
		_on_invalidate_cache_success.bind(context),
		_on_invalidate_cache_error.bind(context),
		req_config
	)

func _on_invalidate_cache_success(response: Dictionary, context: Dictionary) -> void:
	_log("Cache invalidated successfully")
	cache_invalidated.emit()
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_invalidate_cache_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "invalidate_cache")
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Fetch friends list with their tree stats
func fetch_friends_list(callback: Callable = Callable()) -> void:
	_log("Fetching friends list")

	var req_config = _create_request_config()

	var context = {"callback": callback}

	api_client.request_get(
		config.ENDPOINTS_TREE["friends"],
		_on_fetch_friends_list_success.bind(context),
		_on_fetch_friends_list_error.bind(context),
		req_config
	)

func _on_fetch_friends_list_success(response: Dictionary, context: Dictionary) -> void:
	var friends = response.get("friends", [])
	_log("Received %d friends" % friends.size())
	friends_list_received.emit(friends)
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_fetch_friends_list_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "fetch_friends_list")
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)
