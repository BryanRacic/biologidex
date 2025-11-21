extends BaseSceneController
## Dex Gallery - Browse through discovered animals with multi-user support
## Refactored from 636 lines to ~250 lines using component-based architecture

# ============================================================================
# UI Elements
# ============================================================================

# Navigation
@onready var previous_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/HBoxContainer/PreviousButton
@onready var next_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/HBoxContainer/NextButton
@onready var edit_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/EditButton

# Display
@onready var dex_number_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/"Dex Number"

# Components (TODO: Add to scene tree via editor)
# @onready var record_card: RecordCard = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordCard
# @onready var user_selector: UserSelector = $Panel/MarginContainer/VBoxContainer/Header/UserSelector
# @onready var progress_indicator: ProgressIndicator = $Panel/MarginContainer/VBoxContainer/Header/ProgressIndicator

# For now, use legacy image display until RecordCard is wired up in .tscn
@onready var record_image: Control = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage
@onready var bordered_container: AspectRatioContainer = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio
@onready var bordered_image: TextureRect = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio/ImageBorder/Image
@onready var record_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio/ImageBorder/RecordMargin/RecordBackground/RecordTextMargin/RecordLabel
@onready var simple_image: TextureRect = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/Image

# ============================================================================
# State
# ============================================================================

var current_index: int = -1
var current_user_id: String = "self"  # Currently viewing user's dex
var is_syncing: bool = false
var available_users: Dictionary = {}  # user_id -> username mapping
var pending_edit_dex_entry_id: String = ""  # Track edited entry for post-sync navigation

# Image size tracking (for legacy display)
var current_image_width: float = 0.0
var current_image_height: float = 0.0

# ============================================================================
# Initialization
# ============================================================================

func _on_scene_ready() -> void:
	"""Called by BaseSceneController after managers are initialized"""
	scene_name = "Dex"
	print("[Dex] Scene ready (refactored - multi-user mode)")

	# Connect UI signals
	previous_button.pressed.connect(_on_previous_pressed)
	next_button.pressed.connect(_on_next_pressed)
	edit_button.pressed.connect(_on_edit_pressed)

	# Connect to database signals
	DexDatabase.record_added.connect(_on_record_added_multi_user)
	DexDatabase.database_switched.connect(_on_database_switched)

	# Connect to sync signals
	APIManager.dex.sync_started.connect(_on_sync_started)
	APIManager.dex.sync_progress.connect(_on_sync_progress)
	APIManager.dex.sync_user_completed.connect(_on_sync_user_completed)
	APIManager.dex.sync_user_failed.connect(_on_sync_user_failed)
	APIManager.dex.friends_overview_received.connect(_on_friends_overview_received)

	# Check for friend context from navigation (viewing friend's dex)
	var target_creation_index: int = _handle_navigation_context()

	# Initialize user list
	_populate_user_list()

	# Check if we need to sync
	_check_and_sync_if_needed()

	# Load specific record if requested, otherwise load first record
	if target_creation_index >= 0:
		_navigate_to_record(target_creation_index)
	else:
		_load_first_record()


func _handle_navigation_context() -> int:
	"""Handle navigation context (e.g., viewing friend's dex from feed)
	Returns target creation_index or -1 if none"""
	var target_creation_index: int = -1

	if NavigationManager.has_context():
		var context: Dictionary = NavigationManager.get_context()

		if context.has("user_id"):
			var friend_id: String = context.get("user_id")
			var username: String = context.get("username", "Friend")

			print("[Dex] Loading friend's dex: ", username, " (", friend_id, ")")

			# Switch to friend's dex
			current_user_id = friend_id
			available_users[friend_id] = username

			# Check if we should navigate to a specific entry (from feed)
			if context.has("creation_index"):
				target_creation_index = context.get("creation_index", -1)
				print("[Dex] Will navigate to entry #%d" % target_creation_index)

		# Clear context
		NavigationManager.clear_context()

	return target_creation_index


func _populate_user_list() -> void:
	"""Initialize the list of available users (self + cached friends)"""
	# Only set "self" if not already populated (from context)
	if not available_users.has("self"):
		available_users["self"] = "My Dex"

	# Add any friends whose dex we have cached (but don't overwrite existing)
	var tracked_users: Array = DexDatabase.get_tracked_users()
	for user_id in tracked_users:
		if user_id != "self" and not available_users.has(user_id):
			available_users[user_id] = "Friend (%s)" % user_id.substr(0, 8)

	print("[Dex] Available users: ", available_users.keys())

	# Fetch friends overview to update names (async)
	APIManager.dex.get_friends_overview()


func _check_and_sync_if_needed() -> void:
	"""Always trigger sync when opening dex - incremental if we have a last_sync timestamp"""
	# Check if database is empty
	var first_index: int = DexDatabase.get_first_index_for_user("self")
	var database_empty: bool = (first_index < 0)

	# Check if we've never synced
	var last_sync: String = SyncManager.get_last_sync("self")
	var never_synced: bool = last_sync.is_empty()

	# Check if database has corrupted data (records with no valid images)
	var has_corrupted_data: bool = _check_for_corrupted_data(first_index)

	# Force full sync if we have corrupted data
	if has_corrupted_data and not never_synced:
		print("[Dex] Forcing full sync to repair corrupted database")
		SyncManager.clear_sync("self")

	# Log sync reason
	if database_empty or never_synced:
		print("[Dex] Auto-triggering initial sync (database_empty=%s, never_synced=%s)" % [database_empty, never_synced])
	elif has_corrupted_data:
		print("[Dex] Auto-triggering full sync to repair database")
	else:
		print("[Dex] Auto-triggering incremental sync (last_sync: %s)" % last_sync)

	trigger_sync()


func _check_for_corrupted_data(first_index: int) -> bool:
	"""Check if database has corrupted data (records with no valid images)"""
	if first_index < 0:
		return false

	var first_record: Dictionary = DexDatabase.get_record_for_user(first_index, "self")
	var image_path: String = first_record.get("cached_image_path", "")

	if image_path.is_empty() or not FileAccess.file_exists(image_path):
		print("[Dex] Detected corrupted data (record #%d has invalid image)" % first_index)
		return true

	return false

# ============================================================================
# Record Display & Navigation
# ============================================================================

func _load_first_record() -> void:
	"""Load the first record (lowest creation_index) for current user"""
	var first_index: int = DexDatabase.get_first_index_for_user(current_user_id)

	if first_index >= 0:
		# Validate that the record has a valid image before displaying
		var record: Dictionary = DexDatabase.get_record_for_user(first_index, current_user_id)
		var image_path: String = record.get("cached_image_path", "")

		if image_path.length() > 0 and FileAccess.file_exists(image_path):
			_display_record(first_index)
		else:
			print("[Dex] First record #%d has invalid image, showing empty state until sync completes" % first_index)
			_show_empty_state()
	else:
		_show_empty_state()


func _navigate_to_record(creation_index: int) -> void:
	"""Navigate to a specific record (used when coming from feed)"""
	print("[Dex] Navigating to specific record: #%d" % creation_index)

	var record: Dictionary = DexDatabase.get_record_for_user(creation_index, current_user_id)
	if not record.is_empty():
		_display_record(creation_index)
	else:
		print("[Dex] WARNING: Requested record #%d not found, loading first record instead" % creation_index)
		_load_first_record()


func _show_empty_state() -> void:
	"""Show UI when no records exist"""
	current_index = -1
	var user_label: String = available_users.get(current_user_id, current_user_id)
	dex_number_label.text = "%s - No animals discovered yet!" % user_label
	record_image.visible = false
	previous_button.disabled = true
	next_button.disabled = true
	print("[Dex] No records in database for user: ", current_user_id)


func _display_record(creation_index: int) -> void:
	"""Display a specific record for current user"""
	var record: Dictionary = DexDatabase.get_record_for_user(creation_index, current_user_id)

	if record.is_empty():
		show_error("Record not found", "Record #%d not found in database" % creation_index)
		return

	current_index = creation_index

	# Update dex number
	dex_number_label.text = "Dex #%d" % creation_index
	print("[Dex] Displaying record #", creation_index)

	# Load and display image
	var image_path: String = record.get("cached_image_path", "")
	if image_path.length() > 0 and FileAccess.file_exists(image_path):
		_load_and_display_image(image_path)
	else:
		print("[Dex] WARNING: Image not found: ", image_path)
		record_image.visible = false

	# Update animal name label
	_update_record_label(record)

	# Update navigation buttons
	_update_navigation_buttons()


func _update_record_label(record: Dictionary) -> void:
	"""Update the record label with animal name"""
	var scientific_name: String = record.get("scientific_name", "")
	var common_name: String = record.get("common_name", "")

	var display_text := ""
	if scientific_name.length() > 0:
		display_text = scientific_name
		if common_name.length() > 0:
			display_text += " - " + common_name
	elif common_name.length() > 0:
		display_text = common_name
	else:
		display_text = "Unknown"

	record_label.text = display_text


# TODO: Replace this with RecordCard component
func _load_and_display_image(path: String) -> void:
	"""Load image from local cache and display it (legacy display)"""
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		show_error("Failed to load image", "Could not open file: %s" % path)
		return

	var data := file.get_buffer(file.get_length())
	file.close()

	var image := Image.new()
	var error := image.load_png_from_buffer(data)

	if error != OK:
		show_error("Failed to load image", "PNG load error: %d" % error)
		return

	# Create texture
	var texture := ImageTexture.create_from_image(image)

	# Update image dimensions
	current_image_width = float(image.get_width())
	current_image_height = float(image.get_height())

	# Calculate aspect ratio
	if current_image_height > 0.0:
		var aspect_ratio: float = current_image_width / current_image_height
		bordered_container.ratio = aspect_ratio
		print("[Dex] Image loaded: ", current_image_width, "x", current_image_height, " (aspect: ", aspect_ratio, ")")

	# Display in bordered version
	bordered_image.texture = texture
	simple_image.visible = false
	bordered_container.visible = true
	record_image.visible = true

	# Update size after layout
	await get_tree().process_frame
	_update_record_image_size()


func _update_record_image_size() -> void:
	"""Update RecordImage's custom_minimum_size to match AspectRatioContainer's calculated height"""
	var available_width: float = float(record_image.get_parent_control().size.x)

	# Set max width to 2/3 of available width
	var max_card_width: float = available_width * 0.67

	# Cap width at actual image width (don't upscale)
	var max_width: float = min(current_image_width, max_card_width)
	var display_width: float = min(available_width, max_width)

	# Calculate required height based on aspect ratio
	var aspect_ratio: float = bordered_container.ratio
	if aspect_ratio > 0.0:
		var required_height: float = display_width / aspect_ratio
		record_image.custom_minimum_size = Vector2(display_width, required_height)

		# Center the image if smaller than available width
		if display_width < available_width:
			record_image.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		else:
			record_image.size_flags_horizontal = Control.SIZE_FILL

		print("[Dex] Updated RecordImage size - Display: ", display_width, " Height: ", required_height)


func _update_navigation_buttons() -> void:
	"""Enable/disable navigation buttons based on current position"""
	if current_index < 0:
		previous_button.disabled = true
		next_button.disabled = true
		return

	# Check if there's a previous record for current user
	var prev_index: int = DexDatabase.get_previous_index_for_user(current_index, current_user_id)
	previous_button.disabled = (prev_index < 0)

	# Check if there's a next record for current user
	var next_index: int = DexDatabase.get_next_index_for_user(current_index, current_user_id)
	next_button.disabled = (next_index < 0)

# ============================================================================
# User Switching & Sync
# ============================================================================

func switch_user(user_id: String) -> void:
	"""Switch to viewing a different user's dex"""
	if user_id == current_user_id:
		return

	print("[Dex] Switching to user: ", user_id)
	current_user_id = user_id
	DexDatabase.switch_user(user_id)
	_load_first_record()


func trigger_sync() -> void:
	"""Trigger sync for current user"""
	if is_syncing:
		print("[Dex] Sync already in progress")
		return

	print("[Dex] Triggering sync for user: ", current_user_id)
	APIManager.dex.sync_user_dex(current_user_id)

# ============================================================================
# Button Handlers
# ============================================================================

func _on_previous_pressed() -> void:
	"""Navigate to previous record"""
	if current_index < 0:
		return

	var prev_index: int = DexDatabase.get_previous_index_for_user(current_index, current_user_id)
	if prev_index >= 0:
		print("[Dex] Navigating to previous: #", prev_index)
		_display_record(prev_index)
	else:
		print("[Dex] Already at first record")


func _on_next_pressed() -> void:
	"""Navigate to next record"""
	if current_index < 0:
		return

	var next_index: int = DexDatabase.get_next_index_for_user(current_index, current_user_id)
	if next_index >= 0:
		print("[Dex] Navigating to next: #", next_index)
		_display_record(next_index)
	else:
		print("[Dex] Already at last record")


func _on_edit_pressed() -> void:
	"""Open manual entry popup for editing current dex entry"""
	if current_index < 0:
		show_error("No record selected", "Please select a dex entry to edit")
		return

	# Only allow editing own dex
	if current_user_id != "self":
		show_error("Cannot edit", "You can only edit your own dex entries")
		return

	print("[Dex] Opening manual entry for editing record #", current_index)

	# Get current record data
	var record: Dictionary = DexDatabase.get_record_for_user(current_index, current_user_id)
	if record.is_empty():
		show_error("Record not found", "Could not find record #%d" % current_index)
		return

	# Get entry ID for editing
	_get_entry_id_for_edit(record)

# ============================================================================
# Edit Entry Workflow
# ============================================================================

func _get_entry_id_for_edit(record: Dictionary) -> void:
	"""Get the server-side dex entry ID for editing"""
	var creation_index = record.get("creation_index", -1)
	if creation_index < 0:
		show_error("Invalid record", "Record has invalid creation index")
		return

	# Check if we already have the dex_entry_id stored locally
	var entry_id = record.get("dex_entry_id", "")
	if not entry_id.is_empty():
		print("[Dex] Using stored dex_entry_id: ", entry_id)
		_open_manual_entry_popup(entry_id, record)
		return

	# If not stored locally, fetch from server
	print("[Dex] dex_entry_id not stored locally, fetching from server...")
	show_loading("Loading entry details...")
	APIManager.dex.get_my_entries(_on_my_entries_for_edit.bind(creation_index, record))


func _on_my_entries_for_edit(response: Dictionary, code: int, _creation_index: int, record: Dictionary) -> void:
	"""Handle my entries response for editing"""
	hide_loading()

	if not validate_api_response(response, code):
		return

	var entries = response.get("results", [])
	var entry_id = ""

	# Get the animal_id from the local record to match with server
	var local_animal_id = record.get("animal_id", "")

	# Find the entry matching our animal_id
	for entry in entries:
		var server_animal_id = entry.get("animal", "")
		if not local_animal_id.is_empty() and server_animal_id == local_animal_id:
			entry_id = str(entry.get("id", ""))
			print("[Dex] Matched by animal_id: ", local_animal_id)
			break

	if entry_id.is_empty():
		show_error(
			"Entry not found",
			"Could not find this entry on the server. It may have been created before entry tracking was added.",
			code
		)
		return

	print("[Dex] Found dex entry ID: ", entry_id)

	# Store the entry_id in local database for future use
	record["dex_entry_id"] = entry_id
	DexDatabase.add_record_from_dict(record, current_user_id)
	print("[Dex] Stored dex_entry_id in local database for future edits")

	# Now open the manual entry popup
	_open_manual_entry_popup(entry_id, record)


func _open_manual_entry_popup(entry_id: String, record: Dictionary) -> void:
	"""Open the manual entry popup with current data"""
	# Create popup
	var popup_scene = load("res://scenes/social/components/manual_entry_popup.tscn")
	if not popup_scene:
		show_error("Failed to load popup", "Could not load manual entry popup scene")
		return

	var popup = popup_scene.instantiate()

	# Pre-populate with current animal data
	popup.prefill_data = {
		"genus": record.get("genus", ""),
		"species": record.get("species", ""),
		"common_name": record.get("common_name", "")
	}

	# Set the dex entry ID for updating
	popup.current_dex_entry_id = entry_id

	# Connect signals
	popup.entry_updated.connect(_on_edit_entry_updated)
	popup.popup_closed.connect(_on_edit_popup_closed)

	# Show popup
	add_child(popup)
	popup.popup_centered(Vector2(600, 500))


func _on_edit_entry_updated(_taxonomy_data: Dictionary) -> void:
	"""Handle entry update from manual entry popup"""
	print("[Dex] Entry updated with new taxonomy")

	# Store the dex_entry_id of the record we just edited
	var record = DexDatabase.get_record_for_user(current_index, current_user_id)
	pending_edit_dex_entry_id = record.get("dex_entry_id", "")
	print("[Dex] Stored pending_edit_dex_entry_id: ", pending_edit_dex_entry_id)

	# Trigger sync to update from server
	show_loading("Syncing updated entry...")
	trigger_sync()


func _on_edit_popup_closed() -> void:
	"""Handle edit popup closed"""
	print("[Dex] Edit popup closed")

# ============================================================================
# Signal Handlers - Database
# ============================================================================

func _on_record_added_multi_user(record: Dictionary, user_id: String) -> void:
	"""Handle new record added to database (multi-user)"""
	print("[Dex] New record added for user '%s': #%d" % [user_id, record.get("creation_index", -1)])

	# Only update if this record is for the currently viewing user
	if user_id != current_user_id:
		return

	# If we're currently showing empty state, load the new record
	if current_index < 0:
		var creation_index: int = record.get("creation_index", -1)
		if creation_index >= 0:
			_display_record(creation_index)
	else:
		# Update navigation buttons in case new record affects them
		_update_navigation_buttons()


func _on_database_switched(user_id: String) -> void:
	"""Handle database switch event"""
	print("[Dex] Database switched to user: ", user_id)
	current_user_id = user_id
	_load_first_record()

# ============================================================================
# Signal Handlers - Sync
# ============================================================================

func _on_sync_started(user_id: String) -> void:
	"""Handle sync started"""
	if user_id == current_user_id:
		is_syncing = true
		print("[Dex] Sync started for current user")
		# TODO: Use ProgressIndicator component instead
		show_loading("Syncing dex...")


func _on_sync_progress(user_id: String, current: int, total: int) -> void:
	"""Handle sync progress update"""
	if user_id == current_user_id:
		var progress := (float(current) / float(total)) * 100.0
		print("[Dex] Sync progress: %d/%d (%.1f%%)" % [current, total, progress])
		# TODO: Update ProgressIndicator component


func _on_sync_user_completed(user_id: String, entries_updated: int) -> void:
	"""Handle sync completed"""
	if user_id == current_user_id:
		is_syncing = false
		hide_loading()
		print("[Dex] Sync completed: %d entries updated" % entries_updated)

		# If sync returned 0 entries and we have invalid local data, clean it up
		if entries_updated == 0:
			_clean_corrupted_records()
			return

		# If we just edited an entry, find and display it
		if not pending_edit_dex_entry_id.is_empty():
			_navigate_to_edited_entry()
			return

		# Refresh display if we were showing empty state
		if current_index < 0 and entries_updated > 0:
			_load_first_record()
		# Or if the current record no longer exists (was deleted/changed)
		elif current_index >= 0 and not DexDatabase.has_record_for_user(current_index, current_user_id):
			print("[Dex] Current record #%d no longer exists, loading first record" % current_index)
			_load_first_record()


func _clean_corrupted_records() -> void:
	"""Clean up records with invalid images after sync"""
	var all_indices = DexDatabase.get_sorted_indices_for_user(current_user_id)
	var cleaned_count = 0

	for index in all_indices:
		var record = DexDatabase.get_record_for_user(index, current_user_id)
		var image_path: String = record.get("cached_image_path", "")
		if image_path.is_empty() or not FileAccess.file_exists(image_path):
			print("[Dex] Removing corrupted record #%d (no valid image)" % index)
			DexDatabase.remove_record(index, current_user_id)
			cleaned_count += 1

	if cleaned_count > 0:
		print("[Dex] Cleaned %d corrupted records" % cleaned_count)
		_load_first_record()


func _navigate_to_edited_entry() -> void:
	"""Navigate to the entry that was just edited after sync"""
	print("[Dex] Looking for updated record with dex_entry_id: ", pending_edit_dex_entry_id)

	var all_indices = DexDatabase.get_sorted_indices_for_user(current_user_id)
	for index in all_indices:
		var record = DexDatabase.get_record_for_user(index, current_user_id)
		if record.get("dex_entry_id", "") == pending_edit_dex_entry_id:
			print("[Dex] Found updated record at index #%d" % index)
			current_index = index
			_display_record(current_index)
			pending_edit_dex_entry_id = ""
			return

	print("[Dex] WARNING: Could not find updated record after sync")
	pending_edit_dex_entry_id = ""


func _on_sync_user_failed(user_id: String, error_message: String) -> void:
	"""Handle sync failed"""
	if user_id == current_user_id:
		is_syncing = false
		hide_loading()
		show_error("Sync failed", error_message)


func _on_friends_overview_received(friends: Array) -> void:
	"""Handle friends overview received"""
	print("[Dex] Friends overview received: %d friends" % friends.size())

	# Update available_users with real friend names
	for friend in friends:
		var friend_id: String = friend.get("user_id", "")
		var username: String = friend.get("username", "")
		if not friend_id.is_empty() and not username.is_empty():
			available_users[friend_id] = username + "'s Dex"

	# TODO: Update UserSelector component with updated names
