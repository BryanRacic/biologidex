class_name LoadingSpinner extends Control

## Reusable loading spinner component
## Shows animated spinner with optional message

signal animation_started()
signal animation_stopped()

# Configuration
@export var spin_speed: float = 2.0  # Rotations per second
@export var spinner_size: int = 64
@export var show_message: bool = true
@export var default_message: String = "Loading..."

# UI elements
@onready var _spinner: TextureRect = $VBoxContainer/SpinnerContainer/Spinner
@onready var _message_label: Label = $VBoxContainer/MessageLabel

# Private variables
var _is_spinning: bool = false
var _rotation_angle: float = 0.0

func _ready() -> void:
	# Set initial visibility
	visible = false

	# Configure spinner
	if _spinner != null:
		_spinner.pivot_offset = Vector2(spinner_size / 2.0, spinner_size / 2.0)
		_spinner.custom_minimum_size = Vector2(spinner_size, spinner_size)

	# Configure message
	if _message_label != null:
		_message_label.text = default_message
		_message_label.visible = show_message

func _process(delta: float) -> void:
	if _is_spinning and _spinner != null:
		_rotation_angle += delta * spin_speed * TAU
		_spinner.rotation = _rotation_angle

## Show spinner with optional message
func show_loading(message: String = "") -> void:
	if message != "":
		set_message(message)
	elif default_message != "":
		set_message(default_message)

	_is_spinning = true
	visible = true
	animation_started.emit()

## Hide spinner
func hide_loading() -> void:
	_is_spinning = false
	visible = false
	_rotation_angle = 0.0
	if _spinner != null:
		_spinner.rotation = 0.0
	animation_stopped.emit()

## Set loading message
func set_message(message: String) -> void:
	if _message_label != null:
		_message_label.text = message
		_message_label.visible = show_message and message != ""

## Check if currently spinning
func is_loading() -> bool:
	return _is_spinning
