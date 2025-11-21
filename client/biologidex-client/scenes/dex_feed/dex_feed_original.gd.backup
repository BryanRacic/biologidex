extends Control
## Dex Feed - Display friends' dex entries in a chronological feed

# Constants
const FEED_ITEM_SCENE = preload("res://scenes/dex_feed/components/feed_list_item.tscn")
const SYNC_INTERVAL_MS = 60000  # Auto-refresh every minute

# Services
var TokenManager
var NavigationManager
var APIManager
var DexDatabase
var SyncManager

# State Management
var feed_entries: Array[Dictionary] = []
var displayed_entries: Array[Dictionary] = []
var current_filter: String = "all"
var selected_friend_id: String = ""
var is_loading: bool = false
var sync_queue: Array[String] = []
var friends_data: Dictionary = {}  # user_id -> friend info
var is_syncing: bool = false

# UI References
@onready var back_button: Button = $Panel/MarginContainer/VBoxContainer/Header/BackButton
@onready var refresh_button: Button = $Panel/MarginContainer/VBoxContainer/Header/RefreshButton
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/Header/TitleLabel
@onready var filter_all_button: Button = $Panel/MarginContainer/VBoxContainer/FilterBar/AllButton
@onready var filter_dropdown: OptionButton = $Panel/MarginContainer/VBoxContainer/FilterBar/FriendsDropdown
@onready var scroll_container: ScrollContainer = $Panel/MarginContainer/VBoxContainer/ScrollContainer
@onready var feed_container: VBoxContainer = $Panel/MarginContainer/VBoxContainer/ScrollContainer/FeedContainer
@onready var loading_overlay: Control = $LoadingOverlay
@onready var status_label: Label = $Panel/MarginContainer/VBoxContainer/StatusLabel

# Signals
signal feed_loaded(entry_count: int)
signal sync_started()
signal sync_completed()


func _ready() -> void:
	print("[DexFeed] Scene loaded")
	_initialize_services()

	# Check authentication
	if not TokenManager.is_logged_in():
		print("[DexFeed] ERROR: User not logged in")
		NavigationManager.go_back()
		return

	_setup_ui()
	_initialize_feed()


func _initialize_services() -> void:
	"""Initialize service references from autoloads"""
	TokenManager = get_node("/root/TokenManager")
	NavigationManager = get_node("/root/NavigationManager")
	APIManager = get_node("/root/APIManager")
	DexDatabase = get_node("/root/DexDatabase")
	SyncManager = get_node("/root/SyncManager")


func _setup_ui() -> void:
	"""Setup UI elements and connect signals"""
	back_button.pressed.connect(_on_back_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	filter_all_button.pressed.connect(_on_filter_all_pressed)
	filter_dropdown.item_selected.connect(_on_filter_dropdown_selected)

	# Set initial state
	title_label.text = "Friends' Feed"
	_show_loading(false)
	_show_status("", true)


func _initialize_feed() -> void:
	"""Initialize the feed by loading friends and syncing their dex entries"""
	print("[DexFeed] Initializing feed...")
	_show_status("Loading friends...", true)
	_load_friends_list()


func _load_friends_list() -> void:
	"""Load the friends list from the server"""
	if is_loading:
		print("[DexFeed] Already loading, skipping duplicate request")
		return

	is_loading = true
	print("[DexFeed] Loading friends list...")
	APIManager.social.get_friends(_on_friends_loaded)


func _on_friends_loaded(response: Dictionary, code: int) -> void:
	"""Handle friends list response"""
	is_loading = false

	if code != 200:
		var error_msg: String = response.get("error", "Failed to load friends")
		print("[DexFeed] ERROR loading friends: ", error_msg)
		_show_status("Failed to load friends: %s" % error_msg, false)
		return

	var friends: Array = response.get("friends", [])
	print("[DexFeed] Loaded %d friends" % friends.size())

	# Clear and populate friends data
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

	_populate_filter_dropdown()

	if friends_data.is_empty():
		_show_status("No friends yet. Add friends to see their catches!", false)
		_display_empty_state()
		return

	# Start syncing all friends' dex entries
	_sync_all_friends()


func _populate_filter_dropdown() -> void:
	"""Populate the filter dropdown with friend names"""
	filter_dropdown.clear()
	filter_dropdown.add_item("All Friends", 0)

	var index := 1
	for friend_id in friends_data.keys():
		var friend_info: Dictionary = friends_data[friend_id]
		var username: String = friend_info.get("username", "Unknown")
		filter_dropdown.add_item(username, index)
		# Store friend_id in metadata
		filter_dropdown.set_item_metadata(index, friend_id)
		index += 1


func _sync_all_friends() -> void:
	"""Start syncing all friends' dex entries using batch sync"""
	if is_syncing:
		print("[DexFeed] Already syncing, skipping duplicate request")
		return

	is_syncing = true

	print("[DexFeed] Starting batch sync for %d friends" % friends_data.size())
	_show_status("Syncing friends' dex entries...", true)
	_show_loading(true)

	sync_started.emit()

	# Build batch sync request for friends only (not self)
	var sync_requests := []
	for friend_id in friends_data.keys():
		sync_requests.append({
			"user_id": friend_id,
			"last_sync": SyncManager.get_last_sync(friend_id)
		})

	# Execute batch sync
	var req_config = APIManager.dex._create_request_config()
	APIManager.dex.api_client.post(
		"/dex/entries/batch_sync/",
		{"sync_requests": sync_requests},
		_on_batch_sync_success,
		_on_batch_sync_api_error,
		req_config
	)


func _on_batch_sync_success(response: Dictionary) -> void:
	"""Handle successful batch sync API response"""
	_on_batch_sync_completed(response, 200)


func _on_batch_sync_api_error(error) -> void:
	"""Handle batch sync API error"""
	var error_msg: String = ""
	var error_code: int = 500

	if error is Dictionary:
		error_msg = error.get("message", "Unknown error")
		error_code = error.get("code", 500)
	else:
		error_msg = str(error)

	_on_batch_sync_error({"error": error_msg}, error_code)


func _on_batch_sync_completed(response: Dictionary, code: int) -> void:
	"""Handle completion of batch sync"""
	if code != 200:
		print("[DexFeed] ERROR: Batch sync failed with code: ", code)
		_show_status("Sync failed", false)
		_show_loading(false)
		is_syncing = false
		return

	var results: Dictionary = response.get("results", {})
	var server_time: String = response.get("server_time", "")

	print("[DexFeed] Batch sync completed: %d users" % results.size())

	# Process each friend's results
	for user_id in results.keys():
		var user_result = results[user_id]

		if user_result.has("error"):
			var error_msg: String = user_result.get("error", "Unknown error")
			print("[DexFeed] ERROR syncing %s: %s" % [user_id, error_msg])
			continue

		var entries: Array = user_result.get("entries", [])
		print("[DexFeed] Processing %d entries for user: %s" % [entries.size(), user_id])

		# Process entries for this user (similar to DexService._process_sync_entries)
		for entry in entries:
			var creation_index_val: int = entry.get("creation_index", -1)
			var existing_record: Dictionary = DexDatabase.get_record_for_user(creation_index_val, user_id)
			var existing_cached_path: String = existing_record.get("cached_image_path", "")

			var record := {
				"creation_index": creation_index_val,
				"scientific_name": entry.get("scientific_name", ""),
				"common_name": entry.get("common_name", ""),
				"image_checksum": entry.get("image_checksum", ""),
				"dex_compatible_url": entry.get("dex_compatible_url", ""),
				"updated_at": entry.get("updated_at", ""),
				"cached_image_path": existing_cached_path,
				"animal_id": entry.get("animal_id", ""),
				"dex_entry_id": entry.get("id", "")
			}

			DexDatabase.add_record_from_dict(record, user_id)

		# Update sync timestamp for this user
		if not server_time.is_empty():
			SyncManager.update_last_sync(user_id, server_time)

	_on_all_syncs_completed()


func _on_batch_sync_error(response: Dictionary, code: int) -> void:
	"""Handle batch sync error"""
	var error_msg: String = response.get("error", "Unknown error")
	print("[DexFeed] ERROR: Batch sync failed: ", error_msg)

	_show_status("Sync failed: %s" % error_msg, false)
	_show_loading(false)
	is_syncing = false

	# Still try to display cached data
	_load_feed_entries()
	_display_feed()


func _on_all_syncs_completed() -> void:
	"""Called when all friends have been synced"""
	is_syncing = false
	_show_loading(false)

	print("[DexFeed] All syncs completed, loading feed entries...")
	_show_status("Building feed...", true)

	sync_completed.emit()

	# Load and display feed entries
	_load_feed_entries()
	_display_feed()


func _load_feed_entries() -> void:
	"""Load feed entries from all friends' cached dex data"""
	feed_entries.clear()

	# Aggregate entries from all friends
	for friend_id in friends_data.keys():
		var friend_entries: Array = DexDatabase.get_all_records_for_user(friend_id)
		var friend_info: Dictionary = friends_data.get(friend_id, {})

		print("[DexFeed] Loading %d entries for friend: %s" % [friend_entries.size(), friend_info.get("username", "Unknown")])
		for entry in friend_entries:
			print("[DexFeed] Entry #%d cached_path: '%s'" % [entry.get("creation_index", -1), entry.get("cached_image_path", "")])
			var feed_entry := _create_feed_entry(entry, friend_id, friend_info)
			feed_entries.append(feed_entry)

	# Sort by date (newest first)
	feed_entries.sort_custom(_sort_by_date_desc)

	print("[DexFeed] Loaded %d feed entries from %d friends" % [feed_entries.size(), friends_data.size()])


func _create_feed_entry(dex_record: Dictionary, owner_id: String, friend_info: Dictionary) -> Dictionary:
	"""Create a feed entry from a dex record"""
	return {
		"dex_entry_id": dex_record.get("dex_entry_id", ""),
		"owner_id": owner_id,
		"owner_username": friend_info.get("username", "Unknown"),
		"owner_avatar": friend_info.get("avatar", ""),
		"creation_index": dex_record.get("creation_index", -1),
		"animal_id": dex_record.get("animal_id", ""),
		"scientific_name": dex_record.get("scientific_name", "Unknown"),
		"common_name": dex_record.get("common_name", ""),
		"catch_date": dex_record.get("catch_date", dex_record.get("updated_at", "")),
		"updated_at": dex_record.get("updated_at", ""),
		"is_favorite": dex_record.get("is_favorite", false),
		"cached_image_path": dex_record.get("cached_image_path", ""),
		"dex_compatible_url": dex_record.get("dex_compatible_url", "")
	}


func _sort_by_date_desc(a: Dictionary, b: Dictionary) -> bool:
	"""Sort feed entries by date (newest first)"""
	var date_a: String = a.get("updated_at", a.get("catch_date", ""))
	var date_b: String = b.get("updated_at", b.get("catch_date", ""))
	return date_a > date_b  # Newest first


func _display_feed() -> void:
	"""Display the feed entries based on current filters"""
	_clear_feed_display()

	# Apply filters
	displayed_entries = _apply_filters(feed_entries)

	if displayed_entries.is_empty():
		_show_status("No entries to display", false)
		_display_empty_state()
		return

	# Display entries
	print("[DexFeed] Displaying %d entries" % displayed_entries.size())
	for entry in displayed_entries:
		_add_feed_item(entry)

	_show_status("%d entries" % displayed_entries.size(), true)
	feed_loaded.emit(displayed_entries.size())


func _apply_filters(entries: Array[Dictionary]) -> Array[Dictionary]:
	"""Apply current filters to the feed entries"""
	if current_filter == "all":
		return entries.duplicate()

	# Filter by specific friend
	if not selected_friend_id.is_empty():
		var filtered: Array[Dictionary] = []
		for entry in entries:
			if entry.get("owner_id", "") == selected_friend_id:
				filtered.append(entry)
		return filtered

	return entries.duplicate()


func _add_feed_item(entry: Dictionary) -> void:
	"""Add a feed item to the display"""
	var item = FEED_ITEM_SCENE.instantiate()
	feed_container.add_child(item)
	item.setup(entry)

	# Connect signals
	item.item_pressed.connect(_on_view_in_dex)


func _clear_feed_display() -> void:
	"""Clear all feed items from the display"""
	for child in feed_container.get_children():
		child.queue_free()


func _display_empty_state() -> void:
	"""Display empty state message"""
	var empty_label := Label.new()

	if friends_data.is_empty():
		empty_label.text = "No friends yet!\n\nAdd friends to see their catches in the feed."
	else:
		empty_label.text = "No entries to display.\n\nYour friends haven't caught any animals yet!"

	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	empty_label.custom_minimum_size = Vector2(400, 200)

	feed_container.add_child(empty_label)


func _on_view_in_dex(entry: Dictionary) -> void:
	"""Navigate to the friend's dex to view the full entry"""
	var friend_id: String = entry.get("owner_id", "")
	var username: String = entry.get("owner_username", "Friend")
	var creation_index: int = entry.get("creation_index", -1)

	if friend_id.is_empty() or creation_index < 0:
		print("[DexFeed] ERROR: Invalid entry data for navigation")
		return

	print("[DexFeed] Navigating to dex for %s, entry #%d" % [username, creation_index])

	# Set navigation context
	NavigationManager.set_context({
		"user_id": friend_id,
		"username": username,
		"creation_index": creation_index,
		"from_feed": true
	})

	NavigationManager.navigate_to("res://dex.tscn")


func _on_back_pressed() -> void:
	"""Navigate back to previous scene"""
	print("[DexFeed] Back button pressed")
	NavigationManager.go_back()


func _on_refresh_pressed() -> void:
	"""Refresh the feed by re-syncing all friends"""
	print("[DexFeed] Refresh button pressed")
	_show_status("Refreshing...", true)
	_sync_all_friends()


func _on_filter_all_pressed() -> void:
	"""Show all friends' entries"""
	print("[DexFeed] Filter: All friends")
	current_filter = "all"
	selected_friend_id = ""
	filter_dropdown.selected = 0
	_display_feed()


func _on_filter_dropdown_selected(index: int) -> void:
	"""Handle filter dropdown selection"""
	if index == 0:
		# "All Friends" selected
		_on_filter_all_pressed()
		return

	# Get friend_id from metadata
	var friend_id = filter_dropdown.get_item_metadata(index)
	if friend_id is String and not friend_id.is_empty():
		var friend_info: Dictionary = friends_data.get(friend_id, {})
		var username: String = friend_info.get("username", "Unknown")

		print("[DexFeed] Filter: %s" % username)
		current_filter = "friend"
		selected_friend_id = friend_id
		_display_feed()


func _show_loading(visible: bool) -> void:
	"""Show or hide loading overlay"""
	if loading_overlay:
		loading_overlay.visible = visible


func _show_status(message: String, is_success: bool) -> void:
	"""Show status message with appropriate color"""
	if not status_label:
		return

	status_label.text = message

	if message.is_empty():
		status_label.modulate = Color.WHITE
		status_label.visible = false
	else:
		status_label.visible = true
		if is_success:
			status_label.modulate = Color.GREEN
		else:
			status_label.modulate = Color.RED
