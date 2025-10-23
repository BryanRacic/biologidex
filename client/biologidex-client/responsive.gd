extends Control

# Base responsive behavior script for BiologiDex client
# Handles viewport size changes and dynamic scaling

var base_size := Vector2(1280, 720)
var gui_aspect_ratio := 16.0 / 9.0
var gui_margin := 20.0

@onready var main_panel: Panel = $Panel if has_node("Panel") else null
@onready var aspect_container: AspectRatioContainer = $Panel/AspectRatioContainer if has_node("Panel/AspectRatioContainer") else null


func _ready() -> void:
	# Set up full rect anchor for this control
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Connect to viewport size changes
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	# Initial layout update
	_update_responsive_layout()


func _on_viewport_size_changed() -> void:
	_update_responsive_layout()


func _update_responsive_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var scale_factor: float = min(viewport_size.x / base_size.x, viewport_size.y / base_size.y)

	# Update aspect ratio container if it exists
	if aspect_container:
		aspect_container.ratio = min(viewport_size.aspect(), gui_aspect_ratio)

	# Apply GUI margins for safe area
	_apply_margins(gui_margin)

	# Adjust for different device classes
	_adjust_for_device_class(viewport_size, scale_factor)


func _apply_margins(margin: float) -> void:
	# Apply margins to the main panel if it exists
	if main_panel:
		main_panel.offset_left = margin
		main_panel.offset_top = margin
		main_panel.offset_right = -margin
		main_panel.offset_bottom = -margin


func _adjust_for_device_class(viewport_size: Vector2, scale_factor: float) -> void:
	# Determine device class and adjust UI accordingly
	var is_mobile := viewport_size.x < 800
	var is_tablet := viewport_size.x >= 800 and viewport_size.x < 1280
	var is_desktop := viewport_size.x >= 1280

	# You can adjust theme properties here based on device class
	# For example, increasing font sizes for mobile
	if is_mobile:
		# Mobile adjustments
		gui_margin = 16.0
	elif is_tablet:
		# Tablet adjustments
		gui_margin = 32.0
	else:
		# Desktop adjustments
		gui_margin = 48.0


func get_device_class() -> String:
	"""Returns the current device class: 'mobile', 'tablet', or 'desktop'"""
	var viewport_size := get_viewport_rect().size

	if viewport_size.x < 800:
		return "mobile"
	elif viewport_size.x < 1280:
		return "tablet"
	else:
		return "desktop"


func is_portrait() -> bool:
	"""Returns true if the viewport is in portrait orientation"""
	var viewport_size := get_viewport_rect().size
	return viewport_size.y > viewport_size.x


func is_landscape() -> bool:
	"""Returns true if the viewport is in landscape orientation"""
	return not is_portrait()
