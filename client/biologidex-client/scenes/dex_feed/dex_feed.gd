extends BaseSceneNode
## Dex Feed - Display friends' dex entries in a touch-driven vertical carousel.
## Uses PaperCameraScene for gesture handling and FeedCarouselRenderer for efficient pooled rendering.
## Entries are displayed with randomized spacing, size, offset, and rotation for an organic scrapbook feel.

const FeedCarouselRenderer = preload("res://features/dex_feed/feed_carousel_renderer.gd")

# State Management
enum FeedState { IDLE, LOADING, SCROLLING, ERROR }
var _state: FeedState = FeedState.IDLE
var feed_entries: Array[Dictionary] = []
var displayed_entries: Array[Dictionary] = []
var current_filter: String = "all"
var selected_friend_id: String = ""

# PaperCameraScene component
@onready var _paper_camera: PaperCameraScene = get_node("%PaperCameraScene")

# Carousel renderer (created dynamically)
var _carousel_renderer: FeedCarouselRenderer

# Feed-specific scroll configuration
const HORIZONTAL_BOUND_RATIO: float = 0.5  # ±50% of viewport width for horizontal scroll

# UI References
@onready var refresh_button: Button = get_node("%RefreshButton")
@onready var filter_all_button: Button = get_node("%AllButton")
@onready var filter_dropdown: OptionButton = get_node("%FriendsDropdown")
@onready var _content_area: Control = get_node("%ContentArea")
@onready var _carousel_container: Control = get_node("%CarouselContainer")
@onready var _empty_state_label: Label = get_node("%EmptyStateLabel")
@onready var _feed_status_label: Label = get_node("%StatusLabel")
@onready var loading_overlay: Control = get_node("%LoadingOverlay")

# Configuration - item dimensions are now calculated automatically from container width

# Signals
signal feed_loaded(entry_count: int)


func _on_scene_ready() -> void:
	"""Called by BaseSceneNode after managers are initialized and auth is checked"""
	scene_name = "DexFeed"

	_setup_ui()
	await _setup_carousel_components()
	_connect_sync_signals()
	_initialize_feed()


func _setup_ui() -> void:
	"""Setup UI elements and connect signals"""
	refresh_button.pressed.connect(_on_refresh_pressed)
	filter_all_button.pressed.connect(_on_filter_all_pressed)
	filter_dropdown.item_selected.connect(_on_filter_dropdown_selected)

	_show_loading(false)
	_show_status("", true)
	_show_empty_state(false)


func _setup_carousel_components() -> void:
	"""Setup touch controller and carousel renderer"""
	# Wait for layout to settle
	await get_tree().process_frame

	# Use actual content area size for proper desktop/wide-screen support
	var content_width := _content_area.size.x
	var content_height := _content_area.size.y
	assert(content_width > 0 and content_height > 0, "DexFeed: ContentArea size must be > 0. Ensure layout has settled before setup.")

	# Configure scroll limits for vertical feed
	var horizontal_max := content_width * HORIZONTAL_BOUND_RATIO
	_paper_camera.set_scroll_limits(
		Vector2(-horizontal_max, 0.0),
		Vector2(horizontal_max, 0.0)  # Y max set in _on_layout_calculated
	)

	# Connect PaperCameraScene signals
	_paper_camera.view_changed.connect(_on_view_changed)
	_paper_camera.tap_detected.connect(_on_tap_detected)
	_paper_camera.gesture_started.connect(_on_gesture_started)
	_paper_camera.gesture_ended.connect(_on_gesture_ended)

	# Create and configure carousel renderer
	_carousel_renderer = FeedCarouselRenderer.new()
	_carousel_renderer.name = "CarouselRenderer"
	_carousel_renderer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_carousel_container.add_child(_carousel_renderer)

	# Configure carousel dimensions (item height calculated from width automatically)
	_carousel_renderer.setup(content_width, content_height)

	# Connect carousel signals
	_carousel_renderer.item_pressed.connect(_on_view_in_dex)
	_carousel_renderer.image_ready.connect(_on_image_ready)
	_carousel_renderer.layout_calculated.connect(_on_layout_calculated)

	print("[DexFeed] Carousel setup complete: %dx%d" % [int(content_width), int(content_height)])


func _connect_sync_signals() -> void:
	"""Connect to FriendDexSyncService signals"""
	FriendDexSyncService.sync_started.connect(_on_sync_started)
	FriendDexSyncService.sync_completed.connect(_on_sync_completed)
	FriendDexSyncService.sync_failed.connect(_on_sync_failed)
	FriendDexSyncService.friends_loaded.connect(_on_friends_data_loaded)


func _initialize_feed() -> void:
	"""Initialize the feed by syncing friends' dex entries"""
	_set_state(FeedState.LOADING)
	_show_status("Syncing friends...", true)
	_show_loading(true)
	FriendDexSyncService.sync_friends()


# =============================================================================
# State Management
# =============================================================================

func _set_state(new_state: FeedState) -> void:
	"""Update state machine."""
	if _state == new_state:
		return
	print("[DexFeed] State: %s -> %s" % [FeedState.keys()[_state], FeedState.keys()[new_state]])
	_state = new_state


# =============================================================================
# Sync Signal Handlers
# =============================================================================

func _on_friends_data_loaded(friends_data: Dictionary) -> void:
	"""Handle friends data loaded"""
	_populate_filter_dropdown(friends_data)

	if friends_data.is_empty():
		_show_status("No friends yet. Add friends to see their catches!", false)
		_show_loading(false)
		_show_empty_state(true, "No friends yet!\n\nAdd friends to see their catches in the feed.")
		_set_state(FeedState.IDLE)


func _on_sync_started() -> void:
	"""Handle sync started"""
	_set_state(FeedState.LOADING)
	_show_status("Syncing friends' dex entries...", true)
	_show_loading(true)


func _on_sync_completed(friends_data: Dictionary) -> void:
	"""Handle sync completed"""
	_show_loading(false)
	_populate_filter_dropdown(friends_data)

	if friends_data.is_empty():
		_show_status("No friends yet. Add friends to see their catches!", false)
		_show_empty_state(true, "No friends yet!\n\nAdd friends to see their catches in the feed.")
		_set_state(FeedState.IDLE)
		return

	_show_status("Building feed...", true)
	_load_feed_entries()
	_display_feed()
	_set_state(FeedState.IDLE)


func _on_sync_failed(error: String) -> void:
	"""Handle sync failed"""
	_show_loading(false)
	_show_status("Sync failed: %s" % error, false)
	_set_state(FeedState.ERROR)

	# Still try to display cached data
	_load_feed_entries()
	if not feed_entries.is_empty():
		_display_feed()
		_set_state(FeedState.IDLE)


# =============================================================================
# Feed Data Management
# =============================================================================

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
	print("[DexFeed] Loaded %d feed entries" % feed_entries.size())


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
	return date_a > date_b


func _display_feed() -> void:
	"""Display the feed entries using the carousel"""
	# Apply filters
	displayed_entries = _apply_filters(feed_entries)

	if displayed_entries.is_empty():
		_show_status("No entries to display", false)
		_show_empty_state(true, "No entries to display.\n\nYour friends haven't caught any animals yet!")
		_carousel_renderer.clear()
		# Reset scroll limits (horizontal only)
		var content_width := _content_area.size.x
		var horizontal_max := content_width * HORIZONTAL_BOUND_RATIO
		_paper_camera.set_scroll_limits(
			Vector2(-horizontal_max, 0.0),
			Vector2(horizontal_max, 0.0)
		)
		_paper_camera.reset()
		return

	# Hide empty state
	_show_empty_state(false)

	# Configure carousel with entries (this triggers layout calculation via layout_calculated signal)
	_carousel_renderer.set_entries(displayed_entries)

	# Scroll to top (reset to origin)
	_paper_camera.scroll_to(Vector2.ZERO, false)

	_show_status("%d entries" % displayed_entries.size(), true)
	feed_loaded.emit(displayed_entries.size())
	print("[DexFeed] Displaying %d entries in carousel" % displayed_entries.size())


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


# =============================================================================
# PaperCameraScene Signal Handlers
# =============================================================================

func _on_view_changed(cam_position: Vector2, zoom: float) -> void:
	"""Handle view change from PaperCameraScene"""
	if _carousel_renderer:
		_carousel_renderer.update_scroll(cam_position, zoom)


func _on_layout_calculated(total_height: float) -> void:
	"""Handle layout calculation complete - set max scroll"""
	# total_height is now in actual pixels (matching content area)
	# Add extra half screen of scroll space at the bottom
	var visible_height := _content_area.size.y
	var extra_scroll := visible_height * 0.5
	var max_scroll := maxf(0.0, total_height - visible_height + extra_scroll)

	# Update scroll limits (keep existing horizontal limits)
	var content_width := _content_area.size.x
	var horizontal_max := content_width * HORIZONTAL_BOUND_RATIO
	_paper_camera.set_scroll_limits(
		Vector2(-horizontal_max, 0.0),
		Vector2(horizontal_max, max_scroll)
	)
	print("[DexFeed] Layout: total_height=%.0f, visible=%.0f, max_scroll=%.0f" % [total_height, visible_height, max_scroll])


func _on_tap_detected(world_pos: Vector2) -> void:
	"""Handle tap on carousel background - find which entry was tapped"""
	# Convert world position to content space and find entry
	# The camera position represents the scroll offset
	var cam_pos := _paper_camera.get_camera_position()
	var tap_y := cam_pos.y + _content_area.size.y / 2.0

	var entry_index := _carousel_renderer.get_entry_at_position(tap_y)

	if entry_index >= 0 and entry_index < displayed_entries.size():
		var entry: Dictionary = displayed_entries[entry_index]
		_on_view_in_dex(entry)


func _on_gesture_started() -> void:
	"""Handle gesture start"""
	if _state == FeedState.IDLE:
		_set_state(FeedState.SCROLLING)


func _on_gesture_ended() -> void:
	"""Handle gesture end"""
	if _state == FeedState.SCROLLING:
		_set_state(FeedState.IDLE)


func _on_image_ready(_index: int) -> void:
	"""Handle image loaded for carousel item"""
	pass  # Could update status if needed


# =============================================================================
# Navigation
# =============================================================================

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


# =============================================================================
# Filter Handlers
# =============================================================================

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
		print("[DexFeed] Filter: %s" % username)
		current_filter = "friend"
		selected_friend_id = friend_id
		_display_feed()


# =============================================================================
# UI Helpers
# =============================================================================

func _show_loading(should_show: bool) -> void:
	"""Show or hide loading overlay"""
	if loading_overlay:
		loading_overlay.visible = should_show


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


func _show_empty_state(should_show: bool, message: String = "") -> void:
	"""Show or hide empty state message"""
	if _empty_state_label:
		_empty_state_label.visible = should_show
		if should_show and not message.is_empty():
			_empty_state_label.text = message


# =============================================================================
# Cleanup
# =============================================================================

func _on_scene_exit() -> void:
	"""Clean up when scene exits"""
	# Disconnect sync signals
	if FriendDexSyncService.sync_started.is_connected(_on_sync_started):
		FriendDexSyncService.sync_started.disconnect(_on_sync_started)
	if FriendDexSyncService.sync_completed.is_connected(_on_sync_completed):
		FriendDexSyncService.sync_completed.disconnect(_on_sync_completed)
	if FriendDexSyncService.sync_failed.is_connected(_on_sync_failed):
		FriendDexSyncService.sync_failed.disconnect(_on_sync_failed)
	if FriendDexSyncService.friends_loaded.is_connected(_on_friends_data_loaded):
		FriendDexSyncService.friends_loaded.disconnect(_on_friends_data_loaded)

	print("[DexFeed] Scene cleanup complete")
