extends Node
## SyncManager - Manages sync state and timestamps for incremental dex syncing

const SYNC_STATE_FILE = "user://sync_state.json"

## Stores last sync timestamps per user: {user_id: ISO timestamp}
var sync_timestamps: Dictionary = {}

## Emitted when sync state is updated
signal sync_state_updated(user_id: String, timestamp: String)

func _ready():
	load_sync_state()

## Get the last sync timestamp for a user
## @param user_id: User ID (use "self" for current user)
## @return: ISO timestamp string or empty string if never synced
func get_last_sync(user_id: String = "self") -> String:
	return sync_timestamps.get(user_id, "")

## Update the last sync timestamp for a user
## @param user_id: User ID (use "self" for current user)
## @param timestamp: ISO timestamp string (uses current time if empty)
func update_last_sync(user_id: String = "self", timestamp: String = "") -> void:
	if timestamp.is_empty():
		timestamp = Time.get_datetime_string_from_system(true)  # UTC time

	sync_timestamps[user_id] = timestamp
	save_sync_state()
	sync_state_updated.emit(user_id, timestamp)
	print("[SyncManager] Updated last_sync for '%s': %s" % [user_id, timestamp])

## Clear sync timestamp for a user (forces full re-sync)
## @param user_id: User ID to clear
func clear_sync(user_id: String) -> void:
	if sync_timestamps.has(user_id):
		sync_timestamps.erase(user_id)
		save_sync_state()
		print("[SyncManager] Cleared sync state for '%s'" % user_id)

## Clear all sync timestamps
func clear_all_sync() -> void:
	sync_timestamps.clear()
	save_sync_state()
	print("[SyncManager] Cleared all sync state")

## Get all tracked user IDs
func get_tracked_users() -> Array:
	return sync_timestamps.keys()

## Save sync state to disk
func save_sync_state() -> void:
	var file = FileAccess.open(SYNC_STATE_FILE, FileAccess.WRITE)
	if file:
		var data = {
			"version": "1.0",
			"sync_timestamps": sync_timestamps,
			"last_saved": Time.get_datetime_string_from_system(true)
		}
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("[SyncManager] Saved sync state (%d users tracked)" % sync_timestamps.size())
	else:
		push_error("[SyncManager] Failed to save sync state")

## Load sync state from disk
func load_sync_state() -> void:
	if not FileAccess.file_exists(SYNC_STATE_FILE):
		print("[SyncManager] No existing sync state found")
		return

	var file = FileAccess.open(SYNC_STATE_FILE, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()

		var json = JSON.new()
		var parse_result = json.parse(json_string)

		if parse_result == OK:
			var data = json.data
			if data is Dictionary and data.has("sync_timestamps"):
				sync_timestamps = data["sync_timestamps"]
				print("[SyncManager] Loaded sync state (%d users tracked)" % sync_timestamps.size())
			else:
				push_warning("[SyncManager] Invalid sync state format, resetting")
		else:
			push_error("[SyncManager] Failed to parse sync state: %s" % json.get_error_message())
	else:
		push_error("[SyncManager] Failed to open sync state file")

## Get debug information about sync state
func get_debug_info() -> String:
	var info = "[SyncManager Debug Info]\n"
	info += "Tracked users: %d\n" % sync_timestamps.size()
	for user_id in sync_timestamps.keys():
		info += "  - %s: %s\n" % [user_id, sync_timestamps[user_id]]
	return info
