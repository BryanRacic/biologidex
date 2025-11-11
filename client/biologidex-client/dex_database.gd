extends Node
## DexDatabase - Multi-user local storage for discovered animals
## Version 2.0 - Supports multiple users' dex data with image cache deduplication

const DATABASE_VERSION := "2.0"
const OLD_DATABASE_PATH := "user://dex_database.json"
const DATABASE_DIR := "user://dex_data/"
const CACHE_DIR := "user://dex_cache/"

## Structure: {user_id: {creation_index: record}}
## Record format: {
##   "creation_index": int,
##   "scientific_name": String,
##   "common_name": String,
##   "cached_image_path": String,
##   "image_checksum": String (optional),
##   "dex_compatible_url": String (optional),
##   "updated_at": String (optional ISO timestamp)
## }
var dex_data: Dictionary = {}

## Current viewing user (for backwards compatibility)
var current_user_id: String = "self"

## Sorted indices per user: {user_id: Array[int]}
var sorted_indices_per_user: Dictionary = {}

signal record_added(record: Dictionary, user_id: String)
signal database_loaded()
signal database_switched(user_id: String)

## Legacy signal for backwards compatibility
signal record_added_legacy(creation_index: int)


func _ready() -> void:
	print("[DexDatabase] Initializing v%s..." % DATABASE_VERSION)
	ensure_directories()
	migrate_from_v1()
	load_all_databases()


## Ensure required directories exist
func ensure_directories() -> void:
	var dir := DirAccess.open("user://")
	if not dir:
		push_error("[DexDatabase] Failed to access user:// directory")
		return

	if not dir.dir_exists(DATABASE_DIR):
		dir.make_dir(DATABASE_DIR)
		print("[DexDatabase] Created directory: ", DATABASE_DIR)

	if not dir.dir_exists(CACHE_DIR):
		dir.make_dir(CACHE_DIR)
		print("[DexDatabase] Created directory: ", CACHE_DIR)


## Migrate from v1 single-user database to v2 multi-user
func migrate_from_v1() -> void:
	if not FileAccess.file_exists(OLD_DATABASE_PATH):
		return

	print("[DexDatabase] Migrating from v1 database...")

	var file := FileAccess.open(OLD_DATABASE_PATH, FileAccess.READ)
	if not file:
		push_error("[DexDatabase] Failed to open v1 database")
		return

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		push_error("[DexDatabase] Failed to parse v1 database")
		return

	var data: Dictionary = json.data
	if not data.has("records"):
		return

	# Convert v1 records to v2 format
	var v1_records: Dictionary = data["records"]
	for key in v1_records:
		var index := int(key)
		var record: Dictionary = v1_records[key]

		# Add record with expanded format
		add_record_from_dict(record, "self")

	# Rename old database to backup
	DirAccess.rename_absolute(OLD_DATABASE_PATH, OLD_DATABASE_PATH + ".v1.backup")
	print("[DexDatabase] Migration complete. Backup saved at: ", OLD_DATABASE_PATH + ".v1.backup")


## Load all user databases
func load_all_databases() -> void:
	var dir := DirAccess.open(DATABASE_DIR)
	if not dir:
		print("[DexDatabase] No databases to load")
		database_loaded.emit()
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	var loaded_count := 0

	while file_name != "":
		if file_name.ends_with("_dex.json"):
			var user_id := file_name.replace("_dex.json", "")
			load_database(user_id)
			loaded_count += 1
		file_name = dir.get_next()

	dir.list_dir_end()
	print("[DexDatabase] Loaded %d user databases" % loaded_count)
	database_loaded.emit()


## Add or update a dex record (backwards compatible)
func add_record(
	creation_index: int,
	scientific_name: String,
	common_name: String,
	cached_image_path: String
) -> void:
	var record := {
		"creation_index": creation_index,
		"scientific_name": scientific_name,
		"common_name": common_name,
		"cached_image_path": cached_image_path
	}
	add_record_from_dict(record, current_user_id)


## Add or update a record from dictionary (new multi-user method)
func add_record_from_dict(record: Dictionary, user_id: String = "self") -> void:
	if not dex_data.has(user_id):
		dex_data[user_id] = {}
		sorted_indices_per_user[user_id] = []

	var creation_index: int = record.get("creation_index", -1)
	if creation_index < 0:
		push_error("[DexDatabase] Invalid creation_index in record")
		return

	dex_data[user_id][creation_index] = record

	# Update sorted indices
	var indices: Array = sorted_indices_per_user[user_id]
	if creation_index not in indices:
		indices.append(creation_index)
		indices.sort()
		sorted_indices_per_user[user_id] = indices

	print("[DexDatabase] Added record #%d for user '%s': %s" % [
		creation_index, user_id, record.get("scientific_name", "Unknown")
	])

	save_database(user_id)
	record_added.emit(record, user_id)

	# Emit legacy signal for backwards compatibility
	if user_id == current_user_id:
		record_added_legacy.emit(creation_index)


## Get a specific record by creation_index (backwards compatible)
func get_record(creation_index: int) -> Dictionary:
	return get_record_for_user(creation_index, current_user_id)


## Get a specific record for a user (new)
func get_record_for_user(creation_index: int, user_id: String = "self") -> Dictionary:
	if dex_data.has(user_id) and dex_data[user_id].has(creation_index):
		return dex_data[user_id][creation_index]
	return {}


## Get all records as dictionary (backwards compatible)
func get_all_records() -> Dictionary:
	if dex_data.has(current_user_id):
		return dex_data[current_user_id].duplicate()
	return {}


## Get all records for a user as array (new)
func get_all_records_for_user(user_id: String = "self") -> Array:
	if not dex_data.has(user_id):
		return []
	return dex_data[user_id].values()


## Get sorted indices (backwards compatible)
func get_sorted_indices() -> Array[int]:
	return get_sorted_indices_for_user(current_user_id)


## Get sorted indices for a user (new)
func get_sorted_indices_for_user(user_id: String = "self") -> Array[int]:
	if sorted_indices_per_user.has(user_id):
		var result: Array[int] = []
		result.assign(sorted_indices_per_user[user_id])
		return result
	return []


## Get record count (backwards compatible)
func get_record_count() -> int:
	return get_record_count_for_user(current_user_id)


## Get record count for a user (new)
func get_record_count_for_user(user_id: String = "self") -> int:
	if dex_data.has(user_id):
		return dex_data[user_id].size()
	return 0


## Get next index (backwards compatible)
func get_next_index(current_index: int) -> int:
	return get_next_index_for_user(current_index, current_user_id)


## Get next index for a user (new)
func get_next_index_for_user(current_index: int, user_id: String = "self") -> int:
	if not sorted_indices_per_user.has(user_id):
		return -1

	var indices: Array = sorted_indices_per_user[user_id]
	var pos := indices.find(current_index)
	if pos >= 0 and pos < indices.size() - 1:
		return indices[pos + 1]
	return -1


## Get previous index (backwards compatible)
func get_previous_index(current_index: int) -> int:
	return get_previous_index_for_user(current_index, current_user_id)


## Get previous index for a user (new)
func get_previous_index_for_user(current_index: int, user_id: String = "self") -> int:
	if not sorted_indices_per_user.has(user_id):
		return -1

	var indices: Array = sorted_indices_per_user[user_id]
	var pos := indices.find(current_index)
	if pos > 0:
		return indices[pos - 1]
	return -1


## Get first index (backwards compatible)
func get_first_index() -> int:
	return get_first_index_for_user(current_user_id)


## Get first index for a user (new)
func get_first_index_for_user(user_id: String = "self") -> int:
	if not sorted_indices_per_user.has(user_id):
		return -1

	var indices: Array = sorted_indices_per_user[user_id]
	if indices.size() > 0:
		return indices[0]
	return -1


## Check if record exists (backwards compatible)
func has_record(creation_index: int) -> bool:
	return has_record_for_user(creation_index, current_user_id)


## Check if record exists for a user (new)
func has_record_for_user(creation_index: int, user_id: String = "self") -> bool:
	return dex_data.has(user_id) and dex_data[user_id].has(creation_index)


## Switch current viewing user
func switch_user(user_id: String) -> void:
	current_user_id = user_id
	print("[DexDatabase] Switched to user: ", user_id)
	database_switched.emit(user_id)


## Get all tracked user IDs
func get_tracked_users() -> Array:
	return dex_data.keys()


## Clear database for a user
func clear_database(user_id: String = "self") -> void:
	if dex_data.has(user_id):
		dex_data.erase(user_id)
	if sorted_indices_per_user.has(user_id):
		sorted_indices_per_user.erase(user_id)

	# Delete file
	var file_path := get_database_path(user_id)
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)

	print("[DexDatabase] Cleared database for user: ", user_id)


## Get database file path for a user
func get_database_path(user_id: String) -> String:
	return DATABASE_DIR + user_id + "_dex.json"


## Get cache directory for a user
func get_cache_dir(user_id: String) -> String:
	return CACHE_DIR + user_id + "/"


## Save database for a specific user
func save_database(user_id: String) -> void:
	var file_path := get_database_path(user_id)
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		push_error("[DexDatabase] Failed to open database for writing: ", file_path)
		return

	var data := {
		"version": DATABASE_VERSION,
		"user_id": user_id,
		"records": dex_data.get(user_id, {}),
		"last_updated": Time.get_datetime_string_from_system(true)
	}

	file.store_string(JSON.stringify(data, "\t"))
	file.close()


## Load database for a specific user
func load_database(user_id: String) -> void:
	var file_path := get_database_path(user_id)
	if not FileAccess.file_exists(file_path):
		return

	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("[DexDatabase] Failed to open database: ", file_path)
		return

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		push_error("[DexDatabase] Failed to parse database: ", file_path)
		return

	var data: Dictionary = json.data
	if not data.has("records"):
		return

	# Load records
	var loaded_records: Dictionary = data["records"]
	dex_data[user_id] = {}
	var indices: Array[int] = []

	for key in loaded_records:
		var index := int(key)
		dex_data[user_id][index] = loaded_records[key]
		indices.append(index)

	indices.sort()
	sorted_indices_per_user[user_id] = indices

	print("[DexDatabase] Loaded database for '%s' (%d records)" % [user_id, indices.size()])


## Cache an image with deduplication support
## Returns the local file path where the image is cached
func cache_image(image_url: String, image_data: PackedByteArray, user_id: String = "self") -> String:
	# Use URL hash for filename
	var hash := image_url.sha256_text()
	var filename := hash + ".png"

	# First, check if image already exists in any user's cache
	var shared_path := check_shared_image(hash)
	if shared_path:
		print("[DexDatabase] Using shared cached image: ", shared_path)
		return shared_path

	# Create user's cache directory if needed
	var cache_dir := get_cache_dir(user_id)
	ensure_directory(cache_dir)

	# Save new image
	var file_path := cache_dir + filename
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		push_error("[DexDatabase] Failed to cache image: ", file_path)
		return ""

	file.store_buffer(image_data)
	file.close()

	print("[DexDatabase] Cached image for user '%s': %s" % [user_id, filename])
	return file_path


## Check if an image exists in any user's cache (deduplication)
## Returns the full path if found, empty string otherwise
func check_shared_image(hash: String) -> String:
	var dir := DirAccess.open(CACHE_DIR)
	if not dir:
		return ""

	dir.list_dir_begin()
	var user_dir_name := dir.get_next()

	while user_dir_name != "":
		if dir.current_is_dir():
			var image_path := CACHE_DIR + user_dir_name + "/" + hash + ".png"
			if FileAccess.file_exists(image_path):
				return image_path
		user_dir_name = dir.get_next()

	dir.list_dir_end()
	return ""


## Get the cached image path for a specific record
func get_cached_image_path(creation_index: int, user_id: String = "self") -> String:
	var record := get_record_for_user(creation_index, user_id)
	return record.get("cached_image_path", "")


## Ensure a directory exists
func ensure_directory(dir_path: String) -> void:
	var dir := DirAccess.open("user://")
	if not dir:
		push_error("[DexDatabase] Failed to access user:// directory")
		return

	# Remove "user://" prefix if present
	var clean_path := dir_path.replace("user://", "")

	# Create nested directories
	var path_parts := clean_path.split("/")
	var current_path := ""

	for part in path_parts:
		if part.is_empty():
			continue

		current_path += part + "/"
		if not dir.dir_exists(current_path):
			dir.make_dir(current_path)


## Get cache statistics
func get_cache_stats() -> Dictionary:
	var stats := {
		"total_users": get_tracked_users().size(),
		"total_records": 0,
		"cache_size_bytes": 0,
		"unique_images": 0
	}

	# Count total records
	for user_id in get_tracked_users():
		stats["total_records"] += get_record_count_for_user(user_id)

	# Count unique images in cache
	var unique_hashes: Dictionary = {}
	var dir := DirAccess.open(CACHE_DIR)
	if dir:
		_count_images_recursive(dir, CACHE_DIR, unique_hashes, stats)

	stats["unique_images"] = unique_hashes.size()
	return stats


## Helper to recursively count images and calculate size
func _count_images_recursive(dir: DirAccess, path: String, unique_hashes: Dictionary, stats: Dictionary) -> void:
	dir.list_dir_begin()
	var item := dir.get_next()

	while item != "":
		var full_path := path + item

		if dir.current_is_dir() and not item.begins_with("."):
			var sub_dir := DirAccess.open(full_path)
			if sub_dir:
				_count_images_recursive(sub_dir, full_path + "/", unique_hashes, stats)
		elif item.ends_with(".png"):
			# Get file size
			var file := FileAccess.open(full_path, FileAccess.READ)
			if file:
				stats["cache_size_bytes"] += file.get_length()
				file.close()

			# Track unique hash
			var hash := item.replace(".png", "")
			unique_hashes[hash] = true

		item = dir.get_next()

	dir.list_dir_end()
