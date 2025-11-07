"""
TreeCache - Singleton for caching taxonomic tree data.
Handles persistent storage and memory management.
"""
extends Node

# Cache directory structure
const CACHE_DIR = "user://tree_cache/"
const LAYOUT_CACHE_FILE = "tree_data.json"
const CHUNK_CACHE_DIR = "chunks/"
const MAX_CACHED_CHUNKS = 50
const CACHE_VERSION = 1

# In-memory cache
var tree_data: TreeDataModels.TreeData = null
var loaded_chunks: Dictionary = {}  # Vector2i(x,y) -> TreeDataModels.TreeChunk
var chunk_lru: Array[Vector2i] = []  # Least Recently Used tracking

# Cache metadata
var cache_mode: String = ""
var cache_user_id: String = ""
var cache_timestamp: float = 0.0
var cache_ttl: float = 300.0  # 5 minutes default


func _ready() -> void:
	# Ensure cache directory exists
	var dir = DirAccess.open("user://")
	if not dir.dir_exists(CACHE_DIR):
		dir.make_dir_recursive(CACHE_DIR)
	if not dir.dir_exists(CACHE_DIR + CHUNK_CACHE_DIR):
		dir.make_dir_recursive(CACHE_DIR + CHUNK_CACHE_DIR)

	print("[TreeCache] Initialized with cache dir: ", CACHE_DIR)


# =============================================================================
# Tree Data Cache
# =============================================================================

func save_tree_data(data: TreeDataModels.TreeData, mode: String, user_id: String) -> void:
	"""Save complete tree data to disk cache."""
	var cache_data = {
		"version": CACHE_VERSION,
		"mode": mode,
		"user_id": user_id,
		"timestamp": Time.get_unix_time_from_system(),
		"metadata": {
			"mode": data.metadata.mode,
			"username": data.metadata.username,
			"total_nodes": data.metadata.total_nodes,
			"total_edges": data.metadata.total_edges,
		},
		"stats": {
			"total_animals": data.stats.total_animals,
			"user_captures": data.stats.user_captures,
			"friend_captures": data.stats.friend_captures,
		},
		"layout": {
			"world_bounds": {
				"x": data.layout.world_bounds.position.x,
				"y": data.layout.world_bounds.position.y,
				"width": data.layout.world_bounds.size.x,
				"height": data.layout.world_bounds.size.y,
			},
			"chunk_size": {
				"width": data.layout.chunk_size.x,
				"height": data.layout.chunk_size.y,
			}
		},
		"node_count": data.nodes.size(),
		"edge_count": data.edges.size(),
	}

	var json_string = JSON.stringify(cache_data, "\t")
	var file = FileAccess.open(CACHE_DIR + LAYOUT_CACHE_FILE, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("[TreeCache] Saved tree data for mode: ", mode, ", nodes: ", data.nodes.size())
	else:
		push_error("[TreeCache] Failed to save tree data")

	# Update in-memory cache
	tree_data = data
	cache_mode = mode
	cache_user_id = user_id
	cache_timestamp = Time.get_unix_time_from_system()


func load_tree_data(mode: String, user_id: String, max_age: float = 300.0) -> TreeDataModels.TreeData:
	"""
	Load tree data from cache if valid.
	Returns null if cache miss or expired.
	"""
	# Check in-memory cache first
	if tree_data != null and cache_mode == mode and cache_user_id == user_id:
		var age = Time.get_unix_time_from_system() - cache_timestamp
		if age < max_age:
			print("[TreeCache] Using in-memory cached tree data (age: ", int(age), "s)")
			return tree_data

	# Try disk cache
	var file = FileAccess.open(CACHE_DIR + LAYOUT_CACHE_FILE, FileAccess.READ)
	if not file:
		print("[TreeCache] No cached tree data found")
		return null

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("[TreeCache] Failed to parse cached tree data")
		return null

	var cache_data = json.data as Dictionary
	if cache_data.get("version", 0) != CACHE_VERSION:
		print("[TreeCache] Cache version mismatch, invalidating")
		clear_cache()
		return null

	# Check if cache matches requested mode and user
	if cache_data.get("mode", "") != mode or cache_data.get("user_id", "") != user_id:
		print("[TreeCache] Cache mode/user mismatch")
		return null

	# Check cache age
	var timestamp = cache_data.get("timestamp", 0.0) as float
	var age = Time.get_unix_time_from_system() - timestamp
	if age > max_age:
		print("[TreeCache] Cache expired (age: ", int(age), "s)")
		return null

	print("[TreeCache] Loaded tree metadata from cache (age: ", int(age), "s)")
	print("[TreeCache] Note: Full node/edge data must be fetched from API")

	# Note: We only cache metadata, not full node/edge arrays
	# This is because the API response is already fast and we want fresh data
	# Chunks are cached separately for progressive loading

	return null  # Always return null for now, let API provide fresh data


func invalidate_tree_cache() -> void:
	"""Clear tree data cache."""
	tree_data = null
	cache_mode = ""
	cache_user_id = ""
	cache_timestamp = 0.0

	var file_path = CACHE_DIR + LAYOUT_CACHE_FILE
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
	print("[TreeCache] Tree cache invalidated")


# =============================================================================
# Chunk Cache
# =============================================================================

func save_chunk(chunk_id: Vector2i, chunk: TreeDataModels.TreeChunk) -> void:
	"""Save chunk data to disk cache."""
	var chunk_data = {
		"version": CACHE_VERSION,
		"chunk_id": {"x": chunk_id.x, "y": chunk_id.y},
		"timestamp": Time.get_unix_time_from_system(),
		"bounds": {
			"x": chunk.world_bounds.position.x,
			"y": chunk.world_bounds.position.y,
			"width": chunk.world_bounds.size.x,
			"height": chunk.world_bounds.size.y,
		},
		"node_ids": chunk.node_ids,
		"edge_indices": chunk.edge_indices,
	}

	var json_string = JSON.stringify(chunk_data)
	var chunk_file = _get_chunk_filename(chunk_id)
	var file = FileAccess.open(chunk_file, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		_add_to_memory_cache(chunk_id, chunk)
	else:
		push_error("[TreeCache] Failed to save chunk: ", chunk_id)


func load_chunk(chunk_id: Vector2i, max_age: float = 600.0) -> TreeDataModels.TreeChunk:
	"""
	Load chunk from cache if valid.
	Returns null if cache miss or expired.
	"""
	# Check memory cache first
	if chunk_id in loaded_chunks:
		_update_lru(chunk_id)
		print("[TreeCache] Chunk ", chunk_id, " from memory cache")
		return loaded_chunks[chunk_id]

	# Try disk cache
	var chunk_file = _get_chunk_filename(chunk_id)
	if not FileAccess.file_exists(chunk_file):
		return null

	var file = FileAccess.open(chunk_file, FileAccess.READ)
	if not file:
		return null

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("[TreeCache] Failed to parse cached chunk")
		return null

	var chunk_data = json.data as Dictionary
	if chunk_data.get("version", 0) != CACHE_VERSION:
		return null

	# Check age
	var timestamp = chunk_data.get("timestamp", 0.0) as float
	var age = Time.get_unix_time_from_system() - timestamp
	if age > max_age:
		return null

	# Parse chunk
	var chunk = TreeDataModels.TreeChunk.new(chunk_id.x, chunk_id.y, {
		"bounds": chunk_data.get("bounds", {}),
		"node_ids": chunk_data.get("node_ids", []),
		"edges": chunk_data.get("edge_indices", []),
	})

	_add_to_memory_cache(chunk_id, chunk)
	print("[TreeCache] Chunk ", chunk_id, " loaded from disk (age: ", int(age), "s)")

	return chunk


func _add_to_memory_cache(chunk_id: Vector2i, chunk: TreeDataModels.TreeChunk) -> void:
	"""Add chunk to memory cache with LRU eviction."""
	if loaded_chunks.size() >= MAX_CACHED_CHUNKS:
		# Evict oldest chunk
		if chunk_lru.size() > 0:
			var oldest = chunk_lru.pop_front()
			loaded_chunks.erase(oldest)
			print("[TreeCache] Evicted chunk ", oldest, " from memory")

	loaded_chunks[chunk_id] = chunk
	chunk_lru.append(chunk_id)


func _update_lru(chunk_id: Vector2i) -> void:
	"""Update LRU list when chunk is accessed."""
	var idx = chunk_lru.find(chunk_id)
	if idx >= 0:
		chunk_lru.remove_at(idx)
		chunk_lru.append(chunk_id)


func _get_chunk_filename(chunk_id: Vector2i) -> String:
	"""Get cache filename for chunk."""
	return CACHE_DIR + CHUNK_CACHE_DIR + "%d_%d.json" % [chunk_id.x, chunk_id.y]


func clear_chunk_cache() -> void:
	"""Clear all cached chunks."""
	loaded_chunks.clear()
	chunk_lru.clear()

	# Delete chunk files
	var dir = DirAccess.open(CACHE_DIR + CHUNK_CACHE_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json"):
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

	print("[TreeCache] Chunk cache cleared")


# =============================================================================
# Cache Management
# =============================================================================

func clear_cache() -> void:
	"""Clear all cached data."""
	invalidate_tree_cache()
	clear_chunk_cache()
	print("[TreeCache] All caches cleared")


func get_cache_stats() -> Dictionary:
	"""Get current cache statistics."""
	return {
		"has_tree_data": tree_data != null,
		"cache_mode": cache_mode,
		"cache_age": Time.get_unix_time_from_system() - cache_timestamp if tree_data else 0,
		"loaded_chunks": loaded_chunks.size(),
		"max_chunks": MAX_CACHED_CHUNKS,
	}
