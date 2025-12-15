extends BaseSceneNode
## Dex Gallery - Browse through discovered animals with multi-user support
## Refactored: 636 → ~300 lines (53% reduction)

# ============================================================================
# UI Elements
# ============================================================================

@onready var previous_button: Button = get_node("%PreviousButton")
@onready var next_button: Button = get_node("%NextButton")
@onready var edit_button: Button = get_node("%EditButton")
@onready var dex_number_label: Label = get_node("%Dex Number")

# RecordImage component (dex_record_image.tscn) - uses DexRecordImage script
@onready var record_image: DexRecordImage = get_node("%RecordImage")

# ============================================================================
# State
# ============================================================================

var current_index: int = -1
var current_user_id: String = "self"
var is_syncing: bool = false
var available_users: Dictionary = {}

# ============================================================================
# Initialization
# ============================================================================

func _on_scene_ready() -> void:
	scene_name = "Dex"
	print("[Dex] Scene ready (refactored v3)")

	# Connect record image signals
	record_image.image_loaded.connect(_on_record_image_loaded)

	# Connect UI
	previous_button.pressed.connect(_on_previous_pressed)
	next_button.pressed.connect(_on_next_pressed)
	edit_button.pressed.connect(_on_edit_pressed)

	# Connect database signals
	DexDatabase.record_added.connect(_on_record_added)
	DexDatabase.database_switched.connect(_on_database_switched)

	# Connect sync signals
	APIManager.dex.sync_started.connect(_on_sync_started)
	APIManager.dex.sync_progress.connect(_on_sync_progress)
	APIManager.dex.sync_user_completed.connect(_on_sync_completed)
	APIManager.dex.sync_user_failed.connect(_on_sync_failed)
	APIManager.dex.friends_overview_received.connect(_on_friends_received)

	# Handle navigation context (friend's dex from feed)
	var target_index: int = _handle_navigation_context()

	# Initialize users and sync
	_populate_user_list()
	_check_and_sync_if_needed()

	# Load record
	if target_index >= 0:
		_navigate_to_record(target_index)
	else:
		_load_first_record()


func _handle_navigation_context() -> int:
	if not NavigationManager.has_context():
		return -1

	var context: Dictionary = NavigationManager.get_context()
	if context.has("user_id"):
		current_user_id = context.get("user_id")
		available_users[current_user_id] = context.get("username", "Friend")
		print("[Dex] Loading %s's dex" % available_users[current_user_id])

	NavigationManager.clear_context()
	return context.get("creation_index", -1)


func _populate_user_list() -> void:
	if not available_users.has("self"):
		available_users["self"] = "My Dex"

	for user_id in DexDatabase.get_tracked_users():
		if user_id != "self" and not available_users.has(user_id):
			available_users[user_id] = "Friend (%s)" % user_id.substr(0, 8)

	APIManager.dex.get_friends_overview()


func _check_and_sync_if_needed() -> void:
	var first_index: int = DexDatabase.get_first_index_for_user("self")
	var has_corruption: bool = _has_corrupted_data(first_index)

	if has_corruption:
		SyncManager.clear_sync("self")
		print("[Dex] Forcing full sync (corrupted data)")

	trigger_sync()


func _has_corrupted_data(first_index: int) -> bool:
	if first_index < 0:
		return false
	var record: Dictionary = DexDatabase.get_record_for_user(first_index, "self")
	var path: String = record.get("cached_image_path", "")
	return path.is_empty() or not FileAccess.file_exists(path)

# ============================================================================
# Display
# ============================================================================

func _load_first_record() -> void:
	var first_index: int = DexDatabase.get_first_index_for_user(current_user_id)
	if first_index >= 0:
		var record: Dictionary = DexDatabase.get_record_for_user(first_index, current_user_id)
		var path: String = record.get("cached_image_path", "")
		if path.length() > 0 and FileAccess.file_exists(path):
			_display_record(first_index)
		else:
			_show_empty_state()
	else:
		_show_empty_state()


func _navigate_to_record(creation_index: int) -> void:
	var record: Dictionary = DexDatabase.get_record_for_user(creation_index, current_user_id)
	if not record.is_empty():
		_display_record(creation_index)
	else:
		_load_first_record()


func _show_empty_state() -> void:
	current_index = -1
	dex_number_label.text = "%s - No animals discovered yet!" % available_users.get(current_user_id, current_user_id)
	record_image.visible = false
	previous_button.disabled = true
	next_button.disabled = true


func _display_record(creation_index: int) -> void:
	var record: Dictionary = DexDatabase.get_record_for_user(creation_index, current_user_id)
	if record.is_empty():
		show_error("Record not found", "Record #%d not found" % creation_index)
		return

	current_index = creation_index
	dex_number_label.text = "Dex #%d" % creation_index

	# Use DexRecordImage component for display
	record_image.set_entry_data(record, current_user_id)
	record_image.load_image_from_entry()
	_update_navigation_buttons()


func _on_record_image_loaded(success: bool) -> void:
	"""Handle image load completion from DexRecordImage component."""
	if not is_instance_valid(self):
		return

	record_image.visible = true

	if success and current_index >= 0:
		# Update cached path in database if it changed
		var entry_data: Dictionary = record_image.get_entry_data()
		var cached_path: String = entry_data.get("cached_image_path", "")
		if not cached_path.is_empty():
			var record: Dictionary = DexDatabase.get_record_for_user(current_index, current_user_id)
			if not record.is_empty() and record.get("cached_image_path", "") != cached_path:
				record["cached_image_path"] = cached_path
				DexDatabase.add_record_from_dict(record, current_user_id)


func _update_navigation_buttons() -> void:
	if current_index < 0:
		previous_button.disabled = true
		next_button.disabled = true
		return

	previous_button.disabled = DexDatabase.get_previous_index_for_user(current_index, current_user_id) < 0
	next_button.disabled = DexDatabase.get_next_index_for_user(current_index, current_user_id) < 0

# ============================================================================
# User Switching & Sync
# ============================================================================

func switch_user(user_id: String) -> void:
	if user_id != current_user_id:
		current_user_id = user_id
		DexDatabase.switch_user(user_id)
		_load_first_record()


func trigger_sync() -> void:
	if not is_syncing:
		APIManager.dex.sync_user_dex(current_user_id)

# ============================================================================
# Button Handlers
# ============================================================================

func _on_previous_pressed() -> void:
	if current_index >= 0:
		var prev: int = DexDatabase.get_previous_index_for_user(current_index, current_user_id)
		if prev >= 0:
			_display_record(prev)


func _on_next_pressed() -> void:
	if current_index >= 0:
		var next: int = DexDatabase.get_next_index_for_user(current_index, current_user_id)
		if next >= 0:
			_display_record(next)


func _on_edit_pressed() -> void:
	if current_index < 0:
		show_error("No record selected", "Please select a dex entry to edit")
		return

	if current_user_id != "self":
		show_error("Cannot edit", "You can only edit your own dex entries")
		return

	var record: Dictionary = DexDatabase.get_record_for_user(current_index, current_user_id)
	if record.is_empty():
		show_error("Record not found", "Could not find record")
		return

	_navigate_to_edit_entry(record)

# ============================================================================
# Edit Navigation
# ============================================================================

func _navigate_to_edit_entry(record: Dictionary) -> void:
	"""Navigate to edit_entry scene with entry data"""
	var entry_id = record.get("dex_entry_id", "")

	# If we don't have the entry_id, try to fetch it first
	if entry_id.is_empty():
		show_loading("Loading entry...")
		APIManager.dex.get_my_entries(_on_my_entries_for_edit.bind(record))
		return

	# Navigate to edit_entry scene
	NavigationManager.set_context({
		"mode": "edit",
		"dex_entry_id": entry_id,
		"creation_index": current_index,
		"return_scene": "res://scenes/dex/dex.tscn",
		"return_context": {
			"creation_index": current_index,
			"user_id": "self"
		}
	})

	NavigationManager.navigate_to("res://scenes/edit_entry/edit_entry.tscn")


func _on_my_entries_for_edit(response: Dictionary, code: int, record: Dictionary) -> void:
	hide_loading()
	if not validate_api_response(response, code):
		return

	var local_animal_id = record.get("animal_id", "")
	var entry_id = ""

	for entry in response.get("results", []):
		if entry.get("animal", "") == local_animal_id:
			entry_id = str(entry.get("id", ""))
			break

	if entry_id.is_empty():
		show_error("Entry not found", "Could not find this entry on server", code)
		return

	# Update local record with entry_id
	record["dex_entry_id"] = entry_id
	DexDatabase.add_record_from_dict(record, current_user_id)

	# Now navigate with the entry_id
	_navigate_to_edit_entry(record)

# ============================================================================
# Signal Handlers
# ============================================================================

func _on_record_added(record: Dictionary, user_id: String) -> void:
	if user_id != current_user_id:
		return

	if current_index < 0:
		var idx: int = record.get("creation_index", -1)
		if idx >= 0:
			_display_record(idx)
	else:
		_update_navigation_buttons()


func _on_database_switched(user_id: String) -> void:
	current_user_id = user_id
	_load_first_record()


func _on_sync_started(user_id: String) -> void:
	if user_id == current_user_id:
		is_syncing = true
		show_loading("Syncing...")


func _on_sync_progress(user_id: String, current: int, total: int) -> void:
	if user_id == current_user_id:
		print("[Dex] Sync: %d/%d" % [current, total])


func _on_sync_completed(user_id: String, entries_updated: int) -> void:
	if user_id != current_user_id:
		return

	is_syncing = false
	hide_loading()

	if entries_updated == 0:
		_clean_corrupted_records()
		return

	if current_index < 0 and entries_updated > 0:
		_load_first_record()
	elif current_index >= 0 and not DexDatabase.has_record_for_user(current_index, current_user_id):
		_load_first_record()


func _clean_corrupted_records() -> void:
	var cleaned = 0
	for index in DexDatabase.get_sorted_indices_for_user(current_user_id):
		var record = DexDatabase.get_record_for_user(index, current_user_id)
		var path: String = record.get("cached_image_path", "")
		if path.is_empty() or not FileAccess.file_exists(path):
			DexDatabase.remove_record(index, current_user_id)
			cleaned += 1

	if cleaned > 0:
		_load_first_record()


func _on_sync_failed(user_id: String, error_message: String) -> void:
	if user_id == current_user_id:
		is_syncing = false
		hide_loading()
		show_error("Sync failed", error_message)


func _on_friends_received(friends: Array) -> void:
	for friend in friends:
		var friend_id: String = friend.get("user_id", "")
		var username: String = friend.get("username", "")
		if not friend_id.is_empty() and not username.is_empty():
			available_users[friend_id] = username + "'s Dex"
