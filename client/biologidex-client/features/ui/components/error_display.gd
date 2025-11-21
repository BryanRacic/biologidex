class_name ErrorDisplay extends PanelContainer

## Reusable error display component
## Shows error messages with optional retry button

signal retry_requested()
signal dismissed()

# Configuration
@export var auto_hide_delay: float = 5.0  # Seconds (0 = no auto-hide)
@export var show_retry_button: bool = true
@export var show_dismiss_button: bool = true

# UI elements
@onready var _error_label: Label = $MarginContainer/VBoxContainer/ErrorLabel
@onready var _retry_button: Button = $MarginContainer/VBoxContainer/ButtonContainer/RetryButton
@onready var _dismiss_button: Button = $MarginContainer/VBoxContainer/ButtonContainer/DismissButton

# Private variables
var _auto_hide_timer: Timer

func _ready() -> void:
	# Set initial visibility
	visible = false

	# Configure buttons
	if _retry_button != null:
		_retry_button.pressed.connect(_on_retry_pressed)
		_retry_button.visible = show_retry_button

	if _dismiss_button != null:
		_dismiss_button.pressed.connect(_on_dismiss_pressed)
		_dismiss_button.visible = show_dismiss_button

	# Set up auto-hide timer
	if auto_hide_delay > 0:
		_auto_hide_timer = Timer.new()
		_auto_hide_timer.one_shot = true
		_auto_hide_timer.timeout.connect(_on_auto_hide_timeout)
		add_child(_auto_hide_timer)

## Show error with message
func show_error(message: String, enable_retry: bool = true) -> void:
	if _error_label != null:
		_error_label.text = message

	if _retry_button != null:
		_retry_button.visible = show_retry_button and enable_retry

	visible = true

	# Start auto-hide timer if configured
	if _auto_hide_timer != null and auto_hide_delay > 0:
		_auto_hide_timer.start(auto_hide_delay)

## Hide error display
func hide_error() -> void:
	visible = false

	# Stop auto-hide timer
	if _auto_hide_timer != null:
		_auto_hide_timer.stop()

## Set error message without showing
func set_error_message(message: String) -> void:
	if _error_label != null:
		_error_label.text = message

## Get current error message
func get_error_message() -> String:
	if _error_label != null:
		return _error_label.text
	return ""

## Handle retry button press
func _on_retry_pressed() -> void:
	hide_error()
	retry_requested.emit()

## Handle dismiss button press
func _on_dismiss_pressed() -> void:
	hide_error()
	dismissed.emit()

## Handle auto-hide timeout
func _on_auto_hide_timeout() -> void:
	hide_error()
	dismissed.emit()
