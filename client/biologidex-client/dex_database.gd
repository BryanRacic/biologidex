extends Node

# DexDatabase - Local storage for user's discovered animals
# Stores creation_index, animal names, and paths to cached images

const DATABASE_PATH := "user://dex_database.json"

# Dictionary of creation_index -> animal record
# Record format: {
#   "creation_index": int,
#   "scientific_name": String,
#   "common_name": String,
#   "cached_image_path": String (local path in user://dex_cache/)
# }
var records: Dictionary = {}

# Sorted array of creation indices for navigation
var sorted_indices: Array[int] = []

signal record_added(creation_index: int)
signal database_loaded()


func _ready() -> void:
	print("[DexDatabase] Initializing...")
	load_database()


func add_record(
	creation_index: int,
	scientific_name: String,
	common_name: String,
	cached_image_path: String
) -> void:
	"""Add or update a dex record"""
	var record := {
		"creation_index": creation_index,
		"scientific_name": scientific_name,
		"common_name": common_name,
		"cached_image_path": cached_image_path
	}

	records[creation_index] = record

	# Update sorted indices
	if creation_index not in sorted_indices:
		sorted_indices.append(creation_index)
		sorted_indices.sort()

	print("[DexDatabase] Added record #", creation_index, ": ", scientific_name)

	# Save to disk
	save_database()

	# Emit signal
	record_added.emit(creation_index)


func get_record(creation_index: int) -> Dictionary:
	"""Get a specific record by creation_index"""
	return records.get(creation_index, {})


func get_all_records() -> Dictionary:
	"""Get all records"""
	return records.duplicate()


func get_sorted_indices() -> Array[int]:
	"""Get all creation indices sorted in ascending order"""
	return sorted_indices.duplicate()


func get_record_count() -> int:
	"""Get total number of records"""
	return records.size()


func get_next_index(current_index: int) -> int:
	"""Get the next creation_index after current, or -1 if none"""
	var pos := sorted_indices.find(current_index)
	if pos >= 0 and pos < sorted_indices.size() - 1:
		return sorted_indices[pos + 1]
	return -1


func get_previous_index(current_index: int) -> int:
	"""Get the previous creation_index before current, or -1 if none"""
	var pos := sorted_indices.find(current_index)
	if pos > 0:
		return sorted_indices[pos - 1]
	return -1


func get_first_index() -> int:
	"""Get the first (lowest) creation_index, or -1 if empty"""
	if sorted_indices.size() > 0:
		return sorted_indices[0]
	return -1


func has_record(creation_index: int) -> bool:
	"""Check if a record exists"""
	return creation_index in records


func clear_database() -> void:
	"""Clear all records (for testing/debugging)"""
	records.clear()
	sorted_indices.clear()
	save_database()
	print("[DexDatabase] Database cleared")


func save_database() -> void:
	"""Save database to disk as JSON"""
	var file := FileAccess.open(DATABASE_PATH, FileAccess.WRITE)
	if not file:
		push_error("[DexDatabase] Failed to open database for writing: ", DATABASE_PATH)
		return

	# Convert to JSON-serializable format
	var data := {
		"records": records,
		"sorted_indices": sorted_indices
	}

	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	print("[DexDatabase] Database saved (", records.size(), " records)")


func load_database() -> void:
	"""Load database from disk"""
	if not FileAccess.file_exists(DATABASE_PATH):
		print("[DexDatabase] No existing database found, starting fresh")
		database_loaded.emit()
		return

	var file := FileAccess.open(DATABASE_PATH, FileAccess.READ)
	if not file:
		push_error("[DexDatabase] Failed to open database for reading: ", DATABASE_PATH)
		database_loaded.emit()
		return

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_text)

	if parse_result != OK:
		push_error("[DexDatabase] Failed to parse database JSON: ", json.get_error_message())
		database_loaded.emit()
		return

	var data: Dictionary = json.data

	# Load records - convert string keys back to ints
	if data.has("records"):
		var loaded_records: Dictionary = data["records"]
		records.clear()
		for key in loaded_records:
			var index := int(key)
			records[index] = loaded_records[key]

	# Load sorted indices
	if data.has("sorted_indices"):
		sorted_indices.clear()
		var loaded_indices: Array = data["sorted_indices"]
		for idx in loaded_indices:
			sorted_indices.append(int(idx))

	print("[DexDatabase] Database loaded (", records.size(), " records)")
	database_loaded.emit()
