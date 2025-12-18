extends Control
class_name RadialButtonRing

## RadialButtonRing - Draws and handles arc-segment buttons in a ring formation.
##
## Uses custom _draw() for rendering arc segments and _gui_input() for hit detection.
## Segments are evenly distributed around the ring with configurable gaps.

# =============================================================================
# Signals
# =============================================================================

signal segment_pressed(index: int, button_id: String)
signal segment_hovered(index: int, button_id: String)
signal segment_unhovered()

# =============================================================================
# Export Variables
# =============================================================================

@export_group("Ring Geometry")
## Inner radius of the button ring (distance from center to inner edge)
@export var inner_radius: float = 150.0
## Outer radius of the button ring (distance from center to outer edge)
@export var outer_radius: float = 300.0
## Gap between segments in radians (~0.08 rad = ~4.6 degrees)
@export var gap_angle: float = 0.08
## Start angle for first segment (default: -PI/2 = 12 o'clock position)
@export var start_angle: float = -PI / 2

@export_group("Colors")
@export var normal_color: Color = Color(0.2, 0.2, 0.25, 0.85)
@export var hover_color: Color = Color(0.3, 0.3, 0.4, 0.95)
@export var pressed_color: Color = Color(0.1, 0.1, 0.15, 1.0)
@export var disabled_color: Color = Color(0.15, 0.15, 0.15, 0.5)

@export_group("Border")
@export var border_width: float = 2.0
@export var border_color: Color = Color(0.4, 0.4, 0.5, 0.6)

@export_group("Text")
@export var text_color: Color = Color.BLACK
@export var text_color_disabled: Color = Color(0.5, 0.5, 0.5, 0.5)
@export var font_size: int = 32
@export var font: Font = null

# =============================================================================
# Internal State
# =============================================================================

## Button configuration data: [{id, text, icon, visible, disabled}]
var _buttons: Array[Dictionary] = []

## Precomputed segment angles: [{start, end, mid}]
var _segment_angles: Array[Dictionary] = []

## Currently hovered segment index (-1 = none)
var _hovered_index: int = -1

## Currently pressed segment index (-1 = none)
var _pressed_index: int = -1

# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	# Ensure mouse input is processed
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Set minimum size based on outer diameter
	custom_minimum_size = Vector2(outer_radius * 2, outer_radius * 2)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		if _hovered_index >= 0:
			_hovered_index = -1
			segment_unhovered.emit()
			queue_redraw()

# =============================================================================
# Public API
# =============================================================================

func setup_buttons(buttons: Array[Dictionary]) -> void:
	"""Configure all ring buttons at once."""
	_buttons = buttons
	_compute_segment_angles()
	queue_redraw()


func add_button(config: Dictionary) -> void:
	"""Add a single button to the ring."""
	_buttons.append(config)
	_compute_segment_angles()
	queue_redraw()


func remove_button(button_id: String) -> void:
	"""Remove a button by ID."""
	for i in range(_buttons.size() - 1, -1, -1):
		if _buttons[i].get("id", "") == button_id:
			_buttons.remove_at(i)
			break
	_compute_segment_angles()
	queue_redraw()


func clear_buttons() -> void:
	"""Remove all buttons from the ring."""
	_buttons.clear()
	_segment_angles.clear()
	_hovered_index = -1
	_pressed_index = -1
	queue_redraw()


func get_button_count() -> int:
	"""Get the number of buttons in the ring."""
	return _buttons.size()


func get_button_config(index: int) -> Dictionary:
	"""Get the configuration for a button by index."""
	if index >= 0 and index < _buttons.size():
		return _buttons[index]
	return {}


func set_button_disabled(button_id: String, is_disabled: bool) -> void:
	"""Enable or disable a button by ID."""
	for btn in _buttons:
		if btn.get("id", "") == button_id:
			btn["disabled"] = is_disabled
			queue_redraw()
			break


func set_button_visible(button_id: String, is_visible: bool) -> void:
	"""Show or hide a button by ID."""
	for btn in _buttons:
		if btn.get("id", "") == button_id:
			btn["visible"] = is_visible
			queue_redraw()
			break

# =============================================================================
# Angle Computation
# =============================================================================

func _compute_segment_angles() -> void:
	"""Precompute angles for all segments based on button count."""
	_segment_angles.clear()
	var count := _buttons.size()
	if count == 0:
		return

	# Calculate angle available for each segment
	var total_gap := count * gap_angle
	var available_angle := TAU - total_gap
	var angle_per_segment := available_angle / count

	# Compute start, end, and midpoint for each segment
	var current_angle := start_angle
	for i in range(count):
		var seg_start := current_angle + gap_angle / 2
		var seg_end := seg_start + angle_per_segment
		var seg_mid := (seg_start + seg_end) / 2

		_segment_angles.append({
			"start": seg_start,
			"end": seg_end,
			"mid": seg_mid
		})

		current_angle = seg_end + gap_angle / 2

# =============================================================================
# Drawing
# =============================================================================

func _draw() -> void:
	if _buttons.is_empty():
		return

	var center := size / 2

	# Draw each segment
	for i in range(_buttons.size()):
		var btn := _buttons[i]
		if not btn.get("visible", true):
			continue

		var seg := _segment_angles[i]
		var color := _get_segment_color(i, btn)

		# Draw filled arc segment
		_draw_arc_segment(center, inner_radius, outer_radius, seg.start, seg.end, color)

		# Draw segment borders for visual separation
		if border_width > 0:
			_draw_arc_border(center, inner_radius, outer_radius, seg.start, seg.end)

		# Draw text label
		_draw_segment_text(i, center, seg.mid, btn)


func _draw_arc_segment(center: Vector2, inner_r: float, outer_r: float,
					   angle_from: float, angle_to: float, color: Color) -> void:
	"""Draw a filled arc segment (donut slice)."""
	var nb_points := 32
	var points := PackedVector2Array()

	# Outer arc (clockwise)
	for i in range(nb_points + 1):
		var angle := angle_from + i * (angle_to - angle_from) / nb_points
		points.push_back(center + Vector2(cos(angle), sin(angle)) * outer_r)

	# Inner arc (counter-clockwise to close shape)
	for i in range(nb_points, -1, -1):
		var angle := angle_from + i * (angle_to - angle_from) / nb_points
		points.push_back(center + Vector2(cos(angle), sin(angle)) * inner_r)

	draw_polygon(points, PackedColorArray([color]))


func _draw_arc_border(center: Vector2, inner_r: float, outer_r: float,
					  angle_from: float, angle_to: float) -> void:
	"""Draw border lines for arc segment edges."""
	# Draw outer arc
	draw_arc(center, outer_r, angle_from, angle_to, 32, border_color, border_width, true)
	# Draw inner arc
	draw_arc(center, inner_r, angle_from, angle_to, 32, border_color, border_width, true)

	# Draw radial edge lines
	var start_outer := center + Vector2(cos(angle_from), sin(angle_from)) * outer_r
	var start_inner := center + Vector2(cos(angle_from), sin(angle_from)) * inner_r
	var end_outer := center + Vector2(cos(angle_to), sin(angle_to)) * outer_r
	var end_inner := center + Vector2(cos(angle_to), sin(angle_to)) * inner_r

	draw_line(start_inner, start_outer, border_color, border_width, true)
	draw_line(end_inner, end_outer, border_color, border_width, true)


func _draw_segment_text(index: int, center: Vector2, mid_angle: float,
						btn: Dictionary) -> void:
	"""Draw text label centered in segment."""
	var label_text: String = btn.get("text", "")
	if label_text.is_empty():
		return

	# Calculate position at midpoint of segment
	var mid_radius := (inner_radius + outer_radius) / 2.0
	var pos := center + Vector2(cos(mid_angle), sin(mid_angle)) * mid_radius

	# Get font
	var draw_font: Font = font if font else ThemeDB.fallback_font
	var current_text_color := text_color if not btn.get("disabled", false) else text_color_disabled

	# Handle multiline text
	var lines := label_text.split("\n")
	var line_height := font_size * 1.2
	var total_height := lines.size() * line_height
	var start_y := pos.y - total_height / 2 + font_size / 2

	for i in range(lines.size()):
		var line := lines[i]
		var text_size := draw_font.get_string_size(line, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var line_y := start_y + i * line_height
		var text_pos := Vector2(pos.x - text_size.x / 2, line_y)
		draw_string(draw_font, text_pos, line, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, current_text_color)


func _get_segment_color(index: int, btn: Dictionary) -> Color:
	"""Get the fill color for a segment based on its state."""
	if btn.get("disabled", false):
		return disabled_color
	if index == _pressed_index:
		return pressed_color
	if index == _hovered_index:
		return hover_color
	return normal_color

# =============================================================================
# Hit Detection
# =============================================================================

func _get_segment_at_point(point: Vector2) -> int:
	"""Determine which segment (if any) contains the given point."""
	var center := size / 2
	var local := point - center
	var distance := local.length()

	# Check if within ring radius
	if distance < inner_radius or distance > outer_radius:
		return -1

	# Calculate angle of point
	var angle := atan2(local.y, local.x)

	# Find which segment contains this angle
	for i in range(_segment_angles.size()):
		if not _buttons[i].get("visible", true):
			continue

		var seg := _segment_angles[i]

		# Normalize angles to handle wraparound
		var seg_start: float = seg.start
		var seg_end: float = seg.end
		var test_angle: float = angle

		# Normalize all angles to [0, TAU)
		seg_start = fposmod(seg_start, TAU)
		seg_end = fposmod(seg_end, TAU)
		test_angle = fposmod(test_angle, TAU)

		# Check if angle is within segment
		if seg_start <= seg_end:
			# Normal case: segment doesn't cross 0
			if test_angle >= seg_start and test_angle <= seg_end:
				return i
		else:
			# Wraparound case: segment crosses 0/TAU boundary
			if test_angle >= seg_start or test_angle <= seg_end:
				return i

	return -1


func _has_point(point: Vector2) -> bool:
	"""Return true if point is within any segment."""
	return _get_segment_at_point(point) >= 0

# =============================================================================
# Input Handling
# =============================================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var seg := _get_segment_at_point(event.position)

			if event.pressed:
				# Mouse down
				if seg >= 0 and not _buttons[seg].get("disabled", false):
					_pressed_index = seg
					queue_redraw()
					accept_event()
			else:
				# Mouse up
				if _pressed_index >= 0 and seg == _pressed_index:
					# Click completed on same segment
					var btn := _buttons[_pressed_index]
					if not btn.get("disabled", false):
						segment_pressed.emit(_pressed_index, btn.get("id", ""))
				_pressed_index = -1
				queue_redraw()
				accept_event()

	elif event is InputEventMouseMotion:
		var seg := _get_segment_at_point(event.position)

		if seg != _hovered_index:
			if seg >= 0 and not _buttons[seg].get("disabled", false):
				_hovered_index = seg
				var btn := _buttons[seg]
				segment_hovered.emit(seg, btn.get("id", ""))
			else:
				if _hovered_index >= 0:
					segment_unhovered.emit()
				_hovered_index = -1
			queue_redraw()
