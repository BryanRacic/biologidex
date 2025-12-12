extends BaseSceneNode
## Social Scene - Lab book style friends management with PaperCameraScene scrolling

const ClipboardUtils = preload("res://features/ui/components/clipboard/clipboard_helper.gd")

# State
enum SocialState { IDLE, LOADING, SCROLLING }
var _state: SocialState = SocialState.IDLE
var friends_data: Array = []
var pending_requests: Array = []

# PaperCameraScene component
@onready var _paper_camera: PaperCameraScene = get_node("%PaperCameraScene")

# Preloaded scenes
var friend_item_scene = preload("res://scenes/social/components/friend_list_item.tscn")
var pending_item_scene = preload("res://scenes/social/components/pending_request_item.tscn")

# UI References
@onready var refresh_button: Button = get_node("%RefreshButton")
@onready var friend_code_display: Button = get_node("%FriendCodeDisplay")
@onready var copy_feedback: Label = get_node("%CopyFeedback")
@onready var friend_code_input: LineEdit = get_node("%FriendCodeInput")
@onready var add_button: Button = get_node("%AddButton")
@onready var content_area: Control = get_node("%ContentArea")
@onready var scroll_content: VBoxContainer = get_node("%ScrollContent")
@onready var friends_section: VBoxContainer = get_node("%FriendsSection")
@onready var friends_list: VBoxContainer = get_node("%FriendsList")
@onready var pending_section: VBoxContainer = get_node("%PendingSection")
@onready var pending_header: HBoxContainer = get_node("%PendingHeader")
@onready var pending_list: VBoxContainer = get_node("%PendingList")
@onready var loading_overlay: Control = get_node("%LoadingOverlay")

# Confirmation dialog
var confirmation_dialog: ConfirmationDialog = null
var pending_removal_friend: Dictionary = {}
var pending_removal_friendship_id: String = ""

# Copy feedback tween
var _copy_feedback_tween: Tween = null


func _on_scene_ready() -> void:
	"""Called by BaseSceneNode after managers are initialized and auth is checked"""
	scene_name = "Social"
	print("[Social] Scene ready (lab book style)")

	# Wire up status label (back_button is already connected by BaseSceneNode via @export)
	status_label = get_node("%StatusLabel")

	_setup_ui()
	await _setup_scroll_controller()
	_setup_confirmation_dialog()

	# Load initial data
	_load_friend_code()
	_load_friends()
	_load_pending_requests()


func _setup_ui() -> void:
	"""Setup UI elements and connect signals"""
	refresh_button.pressed.connect(_on_refresh_pressed)
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
	# Wait for layout to settle
	await get_tree().process_frame

	var content_height := content_area.size.y
	assert(content_height > 0, "Social: ContentArea size must be > 0")

	# Connect signals
	_paper_camera.view_changed.connect(_on_view_changed)
	_paper_camera.gesture_started.connect(_on_gesture_started)
	_paper_camera.gesture_ended.connect(_on_gesture_ended)

	print("[Social] PaperCameraScene setup complete")


func _setup_confirmation_dialog() -> void:
	"""Create and setup the confirmation dialog for removing friends"""
	confirmation_dialog = ConfirmationDialog.new()
	confirmation_dialog.dialog_text = "Are you sure you want to remove this friend?"
	confirmation_dialog.confirmed.connect(_confirm_remove_friend)
	add_child(confirmation_dialog)


# =============================================================================
# Scroll Handling
# =============================================================================

func _on_view_changed(cam_position: Vector2, _zoom: float) -> void:
	"""Handle view change from PaperCameraScene"""
	if scroll_content:
		scroll_content.position.y = -cam_position.y


func _on_gesture_started() -> void:
	"""Handle gesture start"""
	if _state == SocialState.IDLE:
		_state = SocialState.SCROLLING


func _on_gesture_ended() -> void:
	"""Handle gesture end"""
	if _state == SocialState.SCROLLING:
		_state = SocialState.IDLE


func _update_scroll_limits() -> void:
	"""Update max scroll based on content height"""
	if not _paper_camera or not scroll_content or not content_area:
		return

	await get_tree().process_frame

	var content_height := scroll_content.size.y
	var visible_height := content_area.size.y
	var max_scroll := maxf(0.0, content_height - visible_height)

	_paper_camera.set_scroll_limits(
		Vector2(0.0, 0.0),
		Vector2(0.0, max_scroll)
	)
	print("[Social] Scroll limits updated: content=%d, visible=%d, max=%d" % [
		int(content_height), int(visible_height), int(max_scroll)
	])


# =============================================================================
# Friend Code
# =============================================================================

func _load_friend_code() -> void:
	"""Load the current user's friend code"""
	print("[Social] Loading friend code...")
	APIManager.auth.get_friend_code(_on_friend_code_loaded)


func _on_friend_code_loaded(response: Dictionary, code: int) -> void:
	"""Handle friend code response"""
	if code == 200:
		var friend_code: String = response.get("friend_code", "")
		if not friend_code.is_empty():
			friend_code_display.text = friend_code
			print("[Social] Friend code loaded: ", friend_code)
		else:
			friend_code_display.text = "Error"
			print("[Social] ERROR: Friend code empty in response")
	else:
		friend_code_display.text = "Error"
		var error_msg: String = response.get("error", "Failed to load friend code")
		print("[Social] ERROR loading friend code: ", error_msg)


func _on_own_friend_code_pressed() -> void:
	"""Copy own friend code to clipboard"""
	var friend_code: String = friend_code_display.text
	if friend_code.is_empty() or friend_code == "Error" or friend_code == "Loading...":
		return

	var success := ClipboardUtils.copy_to_clipboard(friend_code)
	if success:
		print("[Social] Copied own friend code: ", friend_code)
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


# =============================================================================
# Add Friend
# =============================================================================

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


# =============================================================================
# Friends List
# =============================================================================

func _load_friends() -> void:
	"""Load friends list from API"""
	if _state == SocialState.LOADING:
		return

	_state = SocialState.LOADING
	_show_loading(true)
	print("[Social] Loading friends list...")
	APIManager.social.get_friends(_on_friends_loaded)


func _on_friends_loaded(response: Dictionary, code: int) -> void:
	"""Handle friends list response"""
	_show_loading(false)

	if code != 200:
		var error_msg: String = response.get("error", "Failed to load friends")
		print("[Social] ERROR loading friends: ", error_msg)
		_show_status("Failed to load friends", false)
		_state = SocialState.IDLE
		return

	friends_data = response.get("friends", [])
	print("[Social] Loaded %d friends" % friends_data.size())
	_populate_friends_list()
	_state = SocialState.IDLE
	_update_scroll_limits()


func _populate_friends_list() -> void:
	"""Populate the friends list with friend items"""
	# Clear existing items
	for child in friends_list.get_children():
		child.queue_free()

	# Show/hide section based on content
	if friends_data.size() == 0:
		var empty_label := Label.new()
		empty_label.text = "No research partners yet.\nAdd friends using their 8-character code!"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty_label.add_theme_font_size_override("font_size", 48)
		friends_list.add_child(empty_label)
		return

	# Add friend items
	for friend in friends_data:
		var item = friend_item_scene.instantiate()
		friends_list.add_child(item)
		item.set_friend_data(friend)

		# Connect signals with context binding
		item.view_dex_requested.connect(_on_view_friend_dex.bind(friend))
		item.view_tree_requested.connect(_on_view_friend_tree.bind(friend))
		item.remove_requested.connect(_on_remove_friend.bind(friend))


# =============================================================================
# Pending Requests
# =============================================================================

func _load_pending_requests() -> void:
	"""Load pending friend requests from API"""
	print("[Social] Loading pending requests...")
	APIManager.social.get_pending_requests(_on_pending_loaded)


func _on_pending_loaded(response: Dictionary, code: int) -> void:
	"""Handle pending requests response"""
	if code != 200:
		var error_msg: String = response.get("error", "Failed to load pending requests")
		print("[Social] ERROR loading pending requests: ", error_msg)
		return

	pending_requests = response.get("requests", [])
	print("[Social] Loaded %d pending requests" % pending_requests.size())
	_populate_pending_list()
	_update_scroll_limits()


func _populate_pending_list() -> void:
	"""Populate the pending requests list"""
	# Clear existing items
	for child in pending_list.get_children():
		child.queue_free()

	# Show/hide section based on content
	pending_section.visible = pending_requests.size() > 0

	if pending_requests.size() == 0:
		return

	# Update header to show count
	var header_label := pending_header.get_node("Label") as Label
	if header_label:
		header_label.text = "Pending Requests (%d)" % pending_requests.size()

	# Add pending request items
	for request in pending_requests:
		var item = pending_item_scene.instantiate()
		pending_list.add_child(item)
		item.set_request_data(request)

		# Connect signals with context binding
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
		print("[Social] ERROR: Friend ID is empty")
		return

	print("[Social] Navigating to dex for friend: ", username)

	NavigationManager.set_context({
		"user_id": friend_id,
		"username": username
	})

	NavigationManager.navigate_to("res://scenes/dex/dex.tscn")


func _on_view_friend_tree(friend: Dictionary) -> void:
	"""Navigate to taxonomic tree showing this specific friend's entries"""
	var friend_id: String = friend.get("id", "")
	var username: String = friend.get("username", "Friend")

	if friend_id.is_empty():
		print("[Social] ERROR: Friend ID is empty")
		return

	print("[Social] Navigating to tree view for friend: ", username)

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
	var friendship_id: String = _get_friendship_id_for_friend(friend)

	if friendship_id.is_empty():
		print("[Social] ERROR: Could not find friendship ID for friend: ", username)
		_show_status("Error: Could not remove friend", false)
		return

	pending_removal_friendship_id = friendship_id

	confirmation_dialog.dialog_text = "Remove %s from your research partners?\n\nThis action cannot be undone." % username
	confirmation_dialog.popup_centered()


func _get_friendship_id_for_friend(friend: Dictionary) -> String:
	"""Extract friendship ID from friend data"""
	return friend.get("id", "")


func _confirm_remove_friend() -> void:
	"""Actually remove the friend after confirmation"""
	var username: String = pending_removal_friend.get("username", "friend")
	print("[Social] Removing friend: ", username)

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
		print("[Social] ERROR: Request ID is empty")
		return

	print("[Social] Accepting friend request from: ", username)
	_show_status("Accepting...", true)

	APIManager.social.respond_to_request(request_id, "accept", _on_request_responded)


func _on_reject_request(request: Dictionary) -> void:
	"""Reject a friend request"""
	var request_id: String = request.get("id", "")
	var from_user: Dictionary = request.get("from_user_details", {})
	var username: String = from_user.get("username", "user")

	if request_id.is_empty():
		print("[Social] ERROR: Request ID is empty")
		return

	print("[Social] Rejecting friend request from: ", username)
	_show_status("Rejecting...", true)

	APIManager.social.respond_to_request(request_id, "reject", _on_request_responded)


func _on_block_request(request: Dictionary) -> void:
	"""Block a user from a friend request"""
	var request_id: String = request.get("id", "")
	var from_user: Dictionary = request.get("from_user_details", {})
	var username: String = from_user.get("username", "user")

	if request_id.is_empty():
		print("[Social] ERROR: Request ID is empty")
		return

	print("[Social] Blocking user: ", username)
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

func _on_back_pressed() -> void:
	"""Navigate back to previous scene"""
	print("[Social] Back button pressed")
	NavigationManager.go_back()


func _on_refresh_pressed() -> void:
	"""Refresh friends and pending requests"""
	print("[Social] Refresh button pressed")
	_show_status("Refreshing...", true)
	_load_friends()
	_load_pending_requests()


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


# =============================================================================
# Cleanup
# =============================================================================

func _on_scene_exit() -> void:
	"""Clean up when scene exits"""
	print("[Social] Scene cleanup")
