class_name BaseSceneController extends Control

# Base class for all scene controllers
# Provides common manager initialization, UI helpers, and error handling patterns

# Core manager references (auto-initialized)
var TokenManager
var NavigationManager
var APIManager
var DexDatabase
var SyncManager

# Common UI elements (optional, wire up in scene if available)
@export var back_button: Button
@export var status_label: Label
@export var loading_spinner: Control

# Error dialog reference (auto-wired if present in scene)
var error_dialog  # Will be typed as ErrorDialog when that component exists

# Common state
var is_loading: bool = false
var scene_name: String = "Unknown"

# Signals for cross-scene communication
signal scene_ready
signal scene_exiting


func _ready() -> void:
	_initialize_managers()
	_setup_common_ui()
	_check_authentication()
	_on_scene_ready()
	scene_ready.emit()


func _initialize_managers() -> void:
	"""Initialize service references from autoloads"""
	TokenManager = get_node("/root/TokenManager")
	NavigationManager = get_node("/root/NavigationManager")
	APIManager = get_node("/root/APIManager")
	DexDatabase = get_node("/root/DexDatabase")
	SyncManager = get_node("/root/SyncManager")

	print("[%s] Managers initialized" % scene_name)


func _setup_common_ui() -> void:
	"""Setup common UI elements and connections"""
	# Auto-wire error dialog if present in scene tree
	if has_node("ErrorDialog"):
		error_dialog = get_node("ErrorDialog")
		print("[%s] Error dialog wired" % scene_name)

	# Connect back button if present
	if back_button and not back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.connect(_on_back_pressed)

	# Hide loading spinner initially
	if loading_spinner:
		loading_spinner.visible = false


func _check_authentication() -> void:
	"""Verify user is logged in, redirect if not"""
	if not TokenManager or not TokenManager.is_logged_in():
		print("[%s] ERROR: User not logged in, redirecting" % scene_name)
		NavigationManager.go_back()


func _on_scene_ready() -> void:
	"""Override in subclasses for scene-specific initialization"""
	pass


# ============================================================================
# UI Helpers
# ============================================================================

func show_loading(message: String = "Loading...") -> void:
	"""Display loading state"""
	is_loading = true

	if loading_spinner:
		loading_spinner.visible = true

	if status_label:
		status_label.text = message

	print("[%s] Loading: %s" % [scene_name, message])


func hide_loading() -> void:
	"""Hide loading state"""
	is_loading = false

	if loading_spinner:
		loading_spinner.visible = false

	if status_label:
		status_label.text = ""


func show_status(message: String) -> void:
	"""Display status message"""
	if status_label:
		status_label.text = message
	print("[%s] Status: %s" % [scene_name, message])


func show_error(message: String, details: String = "", code: int = 0) -> void:
	"""
	Display error message using ErrorDialog component if available.
	Falls back to status label if ErrorDialog not present.
	"""
	hide_loading()

	print("[%s] Error [%d]: %s - %s" % [scene_name, code, message, details])

	if error_dialog and error_dialog.has_method("show_api_error"):
		# Use ErrorDialog component (API error)
		if code >= 400:
			error_dialog.show_api_error(code, message, details)
		else:
			# Network/generic error
			error_dialog.show_network_error(details if details else message)
	elif status_label:
		# Fallback to status label
		status_label.text = "Error: %s" % message


func show_success(message: String) -> void:
	"""Display success message"""
	hide_loading()

	if status_label:
		status_label.text = message

	print("[%s] Success: %s" % [scene_name, message])


# ============================================================================
# Common Event Handlers
# ============================================================================

func _on_back_pressed() -> void:
	"""Handle back button press"""
	print("[%s] Back button pressed" % scene_name)
	scene_exiting.emit()
	NavigationManager.go_back()


# ============================================================================
# Lifecycle
# ============================================================================

func _notification(what: int) -> void:
	"""Handle lifecycle notifications"""
	match what:
		NOTIFICATION_VISIBILITY_CHANGED:
			if visible:
				_on_scene_shown()
			else:
				_on_scene_hidden()
		NOTIFICATION_EXIT_TREE:
			_on_scene_exit()


func _on_scene_shown() -> void:
	"""Override in subclasses - called when scene becomes visible"""
	pass


func _on_scene_hidden() -> void:
	"""Override in subclasses - called when scene becomes hidden"""
	pass


func _on_scene_exit() -> void:
	"""Override in subclasses - called when scene exits tree"""
	scene_exiting.emit()


# ============================================================================
# Validation Helpers
# ============================================================================

func is_callback_valid(callback: Callable) -> bool:
	"""Check if a callback is valid before invoking"""
	return callback.is_valid()


func validate_api_response(response: Dictionary, code: int) -> bool:
	"""Common API response validation"""
	if code == 200 or code == 201:
		return true

	# Handle error
	var error_msg = response.get("message", "Unknown error")
	var error_detail = response.get("detail", "")
	show_error(error_msg, error_detail, code)
	return false