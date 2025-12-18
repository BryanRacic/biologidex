extends RadialMenuBase
class_name RadialMenuRing

## RadialMenuRing - Radial menu with center circle + arc-segment ring buttons.
##
## This variant uses RadialButtonRing for the outer buttons, rendering them
## as arc segments (pie slices) around the center button.
##
## Usage:
##   var menu := RadialMenuRing.new()
##   parent.add_child(menu)
##   menu.set_center_button("upload", "Upload\nImage")
##   menu.add_ring_button("feed", "Dex Feed")
##   menu.center_pressed.connect(_on_upload)
##   menu.button_pressed.connect(_on_nav)
##
## Inherits: RadialMenuBase
## See also: RadialMenuCircles (all circular buttons variant)

# =============================================================================
# Export Variables - Ring Geometry (specific to arc segments)
# =============================================================================

@export_group("Ring Geometry")
## Inner radius of the button ring (distance from center to inner edge)
@export var ring_inner_radius: float = 150.0:
	set(value):
		ring_inner_radius = value
		_request_layout_update()

## Outer radius of the button ring (distance from center to outer edge)
@export var ring_outer_radius: float = 300.0:
	set(value):
		ring_outer_radius = value
		_request_layout_update()

## Gap angle between ring segments (radians)
@export var ring_gap_angle: float = 0.08:
	set(value):
		ring_gap_angle = value
		_request_layout_update()

# =============================================================================
# Internal State
# =============================================================================

## Button ring component
var _button_ring: RadialButtonRing = null

# =============================================================================
# Implementation - Component Creation
# =============================================================================

func _create_components() -> void:
	"""Create center button and ring components."""
	# Create center button using shared method
	_setup_center_button()

	# Create button ring (arc segments)
	_button_ring = RadialButtonRing.new()
	_button_ring.name = "ButtonRing"
	add_child(_button_ring)

	# Connect ring signals
	_button_ring.segment_pressed.connect(_on_ring_segment_pressed)
	_button_ring.segment_hovered.connect(_on_ring_segment_hovered)
	_button_ring.segment_unhovered.connect(_on_ring_segment_unhovered)

	# Mark ready and apply configuration
	_components_ready = true
	_update_layout()
	_apply_center_config()
	_apply_ring_configs()

# =============================================================================
# Implementation - Layout
# =============================================================================

func _calculate_menu_size() -> float:
	"""Calculate the total menu diameter for ring variant."""
	return ring_outer_radius * 2


func _update_layout() -> void:
	"""Update component positions and sizes."""
	if not _components_ready:
		return

	_update_size()

	# Apply center button style
	_apply_center_button_style()

	# Position button ring to fill control
	_button_ring.inner_radius = ring_inner_radius
	_button_ring.outer_radius = ring_outer_radius
	_button_ring.gap_angle = ring_gap_angle
	_button_ring.start_angle = start_angle
	_button_ring.custom_minimum_size = size
	_button_ring.size = size
	_button_ring.position = Vector2.ZERO

	# Apply ring button colors
	_button_ring.normal_color = ring_normal_color
	_button_ring.hover_color = ring_hover_color
	_button_ring.pressed_color = ring_pressed_color
	_button_ring.border_width = ring_border_width
	_button_ring.border_color = ring_border_color
	_button_ring.text_color = text_color
	_button_ring.font_size = ring_font_size
	_button_ring.font = font

	# Trigger redraws
	_button_ring.queue_redraw()

# =============================================================================
# Implementation - Configuration
# =============================================================================

func _apply_center_config() -> void:
	"""Apply center configuration to center button."""
	_apply_center_config_to_button()


func _apply_ring_configs() -> void:
	"""Apply ring configurations to button ring."""
	if not _button_ring:
		return

	# Convert to typed array for setup_buttons
	var typed_configs: Array[Dictionary] = []
	for config in _ring_configs:
		typed_configs.append(config)

	_button_ring.setup_buttons(typed_configs)


func _on_ring_button_state_changed(id: String, property: String, value: Variant) -> void:
	"""Handle individual button state changes efficiently."""
	if not _button_ring:
		return

	match property:
		"disabled":
			_button_ring.set_button_disabled(id, value as bool)
		"visible":
			_button_ring.set_button_visible(id, value as bool)
		_:
			_apply_ring_configs()

# =============================================================================
# Signal Handlers
# =============================================================================

func _on_ring_segment_pressed(_index: int, button_id: String) -> void:
	"""Handle ring segment press."""
	button_pressed.emit(button_id)


func _on_ring_segment_hovered(_index: int, button_id: String) -> void:
	"""Handle ring segment hover."""
	button_hovered.emit(button_id)


func _on_ring_segment_unhovered() -> void:
	"""Handle ring segment unhover."""
	button_unhovered.emit()
