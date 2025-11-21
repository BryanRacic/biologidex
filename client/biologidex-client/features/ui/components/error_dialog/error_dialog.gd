class_name ErrorDialog extends Control

# Reusable error dialog component for displaying errors with user-friendly messages
# Designed to work consistently on web export and desktop
# Pure Control-based (no AcceptDialog/ConfirmationDialog for web compatibility)

signal dismissed
signal action_pressed(action_name: String)

enum ErrorType {
	NETWORK_ERROR,   # Generic networking issues
	API_ERROR,       # Specific API failures with HTTP codes
	VALIDATION_ERROR,  # Client-side validation failures
	TIMEOUT_ERROR,   # Request timeout
	GENERIC         # Generic error
}

# UI Elements (will be created programmatically or in .tscn)
@onready var overlay: Panel = $Overlay
@onready var dialog_panel: Panel = $Overlay/DialogPanel
@onready var title_label: Label = $Overlay/DialogPanel/MarginContainer/VBoxContainer/TitleLabel
@onready var message_label: Label = $Overlay/DialogPanel/MarginContainer/VBoxContainer/MessageLabel
@onready var details_label: Label = $Overlay/DialogPanel/MarginContainer/VBoxContainer/DetailsLabel
@onready var code_label: Label = $Overlay/DialogPanel/MarginContainer/VBoxContainer/CodeLabel
@onready var actions_container: HBoxContainer = $Overlay/DialogPanel/MarginContainer/VBoxContainer/ActionsContainer
@onready var close_button: Button = $Overlay/DialogPanel/MarginContainer/VBoxContainer/TitleContainer/CloseButton

# State
var current_error_type: ErrorType = ErrorType.GENERIC
var auto_dismiss_timer: Timer = null


func _ready() -> void:
	# Hide initially
	visible = false

	# Setup close button if exists
	if close_button and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)

	# Setup overlay click to dismiss
	if overlay:
		overlay.gui_input.connect(_on_overlay_input)


# ============================================================================
# Public API
# ============================================================================

func show_error(
	type: ErrorType,
	message: String,
	details: String = "",
	http_code: int = 0,
	actions: Array[String] = ["Dismiss"]
) -> void:
	"""
	Show error dialog with customizable content.

	Args:
		type: ErrorType enum value
		message: Main error message to display
		details: Optional detailed error information
		http_code: HTTP status code (for API errors)
		actions: Array of action button labels
	"""
	current_error_type = type

	# Set title based on type
	var title = _get_title_for_type(type)
	if title_label:
		title_label.text = title

	# Set message
	if message_label:
		message_label.text = message

	# Set details (optional)
	if details_label:
		details_label.visible = not details.is_empty()
		details_label.text = details

	# Set code (for API errors)
	if code_label:
		code_label.visible = http_code > 0
		if http_code > 0:
			code_label.text = "Error Code: %d" % http_code

	# Setup action buttons
	_setup_action_buttons(actions)

	# Show dialog
	visible = true
	_grab_focus()


func show_api_error(code: int, message: String, details: String = "") -> void:
	"""Convenience method for API errors with HTTP code"""
	show_error(ErrorType.API_ERROR, message, details, code, ["Dismiss"])


func show_network_error(details: String = "") -> void:
	"""Convenience method for network errors"""
	var default_message = "Connection failed. Please check your internet connection and try again."
	show_error(ErrorType.NETWORK_ERROR, default_message, details, 0, ["Dismiss"])


func show_validation_error(message: String, field: String = "") -> void:
	"""Convenience method for validation errors"""
	var details = ("Field: %s" % field) if not field.is_empty() else ""
	show_error(ErrorType.VALIDATION_ERROR, message, details, 0, ["OK"])


func show_timeout_error(operation: String = "") -> void:
	"""Convenience method for timeout errors"""
	var message = "The operation timed out."
	var details = ("Operation: %s" % operation) if not operation.is_empty() else ""
	show_error(ErrorType.TIMEOUT_ERROR, message, details, 0, ["Retry", "Cancel"])


func hide_dialog() -> void:
	"""Hide the error dialog"""
	visible = false
	dismissed.emit()


func set_auto_dismiss(seconds: float) -> void:
	"""Set auto-dismiss timer"""
	if auto_dismiss_timer:
		auto_dismiss_timer.queue_free()

	auto_dismiss_timer = Timer.new()
	auto_dismiss_timer.wait_time = seconds
	auto_dismiss_timer.one_shot = true
	auto_dismiss_timer.timeout.connect(_on_auto_dismiss_timeout)
	add_child(auto_dismiss_timer)
	auto_dismiss_timer.start()


# ============================================================================
# Internal Methods
# ============================================================================

func _get_title_for_type(type: ErrorType) -> String:
	"""Get appropriate title for error type"""
	match type:
		ErrorType.NETWORK_ERROR:
			return "Connection Error"
		ErrorType.API_ERROR:
			return "Server Error"
		ErrorType.VALIDATION_ERROR:
			return "Invalid Input"
		ErrorType.TIMEOUT_ERROR:
			return "Request Timeout"
		_:
			return "Error"


func _setup_action_buttons(actions: Array[String]) -> void:
	"""Create action buttons from array of labels"""
	if not actions_container:
		return

	# Clear existing buttons
	for child in actions_container.get_children():
		child.queue_free()

	# Create new buttons
	for action_name in actions:
		var button = Button.new()
		button.text = action_name
		button.pressed.connect(_on_action_pressed.bind(action_name))
		actions_container.add_child(button)


func _grab_focus() -> void:
	"""Grab focus for keyboard input (ESC to close)"""
	if dialog_panel:
		dialog_panel.grab_focus()


# ============================================================================
# Event Handlers
# ============================================================================

func _on_close_pressed() -> void:
	"""Handle close button press"""
	hide_dialog()


func _on_action_pressed(action_name: String) -> void:
	"""Handle action button press"""
	action_pressed.emit(action_name)

	# Auto-dismiss on most actions except "Retry"
	if action_name != "Retry":
		hide_dialog()


func _on_overlay_input(event: InputEvent) -> void:
	"""Handle overlay click to dismiss"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Check if click is outside dialog panel
		if dialog_panel:
			var local_pos = dialog_panel.get_local_mouse_position()
			var rect = dialog_panel.get_rect()
			if not rect.has_point(local_pos):
				hide_dialog()


func _on_auto_dismiss_timeout() -> void:
	"""Handle auto-dismiss timer timeout"""
	hide_dialog()


func _input(event: InputEvent) -> void:
	"""Handle keyboard input (ESC to close)"""
	if visible and event.is_action_pressed("ui_cancel"):
		hide_dialog()
		get_viewport().set_input_as_handled()