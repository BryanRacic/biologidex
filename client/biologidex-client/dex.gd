extends Control
## Dex Gallery - Browse through discovered animals with multi-user support

@onready var back_button: Button = $Panel/MarginContainer/VBoxContainer/Header/BackButton
@onready var dex_number_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/"Dex Number"
@onready var record_image: Control = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage
@onready var bordered_container: AspectRatioContainer = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio
@onready var bordered_image: TextureRect = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio/ImageBorder/Image
@onready var record_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio/ImageBorder/RecordMargin/RecordBackground/RecordTextMargin/RecordLabel
@onready var simple_image: TextureRect = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/Image
@onready var previous_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/HBoxContainer/PreviousButton
@onready var next_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/HBoxContainer/NextButton

# TODO: Add these UI elements to dex.tscn:
# @onready var user_selector: OptionButton = $Panel/MarginContainer/VBoxContainer/Header/UserSelector
# @onready var sync_button: Button = $Panel/MarginContainer/VBoxContainer/Header/SyncButton
# @onready var sync_progress: ProgressBar = $Panel/MarginContainer/VBoxContainer/Header/SyncProgress

var current_index: int = -1
var current_image_width: float = 0.0
var current_image_height: float = 0.0
var current_user_id: String = "self"  # Currently viewing user's dex
var is_syncing: bool = false
var available_users: Dictionary = {}  # user_id -> username mapping


func _ready() -> void:
	print("[Dex] Scene loaded (Multi-user mode)")

	# Check authentication
	if not TokenManager.is_logged_in():
		print("[Dex] ERROR: User not logged in")
		NavigationManager.go_back()
		return

	# Connect buttons
	back_button.pressed.connect(_on_back_pressed)
	previous_button.pressed.connect(_on_previous_pressed)
	next_button.pressed.connect(_on_next_pressed)

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
	if NavigationManager.has_context():
		var context := NavigationManager.get_context()
		if context.has("user_id"):
			var friend_id: String = context.get("user_id")
			var username: String = context.get("username", "Friend")

			print("[Dex] Loading friend's dex: ", username, " (", friend_id, ")")

			# Switch to friend's dex
			current_user_id = friend_id
			available_users[friend_id] = username

			# Clear context
			NavigationManager.clear_context()

	# Initialize user list
	_populate_user_list()

	# Check if we need to sync
	_check_and_sync_if_needed()

	# Load first record for current user
	_load_first_record()


func _populate_user_list() -> void:
	"""Initialize the list of available users (self + cached friends)"""
	# Only set "self" if not already populated (from context)
	if not available_users.has("self"):
		available_users["self"] = "My Dex"

	# Add any friends whose dex we have cached (but don't overwrite existing)
	var tracked_users := DexDatabase.get_tracked_users()
	for user_id in tracked_users:
		if user_id != "self" and not available_users.has(user_id):
			available_users[user_id] = "Friend (%s)" % user_id.substr(0, 8)

	print("[Dex] Available users: ", available_users.keys())

	# Fetch friends overview to update names
	APIManager.dex.get_friends_overview()


func _check_and_sync_if_needed() -> void:
	"""Always trigger sync when opening dex - incremental if we have a last_sync timestamp"""
	# Check if database is empty
	var first_index := DexDatabase.get_first_index_for_user("self")
	var database_empty := (first_index < 0)

	# Check if we've never synced
	var last_sync := SyncManager.get_last_sync("self")
	var never_synced := last_sync.is_empty()

	# Always trigger sync (will be incremental if last_sync exists)
	if database_empty or never_synced:
		print("[Dex] Auto-triggering initial sync (database_empty=%s, never_synced=%s)" % [database_empty, never_synced])
	else:
		print("[Dex] Auto-triggering incremental sync (last_sync: %s)" % last_sync)

	trigger_sync()


func _load_first_record() -> void:
	"""Load the first record (lowest creation_index) for current user"""
	var first_index := DexDatabase.get_first_index_for_user(current_user_id)

	if first_index >= 0:
		_display_record(first_index)
	else:
		_show_empty_state()


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
	var record := DexDatabase.get_record_for_user(creation_index, current_user_id)

	if record.is_empty():
		print("[Dex] ERROR: Record not found: ", creation_index)
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

	# Update navigation buttons
	_update_navigation_buttons()


func _load_and_display_image(path: String) -> void:
	"""Load image from local cache and display it"""
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[Dex] Failed to open image file: ", path)
		return

	var data := file.get_buffer(file.get_length())
	file.close()

	var image := Image.new()
	var error := image.load_png_from_buffer(data)

	if error != OK:
		push_error("[Dex] Failed to load PNG image: ", error)
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
	var prev_index := DexDatabase.get_previous_index_for_user(current_index, current_user_id)
	previous_button.disabled = (prev_index < 0)

	# Check if there's a next record for current user
	var next_index := DexDatabase.get_next_index_for_user(current_index, current_user_id)
	next_button.disabled = (next_index < 0)


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


func _on_previous_pressed() -> void:
	"""Navigate to previous record"""
	if current_index < 0:
		return

	var prev_index := DexDatabase.get_previous_index_for_user(current_index, current_user_id)
	if prev_index >= 0:
		print("[Dex] Navigating to previous: #", prev_index)
		_display_record(prev_index)
	else:
		print("[Dex] Already at first record")


func _on_next_pressed() -> void:
	"""Navigate to next record"""
	if current_index < 0:
		return

	var next_index := DexDatabase.get_next_index_for_user(current_index, current_user_id)
	if next_index >= 0:
		print("[Dex] Navigating to next: #", next_index)
		_display_record(next_index)
	else:
		print("[Dex] Already at last record")


func _on_back_pressed() -> void:
	"""Navigate back to previous scene"""
	print("[Dex] Back button pressed")
	NavigationManager.go_back()


## Multi-user signal handlers

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


## Sync signal handlers

func _on_sync_started(user_id: String) -> void:
	"""Handle sync started"""
	if user_id == current_user_id:
		is_syncing = true
		print("[Dex] Sync started for current user")
		# TODO: Disable sync button, show progress bar


func _on_sync_progress(user_id: String, current: int, total: int) -> void:
	"""Handle sync progress update"""
	if user_id == current_user_id:
		var progress := (float(current) / float(total)) * 100.0
		print("[Dex] Sync progress: %d/%d (%.1f%%)" % [current, total, progress])
		# TODO: Update progress bar value


func _on_sync_user_completed(user_id: String, entries_updated: int) -> void:
	"""Handle sync completed"""
	if user_id == current_user_id:
		is_syncing = false
		print("[Dex] Sync completed: %d entries updated" % entries_updated)
		# TODO: Hide progress bar, enable sync button, show success message

		# Refresh display if we were showing empty state
		if current_index < 0 and entries_updated > 0:
			_load_first_record()


func _on_sync_user_failed(user_id: String, error_message: String) -> void:
	"""Handle sync failed"""
	if user_id == current_user_id:
		is_syncing = false
		push_error("[Dex] Sync failed: %s" % error_message)
		# TODO: Hide progress bar, enable sync button, show error message


func _on_friends_overview_received(friends: Array) -> void:
	"""Handle friends overview received"""
	print("[Dex] Friends overview received: %d friends" % friends.size())

	# Update available_users with real friend names
	for friend in friends:
		var friend_id: String = friend.get("user_id", "")
		var username: String = friend.get("username", "")
		if not friend_id.is_empty() and not username.is_empty():
			available_users[friend_id] = username + "'s Dex"

	# TODO: Update user selector dropdown with updated names
