class_name HTTPCache extends Node

## HTTP response caching with both memory and disk layers
## Supports cache invalidation, ETags, and conditional requests

signal response_cached(url: String)
signal cache_hit(url: String)
signal cache_miss(url: String)

# Cache layers
var memory_cache: MemoryCache
var disk_cache: DiskCache

# Configuration
const MEMORY_CACHE_SIZE := 100
const DISK_CACHE_SIZE_MB := 50.0
const DEFAULT_MAX_AGE := 300  # 5 minutes

func _init() -> void:
	memory_cache = MemoryCache.new(MEMORY_CACHE_SIZE, 20.0)  # 20MB memory
	disk_cache = DiskCache.new("user://http_cache/", DISK_CACHE_SIZE_MB)

func _ready() -> void:
	# Periodic cleanup
	var timer: Timer = Timer.new()
	timer.wait_time = 120.0  # Every 2 minutes
	timer.timeout.connect(_on_cleanup_timer)
	add_child(timer)
	timer.start()

## Cache an HTTP response
func cache_response(url: String, response: Dictionary, max_age: int = DEFAULT_MAX_AGE) -> void:
	var cache_key: String = _make_cache_key(url)
	var cache_data: Dictionary = {
		"response": response,
		"cached_at": Time.get_unix_time_from_system(),
		"url": url
	}

	# Store in both layers
	memory_cache.set_cached(cache_key, cache_data, max_age)
	disk_cache.set_cached(cache_key, cache_data, max_age)

	response_cached.emit(url)

## Get cached response if available and not expired
func get_cached_response(url: String, max_age: int = DEFAULT_MAX_AGE) -> Variant:
	var cache_key: String = _make_cache_key(url)

	# Try memory first
	var cached_data: Variant = memory_cache.get_cached(cache_key)
	if cached_data != null:
		if _is_response_valid(cached_data, max_age):
			cache_hit.emit(url)
			return cached_data["response"]

	# Try disk
	cached_data = disk_cache.get_cached(cache_key)
	if cached_data != null:
		if _is_response_valid(cached_data, max_age):
			# Promote to memory cache
			memory_cache.set_cached(cache_key, cached_data, max_age)
			cache_hit.emit(url)
			return cached_data["response"]

	cache_miss.emit(url)
	return null

## Check if response is cached
func has_cached_response(url: String, max_age: int = DEFAULT_MAX_AGE) -> bool:
	var cache_key: String = _make_cache_key(url)
	return memory_cache.has_cached(cache_key) or disk_cache.has_cached(cache_key)

## Invalidate cached response
func invalidate(url: String) -> void:
	var cache_key: String = _make_cache_key(url)
	memory_cache.remove_cached(cache_key)
	disk_cache.remove_cached(cache_key)

## Invalidate all responses matching a pattern
func invalidate_pattern(pattern: String) -> void:
	var regex: RegEx = RegEx.new()
	regex.compile(pattern)

	# Invalidate from memory
	for key in memory_cache.get_keys():
		var cached_data: Variant = memory_cache.get_cached(key)
		if cached_data is Dictionary and cached_data.has("url"):
			if regex.search(cached_data["url"]) != null:
				memory_cache.remove_cached(key)

	# Invalidate from disk
	for key in disk_cache.get_keys():
		var cached_data: Variant = disk_cache.get_cached(key)
		if cached_data is Dictionary and cached_data.has("url"):
			if regex.search(cached_data["url"]) != null:
				disk_cache.remove_cached(key)

## Clear all cached responses
func clear_all() -> void:
	memory_cache.clear()
	disk_cache.clear()

## Get cache statistics
func get_stats() -> Dictionary:
	return {
		"memory": memory_cache.get_stats(),
		"disk": disk_cache.get_stats()
	}

## Create cache key from URL
func _make_cache_key(url: String) -> String:
	return url.md5_text()

## Check if cached response is still valid
func _is_response_valid(cached_data: Dictionary, max_age: int) -> bool:
	if not cached_data.has("cached_at"):
		return false

	var cached_at: float = cached_data["cached_at"]
	var current_time: float = Time.get_unix_time_from_system()
	var age: float = current_time - cached_at

	return age <= max_age

## Periodic cleanup
func _on_cleanup_timer() -> void:
	memory_cache.cleanup_expired()

func _exit_tree() -> void:
	# Cleanup on exit
	memory_cache.cleanup_expired()
