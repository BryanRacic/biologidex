extends BaseSceneNode
## Community Scene - Combined dex feed and friends management with tabbed navigation.
##
## Features:
## - JournalTabs component for switching between "Dex Feed" and "Friends" views
## - Dex Feed: World-space carousel with randomized scrapbook layout
## - Friends: Lab book style friend management (add/remove friends, pending requests)
## - Single PaperCameraScene handles scrolling for both tabs
##
## ARCHITECTURE:
## - Feed tab uses FeedVisualization added to PaperCameraScene.content_container
## - Friends tab positions scroll_content directly via camera.position.y

const ClipboardUtils = preload("res://features/ui/components/clipboard/clipboard_helper.gd")
const FeedVisualizationClass = preload("res://features/dex_feed/feed_visualization.gd")

# =============================================================================
# Constants
# =============================================================================

const TAB_FEED := "feed"
const TAB_FRIENDS := "friends"
const HORIZONTAL_BOUND_RATIO: float = 0.3  # ±30% of viewport width for scrapbook wobble

# =============================================================================
# State Management
# =============================================================================

enum CommunityState { IDLE, LOADING, SCROLLING, ERROR }
var _state: CommunityState = CommunityState.IDLE
var _active_tab: String = TAB_FEED

# Feed data
var feed_entries: Array[Dictionary] = []
var displayed_entries: Array[Dictionary] = []
var current_filter: String = "all"
var selected_friend_id: String = ""

# Friends data
var friends_data: Array = []
var pending_requests: Array = []

# =============================================================================
# Components
# =============================================================================

@onready var _paper_camera: PaperCameraScene = get_node("%PaperCameraScene")

# Tabs
var _journal_tabs: JournalTabs

# Feed visualization (created dynamically for web export compatibility)
var _feed_visualization: FeedVisualization = null

# Preloaded scenes for friends list
var friend_item_scene = preload("res://scenes/social/components/friend_list_item.tscn")
var pending_item_scene = preload("res://scenes/social/components/pending_request_item.tscn")

# =============================================================================
# UI References
# =============================================================================

# Header
@onready var refresh_button: Button = get_node("%RefreshButton")

# Feed UI
@onready var _content_area: Control = get_node("%ContentArea")
@onready var _feed_container: Control = get_node("%FeedContainer")
@onready var _feed_empty_label: Label = get_node("%FeedEmptyLabel")

# Filter UI (feed)
@onready var filter_all_button: Button = get_node("%AllButton")
@onready var filter_dropdown: OptionButton = get_node("%FriendsDropdown")
@onready var filter_bar: Control = get_node("%FilterBar")

# Friends UI
@onready var _friends_container: Control = get_node("%FriendsContainer")
@onready var scroll_content: VBoxContainer = get_node("%ScrollContent")
@onready var friend_code_display: Button = get_node("%FriendCodeDisplay")
@onready var copy_feedback: Label = get_node("%CopyFeedback")
@onready var friend_code_input: LineEdit = get_node("%FriendCodeInput")
@onready var add_button: Button = get_node("%AddButton")
@onready var friends_section: VBoxContainer = get_node("%FriendsSection")
@onready var friends_list: VBoxContainer = get_node("%FriendsList")
@onready var pending_section: VBoxContainer = get_node("%PendingSection")
@onready var pending_header: HBoxContainer = get_node("%PendingHeader")
@onready var pending_list: VBoxContainer = get_node("%PendingList")

# Loading overlay
@onready var loading_overlay: Control = get_node("%LoadingOverlay")

# Confirmation dialog (for friend removal)
var confirmation_dialog: ConfirmationDialog = null
var pending_removal_friend: Dictionary = {}
var pending_removal_friendship_id: String = ""

# Copy feedback tween
var _copy_feedback_tween: Tween = null

# =============================================================================
# Lifecycle
# =============================================================================

func _on_scene_ready() -> void:
	"""Called by BaseSceneNode after managers are initialized and auth is checked"""
	scene_name = "Community"
	print("[Community] Scene ready (combined feed + friends)")

	# Wire up status label
	status_label = get_node("%StatusLabel")

	_setup_tabs()
	_setup_ui()
	await _setup_scroll_controller()
	await _setup_feed_visualization()
	_setup_confirmation_dialog()
	_connect_sync_signals()

	# Initialize with feed tab active
	_switch_to_tab(TAB_FEED)
	_initialize_feed()

# =============================================================================
# Tab Setup
# =============================================================================

func _setup_tabs() -> void:
	"""Create and configure the JournalTabs component."""
	_journal_tabs = get_node("%JournalTabs")
	_journal_tabs.add_tab(TAB_FEED, "Dex Feed")
	_journal_tabs.add_tab(TAB_FRIENDS, "Friends")
	_journal_tabs.tab_changed.connect(_on_tab_changed)
	print("[Community] JournalTabs configured")

# =============================================================================
# UI Setup
# =============================================================================

func _setup_ui() -> void:
	"""Setup UI elements and connect signals"""
	# Header
	refresh_button.pressed.connect(_on_refresh_pressed)

	# Feed filter UI
	filter_all_button.pressed.connect(_on_filter_all_pressed)
	filter_dropdown.item_selected.connect(_on_filter_dropdown_selected)

	# Friends UI
	add_button.pressed.connect(_on_add_button_pressed)
	friend_code_input.text_submitted.connect(_on_friend_code_submitted)
	friend_code_display.pressed.connect(_on_own_friend_code_pressed)

	# Hide copy feedback initially
	if copy_feedback:
		copy_feedback.modulate.a = 0.0

	_show_loading(false)
	_show_status("", true)


func _setup_scroll_controller() -> void:
	"""Setup PaperCameraScene for scroll system"""
	await get_tree().process_frame

	# Connect gesture signals for state tracking
	_paper_camera.gesture_started.connect(_on_gesture_started)
	_paper_camera.gesture_ended.connect(_on_gesture_ended)

	print("[Community] PaperCameraScene setup complete")


func _setup_feed_visualization() -> void:
	"""Setup FeedVisualization in world-space (like TreeVisualization)."""
	await get_tree().process_frame

	var content_width := _content_area.size.x
	var content_height := _content_area.size.y
	if content_width <= 0 or content_height <= 0:
		push_error("Community: ContentArea size must be > 0")
		return

	# Create FeedVisualization dynamically (web export compatible)
	_feed_visualization = FeedVisualizationClass.new()
	_feed_visualization.name = "FeedVisualization"

	# Add to PaperCameraScene content container (world-space)
	_paper_camera.content_container.add_child(_feed_visualization)

	# Setup with camera reference
	_feed_visualization.setup(_paper_camera)

	# Connect signals
	_feed_visualization.entry_pressed.connect(_on_view_in_dex)
	_feed_visualization.layout_calculated.connect(_on_feed_layout_calculated)

	print("[Community] FeedVisualization setup complete: content area %dx%d" % [int(content_width), int(content_height)])


func _setup_confirmation_dialog() -> void:
	"""Create and setup the confirmation dialog for removing friends"""
	confirmation_dialog = ConfirmationDialog.new()
	confirmation_dialog.dialog_text = "Are you sure you want to remove this friend?"
	confirmation_dialog.confirmed.connect(_confirm_remove_friend)
	add_child(confirmation_dialog)


func _connect_sync_signals() -> void:
	"""Connect to FriendDexSyncService signals"""
	FriendDexSyncService.sync_started.connect(_on_sync_started)
	FriendDexSyncService.sync_completed.connect(_on_sync_completed)
	FriendDexSyncService.sync_failed.connect(_on_sync_failed)
	FriendDexSyncService.friends_loaded.connect(_on_friends_data_loaded)

# =============================================================================
# Tab Switching
# =============================================================================

func _on_tab_changed(tab_id: String) -> void:
	"""Handle tab change from JournalTabs."""
	_switch_to_tab(tab_id)


func _switch_to_tab(tab_id: String) -> void:
	"""Switch active tab and update visibility/scroll settings."""
	if _active_tab == tab_id and _feed_container.visible == (tab_id == TAB_FEED):
		# Already on this tab with correct visibility
		return

	_active_tab = tab_id
	print("[Community] Switching to tab: ", tab_id)

	if tab_id == TAB_FEED:
		_activate_feed_tab()
	else:
		_activate_friends_tab()


func _activate_feed_tab() -> void:
	"""Activate the feed tab UI and scroll settings."""
	# Update visibility
	_feed_container.visible = true
	_friends_container.visible = false
	filter_bar.visible = true

	# Show feed visualization
	if _feed_visualization:
		_feed_visualization.visible = true

	# Disconnect friends view_changed, connect feed's
	if _paper_camera.view_changed.is_connected(_on_friends_view_changed):
		_paper_camera.view_changed.disconnect(_on_friends_view_changed)

	# Refresh display if we have entries (this sets scroll limits and position)
	if not displayed_entries.is_empty():
		_display_feed()
	else:
		# No entries - set default scroll limits
		var content_width := _content_area.size.x
		var horizontal_max := content_width * HORIZONTAL_BOUND_RATIO
		_paper_camera.set_scroll_limits(
			Vector2(-horizontal_max, 0.0),
			Vector2(horizontal_max, 0.0)
		)
		_paper_camera.scroll_to(Vector2.ZERO, false)


func _activate_friends_tab() -> void:
	"""Activate the friends tab UI and scroll settings."""
	# Update visibility
	_feed_container.visible = false
	_friends_container.visible = true
	filter_bar.visible = false

	# Hide feed visualization
	if _feed_visualization:
		_feed_visualization.visible = false

	# Connect friends view_changed for scroll_content positioning
	if not _paper_camera.view_changed.is_connected(_on_friends_view_changed):
		_paper_camera.view_changed.connect(_on_friends_view_changed)

	# Configure scroll limits for friends (vertical only)
	_paper_camera.set_scroll_limits(
		Vector2(0.0, 0.0),
		Vector2(0.0, 0.0)  # Will be updated in _update_friends_scroll_limits
	)

	# Reset scroll position
	_paper_camera.scroll_to(Vector2.ZERO, false)

	# Load friends data if not already loaded
	if friends_data.is_empty() and pending_requests.is_empty():
		_load_friend_code()
		_load_friends()
		_load_pending_requests()
	else:
		_update_friends_scroll_limits()

# =============================================================================
# Scroll Handling
# =============================================================================

func _on_friends_view_changed(cam_position: Vector2, _zoom: float) -> void:
	"""Handle view change for friends tab (scroll_content positioning)."""
	if _active_tab != TAB_FRIENDS:
		return
	if scroll_content:
		scroll_content.position.y = -cam_position.y


func _on_gesture_started() -> void:
	"""Handle gesture start"""
	if _state == CommunityState.IDLE:
		_state = CommunityState.SCROLLING


func _on_gesture_ended() -> void:
	"""Handle gesture end"""
	if _state == CommunityState.SCROLLING:
		_state = CommunityState.IDLE


func _on_feed_layout_calculated(_total_height: float) -> void:
	"""Handle feed layout calculation complete - set scroll limits."""
	var viewport_size: Vector2 = get_viewport_rect().size
	var current_zoom: float = _paper_camera.get_current_zoom() if _paper_camera else 1.0
	var visible_height: float = viewport_size.y / current_zoom

	# Get actual entry positions from FeedVisualization
	var first_top: float = _feed_visualization.get_first_entry_top()
	var last_bottom: float = _feed_visualization.get_last_entry_bottom()

	# Small margin in world units (3% of visible height)
	var margin: float = visible_height * 0.03

	# Min scroll: camera position that puts first image top near viewport top
	var min_scroll_y: float = first_top + visible_height / 2.0 - margin

	# Max scroll: allow last image to scroll to center of viewport
	var max_scroll_y: float = last_bottom

	# Ensure max >= min
	max_scroll_y = maxf(min_scroll_y, max_scroll_y)

	# Horizontal limits for scrapbook wobble effect
	var horizontal_max: float = viewport_size.x * HORIZONTAL_BOUND_RATIO

	_paper_camera.set_scroll_limits(
		Vector2(-horizontal_max, min_scroll_y),
		Vector2(horizontal_max, max_scroll_y)
	)
	print("[Community] Feed layout: first_top=%.0f, last_bottom=%.0f, visible=%.0f, scroll=[%.0f, %.0f]" % [first_top, last_bottom, visible_height, min_scroll_y, max_scroll_y])


func _update_friends_scroll_limits() -> void:
	"""Update max scroll based on friends content height"""
	if not _paper_camera or not scroll_content or not _content_area:
		return

	await get_tree().process_frame

	var content_height := scroll_content.size.y
	var visible_height := _content_area.size.y
	var max_scroll := maxf(0.0, content_height - visible_height)

	_paper_camera.set_scroll_limits(
		Vector2(0.0, 0.0),
		Vector2(0.0, max_scroll)
	)
	print("[Community] Friends scroll limits: content=%d, visible=%d, max=%d" % [
		int(content_height), int(visible_height), int(max_scroll)
	])

# =============================================================================
# Feed Data Management
# =============================================================================

func _initialize_feed() -> void:
	"""Initialize the feed by syncing friends' dex entries"""
	_set_state(CommunityState.LOADING)
	_show_status("Syncing friends...", true)
	_show_loading(true)
	FriendDexSyncService.sync_friends()


func _on_sync_started() -> void:
	"""Handle sync started"""
	_set_state(CommunityState.LOADING)
	_show_status("Syncing friends' dex entries...", true)
	_show_loading(true)


func _on_sync_completed(friends_sync_data: Dictionary) -> void:
	"""Handle sync completed"""
	_show_loading(false)
	_populate_filter_dropdown(friends_sync_data)

	if friends_sync_data.is_empty():
		_show_status("No friends yet. Add friends to see their catches!", false)
		_show_feed_empty_state(true, "No friends yet!\n\nAdd friends to see their catches in the feed.")
		_set_state(CommunityState.IDLE)
		return

	_show_status("Building feed...", true)
	_load_feed_entries()
	_display_feed()
	_set_state(CommunityState.IDLE)


func _on_sync_failed(error: String) -> void:
	"""Handle sync failed"""
	_show_loading(false)
	_show_status("Sync failed: %s" % error, false)
	_set_state(CommunityState.ERROR)

	# Still try to display cached data
	_load_feed_entries()
	if not feed_entries.is_empty():
		_display_feed()
		_set_state(CommunityState.IDLE)


func _on_friends_data_loaded(friends_sync_data: Dictionary) -> void:
	"""Handle friends data loaded - update filter and check for empty state"""
	_populate_filter_dropdown(friends_sync_data)

	if friends_sync_data.is_empty():
		_show_status("No friends yet. Add friends to see their catches!", false)
		_show_loading(false)
		_show_feed_empty_state(true, "No friends yet!\n\nAdd friends to see their catches in the feed.")
		_set_state(CommunityState.IDLE)


func _populate_filter_dropdown(friends_sync_data: Dictionary) -> void:
	"""Populate the filter dropdown with friend names"""
	filter_dropdown.clear()
	filter_dropdown.add_item("All Friends", 0)

	var index := 1
	for friend_id in friends_sync_data.keys():
		var friend_info: Dictionary = friends_sync_data[friend_id]
		var username: String = friend_info.get("username", "Unknown")
		filter_dropdown.add_item(username, index)
		filter_dropdown.set_item_metadata(index, friend_id)
		index += 1


func _load_feed_entries() -> void:
	"""Load feed entries from all friends' cached dex data"""
	feed_entries.clear()

	for friend_id in FriendDexSyncService.get_friend_ids():
		var friend_entries: Array = FriendDexSyncService.get_friend_entries(friend_id)
		var friend_info: Dictionary = FriendDexSyncService.get_friend_info(friend_id)

		for entry in friend_entries:
			var feed_entry := _create_feed_entry(entry, friend_id, friend_info)
			feed_entries.append(feed_entry)

	feed_entries.sort_custom(_sort_by_date_desc)
	print("[Community] Loaded %d feed entries" % feed_entries.size())


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
	"""Display the feed entries using FeedVisualization."""
	displayed_entries = _apply_filters(feed_entries)

	if displayed_entries.is_empty():
		_show_status("No entries to display", false)
		_show_feed_empty_state(true, "No entries to display.\n\nYour friends haven't caught any animals yet!")
		if _feed_visualization:
			_feed_visualization.clear()
		# Reset scroll limits (horizontal only)
		var content_width := _content_area.size.x
		var horizontal_max := content_width * HORIZONTAL_BOUND_RATIO
		_paper_camera.set_scroll_limits(
			Vector2(-horizontal_max, 0.0),
			Vector2(horizontal_max, 0.0)
		)
		_paper_camera.reset()
		return

	_show_feed_empty_state(false)

	# Set entries - FeedVisualization handles the rest
	# Note: This triggers layout_calculated which sets scroll limits
	if _feed_visualization:
		_feed_visualization.set_entries(displayed_entries)

	# Scroll to show first image at top with small margin
	var viewport_size: Vector2 = get_viewport_rect().size
	var current_zoom: float = _paper_camera.get_current_zoom()
	var visible_height: float = viewport_size.y / current_zoom
	var first_top: float = _feed_visualization.get_first_entry_top()
	var margin: float = visible_height * 0.03
	var scroll_y: float = first_top + visible_height / 2.0 - margin
	_paper_camera.scroll_to(Vector2(0.0, scroll_y), false)

	_show_status("%d entries" % displayed_entries.size(), true)
	print("[Community] Displaying %d entries" % displayed_entries.size())


func _apply_filters(entries: Array[Dictionary]) -> Array[Dictionary]:
	"""Apply current filters to the feed entries"""
	if current_filter == "all":
		return entries.duplicate()

	if not selected_friend_id.is_empty():
		var filtered: Array[Dictionary] = []
		for entry in entries:
			if entry.get("owner_id", "") == selected_friend_id:
				filtered.append(entry)
		return filtered

	return entries.duplicate()

# =============================================================================
# Friends Data Management
# =============================================================================

func _load_friend_code() -> void:
	"""Load the current user's friend code"""
	print("[Community] Loading friend code...")
	APIManager.auth.get_friend_code(_on_friend_code_loaded)


func _on_friend_code_loaded(response: Dictionary, code: int) -> void:
	"""Handle friend code response"""
	if code == 200:
		var friend_code: String = response.get("friend_code", "")
		if not friend_code.is_empty():
			friend_code_display.text = friend_code
			print("[Community] Friend code loaded: ", friend_code)
		else:
			friend_code_display.text = "Error"
	else:
		friend_code_display.text = "Error"


func _on_own_friend_code_pressed() -> void:
	"""Copy own friend code to clipboard"""
	var friend_code: String = friend_code_display.text
	if friend_code.is_empty() or friend_code == "Error" or friend_code == "Loading...":
		return

	var success := ClipboardUtils.copy_to_clipboard(friend_code)
	if success:
		print("[Community] Copied own friend code: ", friend_code)
		_show_copy_feedback()


func _show_copy_feedback() -> void:
	"""Show 'Copied!' feedback that fades out"""
	if not copy_feedback:
		return

	if _copy_feedback_tween and _copy_feedback_tween.is_valid():
		_copy_feedback_tween.kill()

	copy_feedback.modulate.a = 1.0
	_copy_feedback_tween = create_tween()
	_copy_feedback_tween.tween_interval(1.0)
	_copy_feedback_tween.tween_property(copy_feedback, "modulate:a", 0.0, 0.5)


func _on_add_button_pressed() -> void:
	"""Handle add friend button press"""
	var friend_code: String = friend_code_input.text.strip_edges().to_upper()
	_send_friend_request(friend_code)


func _on_friend_code_submitted(text: String) -> void:
	"""Handle enter key in friend code input"""
	var friend_code: String = text.strip_edges().to_upper()
	_send_friend_request(friend_code)


func _send_friend_request(friend_code: String) -> void:
	"""Send a friend request by friend code"""
	if friend_code.length() != 8:
		_show_status("Friend code must be 8 characters", false)
		return

	_show_status("Sending friend request...", true)
	add_button.disabled = true

	APIManager.social.send_friend_request(friend_code, "", _on_friend_request_sent)


func _on_friend_request_sent(response: Dictionary, code: int) -> void:
	"""Handle friend request response"""
	add_button.disabled = false

	if code == 200 or code == 201:
		_show_status("Friend request sent!", true)
		friend_code_input.text = ""
		await get_tree().create_timer(2.0).timeout
		_show_status("", true)
	else:
		var error_msg: String = response.get("error", "Failed to send friend request")
		_show_status("Error: %s" % error_msg, false)


func _load_friends() -> void:
	"""Load friends list from API"""
	if _state == CommunityState.LOADING:
		return

	_set_state(CommunityState.LOADING)
	_show_loading(true)
	print("[Community] Loading friends list...")
	APIManager.social.get_friends(_on_friends_loaded)


func _on_friends_loaded(response: Dictionary, code: int) -> void:
	"""Handle friends list response"""
	_show_loading(false)

	if code != 200:
		var error_msg: String = response.get("error", "Failed to load friends")
		print("[Community] ERROR loading friends: ", error_msg)
		_show_status("Failed to load friends", false)
		_set_state(CommunityState.IDLE)
		return

	friends_data = response.get("friends", [])
	print("[Community] Loaded %d friends" % friends_data.size())
	_populate_friends_list()
	_set_state(CommunityState.IDLE)
	_update_friends_scroll_limits()


func _populate_friends_list() -> void:
	"""Populate the friends list with friend items"""
	# Clear existing items
	for child in friends_list.get_children():
		child.queue_free()

	if friends_data.size() == 0:
		var empty_label := Label.new()
		empty_label.text = "No research partners yet.\nAdd friends using their 8-character code!"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty_label.add_theme_font_size_override("font_size", 48)
		friends_list.add_child(empty_label)
		return

	for friend in friends_data:
		var item = friend_item_scene.instantiate()
		friends_list.add_child(item)
		item.set_friend_data(friend)

		item.view_dex_requested.connect(_on_view_friend_dex.bind(friend))
		item.view_tree_requested.connect(_on_view_friend_tree.bind(friend))
		item.remove_requested.connect(_on_remove_friend.bind(friend))


func _load_pending_requests() -> void:
	"""Load pending friend requests from API"""
	print("[Community] Loading pending requests...")
	APIManager.social.get_pending_requests(_on_pending_loaded)


func _on_pending_loaded(response: Dictionary, code: int) -> void:
	"""Handle pending requests response"""
	if code != 200:
		var error_msg: String = response.get("error", "Failed to load pending requests")
		print("[Community] ERROR loading pending requests: ", error_msg)
		return

	pending_requests = response.get("requests", [])
	print("[Community] Loaded %d pending requests" % pending_requests.size())
	_populate_pending_list()
	_update_friends_scroll_limits()


func _populate_pending_list() -> void:
	"""Populate the pending requests list"""
	for child in pending_list.get_children():
		child.queue_free()

	pending_section.visible = pending_requests.size() > 0

	if pending_requests.size() == 0:
		return

	var header_label := pending_header.get_node("Label") as Label
	if header_label:
		header_label.text = "Pending Requests (%d)" % pending_requests.size()

	for request in pending_requests:
		var item = pending_item_scene.instantiate()
		pending_list.add_child(item)
		item.set_request_data(request)

		item.accept_requested.connect(_on_accept_request.bind(request))
		item.reject_requested.connect(_on_reject_request.bind(request))
		item.block_requested.connect(_on_block_request.bind(request))

# =============================================================================
# Friend Actions
# =============================================================================

func _on_view_friend_dex(friend: Dictionary) -> void:
	"""Navigate to friend's dex"""
	var friend_id: String = friend.get("id", "")
	var username: String = friend.get("username", "Friend")

	if friend_id.is_empty():
		print("[Community] ERROR: Friend ID is empty")
		return

	print("[Community] Navigating to dex for friend: ", username)
	NavigationManager.set_context({"user_id": friend_id, "username": username})
	NavigationManager.navigate_to("res://scenes/dex/dex.tscn")


func _on_view_friend_tree(friend: Dictionary) -> void:
	"""Navigate to taxonomic tree showing this specific friend's entries"""
	var friend_id: String = friend.get("id", "")
	var username: String = friend.get("username", "Friend")

	if friend_id.is_empty():
		print("[Community] ERROR: Friend ID is empty")
		return

	print("[Community] Navigating to tree view for friend: ", username)
	NavigationManager.set_context({
		"mode": "selected",
		"friend_id": friend_id,
		"username": username
	})
	NavigationManager.navigate_to("res://scenes/tree/tree.tscn")


func _on_remove_friend(friend: Dictionary) -> void:
	"""Show confirmation dialog before removing friend"""
	pending_removal_friend = friend
	var username: String = friend.get("username", "this friend")
	var friendship_id: String = friend.get("id", "")

	if friendship_id.is_empty():
		print("[Community] ERROR: Could not find friendship ID for friend: ", username)
		_show_status("Error: Could not remove friend", false)
		return

	pending_removal_friendship_id = friendship_id
	confirmation_dialog.dialog_text = "Remove %s from your research partners?\n\nThis action cannot be undone." % username
	confirmation_dialog.popup_centered()


func _confirm_remove_friend() -> void:
	"""Actually remove the friend after confirmation"""
	var username: String = pending_removal_friend.get("username", "friend")
	print("[Community] Removing friend: ", username)

	_show_status("Removing...", true)
	APIManager.social.unfriend(pending_removal_friendship_id, _on_friend_removed)


func _on_friend_removed(response: Dictionary, code: int) -> void:
	"""Handle friend removal response"""
	if code == 200 or code == 204:
		var username: String = pending_removal_friend.get("username", "Friend")
		_show_status("%s removed" % username, true)

		await get_tree().create_timer(1.0).timeout
		_load_friends()
		_show_status("", true)
	else:
		var error_msg: String = response.get("error", "Failed to remove friend")
		_show_status("Error: %s" % error_msg, false)

	pending_removal_friend = {}
	pending_removal_friendship_id = ""

# =============================================================================
# Request Actions
# =============================================================================

func _on_accept_request(request: Dictionary) -> void:
	"""Accept a friend request"""
	var request_id: String = request.get("id", "")
	var from_user: Dictionary = request.get("from_user_details", {})
	var username: String = from_user.get("username", "user")

	if request_id.is_empty():
		print("[Community] ERROR: Request ID is empty")
		return

	print("[Community] Accepting friend request from: ", username)
	_show_status("Accepting...", true)

	APIManager.social.respond_to_request(request_id, "accept", _on_request_responded)


func _on_reject_request(request: Dictionary) -> void:
	"""Reject a friend request"""
	var request_id: String = request.get("id", "")
	var from_user: Dictionary = request.get("from_user_details", {})
	var username: String = from_user.get("username", "user")

	if request_id.is_empty():
		print("[Community] ERROR: Request ID is empty")
		return

	print("[Community] Rejecting friend request from: ", username)
	_show_status("Rejecting...", true)

	APIManager.social.respond_to_request(request_id, "reject", _on_request_responded)


func _on_block_request(request: Dictionary) -> void:
	"""Block a user from a friend request"""
	var request_id: String = request.get("id", "")
	var from_user: Dictionary = request.get("from_user_details", {})
	var username: String = from_user.get("username", "user")

	if request_id.is_empty():
		print("[Community] ERROR: Request ID is empty")
		return

	print("[Community] Blocking user: ", username)
	_show_status("Blocking...", true)

	APIManager.social.respond_to_request(request_id, "block", _on_request_responded)


func _on_request_responded(response: Dictionary, code: int) -> void:
	"""Handle response to friend request"""
	if code == 200:
		_show_status("Done", true)

		await get_tree().create_timer(1.0).timeout
		_load_friends()
		_load_pending_requests()
		_show_status("", true)
	else:
		var error_msg: String = response.get("error", "Failed to process request")
		_show_status("Error: %s" % error_msg, false)

# =============================================================================
# Navigation
# =============================================================================

func _on_view_in_dex(entry: Dictionary) -> void:
	"""Navigate to the friend's dex to view the full entry"""
	var friend_id: String = entry.get("owner_id", "")
	var username: String = entry.get("owner_username", "Friend")
	var creation_index: int = entry.get("creation_index", -1)

	if friend_id.is_empty() or creation_index < 0:
		print("[Community] ERROR: Invalid entry data for navigation")
		return

	print("[Community] Navigating to dex for %s, entry #%d" % [username, creation_index])

	NavigationManager.set_context({
		"user_id": friend_id,
		"username": username,
		"creation_index": creation_index,
		"from_feed": true
	})

	NavigationManager.navigate_to("res://dex.tscn")


func _on_back_pressed() -> void:
	"""Navigate back to previous scene"""
	print("[Community] Back button pressed")
	NavigationManager.go_back()

# =============================================================================
# Filter Handlers
# =============================================================================

func _on_refresh_pressed() -> void:
	"""Refresh data for current tab"""
	print("[Community] Refresh button pressed")
	_show_status("Refreshing...", true)

	if _active_tab == TAB_FEED:
		FriendDexSyncService.sync_friends()
	else:
		_load_friends()
		_load_pending_requests()


func _on_filter_all_pressed() -> void:
	"""Show all friends' entries"""
	print("[Community] Filter: All friends")
	current_filter = "all"
	selected_friend_id = ""
	filter_dropdown.selected = 0
	_display_feed()


func _on_filter_dropdown_selected(index: int) -> void:
	"""Handle filter dropdown selection"""
	if index == 0:
		_on_filter_all_pressed()
		return

	var friend_id = filter_dropdown.get_item_metadata(index)
	if friend_id is String and not friend_id.is_empty():
		var username: String = FriendDexSyncService.get_friend_username(friend_id)
		print("[Community] Filter: %s" % username)
		current_filter = "friend"
		selected_friend_id = friend_id
		_display_feed()

# =============================================================================
# State Management
# =============================================================================

func _set_state(new_state: CommunityState) -> void:
	"""Update state machine."""
	if _state == new_state:
		return
	print("[Community] State: %s -> %s" % [CommunityState.keys()[_state], CommunityState.keys()[new_state]])
	_state = new_state

# =============================================================================
# UI Helpers
# =============================================================================

func _show_loading(should_show: bool) -> void:
	"""Show or hide loading overlay"""
	if loading_overlay:
		loading_overlay.visible = should_show


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
			status_label.modulate = Color(0.2, 0.5, 0.2, 1.0)
		else:
			status_label.modulate = Color(0.6, 0.2, 0.2, 1.0)


func _show_feed_empty_state(should_show: bool, message: String = "") -> void:
	"""Show or hide empty state message for feed"""
	if _feed_empty_label:
		_feed_empty_label.visible = should_show
		if should_show and not message.is_empty():
			_feed_empty_label.text = message

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

	print("[Community] Scene cleanup complete")
