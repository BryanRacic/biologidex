class_name DexEntryManager extends Node
## Centralized manager for dex entry creation, updates, and synchronization
##
## This module extracts and centralizes dex entry management logic that was
## previously scattered across camera.gd and dex.gd scenes.
##
## Features:
## - Create dex entries (local + remote)
## - Update existing entries
## - Handle local/remote sync
## - Manage entry metadata
## - Cache images locally
## - Validation and error handling

# ============================================================================
# Signals
# ============================================================================

signal entry_created(entry_id: String, entry_data: Dictionary)
signal entry_updated(entry_id: String, entry_data: Dictionary)
signal entry_creation_failed(error_message: String)
signal entry_update_failed(error_message: String)
signal local_entry_saved(creation_index: int)
signal remote_entry_synced(entry_id: String)

# ============================================================================
# Dependencies
# ============================================================================

var TokenManager
var DexDatabase
var APIManager

# ============================================================================
# State
# ============================================================================

var pending_entries: Dictionary = {}  # entry_id -> entry_data

# ============================================================================
# Initialization
# ============================================================================

func _ready() -> void:
	TokenManager = get_node("/root/TokenManager")
	DexDatabase = get_node("/root/DexDatabase")
	APIManager = get_node("/root/APIManager")
	print("[DexEntryManager] Initialized")

# ============================================================================
# Entry Creation
# ============================================================================

func create_entry(
	animal_data: Dictionary,
	image_data: PackedByteArray,
	visibility: String = "private",
	notes: String = "",
	location: String = "",
	metadata: Dictionary = {}
) -> void:
	"""
	Create a new dex entry both locally and on the server.

	Args:
		animal_data: Animal information from CV analysis or manual entry
		image_data: PNG image data
		visibility: Entry visibility (private, friends, public)
		notes: User notes
		location: Location captured
		metadata: Additional metadata (e.g., captured_at, device_info)
	"""
	print("[DexEntryManager] Creating dex entry for: ", animal_data.get("scientific_name", "Unknown"))

	# Create local entry first (immediate feedback)
	var local_entry_id: int = _create_local_entry(animal_data, image_data, visibility, notes, location, metadata)

	if local_entry_id < 0:
		entry_creation_failed.emit("Failed to create local dex entry")
		return

	local_entry_saved.emit(local_entry_id)

	# Then create remote entry (async)
	_create_remote_entry(animal_data, image_data, visibility, notes, location, metadata, local_entry_id)


func _create_local_entry(
	animal_data: Dictionary,
	image_data: PackedByteArray,
	visibility: String,
	notes: String,
	location: String,
	metadata: Dictionary
) -> int:
	"""Create local dex entry and cache image. Returns creation_index or -1 on failure."""

	# Cache image locally
	var cache_dir: String = "user://dex_cache/%s/" % TokenManager.get_user_id()
	var creation_index: int = animal_data.get("creation_index", -1)

	if creation_index < 0:
		push_error("[DexEntryManager] Invalid creation_index")
		return -1

	var image_filename: String = "%d.png" % creation_index
	var local_image_path: String = cache_dir + image_filename

	# Ensure directory exists
	DirAccess.make_dir_recursive_absolute(cache_dir)

	# Save image
	var file := FileAccess.open(local_image_path, FileAccess.WRITE)
	if not file:
		push_error("[DexEntryManager] Failed to save image to: ", local_image_path)
		return -1

	file.store_buffer(image_data)
	file.close()

	print("[DexEntryManager] Cached image: ", local_image_path)

	# Create database record
	var entry_record: Dictionary = {
		"creation_index": creation_index,
		"animal_id": animal_data.get("id", ""),
		"scientific_name": animal_data.get("scientific_name", ""),
		"common_name": animal_data.get("common_name", ""),
		"genus": animal_data.get("genus", ""),
		"species": animal_data.get("species", ""),
		"subspecies": animal_data.get("subspecies", ""),
		"kingdom": animal_data.get("kingdom", ""),
		"phylum": animal_data.get("phylum", ""),
		"animal_class": animal_data.get("animal_class", ""),
		"order": animal_data.get("order", ""),
		"family": animal_data.get("family", ""),
		"cached_image_path": local_image_path,
		"visibility": visibility,
		"notes": notes,
		"location": location,
		"captured_at": metadata.get("captured_at", ""),
		"created_at": metadata.get("created_at", ""),
		"updated_at": metadata.get("updated_at", ""),
		"is_favorite": false,
		"dex_entry_id": ""  # Will be set after remote creation
	}

	DexDatabase.add_record_from_dict(entry_record, "self")
	print("[DexEntryManager] Local entry created: #", creation_index)

	return creation_index


func _create_remote_entry(
	animal_data: Dictionary,
	image_data: PackedByteArray,
	visibility: String,
	notes: String,
	location: String,
	metadata: Dictionary,
	local_creation_index: int
) -> void:
	"""Create remote dex entry via API"""

	# Prepare entry data
	var entry_data: Dictionary = {
		"animal": animal_data.get("id", ""),
		"visibility": visibility,
		"notes": notes,
		"location": location,
		"captured_at": metadata.get("captured_at", ""),
		"image_data": Marshalls.raw_to_base64(image_data)
	}

	# Call API to create entry
	APIManager.dex.create_entry(
		entry_data,
		_on_entry_created.bind(local_creation_index)
	)


func _on_entry_created(response: Dictionary, code: int, local_creation_index: int) -> void:
	"""Handle remote entry creation response"""

	if code != 201 and code != 200:
		var error_msg: String = response.get("message", "Failed to create remote dex entry")
		push_error("[DexEntryManager] Remote creation failed: ", error_msg)
		entry_creation_failed.emit(error_msg)
		return

	# Extract entry ID from response
	var entry_id: String = str(response.get("id", ""))

	if entry_id.is_empty():
		push_error("[DexEntryManager] No entry ID in response")
		entry_creation_failed.emit("Invalid server response")
		return

	print("[DexEntryManager] Remote entry created: ", entry_id)

	# Update local database with remote entry ID
	var local_record: Dictionary = DexDatabase.get_record_for_user(local_creation_index, "self")
	if not local_record.is_empty():
		local_record["dex_entry_id"] = entry_id
		DexDatabase.add_record_from_dict(local_record, "self")
		print("[DexEntryManager] Updated local record with entry ID: ", entry_id)

	remote_entry_synced.emit(entry_id)
	entry_created.emit(entry_id, response)

# ============================================================================
# Entry Updates
# ============================================================================

func update_entry(
	entry_id: String,
	updates: Dictionary
) -> void:
	"""
	Update an existing dex entry.

	Args:
		entry_id: Server-side dex entry ID
		updates: Dictionary of fields to update (e.g., notes, visibility, animal)
	"""
	print("[DexEntryManager] Updating entry: ", entry_id)

	# Call API to update entry
	APIManager.dex.update_entry(
		entry_id,
		updates,
		_on_entry_updated.bind(entry_id)
	)


func _on_entry_updated(response: Dictionary, code: int, entry_id: String) -> void:
	"""Handle entry update response"""

	if code != 200:
		var error_msg: String = response.get("message", "Failed to update dex entry")
		push_error("[DexEntryManager] Update failed: ", error_msg)
		entry_update_failed.emit(error_msg)
		return

	print("[DexEntryManager] Entry updated: ", entry_id)
	entry_updated.emit(entry_id, response)

# ============================================================================
# Entry Deletion
# ============================================================================

func delete_entry(entry_id: String, creation_index: int) -> void:
	"""
	Delete a dex entry both locally and remotely.

	Args:
		entry_id: Server-side dex entry ID
		creation_index: Local creation index
	"""
	print("[DexEntryManager] Deleting entry: ", entry_id)

	# Delete from local database
	DexDatabase.remove_record(creation_index, "self")

	# Delete cached image
	var record: Dictionary = DexDatabase.get_record_for_user(creation_index, "self")
	var image_path: String = record.get("cached_image_path", "")
	if image_path.length() > 0 and FileAccess.file_exists(image_path):
		DirAccess.remove_absolute(image_path)
		print("[DexEntryManager] Deleted cached image: ", image_path)

	# Delete from server
	APIManager.dex.delete_entry(entry_id, _on_entry_deleted.bind(entry_id))


func _on_entry_deleted(response: Dictionary, code: int, entry_id: String) -> void:
	"""Handle entry deletion response"""

	if code != 204 and code != 200:
		var error_msg: String = response.get("message", "Failed to delete dex entry")
		push_error("[DexEntryManager] Deletion failed: ", error_msg)
		return

	print("[DexEntryManager] Entry deleted: ", entry_id)

# ============================================================================
# Utility Methods
# ============================================================================

func get_entry_by_id(entry_id: String) -> Dictionary:
	"""Get local dex entry by server-side entry ID"""
	var all_indices = DexDatabase.get_sorted_indices_for_user("self")

	for index in all_indices:
		var record = DexDatabase.get_record_for_user(index, "self")
		if record.get("dex_entry_id", "") == entry_id:
			return record

	return {}


func get_entry_by_creation_index(creation_index: int) -> Dictionary:
	"""Get local dex entry by creation index"""
	return DexDatabase.get_record_for_user(creation_index, "self")


func has_entry(entry_id: String) -> bool:
	"""Check if entry exists locally"""
	return not get_entry_by_id(entry_id).is_empty()


func get_entry_count() -> int:
	"""Get total number of local dex entries"""
	return DexDatabase.get_sorted_indices_for_user("self").size()


func validate_entry_data(animal_data: Dictionary) -> bool:
	"""Validate required fields for dex entry creation"""

	if not animal_data.has("id"):
		push_error("[DexEntryManager] Missing animal ID")
		return false

	if not animal_data.has("creation_index"):
		push_error("[DexEntryManager] Missing creation_index")
		return false

	# At least one name field required
	if not animal_data.has("scientific_name") and not animal_data.has("common_name"):
		push_error("[DexEntryManager] Missing both scientific_name and common_name")
		return false

	return true

# ============================================================================
# Batch Operations
# ============================================================================

func create_entries_batch(entries: Array) -> void:
	"""Create multiple dex entries (useful for bulk import/sync)"""
	print("[DexEntryManager] Creating %d entries in batch" % entries.size())

	for entry_data in entries:
		var animal_data: Dictionary = entry_data.get("animal", {})
		var image_data: PackedByteArray = entry_data.get("image_data", PackedByteArray())
		var visibility: String = entry_data.get("visibility", "private")
		var notes: String = entry_data.get("notes", "")
		var location: String = entry_data.get("location", "")
		var metadata: Dictionary = entry_data.get("metadata", {})

		if validate_entry_data(animal_data):
			create_entry(animal_data, image_data, visibility, notes, location, metadata)
