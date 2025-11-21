class_name BaseCache extends RefCounted

## Base class for caching implementations
## Provides common interface for all cache types

signal cache_cleared()
signal item_expired(key: String)

# Constants
const DEFAULT_MAX_AGE := 3600  # 1 hour in seconds

# Private variables
var _cache: Dictionary = {}
var _timestamps: Dictionary = {}

## Store an item in the cache
func set_cached(key: String, value: Variant, max_age: int = DEFAULT_MAX_AGE) -> void:
	_cache[key] = value
	_timestamps[key] = {
		"created_at": Time.get_unix_time_from_system(),
		"max_age": max_age
	}

## Retrieve an item from the cache
## Returns null if not found or expired
func get_cached(key: String) -> Variant:
	if not has_cached(key):
		return null

	if _is_expired(key):
		remove_cached(key)
		item_expired.emit(key)
		return null

	return _cache[key]

## Check if a key exists in cache (and is not expired)
func has_cached(key: String) -> bool:
	if not key in _cache:
		return false

	if _is_expired(key):
		remove_cached(key)
		return false

	return true

## Remove an item from the cache
func remove_cached(key: String) -> void:
	_cache.erase(key)
	_timestamps.erase(key)

## Clear all cached items
func clear() -> void:
	_cache.clear()
	_timestamps.clear()
	cache_cleared.emit()

## Remove all expired items
func cleanup_expired() -> int:
	var removed_count := 0
	var keys_to_remove: Array[String] = []

	for key in _timestamps.keys():
		if _is_expired(key):
			keys_to_remove.append(key)

	for key in keys_to_remove:
		remove_cached(key)
		removed_count += 1
		item_expired.emit(key)

	return removed_count

## Get the number of items in cache
func get_size() -> int:
	return _cache.size()

## Get all cache keys
func get_keys() -> Array:
	return _cache.keys()

## Check if a key is expired
func _is_expired(key: String) -> bool:
	if not key in _timestamps:
		return true

	var timestamp_data: Dictionary = _timestamps[key]
	var created_at: float = timestamp_data.get("created_at", 0.0)
	var max_age: int = timestamp_data.get("max_age", DEFAULT_MAX_AGE)
	var current_time: float = Time.get_unix_time_from_system()

	return (current_time - created_at) > max_age

## Get cache statistics
func get_stats() -> Dictionary:
	return {
		"size": get_size(),
		"expired_count": _count_expired()
	}

## Count expired items without removing them
func _count_expired() -> int:
	var count := 0
	for key in _timestamps.keys():
		if _is_expired(key):
			count += 1
	return count
