extends Control
## FriendListItem - Lab book style friend entry for the table of contents
## Displays username, stats, copyable friend code, and action buttons

const ClipboardHelper = preload("res://features/ui/components/clipboard/clipboard_helper.gd")

signal view_dex_requested
signal view_tree_requested
signal remove_requested
signal code_copied(code: String)

# UI References
@onready var username_label: Label = get_node("%UsernameLabel")
@onready var stats_label: Label = get_node("%StatsLabel")
@onready var friend_code_button: Button = get_node("%FriendCodeButton")
@onready var view_dex_button: Button = get_node("%ViewDexButton")
@onready var view_tree_button: Button = get_node("%ViewTreeButton")
@onready var remove_button: Button = get_node("%RemoveButton")
@onready var copy_feedback: Label = get_node("%CopyFeedback")

var friend_data: Dictionary = {}
var _copy_feedback_tween: Tween = null


func _ready() -> void:
	# Connect button signals
	friend_code_button.pressed.connect(_on_friend_code_pressed)
	view_dex_button.pressed.connect(_on_view_dex_pressed)
	view_tree_button.pressed.connect(_on_view_tree_pressed)
	remove_button.pressed.connect(_on_remove_pressed)

	# Hide copy feedback initially
	if copy_feedback:
		copy_feedback.modulate.a = 0.0


func set_friend_data(data: Dictionary) -> void:
	"""Populate the friend item with data"""
	friend_data = data

	# Set username
	var username: String = data.get("username", "Unknown")
	username_label.text = username

	# Set stats
	var total_catches: int = data.get("total_catches", 0)
	var unique_species: int = data.get("unique_species", 0)
	stats_label.text = "%d catches  |  %d species" % [total_catches, unique_species]

	# Set friend code on button
	var friend_code: String = data.get("friend_code", "")
	if not friend_code.is_empty():
		friend_code_button.text = friend_code
		friend_code_button.visible = true
	else:
		friend_code_button.visible = false


func _on_friend_code_pressed() -> void:
	"""Copy friend code to clipboard"""
	var friend_code: String = friend_data.get("friend_code", "")
	if friend_code.is_empty():
		return

	var success := ClipboardHelper.copy_to_clipboard(friend_code)
	if success:
		print("[FriendListItem] Copied friend code: ", friend_code)
		_show_copy_feedback()
		code_copied.emit(friend_code)
	else:
		print("[FriendListItem] Failed to copy friend code")


func _show_copy_feedback() -> void:
	"""Show 'Copied!' feedback that fades out"""
	if not copy_feedback:
		return

	# Kill any existing tween
	if _copy_feedback_tween and _copy_feedback_tween.is_valid():
		_copy_feedback_tween.kill()

	# Show and fade out
	copy_feedback.modulate.a = 1.0
	_copy_feedback_tween = create_tween()
	_copy_feedback_tween.tween_interval(1.0)
	_copy_feedback_tween.tween_property(copy_feedback, "modulate:a", 0.0, 0.5)


func _on_view_dex_pressed() -> void:
	print("[FriendListItem] View dex requested for: ", friend_data.get("username", ""))
	view_dex_requested.emit()


func _on_view_tree_pressed() -> void:
	print("[FriendListItem] View tree requested for: ", friend_data.get("username", ""))
	view_tree_requested.emit()


func _on_remove_pressed() -> void:
	print("[FriendListItem] Remove requested for: ", friend_data.get("username", ""))
	remove_requested.emit()
