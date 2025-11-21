extends Panel
## FriendListItem - Displays a single friend in the friends list

signal view_dex_requested
signal view_tree_requested
signal remove_requested

@onready var username_label: Label = $MarginContainer/HBoxContainer/InfoContainer/UsernameLabel
@onready var stats_label: Label = $MarginContainer/HBoxContainer/InfoContainer/StatsLabel
@onready var friend_code_label: Label = $MarginContainer/HBoxContainer/InfoContainer/FriendCodeLabel
@onready var view_dex_button: Button = $MarginContainer/HBoxContainer/ActionsContainer/ViewDexButton
@onready var view_tree_button: Button = $MarginContainer/HBoxContainer/ActionsContainer/ViewTreeButton
@onready var remove_button: Button = $MarginContainer/HBoxContainer/ActionsContainer/RemoveButton

var friend_data: Dictionary = {}


func _ready() -> void:
	# Connect button signals
	view_dex_button.pressed.connect(_on_view_dex_pressed)
	view_tree_button.pressed.connect(_on_view_tree_pressed)
	remove_button.pressed.connect(_on_remove_pressed)


func set_friend_data(data: Dictionary) -> void:
	"""Populate the friend item with data"""
	friend_data = data

	# Set username
	var username: String = data.get("username", "Unknown")
	username_label.text = username

	# Set stats
	var total_catches: int = data.get("total_catches", 0)
	var unique_species: int = data.get("unique_species", 0)
	stats_label.text = "%d catches, %d unique species" % [total_catches, unique_species]

	# Set friend code
	var friend_code: String = data.get("friend_code", "")
	if friend_code.length() > 0:
		friend_code_label.text = "Code: %s" % friend_code
	else:
		friend_code_label.text = ""


func _on_view_dex_pressed() -> void:
	print("[FriendListItem] View dex requested for: ", friend_data.get("username", ""))
	view_dex_requested.emit()


func _on_view_tree_pressed() -> void:
	print("[FriendListItem] View tree requested for: ", friend_data.get("username", ""))
	view_tree_requested.emit()


func _on_remove_pressed() -> void:
	print("[FriendListItem] Remove requested for: ", friend_data.get("username", ""))
	remove_requested.emit()
