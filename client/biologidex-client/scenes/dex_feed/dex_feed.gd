extends BaseSceneNode
## Dex Feed - Display friends' dex entries in a chronological feed
## Uses FriendDexSyncService for centralized sync logic.

# Constants
const FEED_ITEM_SCENE = preload("res://scenes/dex_feed/components/feed_list_item.tscn")

# State Management (is_loading inherited from BaseSceneNode)
var feed_entries: Array[Dictionary] = []
var displayed_entries: Array[Dictionary] = []
var current_filter: String = "all"
var selected_friend_id: String = ""

# UI References (back_button inherited from BaseSceneNode, set via @export)
@onready var refresh_button: Button = get_node("%RefreshButton")
@onready var filter_all_button: Button = get_node("%AllButton")
@onready var filter_dropdown: OptionButton = get_node("%FriendsDropdown")
@onready var scroll_container: ScrollContainer = get_node("%ScrollContainer")
@onready var feed_container: VBoxContainer = get_node("%FeedContainer")
@onready var _feed_status_label: Label = get_node("%StatusLabel")
@onready var loading_overlay: Control = get_node("%LoadingOverlay")

# Signals
signal feed_loaded(entry_count: int)


func _on_scene_ready() -> void:
	"""Called by BaseSceneNode after managers are initialized and auth is checked"""
	scene_name = "DexFeed"

	_setup_ui()
	_connect_sync_signals()
	_initialize_feed()


func _setup_ui() -> void:
	"""Setup UI elements and connect signals"""
	refresh_button.pressed.connect(_on_refresh_pressed)
	filter_all_button.pressed.connect(_on_filter_all_pressed)
	filter_dropdown.item_selected.connect(_on_filter_dropdown_selected)

	_show_loading(false)
	_show_status("", true)


func _connect_sync_signals() -> void:
	"""Connect to FriendDexSyncService signals"""
	FriendDexSyncService.sync_started.connect(_on_sync_started)
	FriendDexSyncService.sync_completed.connect(_on_sync_completed)
	FriendDexSyncService.sync_failed.connect(_on_sync_failed)
	FriendDexSyncService.friends_loaded.connect(_on_friends_data_loaded)


func _initialize_feed() -> void:
	"""Initialize the feed by syncing friends' dex entries"""
	_show_status("Syncing friends...", true)
	_show_loading(true)
	FriendDexSyncService.sync_friends()


func _on_friends_data_loaded(friends_data: Dictionary) -> void:
	"""Handle friends data loaded"""
	_populate_filter_dropdown(friends_data)

	if friends_data.is_empty():
		_show_status("No friends yet. Add friends to see their catches!", false)
		_show_loading(false)
		_display_empty_state()


func _on_sync_started() -> void:
	"""Handle sync started"""
	_show_status("Syncing friends' dex entries...", true)
	_show_loading(true)


func _on_sync_completed(friends_data: Dictionary) -> void:
	"""Handle sync completed"""
	_show_loading(false)
	_populate_filter_dropdown(friends_data)

	if friends_data.is_empty():
		_show_status("No friends yet. Add friends to see their catches!", false)
		_display_empty_state()
		return

	_show_status("Building feed...", true)
	_load_feed_entries()
	_display_feed()


func _on_sync_failed(error: String) -> void:
	"""Handle sync failed"""
	_show_loading(false)
	_show_status("Sync failed: %s" % error, false)

	# Still try to display cached data
	_load_feed_entries()
	_display_feed()


func _populate_filter_dropdown(friends_data: Dictionary) -> void:
	"""Populate the filter dropdown with friend names"""
	filter_dropdown.clear()
	filter_dropdown.add_item("All Friends", 0)

	var index := 1
	for friend_id in friends_data.keys():
		var friend_info: Dictionary = friends_data[friend_id]
		var username: String = friend_info.get("username", "Unknown")
		filter_dropdown.add_item(username, index)
		filter_dropdown.set_item_metadata(index, friend_id)
		index += 1


func _load_feed_entries() -> void:
	"""Load feed entries from all friends' cached dex data"""
	feed_entries.clear()

	# Aggregate entries from all friends using FriendDexSyncService
	for friend_id in FriendDexSyncService.get_friend_ids():
		var friend_entries: Array = FriendDexSyncService.get_friend_entries(friend_id)
		var friend_info: Dictionary = FriendDexSyncService.get_friend_info(friend_id)

		for entry in friend_entries:
			var feed_entry := _create_feed_entry(entry, friend_id, friend_info)
			feed_entries.append(feed_entry)

	# Sort by date (newest first)
	feed_entries.sort_custom(_sort_by_date_desc)


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

	if not FriendDexSyncService.has_friends():
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
	FriendDexSyncService.sync_friends()


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
		var username: String = FriendDexSyncService.get_friend_username(friend_id)
		current_filter = "friend"
		selected_friend_id = friend_id
		_display_feed()


func _show_loading(visible: bool) -> void:
	"""Show or hide loading overlay"""
	if loading_overlay:
		loading_overlay.visible = visible


func _show_status(message: String, is_success: bool) -> void:
	"""Show status message with appropriate color"""
	if not _feed_status_label:
		return

	_feed_status_label.text = message

	if message.is_empty():
		_feed_status_label.modulate = Color.WHITE
		_feed_status_label.visible = false
	else:
		_feed_status_label.visible = true
		if is_success:
			_feed_status_label.modulate = Color.GREEN
		else:
			_feed_status_label.modulate = Color.RED
