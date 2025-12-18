extends Control
class_name RadialButtonBase

## RadialButtonBase - Base class for circular radial menu buttons.
##
## Provides shared functionality for all circular buttons in radial menus:
## - Circular hit detection via _has_point()
## - State management (hover, press, disabled)
## - Drawing (circle fill, border, icon, text)
## - Input handling
##
## Subclasses: RadialCenterButton, RadialButtonCircle

# =============================================================================
# Signals
# =============================================================================

signal pressed()
signal hover_changed(is_hovered: bool)

# =============================================================================
# Export Variables - Geometry
# =============================================================================

@export_group("Geometry")
## Radius of the circular button
@export var radius: float = 60.0:
	set(value):
		radius = value
		_update_size()
		queue_redraw()

# =============================================================================
# Export Variables - Colors
# =============================================================================

@export_group("Colors")
@export var normal_color: Color = Color(0.2, 0.2, 0.25, 0.85)
@export var hover_color: Color = Color(0.3, 0.3, 0.4, 0.95)
@export var pressed_color: Color = Color(0.1, 0.1, 0.15, 1.0)
@export var disabled_color: Color = Color(0.15, 0.15, 0.15, 0.5)

# =============================================================================
# Export Variables - Border
# =============================================================================

@export_group("Border")
@export var border_width: float = 2.0
@export var border_color: Color = Color(0.4, 0.4, 0.5, 0.6)

# =============================================================================
# Export Variables - Text
# =============================================================================

@export_group("Text")
@export var text: String = ""
@export var text_color: Color = Color.BLACK
@export var text_color_disabled: Color = Color(0.5, 0.5, 0.5, 0.5)
@export var font_size: int = 32
@export var font: Font = null

# =============================================================================
# Export Variables - Icon
# =============================================================================

@export_group("Icon")
@export var icon: Texture2D = null
@export var icon_size: Vector2 = Vector2(32, 32)
@export var icon_color: Color = Color.WHITE

# =============================================================================
# Export Variables - State
# =============================================================================

@export_group("State")
@export var disabled: bool = false
@export var button_id: String = ""

# =============================================================================
# Internal State
# =============================================================================

var _is_hovered: bool = false
var _is_pressed: bool = false

# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_size()
	_on_ready()


## Override point for subclasses to add initialization
func _on_ready() -> void:
	pass


func _update_size() -> void:
	"""Update control size based on radius."""
	var diameter := radius * 2
	custom_minimum_size = Vector2(diameter, diameter)
	size = Vector2(diameter, diameter)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		if _is_hovered:
			_is_hovered = false
			hover_changed.emit(false)
			queue_redraw()

# =============================================================================
# Drawing
# =============================================================================

func _draw() -> void:
	var center := size / 2

	# Get fill color based on state
	var fill_color := _get_fill_color()

	# Draw filled circle
	draw_circle(center, radius, fill_color)

	# Draw border
	if border_width > 0:
		draw_arc(center, radius, 0, TAU, 64, border_color, border_width, true)

	# Draw content (icon and/or text)
	_draw_content(center)


func _get_fill_color() -> Color:
	"""Get the fill color based on current state."""
	if disabled:
		return disabled_color
	if _is_pressed:
		return pressed_color
	if _is_hovered:
		return hover_color
	return normal_color


func _draw_content(center: Vector2) -> void:
	"""Draw icon and/or text centered in the button."""
	var draw_font: Font = font if font else ThemeDB.fallback_font
	var current_text_color := text_color if not disabled else text_color_disabled

	if icon:
		# Draw icon centered (or above text if both exist)
		var icon_pos := center - icon_size / 2
		if not text.is_empty():
			# Icon above text
			var total_height := icon_size.y + 8 + font_size
			icon_pos.y = center.y - total_height / 2
		draw_texture_rect(icon, Rect2(icon_pos, icon_size), false, icon_color)

		# Draw text below icon
		if not text.is_empty():
			var text_pos := Vector2(center.x, center.y + icon_size.y / 2 + 8 + font_size / 2)
			_draw_text_at(text, text_pos, draw_font, current_text_color)
	elif not text.is_empty():
		# Text only - handle multiline
		_draw_multiline_text(center, draw_font, current_text_color)


func _draw_text_at(text_str: String, pos: Vector2, draw_font: Font, color: Color) -> void:
	"""Draw text centered at position."""
	var text_size := draw_font.get_string_size(text_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := pos - Vector2(text_size.x / 2, -text_size.y / 4)
	draw_string(draw_font, text_pos, text_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)


func _draw_multiline_text(center: Vector2, draw_font: Font, color: Color) -> void:
	"""Draw multiline text centered in the button."""
	var lines := text.split("\n")
	var line_height := font_size * 1.2
	var total_height := lines.size() * line_height
	var start_y := center.y - total_height / 2 + font_size / 2

	for i in range(lines.size()):
		var line := lines[i]
		var line_text_size := draw_font.get_string_size(line, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var line_y := start_y + i * line_height
		var text_pos := Vector2(center.x - line_text_size.x / 2, line_y)
		draw_string(draw_font, text_pos, line, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)

# =============================================================================
# Hit Detection
# =============================================================================

func _has_point(point: Vector2) -> bool:
	"""Circular hit detection - return true if point is within radius."""
	var center := size / 2
	return point.distance_to(center) <= radius

# =============================================================================
# Input Handling
# =============================================================================

func _gui_input(event: InputEvent) -> void:
	if disabled:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_pressed = true
				queue_redraw()
				accept_event()
			else:
				if _is_pressed:
					_is_pressed = false
					queue_redraw()
					# Emit pressed only if mouse is still over button
					if _has_point(event.position):
						pressed.emit()
					accept_event()

	elif event is InputEventMouseMotion:
		var is_over := _has_point(event.position)
		if is_over != _is_hovered:
			_is_hovered = is_over
			hover_changed.emit(_is_hovered)
			queue_redraw()

# =============================================================================
# Public API
# =============================================================================

func set_text(new_text: String) -> void:
	"""Update the button text."""
	text = new_text
	queue_redraw()


func set_icon(new_icon: Texture2D) -> void:
	"""Update the button icon."""
	icon = new_icon
	queue_redraw()


func set_disabled(is_disabled: bool) -> void:
	"""Enable or disable the button."""
	disabled = is_disabled
	queue_redraw()


func get_radius() -> float:
	"""Get the button radius."""
	return radius


func set_radius(new_radius: float) -> void:
	"""Set the button radius and update size."""
	radius = new_radius
	_update_size()
	queue_redraw()


func configure(config: Dictionary) -> void:
	"""Configure button from a dictionary."""
	button_id = config.get("id", "")
	text = config.get("text", "")
	icon = config.get("icon", null)
	disabled = config.get("disabled", false)
	visible = config.get("visible", true)
	queue_redraw()


func is_hovered() -> bool:
	"""Check if button is currently hovered."""
	return _is_hovered


func is_button_pressed() -> bool:
	"""Check if button is currently pressed."""
	return _is_pressed
