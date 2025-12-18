extends Control
class_name RadialMenuBase

## RadialMenuBase - Abstract base class for radial menu containers.
##
## Provides shared functionality for radial menus:
## - Configuration storage and public API
## - Common signals for button interactions
## - Reveal/hide animations
## - Export variables for appearance customization
##
## Subclasses must implement:
## - _create_components(): Create the specific button components
## - _update_layout(): Position and style components
## - _apply_center_config(): Apply center button configuration
## - _apply_ring_configs(): Apply ring buttons configuration
##
## Subclasses: RadialMenuRing, RadialMenuCircles

# =============================================================================
# Signals
# =============================================================================

## Emitted when a ring button is pressed
signal button_pressed(button_id: String)

## Emitted when the center button is pressed
signal center_pressed()

## Emitted when any button is hovered
signal button_hovered(button_id: String)

## Emitted when hover ends
signal button_unhovered()

# =============================================================================
# Export Variables - Layout
# =============================================================================

@export_group("Layout")
## Radius of the center button
@export var center_radius: float = 120.0:
	set(value):
		center_radius = value
		_request_layout_update()

## Distance from center to ring buttons
@export var ring_distance: float = 220.0:
	set(value):
		ring_distance = value
		_request_layout_update()

## Start angle for ring buttons (-PI/2 = 12 o'clock)
@export var start_angle: float = -PI / 2:
	set(value):
		start_angle = value
		_request_layout_update()

# =============================================================================
# Export Variables - Center Button Appearance
# =============================================================================

@export_group("Center Button Colors")
@export var center_normal_color: Color = Color(0.15, 0.15, 0.18, 0.95)
@export var center_hover_color: Color = Color(0.25, 0.25, 0.35, 0.95)
@export var center_pressed_color: Color = Color(0.1, 0.1, 0.12, 1.0)
@export var center_border_width: float = 3.0
@export var center_border_color: Color = Color(0.4, 0.4, 0.5, 0.8)

# =============================================================================
# Export Variables - Ring Button Appearance
# =============================================================================

@export_group("Ring Button Colors")
@export var ring_normal_color: Color = Color(0.2, 0.2, 0.25, 0.85)
@export var ring_hover_color: Color = Color(0.3, 0.3, 0.4, 0.95)
@export var ring_pressed_color: Color = Color(0.1, 0.1, 0.15, 1.0)
@export var ring_border_width: float = 2.0
@export var ring_border_color: Color = Color(0.4, 0.4, 0.5, 0.6)

# =============================================================================
# Export Variables - Text
# =============================================================================

@export_group("Text")
@export var text_color: Color = Color.BLACK
@export var center_font_size: int = 48
@export var ring_font_size: int = 32
@export var font: Font = null

# =============================================================================
# Export Variables - Icons
# =============================================================================

@export_group("Icons")
@export var center_icon_color: Color = Color.BLACK
@export var center_icon_size: Vector2 = Vector2(64, 64)
@export var ring_icon_color: Color = Color.BLACK
@export var ring_icon_size: Vector2 = Vector2(32, 32)

# =============================================================================
# Export Variables - Animation
# =============================================================================

@export_group("Animation")
## Whether to animate menu appearance on ready
@export var animate_on_ready: bool = true
## Duration of reveal animation
@export var reveal_duration: float = 0.3

# =============================================================================
# Internal State
# =============================================================================

## Center button configuration
var _center_config: Dictionary = {}

## Ring button configurations
var _ring_configs: Array[Dictionary] = []

## Center button component (created by subclass)
var _center_button: RadialCenterButton = null

## Whether components have been created
var _components_ready: bool = false

## Pending layout update flag
var _layout_dirty: bool = false

# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	# Set size to accommodate full menu
	_update_size()

	# Create child components (implemented by subclass)
	_create_components()

	# Apply reveal animation if enabled
	if animate_on_ready:
		_animate_reveal()


func _process(_delta: float) -> void:
	if _layout_dirty and _components_ready:
		_layout_dirty = false
		_update_layout()


func _request_layout_update() -> void:
	"""Request a deferred layout update."""
	_layout_dirty = true

# =============================================================================
# Abstract Methods - Must Be Implemented by Subclasses
# =============================================================================

func _create_components() -> void:
	"""Create button components. Override in subclass."""
	push_error("RadialMenuBase._create_components() must be overridden")


func _update_layout() -> void:
	"""Update component positions and sizes. Override in subclass."""
	push_error("RadialMenuBase._update_layout() must be overridden")


func _apply_center_config() -> void:
	"""Apply center configuration to button. Override in subclass."""
	push_error("RadialMenuBase._apply_center_config() must be overridden")


func _apply_ring_configs() -> void:
	"""Apply ring configurations to buttons. Override in subclass."""
	push_error("RadialMenuBase._apply_ring_configs() must be overridden")

# =============================================================================
# Shared Implementation
# =============================================================================

func _update_size() -> void:
	"""Update control size to fit the menu. Can be overridden."""
	var menu_size := _calculate_menu_size()
	custom_minimum_size = Vector2(menu_size, menu_size)
	size = Vector2(menu_size, menu_size)


func _calculate_menu_size() -> float:
	"""Calculate the total menu diameter. Override for different layouts."""
	# Default: accommodate ring buttons at ring_distance
	return (ring_distance + 60.0) * 2  # Assumes ~60px ring button radius


func _setup_center_button() -> void:
	"""Create and configure the center button (shared by all subclasses)."""
	_center_button = RadialCenterButton.new()
	_center_button.name = "CenterButton"
	add_child(_center_button)

	# Connect signals
	_center_button.pressed.connect(_on_center_pressed)
	_center_button.hover_changed.connect(_on_center_hover_changed)


func _apply_center_button_style() -> void:
	"""Apply style properties to center button."""
	if not _center_button:
		return

	_center_button.radius = center_radius
	_center_button.custom_minimum_size = Vector2(center_radius * 2, center_radius * 2)
	_center_button.size = Vector2(center_radius * 2, center_radius * 2)
	_center_button.position = (size - _center_button.size) / 2

	_center_button.normal_color = center_normal_color
	_center_button.hover_color = center_hover_color
	_center_button.pressed_color = center_pressed_color
	_center_button.border_width = center_border_width
	_center_button.border_color = center_border_color
	_center_button.text_color = text_color
	_center_button.font_size = center_font_size
	_center_button.font = font
	_center_button.icon_color = center_icon_color
	_center_button.icon_size = center_icon_size
	_center_button.queue_redraw()


func _apply_center_config_to_button() -> void:
	"""Apply center config dictionary to center button."""
	if not _center_button or _center_config.is_empty():
		return

	_center_button.button_id = _center_config.get("id", "")
	_center_button.text = _center_config.get("text", "")
	_center_button.icon = _center_config.get("icon", null)
	_center_button.disabled = _center_config.get("disabled", false)
	_center_button.visible = _center_config.get("visible", true)
	_center_button.queue_redraw()

# =============================================================================
# Public API - Center Button
# =============================================================================

func set_center_button(id: String, text: String, icon: Texture2D = null) -> void:
	"""Configure the center button."""
	_center_config = {
		"id": id,
		"text": text,
		"icon": icon,
		"visible": true,
		"disabled": false
	}
	_apply_center_config()


func set_center_text(new_text: String) -> void:
	"""Update center button text."""
	_center_config["text"] = new_text
	if _center_button:
		_center_button.set_text(new_text)


func set_center_icon(icon: Texture2D) -> void:
	"""Update center button icon."""
	_center_config["icon"] = icon
	if _center_button:
		_center_button.set_icon(icon)


func set_center_disabled(is_disabled: bool) -> void:
	"""Enable or disable center button."""
	_center_config["disabled"] = is_disabled
	if _center_button:
		_center_button.set_disabled(is_disabled)


func get_center_config() -> Dictionary:
	"""Get current center button configuration."""
	return _center_config.duplicate()

# =============================================================================
# Public API - Ring Buttons
# =============================================================================

func add_ring_button(id: String, text: String, icon: Texture2D = null) -> void:
	"""Add a button to the ring."""
	var config := {
		"id": id,
		"text": text,
		"icon": icon,
		"visible": true,
		"disabled": false
	}
	_ring_configs.append(config)
	_apply_ring_configs()


func remove_ring_button(id: String) -> void:
	"""Remove a ring button by ID."""
	for i in range(_ring_configs.size() - 1, -1, -1):
		if _ring_configs[i].get("id", "") == id:
			_ring_configs.remove_at(i)
			break
	_apply_ring_configs()


func clear_ring_buttons() -> void:
	"""Remove all ring buttons."""
	_ring_configs.clear()
	_apply_ring_configs()


func set_ring_button_disabled(id: String, is_disabled: bool) -> void:
	"""Enable or disable a ring button by ID."""
	for config in _ring_configs:
		if config.get("id", "") == id:
			config["disabled"] = is_disabled
			break
	_on_ring_button_state_changed(id, "disabled", is_disabled)


func set_ring_button_visible(id: String, is_visible: bool) -> void:
	"""Show or hide a ring button by ID."""
	for config in _ring_configs:
		if config.get("id", "") == id:
			config["visible"] = is_visible
			break
	_on_ring_button_state_changed(id, "visible", is_visible)


func get_ring_button_count() -> int:
	"""Get the number of ring buttons."""
	return _ring_configs.size()


func get_ring_configs() -> Array[Dictionary]:
	"""Get current ring button configurations."""
	var result: Array[Dictionary] = []
	for config in _ring_configs:
		result.append(config.duplicate())
	return result


## Override point for subclasses to handle individual button state changes
func _on_ring_button_state_changed(_id: String, _property: String, _value: Variant) -> void:
	_apply_ring_configs()

# =============================================================================
# Public API - Full Setup
# =============================================================================

func setup(center_config: Dictionary, ring_configs: Array[Dictionary]) -> void:
	"""Configure the entire menu at once."""
	_center_config = center_config
	_ring_configs.clear()
	for config in ring_configs:
		_ring_configs.append(config)

	_apply_center_config()
	_apply_ring_configs()

# =============================================================================
# Animation
# =============================================================================

func _animate_reveal() -> void:
	"""Animate the menu appearing."""
	# Start invisible and scaled down
	modulate.a = 0.0
	scale = Vector2(0.8, 0.8)
	pivot_offset = size / 2

	# Animate in
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, reveal_duration) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, reveal_duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func animate_hide(callback: Callable = Callable()) -> void:
	"""Animate the menu disappearing."""
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, reveal_duration * 0.8) \
		.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2(0.8, 0.8), reveal_duration * 0.8) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	if callback.is_valid():
		tween.tween_callback(callback)


# =============================================================================
# Public API - Positioning
# =============================================================================

func center_at_position(world_pos: Vector2) -> void:
	"""Center the menu at a world position.

	Since Control nodes position from their top-left corner, this calculates
	the offset needed to center the menu at the given world position.
	Uses custom_minimum_size for reliable sizing (especially on web export).
	"""
	# Use custom_minimum_size for reliable sizing (web export compatible)
	var menu_size := custom_minimum_size
	if menu_size == Vector2.ZERO:
		# Fallback to calculated size if custom_minimum_size not set
		menu_size = Vector2(_calculate_menu_size(), _calculate_menu_size())

	position = world_pos - menu_size / 2


func get_menu_center() -> Vector2:
	"""Get the world position of the menu's center.

	Returns the position that would be passed to center_at_position()
	to achieve the current positioning.
	"""
	var menu_size := custom_minimum_size
	if menu_size == Vector2.ZERO:
		menu_size = Vector2(_calculate_menu_size(), _calculate_menu_size())

	return position + menu_size / 2

# =============================================================================
# Signal Handlers
# =============================================================================

func _on_center_pressed() -> void:
	"""Handle center button press."""
	center_pressed.emit()


func _on_center_hover_changed(is_hovered: bool) -> void:
	"""Handle center button hover state change."""
	if is_hovered:
		var id: String = _center_config.get("id", "center")
		button_hovered.emit(id)
	else:
		button_unhovered.emit()
