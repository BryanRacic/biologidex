extends RadialMenuBase
class_name RadialMenuCircles

## RadialMenuCircles - Radial menu with all circular buttons.
##
## This variant uses RadialButtonCircle instances for the outer buttons,
## rendering them as individual circles arranged around the center button.
##
## Usage:
##   var menu := RadialMenuCircles.new()
##   parent.add_child(menu)
##   menu.set_center_button("upload", "Upload\nImage")
##   menu.add_ring_button("feed", "Dex Feed")
##   menu.center_pressed.connect(_on_upload)
##   menu.button_pressed.connect(_on_nav)
##
## Inherits: RadialMenuBase
## See also: RadialMenuRing (arc-segment variant)

# =============================================================================
# Export Variables - Circle Geometry
# =============================================================================

@export_group("Ring Circle Geometry")
## Radius of each ring button circle
@export var ring_button_radius: float = 60.0:
	set(value):
		ring_button_radius = value
		_request_layout_update()

## Spacing between ring buttons (angle in radians, 0 = automatic)
@export var ring_button_spacing: float = 0.0:
	set(value):
		ring_button_spacing = value
		_request_layout_update()

## If enabled, adds an invisible placeholder at the top position (index 0),
## offsetting visible buttons to form a triangle below the center button.
@export var placeholder_button: bool = false:
	set(value):
		placeholder_button = value
		_request_layout_update()

# =============================================================================
# Internal State
# =============================================================================

## Array of ring button components
var _ring_buttons: Array[RadialButtonCircle] = []

# =============================================================================
# Implementation - Component Creation
# =============================================================================

func _create_components() -> void:
	"""Create center button. Ring buttons created dynamically."""
	# Create center button using shared method
	_setup_center_button()

	# Mark ready and apply configuration
	_components_ready = true
	_update_layout()
	_apply_center_config()
	_apply_ring_configs()

# =============================================================================
# Implementation - Layout
# =============================================================================

func _calculate_menu_size() -> float:
	"""Calculate the total menu diameter for circles variant."""
	# Need to fit: center + ring distance + ring button radius + margin
	return (ring_distance + ring_button_radius + 10.0) * 2


func _update_layout() -> void:
	"""Update component positions and sizes."""
	if not _components_ready:
		return

	_update_size()

	# Apply center button style
	_apply_center_button_style()

	# Update ring button positions
	_position_ring_buttons()

# =============================================================================
# Implementation - Ring Button Management
# =============================================================================

func _apply_center_config() -> void:
	"""Apply center configuration to center button."""
	_apply_center_config_to_button()


func _apply_ring_configs() -> void:
	"""Apply ring configurations - create/update ring buttons."""
	_sync_ring_buttons()
	_position_ring_buttons()


func _sync_ring_buttons() -> void:
	"""Synchronize ring button instances with configurations."""
	var config_count := _ring_configs.size()
	var button_count := _ring_buttons.size()

	# Remove excess buttons
	while _ring_buttons.size() > config_count:
		var btn: RadialButtonCircle = _ring_buttons.pop_back()
		btn.pressed.disconnect(_on_ring_button_pressed)
		btn.hover_changed.disconnect(_on_ring_button_hover_changed)
		btn.queue_free()

	# Add missing buttons
	while _ring_buttons.size() < config_count:
		var btn := RadialButtonCircle.new()
		btn.name = "RingButton_%d" % _ring_buttons.size()
		add_child(btn)

		var idx := _ring_buttons.size()
		btn.set_ring_index(idx)
		btn.pressed.connect(_on_ring_button_pressed.bind(idx))
		btn.hover_changed.connect(_on_ring_button_hover_changed.bind(idx))

		_ring_buttons.append(btn)

	# Update button configurations
	for i in range(config_count):
		var btn := _ring_buttons[i]
		var config := _ring_configs[i]

		btn.configure(config)
		_apply_ring_button_style(btn)


func _apply_ring_button_style(btn: RadialButtonCircle) -> void:
	"""Apply common style properties to a ring button."""
	btn.radius = ring_button_radius
	btn.normal_color = ring_normal_color
	btn.hover_color = ring_hover_color
	btn.pressed_color = ring_pressed_color
	btn.border_width = ring_border_width
	btn.border_color = ring_border_color
	btn.text_color = text_color
	btn.font_size = ring_font_size
	btn.font = font
	btn.icon_color = ring_icon_color
	btn.icon_size = ring_icon_size


func _position_ring_buttons() -> void:
	"""Position ring buttons around the center."""
	var count := _ring_buttons.size()
	if count == 0:
		return

	var menu_center := size / 2

	# Account for placeholder in angle calculation
	var position_count := count + (1 if placeholder_button else 0)

	# Calculate angle per button
	var angle_per_button: float
	if ring_button_spacing > 0:
		angle_per_button = ring_button_spacing
	else:
		# Automatic: distribute evenly around the circle
		angle_per_button = TAU / position_count

	# Position each button (offset by 1 if placeholder exists)
	var index_offset := 1 if placeholder_button else 0
	for i in range(count):
		var btn := _ring_buttons[i]
		var button_angle := start_angle + (i + index_offset) * angle_per_button

		btn.set_ring_position(button_angle, ring_distance, menu_center)
		btn.queue_redraw()


func _on_ring_button_state_changed(id: String, property: String, value: Variant) -> void:
	"""Handle individual button state changes efficiently."""
	for btn in _ring_buttons:
		if btn.button_id == id:
			match property:
				"disabled":
					btn.set_disabled(value as bool)
				"visible":
					btn.visible = value as bool
			break

# =============================================================================
# Signal Handlers
# =============================================================================

func _on_ring_button_pressed(index: int) -> void:
	"""Handle ring button press."""
	if index >= 0 and index < _ring_buttons.size():
		var btn := _ring_buttons[index]
		button_pressed.emit(btn.button_id)


func _on_ring_button_hover_changed(is_hovered: bool, index: int) -> void:
	"""Handle ring button hover state change."""
	if is_hovered:
		if index >= 0 and index < _ring_buttons.size():
			var btn := _ring_buttons[index]
			button_hovered.emit(btn.button_id)
	else:
		button_unhovered.emit()

# =============================================================================
# Public API - Additional Methods
# =============================================================================

func get_ring_button(index: int) -> RadialButtonCircle:
	"""Get a ring button by index for direct manipulation."""
	if index >= 0 and index < _ring_buttons.size():
		return _ring_buttons[index]
	return null


func get_ring_button_by_id(id: String) -> RadialButtonCircle:
	"""Get a ring button by ID for direct manipulation."""
	for btn in _ring_buttons:
		if btn.button_id == id:
			return btn
	return null
