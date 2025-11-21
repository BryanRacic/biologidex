extends BaseSceneController
## Social Scene - Manage friends and friend requests
## Refactored: 443 → ~415 lines (6% reduction)

# Note: Services (TokenManager, NavigationManager, APIManager)
# are automatically initialized by BaseSceneController

# UI References (back_button, status_label, is_loading inherited from BaseSceneController)
@onready var refresh_button: Button = $Panel/MarginContainer/VBoxContainer/Header/RefreshButton
@onready var friend_code_display: LineEdit = $Panel/MarginContainer/VBoxContainer/YourFriendCodeSection/FriendCodeDisplay
@onready var friend_code_input: LineEdit = $Panel/MarginContainer/VBoxContainer/AddFriendSection/InputContainer/FriendCodeInput
@onready var add_button: Button = $Panel/MarginContainer/VBoxContainer/AddFriendSection/InputContainer/AddButton
@onready var tab_container: TabContainer = $Panel/MarginContainer/VBoxContainer/TabContainer
@onready var friends_list: VBoxContainer = $Panel/MarginContainer/VBoxContainer/TabContainer/Friends/FriendsList
@onready var pending_list: VBoxContainer = $Panel/MarginContainer/VBoxContainer/TabContainer/Pending/PendingList

# Preloaded scenes
var friend_item_scene = preload("res://scenes/social/components/friend_list_item.tscn")
var pending_item_scene = preload("res://scenes/social/components/pending_request_item.tscn")

# State (is_loading inherited from BaseSceneController)
var friends_data: Array = []
var pending_requests: Array = []

# Confirmation dialog
var confirmation_dialog: ConfirmationDialog = null
var pending_removal_friend: Dictionary = {}
var pending_removal_friendship_id: String = ""


func _on_scene_ready() -> void:
	"""Called by BaseSceneController after managers are initialized and auth is checked"""
	scene_name = "Social"
	print("[Social] Scene ready (refactored v2)")

	# Wire up UI elements from scene (BaseSceneController members)
	back_button = $Panel/MarginContainer/VBoxContainer/Header/BackButton
	status_label = $Panel/MarginContainer/VBoxContainer/AddFriendSection/StatusLabel

	# Connect UI signals
	back_button.pressed.connect(_on_back_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	add_button.pressed.connect(_on_add_button_pressed)
	friend_code_input.text_submitted.connect(_on_friend_code_submitted)

	# Create confirmation dialog
	_setup_confirmation_dialog()

	# Load friend code
	_load_friend_code()

	# Load initial data
	_load_friends()
	_load_pending_requests()


func _setup_confirmation_dialog() -> void:
	"""Create and setup the confirmation dialog for removing friends"""
	confirmation_dialog = ConfirmationDialog.new()
	confirmation_dialog.dialog_text = "Are you sure you want to remove this friend?"
	confirmation_dialog.confirmed.connect(_confirm_remove_friend)
	add_child(confirmation_dialog)


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
			friend_code_display.text = "Error loading code"
			print("[Social] ERROR: Friend code empty in response")
	else:
		friend_code_display.text = "Error loading code"
		var error_msg: String = response.get("error", "Failed to load friend code")
		print("[Social] ERROR loading friend code: ", error_msg)


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
		_show_status("Friend request sent successfully!", true)
		friend_code_input.text = ""
		# Refresh lists after short delay
		await get_tree().create_timer(1.0).timeout
		_show_status("", true)
	else:
		var error_msg: String = response.get("error", "Failed to send friend request")
		_show_status("Error: %s" % error_msg, false)


func _load_friends() -> void:
	"""Load friends list from API"""
	if is_loading:
		return

	is_loading = true
	print("[Social] Loading friends list...")
	APIManager.social.get_friends(_on_friends_loaded)


func _on_friends_loaded(response: Dictionary, code: int) -> void:
	"""Handle friends list response"""
	is_loading = false

	if code != 200:
		var error_msg: String = response.get("error", "Failed to load friends")
		print("[Social] ERROR loading friends: ", error_msg)
		_show_status("Failed to load friends", false)
		return

	friends_data = response.get("friends", [])
	print("[Social] Loaded %d friends" % friends_data.size())
	_populate_friends_list()

	# Clear status if showing refresh message
	if status_label.text == "Refreshing...":
		_show_status("", true)


func _populate_friends_list() -> void:
	"""Populate the friends list with friend items"""
	# Clear existing items
	for child in friends_list.get_children():
		child.queue_free()

	# Show empty state if no friends
	if friends_data.size() == 0:
		var empty_label := Label.new()
		empty_label.text = "No friends yet. Add your first friend using their friend code!"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD
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

	# Update tab badge (if TabContainer supports it)
	# For now, just update the tab name
	if pending_requests.size() > 0:
		tab_container.set_tab_title(1, "Pending (%d)" % pending_requests.size())
	else:
		tab_container.set_tab_title(1, "Pending")


func _populate_pending_list() -> void:
	"""Populate the pending requests list"""
	# Clear existing items
	for child in pending_list.get_children():
		child.queue_free()

	# Show empty state if no pending requests
	if pending_requests.size() == 0:
		var empty_label := Label.new()
		empty_label.text = "No pending friend requests"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pending_list.add_child(empty_label)
		return

	# Add pending request items
	for request in pending_requests:
		var item = pending_item_scene.instantiate()
		pending_list.add_child(item)
		item.set_request_data(request)

		# Connect signals with context binding
		item.accept_requested.connect(_on_accept_request.bind(request))
		item.reject_requested.connect(_on_reject_request.bind(request))
		item.block_requested.connect(_on_block_request.bind(request))


func _on_view_friend_dex(friend: Dictionary) -> void:
	"""Navigate to friend's dex"""
	var friend_id: String = friend.get("id", "")
	var username: String = friend.get("username", "Friend")

	if friend_id.is_empty():
		print("[Social] ERROR: Friend ID is empty")
		return

	print("[Social] Navigating to dex for friend: ", username)

	# Set navigation context
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

	# Set navigation context to use SELECTED mode with just this friend
	# Note: This shows the current user + this specific friend's entries
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

	# Find friendship ID - need to look through friends_data for the friendship relationship
	# The API response should include friendship details
	var friendship_id: String = _get_friendship_id_for_friend(friend)

	if friendship_id.is_empty():
		print("[Social] ERROR: Could not find friendship ID for friend: ", username)
		_show_status("Error: Could not remove friend", false)
		return

	pending_removal_friendship_id = friendship_id

	confirmation_dialog.dialog_text = "Remove %s from your friends?\n\nThis action cannot be undone." % username
	confirmation_dialog.popup_centered()


func _get_friendship_id_for_friend(friend: Dictionary) -> String:
	"""Extract friendship ID from friend data"""
	# The friend data structure from the API should include the friendship_id
	# or we need to derive it from the relationship
	var friend_id: String = friend.get("id", "")

	# For now, we'll need to store the friendship_id when we load friends
	# The API returns friends with their details but we need the friendship record ID
	# This is a limitation - we may need to modify the API response or track it separately

	# Workaround: The friendship ID might be in the response, or we need to query it
	# For now, return the friend's user ID and we'll handle it in the API call
	return friend_id


func _confirm_remove_friend() -> void:
	"""Actually remove the friend after confirmation"""
	var username: String = pending_removal_friend.get("username", "friend")
	print("[Social] Removing friend: ", username)

	_show_status("Removing friend...", true)

	# Note: The unfriend API expects a friendship ID, not user ID
	# We need to store friendship IDs with friends, or make an additional lookup
	# For now, we'll pass the user_id and handle the lookup server-side if needed
	APIManager.social.unfriend(pending_removal_friendship_id, _on_friend_removed)


func _on_friend_removed(response: Dictionary, code: int) -> void:
	"""Handle friend removal response"""
	if code == 200 or code == 204:
		var username: String = pending_removal_friend.get("username", "Friend")
		_show_status("%s has been removed from your friends" % username, true)

		# Refresh the friends list
		await get_tree().create_timer(1.0).timeout
		_load_friends()
		_show_status("", true)
	else:
		var error_msg: String = response.get("error", "Failed to remove friend")
		_show_status("Error: %s" % error_msg, false)

	pending_removal_friend = {}
	pending_removal_friendship_id = ""


func _on_accept_request(request: Dictionary) -> void:
	"""Accept a friend request"""
	var request_id: String = request.get("id", "")
	var from_user: Dictionary = request.get("from_user_details", {})
	var username: String = from_user.get("username", "user")

	if request_id.is_empty():
		print("[Social] ERROR: Request ID is empty")
		return

	print("[Social] Accepting friend request from: ", username)
	_show_status("Accepting friend request...", true)

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
	_show_status("Rejecting friend request...", true)

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
	_show_status("Blocking user...", true)

	APIManager.social.respond_to_request(request_id, "block", _on_request_responded)


func _on_request_responded(response: Dictionary, code: int) -> void:
	"""Handle response to friend request"""
	if code == 200:
		_show_status("Request processed successfully", true)

		# Refresh both lists
		await get_tree().create_timer(1.0).timeout
		_load_friends()
		_load_pending_requests()
		_show_status("", true)
	else:
		var error_msg: String = response.get("error", "Failed to process request")
		_show_status("Error: %s" % error_msg, false)


func _show_status(message: String, is_success: bool) -> void:
	"""Show status message with appropriate color"""
	status_label.text = message

	if message.is_empty():
		status_label.modulate = Color.WHITE
	elif is_success:
		status_label.modulate = Color.GREEN
	else:
		status_label.modulate = Color.RED
