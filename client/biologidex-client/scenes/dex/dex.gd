extends BaseSceneController
## Dex Gallery - Browse through discovered animals with multi-user support
## Refactored: 636 → ~300 lines (53% reduction)

# ============================================================================
# UI Elements
# ============================================================================

@onready var previous_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/HBoxContainer/PreviousButton
@onready var next_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/HBoxContainer/NextButton
@onready var edit_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/EditButton
@onready var dex_number_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/"Dex Number"

# Legacy display (TODO: Replace with RecordCard component)
@onready var record_image: Control = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage
@onready var bordered_container: AspectRatioContainer = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio
@onready var bordered_image: TextureRect = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio/ImageBorder/Image
@onready var record_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio/ImageBorder/RecordMargin/RecordBackground/RecordTextMargin/RecordLabel
@onready var simple_image: TextureRect = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/Image

# ============================================================================
# State
# ============================================================================

var current_index: int = -1
var current_user_id: String = "self"
var is_syncing: bool = false
var available_users: Dictionary = {}
var pending_edit_dex_entry_id: String = ""
var current_image_width: float = 0.0
var current_image_height: float = 0.0

# ============================================================================
# Initialization
# ============================================================================

func _on_scene_ready() -> void:
	scene_name = "Dex"
	print("[Dex] Scene ready (refactored v2)")

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
	var last_sync: String = SyncManager.get_last_sync("self")
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

	var image_path: String = record.get("cached_image_path", "")
	if image_path.length() > 0 and FileAccess.file_exists(image_path):
		_load_and_display_image(image_path)
	else:
		record_image.visible = false

	_update_record_label(record)
	_update_navigation_buttons()


func _update_record_label(record: Dictionary) -> void:
	var sci: String = record.get("scientific_name", "")
	var common: String = record.get("common_name", "")

	if sci.length() > 0:
		record_label.text = sci + (" - " + common if common.length() > 0 else "")
	elif common.length() > 0:
		record_label.text = common
	else:
		record_label.text = "Unknown"


func _load_and_display_image(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		show_error("Failed to load image", "Could not open: %s" % path)
		return

	var data := file.get_buffer(file.get_length())
	file.close()

	var image := Image.new()
	if image.load_png_from_buffer(data) != OK:
		show_error("Failed to load image", "PNG load error")
		return

	current_image_width = float(image.get_width())
	current_image_height = float(image.get_height())

	if current_image_height > 0.0:
		bordered_container.ratio = current_image_width / current_image_height

	bordered_image.texture = ImageTexture.create_from_image(image)
	simple_image.visible = false
	bordered_container.visible = true
	record_image.visible = true

	await get_tree().process_frame
	_update_record_image_size()


func _update_record_image_size() -> void:
	var available_width: float = float(record_image.get_parent_control().size.x)
	var max_width: float = min(current_image_width, available_width * 0.67)
	var display_width: float = min(available_width, max_width)

	if bordered_container.ratio > 0.0:
		var height: float = display_width / bordered_container.ratio
		record_image.custom_minimum_size = Vector2(display_width, height)
		record_image.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if display_width < available_width else Control.SIZE_FILL


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

	_get_entry_id_for_edit(record)

# ============================================================================
# Edit Workflow
# ============================================================================

func _get_entry_id_for_edit(record: Dictionary) -> void:
	var entry_id = record.get("dex_entry_id", "")
	if not entry_id.is_empty():
		_open_manual_entry_popup(entry_id, record)
		return

	show_loading("Loading entry...")
	APIManager.dex.get_my_entries(_on_my_entries_for_edit.bind(record))


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

	record["dex_entry_id"] = entry_id
	DexDatabase.add_record_from_dict(record, current_user_id)
	_open_manual_entry_popup(entry_id, record)


func _open_manual_entry_popup(entry_id: String, record: Dictionary) -> void:
	var popup_scene = load("res://scenes/social/components/manual_entry_popup.tscn")
	if not popup_scene:
		show_error("Failed to load popup", "Could not load popup scene")
		return

	var popup = popup_scene.instantiate()
	popup.prefill_data = {
		"genus": record.get("genus", ""),
		"species": record.get("species", ""),
		"common_name": record.get("common_name", "")
	}
	popup.current_dex_entry_id = entry_id
	popup.entry_updated.connect(_on_entry_updated)
	popup.popup_closed.connect(_on_popup_closed)

	add_child(popup)
	popup.popup_centered(Vector2(600, 500))


func _on_entry_updated(_taxonomy: Dictionary) -> void:
	var record = DexDatabase.get_record_for_user(current_index, current_user_id)
	pending_edit_dex_entry_id = record.get("dex_entry_id", "")
	show_loading("Syncing...")
	trigger_sync()


func _on_popup_closed() -> void:
	print("[Dex] Popup closed")

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

	if not pending_edit_dex_entry_id.is_empty():
		_navigate_to_edited_entry()
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


func _navigate_to_edited_entry() -> void:
	for index in DexDatabase.get_sorted_indices_for_user(current_user_id):
		var record = DexDatabase.get_record_for_user(index, current_user_id)
		if record.get("dex_entry_id", "") == pending_edit_dex_entry_id:
			current_index = index
			_display_record(current_index)
			pending_edit_dex_entry_id = ""
			return

	pending_edit_dex_entry_id = ""


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
