extends Node
## FriendDexSyncService - Centralized friend dex sync service
## Handles loading friends list and syncing their dex entries to DexDatabase.
## Used by DexFeed, TreeController, and other components that need friend data.

# Signals
signal friends_loaded(friends_data: Dictionary)
signal friends_load_failed(error: String)
signal sync_started()
signal sync_progress(synced: int, total: int)
signal sync_completed(friends_data: Dictionary)
signal sync_failed(error: String)

# State
var friends_data: Dictionary = {}  # {user_id: {username, avatar, friend_code, total_catches, unique_species}}
var is_loading_friends: bool = false
var is_syncing: bool = false
var _last_sync_time: String = ""

# References
var _dex_db: Node = null
var _sync_manager: Node = null


func _ready() -> void:
	_dex_db = get_node_or_null("/root/DexDatabase")
	_sync_manager = get_node_or_null("/root/SyncManager")


## Load friends list from server
func load_friends(callback: Callable = Callable()) -> void:
	if is_loading_friends:
		return

	is_loading_friends = true
	APIManager.social.get_friends(_on_friends_response.bind(callback))


func _on_friends_response(response: Dictionary, code: int, callback: Callable) -> void:
	is_loading_friends = false

	if code != 200:
		var error_msg: String = response.get("error", "Failed to load friends")
		friends_load_failed.emit(error_msg)
		if callback.is_valid():
			callback.call(false, error_msg)
		return

	var friends: Array = response.get("friends", [])

	# Populate friends data
	friends_data.clear()
	for friend in friends:
		var friend_id: String = friend.get("id", "")
		if not friend_id.is_empty():
			friends_data[friend_id] = {
				"username": friend.get("username", "Unknown"),
				"avatar": friend.get("avatar", ""),
				"friend_code": friend.get("friend_code", ""),
				"total_catches": friend.get("total_catches", 0),
				"unique_species": friend.get("unique_species", 0)
			}

	friends_loaded.emit(friends_data)
	if callback.is_valid():
		callback.call(true, "")


## Sync all friends' dex entries to local DexDatabase
## If friends haven't been loaded yet, loads them first
func sync_friends(callback: Callable = Callable()) -> void:
	if is_syncing:
		return

	if friends_data.is_empty():
		# Load friends first, then sync
		load_friends(_on_friends_loaded_for_sync.bind(callback))
		return

	_start_batch_sync(callback)


func _on_friends_loaded_for_sync(success: bool, error: String, callback: Callable) -> void:
	if not success:
		sync_failed.emit(error)
		if callback.is_valid():
			callback.call(false, error)
		return

	if friends_data.is_empty():
		sync_completed.emit(friends_data)
		if callback.is_valid():
			callback.call(true, "")
		return

	_start_batch_sync(callback)


func _start_batch_sync(callback: Callable) -> void:
	is_syncing = true
	sync_started.emit()

	# Build batch sync request
	var sync_requests := []
	for friend_id in friends_data.keys():
		var last_sync := ""
		if _sync_manager:
			last_sync = _sync_manager.get_last_sync(friend_id)
		sync_requests.append({
			"user_id": friend_id,
			"last_sync": last_sync
		})

	# Execute batch sync
	var req_config = APIManager.dex._create_request_config()
	APIManager.dex.api_client.post(
		"/dex/entries/batch_sync/",
		{"sync_requests": sync_requests},
		_on_batch_sync_success.bind(callback),
		_on_batch_sync_error.bind(callback),
		req_config
	)


func _on_batch_sync_success(response: Dictionary, callback: Callable) -> void:
	var results: Dictionary = response.get("results", {})
	var server_time: String = response.get("server_time", "")
	_last_sync_time = server_time

	var synced_count := 0
	var total_count := results.size()

	# Process each friend's results
	for user_id in results.keys():
		var user_result = results[user_id]

		if user_result.has("error"):
			continue

		var entries: Array = user_result.get("entries", [])

		# Process entries for this user
		for entry in entries:
			var creation_index: int = entry.get("creation_index", -1)
			if creation_index < 0:
				continue

			var existing_record: Dictionary = {}
			if _dex_db:
				existing_record = _dex_db.get_record_for_user(creation_index, user_id)

			var existing_cached_path: String = existing_record.get("cached_image_path", "")

			var record := {
				"creation_index": creation_index,
				"scientific_name": entry.get("scientific_name", ""),
				"common_name": entry.get("common_name", ""),
				"image_checksum": entry.get("image_checksum", ""),
				"dex_compatible_url": entry.get("dex_compatible_url", ""),
				"updated_at": entry.get("updated_at", ""),
				"cached_image_path": existing_cached_path,
				"animal_id": entry.get("animal_id", ""),
				"dex_entry_id": entry.get("id", ""),
				"owner_username": friends_data.get(user_id, {}).get("username", "")
			}

			if _dex_db:
				_dex_db.add_record_from_dict(record, user_id)

		# Update sync timestamp
		if _sync_manager and not server_time.is_empty():
			_sync_manager.update_last_sync(user_id, server_time)

		synced_count += 1
		sync_progress.emit(synced_count, total_count)

	is_syncing = false
	sync_completed.emit(friends_data)
	if callback.is_valid():
		callback.call(true, "")


func _on_batch_sync_error(error, callback: Callable) -> void:
	is_syncing = false

	var error_msg: String = ""
	if error is Dictionary:
		error_msg = error.get("message", "Unknown error")
	else:
		error_msg = str(error)

	sync_failed.emit(error_msg)
	if callback.is_valid():
		callback.call(false, error_msg)


## Get friend info by user_id
func get_friend_info(user_id: String) -> Dictionary:
	return friends_data.get(user_id, {})


## Get username for a friend
func get_friend_username(user_id: String) -> String:
	return friends_data.get(user_id, {}).get("username", "Unknown")


## Check if friends have been loaded
func has_friends() -> bool:
	return not friends_data.is_empty()


## Get all friend IDs
func get_friend_ids() -> Array:
	return friends_data.keys()


## Find a friend's dex entry by animal_id
## Returns the entry dict or empty dict if not found
func find_friend_entry_by_animal(user_id: String, animal_id: String) -> Dictionary:
	if not _dex_db:
		return {}

	var entries: Array = _dex_db.get_all_records_for_user(user_id)
	for entry in entries:
		if entry.get("animal_id", "") == animal_id:
			return entry
	return {}


## Find a friend's dex entry by scientific name
## Returns the entry dict or empty dict if not found
func find_friend_entry_by_name(user_id: String, scientific_name: String) -> Dictionary:
	if not _dex_db:
		return {}

	var entries: Array = _dex_db.get_all_records_for_user(user_id)
	for entry in entries:
		if entry.get("scientific_name", "") == scientific_name:
			return entry
	return {}


## Get all entries for a friend
func get_friend_entries(user_id: String) -> Array:
	if not _dex_db:
		return []
	return _dex_db.get_all_records_for_user(user_id)
