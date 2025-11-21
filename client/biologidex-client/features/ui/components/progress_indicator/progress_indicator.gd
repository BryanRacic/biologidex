class_name ProgressIndicator extends Control

# Reusable progress indicator component
# Supports spinner, progress bar, and percentage display modes

signal cancelled
signal completed

enum IndicatorStyle {
	SPINNER,     # Spinning animation
	BAR,         # Progress bar (0-100%)
	PERCENTAGE,  # Text percentage
	COMBINED     # Bar + percentage
}

# Configuration
@export var style: IndicatorStyle = IndicatorStyle.SPINNER
@export var show_message: bool = true
@export var show_cancel_button: bool = false
@export var auto_hide_on_complete: bool = true
@export var auto_hide_delay: float = 1.0

# UI Elements (will be wired from scene or created programmatically)
@onready var spinner_container: Control = $SpinnerContainer
@onready var spinner: Control = $SpinnerContainer/Spinner
@onready var bar_container: Control = $BarContainer
@onready var progress_bar: ProgressBar = $BarContainer/ProgressBar
@onready var percentage_label: Label = $PercentageLabel
@onready var message_label: Label = $MessageLabel
@onready var cancel_button: Button = $CancelButton

# State
var current_progress: float = 0.0  # 0.0 to 1.0
var current_message: String = ""
var is_active: bool = false
var is_indeterminate: bool = true
var completion_timer: Timer = null


func _ready() -> void:
	_setup_ui()
	hide_progress()


# ============================================================================
# Public API - Control
# ============================================================================

func show_progress(message: String = "", indeterminate: bool = true) -> void:
	"""
	Show progress indicator.

	Args:
		message: Optional message to display
		indeterminate: If true, shows spinner. If false, shows progress bar.
	"""
	is_active = true
	is_indeterminate = indeterminate
	current_message = message
	current_progress = 0.0

	_update_display()
	visible = true

	print("[ProgressIndicator] Showing: %s (indeterminate: %s)" % [message, indeterminate])


func hide_progress() -> void:
	"""Hide progress indicator"""
	is_active = false
	visible = false
	current_progress = 0.0
	current_message = ""

	if completion_timer and not completion_timer.is_stopped():
		completion_timer.stop()


func update_progress(progress: float, message: String = "") -> void:
	"""
	Update progress value (0.0 to 1.0).

	Args:
		progress: Progress value between 0.0 and 1.0
		message: Optional message to update
	"""
	current_progress = clamp(progress, 0.0, 1.0)
	is_indeterminate = false

	if not message.is_empty():
		current_message = message

	_update_display()

	# Auto-complete at 100%
	if current_progress >= 1.0:
		_on_progress_complete()


func set_message(message: String) -> void:
	"""Update message text"""
	current_message = message
	if message_label:
		message_label.text = message


func set_indeterminate(indeterminate: bool) -> void:
	"""Switch between indeterminate (spinner) and determinate (bar) mode"""
	is_indeterminate = indeterminate
	_update_display()


# ============================================================================
# Public API - Configuration
# ============================================================================

func set_style(new_style: IndicatorStyle) -> void:
	"""Change indicator style"""
	style = new_style
	_update_display()


func set_show_cancel_button(show: bool) -> void:
	"""Show/hide cancel button"""
	show_cancel_button = show
	if cancel_button:
		cancel_button.visible = show


# ============================================================================
# Internal Methods
# ============================================================================

func _setup_ui() -> void:
	"""Setup initial UI state"""
	# Wire cancel button
	if cancel_button:
		cancel_button.visible = show_cancel_button
		if not cancel_button.pressed.is_connected(_on_cancel_pressed):
			cancel_button.pressed.connect(_on_cancel_pressed)

	# Setup completion timer
	completion_timer = Timer.new()
	completion_timer.wait_time = auto_hide_delay
	completion_timer.one_shot = true
	completion_timer.timeout.connect(_on_completion_timer_timeout)
	add_child(completion_timer)

	_update_display()


func _update_display() -> void:
	"""Update UI based on current state"""
	if not is_inside_tree():
		return

	# Update message
	if message_label:
		message_label.visible = show_message and not current_message.is_empty()
		message_label.text = current_message

	# Update based on style and indeterminate state
	if is_indeterminate:
		_show_spinner()
	else:
		match style:
			IndicatorStyle.SPINNER:
				_show_spinner()
			IndicatorStyle.BAR:
				_show_bar()
			IndicatorStyle.PERCENTAGE:
				_show_percentage()
			IndicatorStyle.COMBINED:
				_show_bar()
				_show_percentage()


func _show_spinner() -> void:
	"""Show spinner mode"""
	if spinner_container:
		spinner_container.visible = true
	if bar_container:
		bar_container.visible = false
	if percentage_label:
		percentage_label.visible = false


func _show_bar() -> void:
	"""Show progress bar"""
	if spinner_container:
		spinner_container.visible = false
	if bar_container:
		bar_container.visible = true
	if progress_bar:
		progress_bar.value = current_progress * 100.0


func _show_percentage() -> void:
	"""Show percentage text"""
	if percentage_label:
		percentage_label.visible = true
		percentage_label.text = "%d%%" % int(current_progress * 100.0)


# ============================================================================
# Event Handlers
# ============================================================================

func _on_cancel_pressed() -> void:
	"""Handle cancel button press"""
	print("[ProgressIndicator] Cancelled by user")
	cancelled.emit()
	hide_progress()


func _on_progress_complete() -> void:
	"""Handle progress completion"""
	print("[ProgressIndicator] Complete")
	completed.emit()

	if auto_hide_on_complete:
		completion_timer.start()
	else:
		# Update message to show completion
		set_message("Complete!")


func _on_completion_timer_timeout() -> void:
	"""Handle completion timer timeout"""
	hide_progress()


# ============================================================================
# Process (for spinner animation)
# ============================================================================

var rotation_speed: float = 2.0  # Radians per second

func _process(delta: float) -> void:
	"""Animate spinner if active"""
	if not is_active or not is_indeterminate:
		return

	if spinner and spinner.visible:
		spinner.rotation += rotation_speed * delta