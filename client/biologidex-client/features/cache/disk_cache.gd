class_name DiskCache extends BaseCache

## Disk-based caching with persistent storage
## Best for large data that should survive app restarts

signal disk_error(error_msg: String)
signal disk_write_complete(key: String)

# Constants
const DEFAULT_CACHE_DIR := "user://cache/"
const METADATA_FILE := "cache_metadata.json"
const DEFAULT_MAX_DISK_SIZE_MB := 100.0

# Configuration
var cache_directory: String = DEFAULT_CACHE_DIR
var max_disk_size_bytes: int = int(DEFAULT_MAX_DISK_SIZE_MB * 1024 * 1024)

# Private variables
var _disk_usage: int = 0
var _metadata: Dictionary = {}

func _init(p_cache_dir: String = DEFAULT_CACHE_DIR, p_max_size_mb: float = DEFAULT_MAX_DISK_SIZE_MB) -> void:
	cache_directory = p_cache_dir
	max_disk_size_bytes = int(p_max_size_mb * 1024 * 1024)
	_ensure_cache_dir_exists()
	_load_metadata()

## Store an item to disk
func set_cached(key: String, value: Variant, max_age: int = DEFAULT_MAX_AGE) -> void:
	var file_path: String = _get_cache_file_path(key)
	var serialized: String = JSON.stringify(value)
	var file_size: int = serialized.length()

	# Check if we need to free up space
	while (_disk_usage + file_size) > max_disk_size_bytes and not _cache.is_empty():
		_evict_oldest()

	# Write to disk
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		var error_msg: String = "Failed to write cache file: %s (Error: %d)" % [file_path, FileAccess.get_open_error()]
		push_error(error_msg)
		disk_error.emit(error_msg)
		return

	file.store_string(serialized)
	file.close()

	# Update in-memory tracking
	super.set_cached(key, null, max_age)  # Don't store value in memory
	_metadata[key] = {
		"file_path": file_path,
		"size": file_size,
		"created_at": Time.get_unix_time_from_system(),
		"max_age": max_age
	}

	_disk_usage += file_size
	_save_metadata()
	disk_write_complete.emit(key)

## Retrieve an item from disk
func get_cached(key: String) -> Variant:
	if not has_cached(key):
		return null

	if _is_expired(key):
		remove_cached(key)
		item_expired.emit(key)
		return null

	var file_path: String = _get_cache_file_path(key)
	if not FileAccess.file_exists(file_path):
		push_warning("DiskCache: Cache file missing: %s" % file_path)
		remove_cached(key)
		return null

	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		var error_msg: String = "Failed to read cache file: %s" % file_path
		push_error(error_msg)
		disk_error.emit(error_msg)
		return null

	var content: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var parse_result: int = json.parse(content)
	if parse_result != OK:
		push_error("DiskCache: Failed to parse cache file: %s" % file_path)
		remove_cached(key)
		return null

	return json.data

## Remove an item from disk
func remove_cached(key: String) -> void:
	if key in _metadata:
		var file_path: String = _metadata[key].get("file_path", "")
		var file_size: int = _metadata[key].get("size", 0)

		if FileAccess.file_exists(file_path):
			var dir: DirAccess = DirAccess.open(cache_directory)
			if dir != null:
				dir.remove(file_path)

		_disk_usage -= file_size
		_metadata.erase(key)

	super.remove_cached(key)
	_save_metadata()

## Clear all cached files
func clear() -> void:
	var dir: DirAccess = DirAccess.open(cache_directory)
	if dir == null:
		return

	for key in _metadata.keys():
		var file_path: String = _metadata[key].get("file_path", "")
		if FileAccess.file_exists(file_path):
			dir.remove(file_path)

	_metadata.clear()
	_disk_usage = 0
	super.clear()
	_save_metadata()

## Get cache statistics with disk info
func get_stats() -> Dictionary:
	var base_stats: Dictionary = super.get_stats()
	base_stats["disk_used_bytes"] = _disk_usage
	base_stats["disk_used_mb"] = _disk_usage / 1024.0 / 1024.0
	base_stats["disk_limit_mb"] = max_disk_size_bytes / 1024.0 / 1024.0
	base_stats["disk_usage_percent"] = (_disk_usage * 100.0) / max_disk_size_bytes if max_disk_size_bytes > 0 else 0.0
	return base_stats

## Check if a key exists and update tracking from metadata
func has_cached(key: String) -> bool:
	if key in _metadata:
		var metadata: Dictionary = _metadata[key]
		_timestamps[key] = {
			"created_at": metadata.get("created_at", 0.0),
			"max_age": metadata.get("max_age", DEFAULT_MAX_AGE)
		}
		_cache[key] = null  # Marker that it exists
		return not _is_expired(key)
	return false

## Ensure cache directory exists
func _ensure_cache_dir_exists() -> void:
	if not DirAccess.dir_exists_absolute(cache_directory):
		DirAccess.make_dir_recursive_absolute(cache_directory)

## Get file path for a cache key
func _get_cache_file_path(key: String) -> String:
	var safe_key: String = key.md5_text()  # Hash to create safe filename
	return cache_directory.path_join(safe_key + ".cache")

## Load metadata from disk
func _load_metadata() -> void:
	var metadata_path: String = cache_directory.path_join(METADATA_FILE)
	if not FileAccess.file_exists(metadata_path):
		return

	var file: FileAccess = FileAccess.open(metadata_path, FileAccess.READ)
	if file == null:
		return

	var content: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	if json.parse(content) == OK:
		_metadata = json.data
		_recalculate_disk_usage()

## Save metadata to disk
func _save_metadata() -> void:
	var metadata_path: String = cache_directory.path_join(METADATA_FILE)
	var file: FileAccess = FileAccess.open(metadata_path, FileAccess.WRITE)
	if file == null:
		return

	file.store_string(JSON.stringify(_metadata))
	file.close()

## Recalculate disk usage from metadata
func _recalculate_disk_usage() -> void:
	_disk_usage = 0
	for key in _metadata.keys():
		_disk_usage += _metadata[key].get("size", 0)

## Evict oldest item based on creation time
func _evict_oldest() -> void:
	if _metadata.is_empty():
		return

	var oldest_key: String = ""
	var oldest_time: float = INF

	for key in _metadata.keys():
		var created_at: float = _metadata[key].get("created_at", 0.0)
		if created_at < oldest_time:
			oldest_time = created_at
			oldest_key = key

	if oldest_key != "":
		remove_cached(oldest_key)
