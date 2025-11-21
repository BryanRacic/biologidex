class_name UserSelector extends Control

# Reusable user selector component for multi-user dex viewing
# Displays available users (self + friends) with sync status

signal user_selected(user_id: String, user_data: Dictionary)
signal refresh_requested

# Configuration
@export var show_sync_status: bool = true
@export var show_self_option: bool = true
@export var enable_refresh: bool = true

# UI Elements (will be wired from scene or created programmatically)
@onready var user_list_container: VBoxContainer = $ScrollContainer/UserListContainer
@onready var refresh_button: Button = $HeaderContainer/RefreshButton
@onready var loading_indicator: Control = $HeaderContainer/LoadingIndicator
@onready var scroll_container: ScrollContainer = $ScrollContainer

# State
var current_user_id: String = ""
var available_users: Array[Dictionary] = []
var selected_user_id: String = ""
var sync_statuses: Dictionary = {}  # user_id -> sync_status_dict


func _ready() -> void:
	_setup_ui()


# ============================================================================
# Public API - Data
# ============================================================================

func set_current_user_id(user_id: String) -> void:
	"""Set the current logged-in user ID"""
	current_user_id = user_id


func set_available_users(users: Array[Dictionary]) -> void:
	"""
	Set available users list.

	Expected format:
	[
		{
			"id": "user_id",
			"username": "username",
			"friend_code": "ABCD1234",
			"is_self": true/false
		},
		...
	]
	"""
	available_users = users
	_rebuild_user_list()


func add_user(user_data: Dictionary) -> void:
	"""Add a single user to the list"""
	available_users.append(user_data)
	_rebuild_user_list()


func remove_user(user_id: String) -> void:
	"""Remove a user from the list"""
	available_users = available_users.filter(func(u): return u.get("id") != user_id)
	_rebuild_user_list()


func set_sync_status(user_id: String, status: Dictionary) -> void:
	"""
	Set sync status for a user.

	Status format:
	{
		"is_synced": true/false,
		"last_sync": "2024-01-01T00:00:00Z",
		"entry_count": 123,
		"is_syncing": false
	}
	"""
	sync_statuses[user_id] = status
	_update_user_sync_status(user_id)


func clear_sync_statuses() -> void:
	"""Clear all sync statuses"""
	sync_statuses.clear()
	_rebuild_user_list()


# ============================================================================
# Public API - Selection
# ============================================================================

func get_selected_user_id() -> String:
	"""Get currently selected user ID"""
	return selected_user_id


func select_user(user_id: String) -> void:
	"""Programmatically select a user"""
	selected_user_id = user_id
	_update_selection_visual()

	# Find user data
	for user in available_users:
		if user.get("id") == user_id:
			user_selected.emit(user_id, user)
			break


func select_self() -> void:
	"""Select the current user (self)"""
	if current_user_id:
		select_user(current_user_id)


# ============================================================================
# Public API - UI State
# ============================================================================

func show_loading() -> void:
	"""Show loading indicator"""
	if loading_indicator:
		loading_indicator.visible = true
	if refresh_button:
		refresh_button.disabled = true


func hide_loading() -> void:
	"""Hide loading indicator"""
	if loading_indicator:
		loading_indicator.visible = false
	if refresh_button:
		refresh_button.disabled = false


# ============================================================================
# Internal Methods
# ============================================================================

func _setup_ui() -> void:
	"""Setup initial UI state"""
	if refresh_button:
		refresh_button.visible = enable_refresh
		if not refresh_button.pressed.is_connected(_on_refresh_pressed):
			refresh_button.pressed.connect(_on_refresh_pressed)

	if loading_indicator:
		loading_indicator.visible = false


func _rebuild_user_list() -> void:
	"""Rebuild the entire user list UI"""
	if not user_list_container:
		return

	# Clear existing items
	for child in user_list_container.get_children():
		child.queue_free()

	# Add self option first if enabled
	if show_self_option and current_user_id:
		var self_user = _find_user_by_id(current_user_id)
		if self_user:
			_create_user_item(self_user, true)

	# Add other users (friends)
	for user in available_users:
		var user_id = user.get("id", "")
		if user_id != current_user_id:
			_create_user_item(user, false)


func _create_user_item(user_data: Dictionary, is_self: bool) -> void:
	"""Create a user list item"""
	var user_id = user_data.get("id", "")
	var username = user_data.get("username", "Unknown")
	var friend_code = user_data.get("friend_code", "")

	# Create container
	var item = Button.new()
	item.set_meta("user_id", user_id)
	item.set_meta("user_data", user_data)
	item.text = ""
	item.pressed.connect(_on_user_item_pressed.bind(user_id, user_data))

	# Create label with username
	var label_text = username
	if is_self:
		label_text += " (You)"
	if not friend_code.is_empty():
		label_text += " - %s" % friend_code

	item.text = label_text

	# Add sync status if enabled
	if show_sync_status and sync_statuses.has(user_id):
		var status = sync_statuses[user_id]
		var sync_text = _format_sync_status(status)
		item.text += "\n%s" % sync_text

	user_list_container.add_child(item)


func _find_user_by_id(user_id: String) -> Dictionary:
	"""Find user data by ID"""
	for user in available_users:
		if user.get("id") == user_id:
			return user
	return {}


func _update_user_sync_status(user_id: String) -> void:
	"""Update sync status display for a specific user"""
	if not user_list_container:
		return

	# Find the user item
	for child in user_list_container.get_children():
		if child.has_meta("user_id") and child.get_meta("user_id") == user_id:
			var user_data = child.get_meta("user_data")
			var username = user_data.get("username", "Unknown")
			var is_self = user_id == current_user_id

			# Update text with sync status
			var label_text = username
			if is_self:
				label_text += " (You)"

			if show_sync_status and sync_statuses.has(user_id):
				var status = sync_statuses[user_id]
				var sync_text = _format_sync_status(status)
				label_text += "\n%s" % sync_text

			child.text = label_text
			break


func _format_sync_status(status: Dictionary) -> String:
	"""Format sync status for display"""
	var is_synced = status.get("is_synced", false)
	var is_syncing = status.get("is_syncing", false)
	var entry_count = status.get("entry_count", 0)

	if is_syncing:
		return "Syncing..."
	elif is_synced:
		return "%d entries" % entry_count
	else:
		return "Not synced"


func _update_selection_visual() -> void:
	"""Update visual appearance of selected item"""
	if not user_list_container:
		return

	# Highlight selected item
	for child in user_list_container.get_children():
		if child is Button:
			var user_id = child.get_meta("user_id", "")
			child.button_pressed = (user_id == selected_user_id)


# ============================================================================
# Event Handlers
# ============================================================================

func _on_user_item_pressed(user_id: String, user_data: Dictionary) -> void:
	"""Handle user item press"""
	selected_user_id = user_id
	_update_selection_visual()
	user_selected.emit(user_id, user_data)
	print("[UserSelector] User selected: %s" % user_id)


func _on_refresh_pressed() -> void:
	"""Handle refresh button press"""
	refresh_requested.emit()
	print("[UserSelector] Refresh requested")