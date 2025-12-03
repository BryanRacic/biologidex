class_name BackgroundTouchController
extends Control

## Handles touch/mouse gestures for panning and zooming the shader background.
## Designed for web export compatibility across all platforms.
## Uses position-based tracking (not touch index) to work around iOS web bugs.

signal scroll_changed(offset: Vector2)
signal scale_changed(new_scale: float)
signal gesture_started()
signal gesture_ended()

# Configuration
@export var min_scale: float = 0.5
@export var max_scale: float = 4.0
@export var pan_sensitivity: float = 1.0
@export var zoom_sensitivity: float = 0.002
@export var inertia_enabled: bool = true
@export var inertia_decay: float = 5.0  # Higher = faster slowdown
@export var inertia_stop_threshold: float = 1.0  # px/sec

# State
var scroll_offset: Vector2 = Vector2.ZERO
var current_scale: float = 1.0

# Touch tracking (position-based for web compatibility)
var _touch_state: Dictionary = {}  # { index: Vector2 position }
var _base_touch_state: Dictionary = {}  # State when finger count changed
var _base_scroll: Vector2 = Vector2.ZERO
var _base_scale: float = 1.0
var _base_pinch_distance: float = 0.0

# Inertia
var _velocity: Vector2 = Vector2.ZERO
var _last_positions: Array[Vector2] = []  # For velocity smoothing
var _last_times: Array[float] = []
const VELOCITY_SAMPLES: int = 5
const VELOCITY_MAX_AGE: float = 0.1  # seconds

# Mouse state
var _mouse_dragging: bool = false
var _mouse_last_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Ensure we receive input
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	# Handle touch events
	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)
	# Handle mouse events (for desktop/web mouse users)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	var prev_finger_count := _touch_state.size()

	if event.pressed:
		# Finger down
		_touch_state[event.index] = event.position
		_stop_inertia()

		if prev_finger_count == 0:
			gesture_started.emit()
	else:
		# Finger up
		_touch_state.erase(event.index)

		if _touch_state.size() == 0:
			_start_inertia()
			gesture_ended.emit()

	# Finger count changed - reset base state
	if _touch_state.size() != prev_finger_count:
		_update_base_state()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if not _touch_state.has(event.index):
		return

	# Update position (use absolute position, not relative - web compatibility)
	_touch_state[event.index] = event.position

	# Track for inertia
	_record_position_sample(event.position)

	var finger_count := _touch_state.size()

	if finger_count == 1:
		_handle_single_finger_pan()
	elif finger_count == 2:
		_handle_two_finger_gesture()


func _handle_single_finger_pan() -> void:
	if _base_touch_state.is_empty():
		return

	var current_pos: Vector2 = _touch_state.values()[0]
	var base_pos: Vector2 = _base_touch_state.values()[0]
	var delta: Vector2 = current_pos - base_pos

	# Apply pan (invert direction - dragging right moves pattern left)
	scroll_offset = _base_scroll - delta * pan_sensitivity
	scroll_changed.emit(scroll_offset)

	# Continuously update base for smooth panning
	var first_key: int = _touch_state.keys()[0] as int
	_base_touch_state[first_key] = current_pos
	_base_scroll = scroll_offset


func _handle_two_finger_gesture() -> void:
	if _base_touch_state.size() < 2:
		return

	# Get current and base finger positions
	var keys: Array = _touch_state.keys()
	var p1: Vector2 = _touch_state[keys[0]]
	var p2: Vector2 = _touch_state[keys[1]]

	var base_keys: Array = _base_touch_state.keys()
	var bp1: Vector2 = _base_touch_state[base_keys[0]]
	var bp2: Vector2 = _base_touch_state[base_keys[1]]

	# Calculate pinch zoom
	var current_distance := p1.distance_to(p2)
	var base_distance := bp1.distance_to(bp2)

	if base_distance > 10.0:  # Avoid division by tiny numbers
		var scale_factor := current_distance / base_distance
		var new_scale := clampf(_base_scale * scale_factor, min_scale, max_scale)

		if absf(new_scale - current_scale) > 0.001:
			current_scale = new_scale
			scale_changed.emit(current_scale)

	# Calculate pan from midpoint movement
	var current_center := (p1 + p2) / 2.0
	var base_center := (bp1 + bp2) / 2.0
	var center_delta := current_center - base_center

	scroll_offset = _base_scroll - center_delta * pan_sensitivity
	scroll_changed.emit(scroll_offset)


func _update_base_state() -> void:
	_base_touch_state = _touch_state.duplicate()
	_base_scroll = scroll_offset
	_base_scale = current_scale

	if _touch_state.size() == 2:
		var positions: Array = _touch_state.values()
		var pos0: Vector2 = positions[0] as Vector2
		var pos1: Vector2 = positions[1] as Vector2
		_base_pinch_distance = pos0.distance_to(pos1)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	# Left click for pan
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_dragging = true
			_mouse_last_pos = event.position
			_stop_inertia()
			gesture_started.emit()
		else:
			_mouse_dragging = false
			_start_inertia()
			gesture_ended.emit()

	# Scroll wheel for zoom
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_zoom_at_point(event.position, 1.1)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_zoom_at_point(event.position, 0.9)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _mouse_dragging:
		return

	var delta := event.position - _mouse_last_pos
	_mouse_last_pos = event.position

	# Track for inertia
	_record_position_sample(event.position)

	# Apply pan
	scroll_offset -= delta * pan_sensitivity
	scroll_changed.emit(scroll_offset)


func _zoom_at_point(point: Vector2, factor: float) -> void:
	"""Zoom centered on a specific point (mouse cursor)."""
	var old_scale := current_scale
	current_scale = clampf(current_scale * factor, min_scale, max_scale)

	if absf(current_scale - old_scale) < 0.001:
		return

	# Adjust scroll to keep point stationary
	var scale_ratio := current_scale / old_scale
	var point_offset := point - get_viewport_rect().size / 2.0
	scroll_offset = scroll_offset * scale_ratio + point_offset * (1.0 - scale_ratio)

	scroll_changed.emit(scroll_offset)
	scale_changed.emit(current_scale)


func _process(delta: float) -> void:
	if not inertia_enabled:
		return

	# Apply inertia when no active touches
	if _touch_state.is_empty() and not _mouse_dragging:
		if _velocity.length() > inertia_stop_threshold:
			scroll_offset -= _velocity * delta
			scroll_changed.emit(scroll_offset)

			# Exponential decay
			_velocity = _velocity.move_toward(Vector2.ZERO, _velocity.length() * inertia_decay * delta)
		else:
			_velocity = Vector2.ZERO


func _record_position_sample(pos: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_last_positions.append(pos)
	_last_times.append(now)

	# Keep only recent samples
	while _last_positions.size() > VELOCITY_SAMPLES:
		_last_positions.pop_front()
		_last_times.pop_front()


func _calculate_velocity() -> Vector2:
	"""Calculate smoothed velocity from recent position samples."""
	if _last_positions.size() < 2:
		return Vector2.ZERO

	var now := Time.get_ticks_msec() / 1000.0

	# Find oldest valid sample
	var oldest_idx := 0
	for i in range(_last_times.size()):
		if now - _last_times[i] <= VELOCITY_MAX_AGE:
			oldest_idx = i
			break

	if oldest_idx >= _last_positions.size() - 1:
		return Vector2.ZERO

	var oldest_pos := _last_positions[oldest_idx]
	var newest_pos := _last_positions[-1]
	var time_delta := _last_times[-1] - _last_times[oldest_idx]

	if time_delta < 0.001:
		return Vector2.ZERO

	return (oldest_pos - newest_pos) / time_delta


func _start_inertia() -> void:
	_velocity = _calculate_velocity()
	_last_positions.clear()
	_last_times.clear()


func _stop_inertia() -> void:
	_velocity = Vector2.ZERO
	_last_positions.clear()
	_last_times.clear()


func reset() -> void:
	"""Reset scroll and scale to defaults."""
	scroll_offset = Vector2.ZERO
	current_scale = 1.0
	_velocity = Vector2.ZERO
	_touch_state.clear()
	_base_touch_state.clear()
	scroll_changed.emit(scroll_offset)
	scale_changed.emit(current_scale)
