extends Panel
## PendingRequestItem - Displays a single pending friend request

signal accept_requested
signal reject_requested
signal block_requested

@onready var username_label: Label = $MarginContainer/HBoxContainer/InfoContainer/UsernameLabel
@onready var time_label: Label = $MarginContainer/HBoxContainer/InfoContainer/TimeLabel
@onready var accept_button: Button = $MarginContainer/HBoxContainer/ActionsContainer/AcceptButton
@onready var reject_button: Button = $MarginContainer/HBoxContainer/ActionsContainer/RejectButton
@onready var block_button: Button = $MarginContainer/HBoxContainer/ActionsContainer/BlockButton

var request_data: Dictionary = {}


func _ready() -> void:
	# Connect button signals
	accept_button.pressed.connect(_on_accept_pressed)
	reject_button.pressed.connect(_on_reject_pressed)
	block_button.pressed.connect(_on_block_pressed)


func set_request_data(data: Dictionary) -> void:
	"""Populate the request item with data"""
	request_data = data

	# Set username from from_user_details
	var from_user: Dictionary = data.get("from_user_details", {})
	var username: String = from_user.get("username", "Unknown")
	username_label.text = username

	# Set time label
	var created_at: String = data.get("created_at", "")
	if created_at.length() > 0:
		var time_str: String = _format_time_ago(created_at)
		time_label.text = "Requested %s" % time_str
	else:
		time_label.text = "Requested recently"


func _format_time_ago(timestamp: String) -> String:
	"""Format timestamp as relative time (e.g., '2 days ago')"""
	# Simple implementation - just show the date for now
	# Format: 2025-01-01T12:00:00Z
	if timestamp.length() >= 10:
		var date_part: String = timestamp.substr(0, 10)
		return "on %s" % date_part
	return "recently"


func _on_accept_pressed() -> void:
	print("[PendingRequestItem] Accept requested for: ", request_data.get("from_user_details", {}).get("username", ""))
	accept_requested.emit()


func _on_reject_pressed() -> void:
	print("[PendingRequestItem] Reject requested for: ", request_data.get("from_user_details", {}).get("username", ""))
	reject_requested.emit()


func _on_block_pressed() -> void:
	print("[PendingRequestItem] Block requested for: ", request_data.get("from_user_details", {}).get("username", ""))
	block_requested.emit()