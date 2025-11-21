class_name MemoryCache extends BaseCache

## In-memory caching with size limits and LRU eviction
## Best for frequently accessed, non-persistent data

signal cache_full(size: int)
signal item_evicted(key: String)

# Constants
const DEFAULT_MAX_SIZE := 100  # Maximum number of items
const DEFAULT_MAX_MEMORY_MB := 50.0  # Maximum memory in MB

# Configuration
var max_size: int = DEFAULT_MAX_SIZE
var max_memory_bytes: int = int(DEFAULT_MAX_MEMORY_MB * 1024 * 1024)

# Private variables
var _access_order: Array[String] = []  # LRU tracking
var _item_sizes: Dictionary = {}  # Track size of each item
var _total_memory: int = 0

func _init(p_max_size: int = DEFAULT_MAX_SIZE, p_max_memory_mb: float = DEFAULT_MAX_MEMORY_MB) -> void:
	max_size = p_max_size
	max_memory_bytes = int(p_max_memory_mb * 1024 * 1024)

## Store an item with LRU tracking
func set_cached(key: String, value: Variant, max_age: int = DEFAULT_MAX_AGE) -> void:
	# Remove old entry if exists
	if has_cached(key):
		_remove_from_lru(key)
		_update_memory_usage(key, 0)

	# Estimate memory usage
	var item_size: int = _estimate_size(value)

	# Evict items if necessary
	while (_cache.size() >= max_size or (_total_memory + item_size) > max_memory_bytes) and not _cache.is_empty():
		_evict_lru()

	# Check if we can fit this item
	if _cache.is_empty() and item_size > max_memory_bytes:
		push_warning("MemoryCache: Item too large for cache: %d bytes" % item_size)
		return

	# Store item
	super.set_cached(key, value, max_age)
	_access_order.append(key)
	_item_sizes[key] = item_size
	_total_memory += item_size

	if _cache.size() >= max_size:
		cache_full.emit(_cache.size())

## Retrieve item and update LRU
func get_cached(key: String) -> Variant:
	var value: Variant = super.get_cached(key)
	if value != null:
		_update_lru(key)
	return value

## Remove item and clean up tracking
func remove_cached(key: String) -> void:
	if key in _cache:
		_remove_from_lru(key)
		_update_memory_usage(key, 0)
		super.remove_cached(key)

## Clear all with tracking cleanup
func clear() -> void:
	_access_order.clear()
	_item_sizes.clear()
	_total_memory = 0
	super.clear()

## Get cache statistics with memory info
func get_stats() -> Dictionary:
	var base_stats: Dictionary = super.get_stats()
	base_stats["memory_used_bytes"] = _total_memory
	base_stats["memory_used_mb"] = _total_memory / 1024.0 / 1024.0
	base_stats["memory_limit_mb"] = max_memory_bytes / 1024.0 / 1024.0
	base_stats["size_limit"] = max_size
	base_stats["memory_usage_percent"] = (_total_memory * 100.0) / max_memory_bytes if max_memory_bytes > 0 else 0.0
	return base_stats

## Evict least recently used item
func _evict_lru() -> void:
	if _access_order.is_empty():
		return

	var key: String = _access_order[0]
	item_evicted.emit(key)
	remove_cached(key)

## Update LRU order when accessing an item
func _update_lru(key: String) -> void:
	_remove_from_lru(key)
	_access_order.append(key)

## Remove from LRU tracking
func _remove_from_lru(key: String) -> void:
	var index: int = _access_order.find(key)
	if index >= 0:
		_access_order.remove_at(index)

## Update memory usage tracking
func _update_memory_usage(key: String, new_size: int) -> void:
	if key in _item_sizes:
		_total_memory -= _item_sizes[key]
		if new_size == 0:
			_item_sizes.erase(key)
		else:
			_item_sizes[key] = new_size
			_total_memory += new_size
	elif new_size > 0:
		_item_sizes[key] = new_size
		_total_memory += new_size

## Estimate size of a value in bytes
func _estimate_size(value: Variant) -> int:
	var type: int = typeof(value)
	match type:
		TYPE_NIL:
			return 0
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return 8
		TYPE_STRING:
			return value.length() * 2  # Approximate UTF-16 size
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return 16
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return 24
		TYPE_COLOR:
			return 32
		TYPE_DICTIONARY:
			var size := 0
			for k in value.keys():
				size += _estimate_size(k)
				size += _estimate_size(value[k])
			return size
		TYPE_ARRAY:
			var size := 0
			for item in value:
				size += _estimate_size(item)
			return size
		TYPE_PACKED_BYTE_ARRAY:
			return value.size()
		TYPE_OBJECT:
			if value is Image:
				return value.get_width() * value.get_height() * 4  # RGBA
			elif value is Texture2D:
				return 1024 * 1024  # Estimate 1MB for textures
			else:
				return 1024  # Default estimate for objects
		_:
			return 512  # Default estimate
