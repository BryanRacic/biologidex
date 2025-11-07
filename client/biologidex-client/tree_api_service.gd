"""
TreeAPIService - Handles all API communication for taxonomic tree.
Uses APIManager for HTTP requests, matches server DynamicTreeView endpoints.
"""
extends Node

# API endpoints for tree (relative to BASE_URL)
const TREE_ENDPOINT = "/graph/tree/"
const TREE_CHUNK_ENDPOINT = "/graph/tree/chunk/%d/%d/"  # Format with x, y
const TREE_SEARCH_ENDPOINT = "/graph/tree/search/"
const TREE_INVALIDATE_ENDPOINT = "/graph/tree/invalidate/"
const TREE_FRIENDS_ENDPOINT = "/graph/tree/friends/"

# View modes (must match server DynamicTaxonomicTreeService)
enum TreeMode {
	PERSONAL,   # User's dex only
	FRIENDS,    # User + all friends (default)
	SELECTED,   # User + specific friends
	GLOBAL      # All users (admin only)
}

# Mode string values
const MODE_STRINGS = {
	TreeMode.PERSONAL: "personal",
	TreeMode.FRIENDS: "friends",
	TreeMode.SELECTED: "selected",
	TreeMode.GLOBAL: "global",
}

# Signals
signal tree_loaded(tree_data: TreeDataModels.TreeData)
signal tree_load_failed(error: String)
signal chunk_loaded(chunk_id: Vector2i, chunk: TreeDataModels.TreeChunk)
signal chunk_load_failed(chunk_id: Vector2i, error: String)
signal search_results_received(results: Array)
signal search_failed(error: String)
signal friends_list_received(friends: Array)


# =============================================================================
# Tree Data Fetching
# =============================================================================

func fetch_tree(mode: TreeMode = TreeMode.FRIENDS, friend_ids: Array[int] = [], use_cache: bool = true) -> void:
	"""
	Fetch complete tree data from server.

	Args:
		mode: Tree view mode
		friend_ids: Array of friend IDs for SELECTED mode
		use_cache: Whether to use server-side cache
	"""
	var mode_str = MODE_STRINGS[mode]
	print("[TreeAPIService] Fetching tree (mode: ", mode_str, ")")

	# Build query params
	var params = {
		"mode": mode_str,
		"use_cache": "true" if use_cache else "false"
	}

	# Add friend_ids for selected mode
	if mode == TreeMode.SELECTED and friend_ids.size() > 0:
		var friend_ids_str = ",".join(friend_ids.map(func(id): return str(id)))
		params["friend_ids"] = friend_ids_str

	# Build URL with query params
	var url = _build_url(TREE_ENDPOINT, params)

	# Make request
	APIManager.make_request(
		HTTPClient.METHOD_GET,
		url,
		{},
		_on_tree_loaded,
		_on_tree_load_failed
	)


func _on_tree_loaded(response: Dictionary) -> void:
	"""Handle successful tree data response."""
	print("[TreeAPIService] Tree data received")
	print("[TreeAPIService] Nodes: ", response.get("nodes", []).size())
	print("[TreeAPIService] Edges: ", response.get("edges", []).size())

	# Parse response into TreeData model
	var tree_data = TreeDataModels.TreeData.new(response)

	# Cache the data
	var mode = tree_data.metadata.mode
	var user_id = tree_data.metadata.user_id
	TreeCache.save_tree_data(tree_data, mode, user_id)

	# Emit signal
	emit_signal("tree_loaded", tree_data)


func _on_tree_load_failed(error: String) -> void:
	"""Handle tree data loading failure."""
	push_error("[TreeAPIService] Failed to load tree: ", error)
	emit_signal("tree_load_failed", error)


# =============================================================================
# Chunk Loading
# =============================================================================

func fetch_chunk(chunk_x: int, chunk_y: int, mode: TreeMode = TreeMode.FRIENDS, friend_ids: Array[int] = []) -> void:
	"""
	Fetch specific chunk from server.

	Args:
		chunk_x: Chunk X coordinate
		chunk_y: Chunk Y coordinate
		mode: Tree view mode
		friend_ids: Array of friend IDs for SELECTED mode
	"""
	var chunk_id = Vector2i(chunk_x, chunk_y)
	print("[TreeAPIService] Fetching chunk ", chunk_id)

	# Check cache first
	var cached_chunk = TreeCache.load_chunk(chunk_id)
	if cached_chunk:
		emit_signal("chunk_loaded", chunk_id, cached_chunk)
		return

	# Build query params
	var mode_str = MODE_STRINGS[mode]
	var params = {"mode": mode_str}

	if mode == TreeMode.SELECTED and friend_ids.size() > 0:
		var friend_ids_str = ",".join(friend_ids.map(func(id): return str(id)))
		params["friend_ids"] = friend_ids_str

	# Build URL
	var endpoint = TREE_CHUNK_ENDPOINT % [chunk_x, chunk_y]
	var url = _build_url(endpoint, params)

	# Make request
	APIManager.make_request(
		HTTPClient.METHOD_GET,
		url,
		{},
		_on_chunk_loaded.bind(chunk_id),
		_on_chunk_load_failed.bind(chunk_id)
	)


func _on_chunk_loaded(response: Dictionary, chunk_id: Vector2i) -> void:
	"""Handle successful chunk response."""
	print("[TreeAPIService] Chunk ", chunk_id, " received")

	# Parse chunk
	var chunk = TreeDataModels.TreeChunk.new(chunk_id.x, chunk_id.y, response)

	# Cache the chunk
	TreeCache.save_chunk(chunk_id, chunk)

	# Emit signal
	emit_signal("chunk_loaded", chunk_id, chunk)


func _on_chunk_load_failed(error: String, chunk_id: Vector2i) -> void:
	"""Handle chunk loading failure."""
	push_error("[TreeAPIService] Failed to load chunk ", chunk_id, ": ", error)
	emit_signal("chunk_load_failed", chunk_id, error)


# =============================================================================
# Search
# =============================================================================

func search_tree(query: String, mode: TreeMode = TreeMode.FRIENDS, friend_ids: Array[int] = [], limit: int = 50) -> void:
	"""
	Search within current tree scope.

	Args:
		query: Search query string
		mode: Tree view mode
		friend_ids: Array of friend IDs for SELECTED mode
		limit: Maximum results to return
	"""
	if query.strip_edges().is_empty():
		push_error("[TreeAPIService] Search query cannot be empty")
		emit_signal("search_failed", "Query cannot be empty")
		return

	print("[TreeAPIService] Searching for: ", query)

	# Build query params
	var mode_str = MODE_STRINGS[mode]
	var params = {
		"q": query,
		"mode": mode_str,
		"limit": str(limit)
	}

	if mode == TreeMode.SELECTED and friend_ids.size() > 0:
		var friend_ids_str = ",".join(friend_ids.map(func(id): return str(id)))
		params["friend_ids"] = friend_ids_str

	# Build URL
	var url = _build_url(TREE_SEARCH_ENDPOINT, params)

	# Make request
	APIManager.make_request(
		HTTPClient.METHOD_GET,
		url,
		{},
		_on_search_results,
		_on_search_failed
	)


func _on_search_results(response: Dictionary) -> void:
	"""Handle successful search response."""
	var results = response.get("results", [])
	print("[TreeAPIService] Search returned ", results.size(), " results")
	emit_signal("search_results_received", results)


func _on_search_failed(error: String) -> void:
	"""Handle search failure."""
	push_error("[TreeAPIService] Search failed: ", error)
	emit_signal("search_failed", error)


# =============================================================================
# Cache Invalidation
# =============================================================================

func invalidate_cache(scope: String = "user") -> void:
	"""
	Invalidate tree cache on server.

	Args:
		scope: "user" or "global" (admin only)
	"""
	print("[TreeAPIService] Invalidating cache (scope: ", scope, ")")

	var body = {"scope": scope}

	APIManager.make_request(
		HTTPClient.METHOD_POST,
		APIManager.BASE_URL + TREE_INVALIDATE_ENDPOINT,
		body,
		func(response): print("[TreeAPIService] Cache invalidated successfully"),
		func(error): push_error("[TreeAPIService] Cache invalidation failed: ", error)
	)

	# Also clear local cache
	TreeCache.invalidate_tree_cache()


# =============================================================================
# Friends List
# =============================================================================

func fetch_friends_list() -> void:
	"""Fetch friends list with their tree stats."""
	print("[TreeAPIService] Fetching friends list")

	APIManager.make_request(
		HTTPClient.METHOD_GET,
		APIManager.BASE_URL + TREE_FRIENDS_ENDPOINT,
		{},
		_on_friends_list_received,
		func(error): push_error("[TreeAPIService] Failed to fetch friends: ", error)
	)


func _on_friends_list_received(response: Dictionary) -> void:
	"""Handle friends list response."""
	var friends = response.get("friends", [])
	print("[TreeAPIService] Received ", friends.size(), " friends")
	emit_signal("friends_list_received", friends)


# =============================================================================
# Helper Functions
# =============================================================================

func _build_url(endpoint: String, params: Dictionary = {}) -> String:
	"""Build URL with query parameters."""
	var url = APIManager.BASE_URL + endpoint

	if params.size() > 0:
		var param_strings = []
		for key in params:
			param_strings.append("%s=%s" % [key, params[key]])
		url += "?" + "&".join(param_strings)

	return url


func get_mode_string(mode: TreeMode) -> String:
	"""Get string representation of mode."""
	return MODE_STRINGS[mode]
