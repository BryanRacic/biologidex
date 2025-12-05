class_name BackgroundTouchController
extends Control

## Handles touch/mouse gestures for panning and zooming the shader background.
## Designed for web export compatibility across all platforms.
## Uses position-based tracking (not touch index) to work around iOS web bugs.
##
## IMPORTANT: Uses MOUSE_FILTER_PASS with gesture thresholds to allow taps
## to pass through to buttons while capturing drag/pan gestures.
##
## Optional scroll limits with rubber-banding for bounded scrolling (e.g., feeds).

signal scroll_changed(offset: Vector2)
signal scale_changed(new_scale: float)
signal gesture_started()
signal gesture_ended()
signal tap_detected()  # Emitted when gesture ends without drag (tap on background)

# Configuration
@export_group("Scale")
@export var min_scale: float = 0.5
@export var max_scale: float = 4.0

@export_group("Pan")
@export var pan_sensitivity: float = 1.0
@export var zoom_sensitivity: float = 0.002
@export var drag_threshold: float = 10.0  # px movement before considered a drag

@export_group("Inertia")
@export var inertia_enabled: bool = true
@export var inertia_decay: float = 5.0  # Higher = faster slowdown
@export var inertia_stop_threshold: float = 1.0  # px/sec

@export_group("Scroll Limits")
## Enable bounded scrolling with rubber-banding at edges
@export var scroll_limits_enabled: bool = false
## Minimum scroll offset (use -INF for unbounded)
@export var scroll_min: Vector2 = Vector2(-INF, -INF)
## Maximum scroll offset (use INF for unbounded)
@export var scroll_max: Vector2 = Vector2(INF, INF)
## Enable rubber-band effect when scrolling past limits
@export var rubber_band_enabled: bool = true
## Resistance factor when past limits (0-1, lower = more resistance)
@export var rubber_band_factor: float = 0.3
## Maximum overscroll distance in pixels
@export var rubber_band_max: float = 100.0
## Speed of snap-back animation (0-1, higher = faster)
@export var snap_back_lerp: float = 0.15

# State
var scroll_offset: Vector2 = Vector2.ZERO
var current_scale: float = 1.0

# Touch tracking (position-based for web compatibility)
var _touch_state: Dictionary = {}  # { index: Vector2 position }
var _touch_start_positions: Dictionary = {}  # { index: Vector2 } - where each touch began
var _gesture_recognized: bool = false  # True once movement exceeds threshold
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
var _mouse_drag_recognized: bool = false  # True once mouse drag exceeds threshold
var _mouse_start_pos: Vector2 = Vector2.ZERO
var _mouse_last_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Use PASS to allow taps to reach buttons underneath
	mouse_filter = Control.MOUSE_FILTER_PASS


func _gui_input(event: InputEvent) -> void:
	# With emulate_mouse_from_touch=true, we only handle mouse events.
	# Touch events are converted to mouse events automatically, so handling
	# both would cause double-panning. Mouse-only handling works for:
	# - Desktop: real mouse events
	# - Mobile: touch → emulated mouse events
	#
	# We still track touch for multi-touch gestures (pinch zoom) since
	# mouse emulation doesn't preserve multi-touch information.

	if event is InputEventScreenTouch:
		# Track multi-touch state for pinch zoom detection
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			_touch_state[touch_event.index] = touch_event.position
			# Stop inertia on first touch to prevent velocity pollution
			if _touch_state.size() == 1:
				_stop_inertia()
		else:
			_touch_state.erase(touch_event.index)
			# Reset pinch base state when fingers lifted
			if _touch_state.size() < 2:
				_base_touch_state.clear()
		# Don't consume - let it become a mouse event
		return
	elif event is InputEventScreenDrag:
		# Update touch position for pinch zoom
		var drag_event := event as InputEventScreenDrag
		if _touch_state.has(drag_event.index):
			_touch_state[drag_event.index] = drag_event.position
		# Handle pinch zoom when 2+ fingers
		if _touch_state.size() >= 2:
			_handle_pinch_zoom()
			accept_event()
		# Single finger drag - let mouse emulation handle it
		return
	# Handle mouse events (works for both desktop and mobile via emulation)
	elif event is InputEventMouseButton:
		var should_accept := _handle_mouse_button(event as InputEventMouseButton)
		if should_accept:
			accept_event()
	elif event is InputEventMouseMotion:
		var should_accept := _handle_mouse_motion(event as InputEventMouseMotion)
		if should_accept:
			accept_event()


func _handle_screen_touch(event: InputEventScreenTouch) -> bool:
	var prev_finger_count := _touch_state.size()

	if event.pressed:
		# Finger down - track but don't consume yet (might be a tap on a button)
		_touch_state[event.index] = event.position
		_touch_start_positions[event.index] = event.position
		_stop_inertia()

		if prev_finger_count == 0:
			_gesture_recognized = false  # Reset for new gesture
			gesture_started.emit()

		# Two fingers = pinch zoom, immediately recognize as gesture
		if _touch_state.size() >= 2:
			_gesture_recognized = true
	else:
		# Finger up
		_touch_state.erase(event.index)
		_touch_start_positions.erase(event.index)

		if _touch_state.size() == 0:
			var was_gesture := _gesture_recognized
			if _gesture_recognized:
				_start_inertia()
			_gesture_recognized = false
			gesture_ended.emit()
			# Only consume touch-up if we recognized a gesture (not a tap)
			return was_gesture

	# Finger count changed - reset base state
	if _touch_state.size() != prev_finger_count:
		_update_base_state()

	# Accept multi-touch immediately, single touch only after gesture recognized
	return _touch_state.size() >= 2 or _gesture_recognized


func _handle_screen_drag(event: InputEventScreenDrag) -> bool:
	if not _touch_state.has(event.index):
		return false

	# Update position (use absolute position, not relative - web compatibility)
	_touch_state[event.index] = event.position

	# Check if drag exceeds threshold to recognize as gesture
	if not _gesture_recognized and _touch_start_positions.has(event.index):
		var start_pos: Vector2 = _touch_start_positions[event.index]
		var distance := event.position.distance_to(start_pos)
		if distance >= drag_threshold:
			_gesture_recognized = true

	# Only process pan/zoom once gesture is recognized
	if not _gesture_recognized:
		return false

	# Track for inertia
	_record_position_sample(event.position)

	var finger_count := _touch_state.size()

	if finger_count == 1:
		_handle_single_finger_pan()
	elif finger_count == 2:
		_handle_two_finger_gesture()

	return true  # Consume drag events once gesture is recognized


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


func _handle_pinch_zoom() -> void:
	"""Handle pinch zoom from raw touch state (used when mouse emulation is active)."""
	if _touch_state.size() < 2:
		return

	var keys: Array = _touch_state.keys()
	var p1: Vector2 = _touch_state[keys[0]]
	var p2: Vector2 = _touch_state[keys[1]]
	var current_distance := p1.distance_to(p2)

	# Initialize base state if needed
	if _base_touch_state.size() < 2:
		_base_touch_state = _touch_state.duplicate()
		_base_scale = current_scale
		_base_scroll = scroll_offset
		_base_pinch_distance = current_distance
		return

	# Calculate zoom
	if _base_pinch_distance > 10.0:
		var scale_factor := current_distance / _base_pinch_distance
		var new_scale := clampf(_base_scale * scale_factor, min_scale, max_scale)

		if absf(new_scale - current_scale) > 0.001:
			current_scale = new_scale
			scale_changed.emit(current_scale)

	# Calculate pan from midpoint movement
	var base_keys: Array = _base_touch_state.keys()
	var bp1: Vector2 = _base_touch_state[base_keys[0]]
	var bp2: Vector2 = _base_touch_state[base_keys[1]]
	var current_center := (p1 + p2) / 2.0
	var base_center := (bp1 + bp2) / 2.0
	var center_delta := current_center - base_center

	scroll_offset = _base_scroll - center_delta * pan_sensitivity
	scroll_changed.emit(scroll_offset)

	# Record pinch center for velocity calculation (enables inertia after pinch)
	_record_position_sample(current_center)


func _update_base_state() -> void:
	_base_touch_state = _touch_state.duplicate()
	_base_scroll = scroll_offset
	_base_scale = current_scale

	if _touch_state.size() == 2:
		var positions: Array = _touch_state.values()
		var pos0: Vector2 = positions[0] as Vector2
		var pos1: Vector2 = positions[1] as Vector2
		_base_pinch_distance = pos0.distance_to(pos1)


func _handle_mouse_button(event: InputEventMouseButton) -> bool:
	# Left click for pan
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_dragging = true
			_mouse_drag_recognized = false  # Reset - might be a click on a button
			_mouse_start_pos = event.position
			_mouse_last_pos = event.position
			_stop_inertia()
			gesture_started.emit()
			# Don't consume mouse down - let clicks reach buttons
			return false
		else:
			_mouse_dragging = false
			var was_drag := _mouse_drag_recognized
			if _mouse_drag_recognized:
				_start_inertia()
			else:
				# Was a tap, not a drag - emit tap signal
				tap_detected.emit()
			_mouse_drag_recognized = false
			gesture_ended.emit()
			# Only consume mouse up if we were dragging (not clicking a button)
			return was_drag

	# Scroll wheel for zoom - always consume
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_zoom_at_point(event.position, 1.1)
		return true
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_zoom_at_point(event.position, 0.9)
		return true

	return false


func _handle_mouse_motion(event: InputEventMouseMotion) -> bool:
	if not _mouse_dragging:
		return false

	# Check if drag exceeds threshold to recognize as gesture
	if not _mouse_drag_recognized:
		var distance := event.position.distance_to(_mouse_start_pos)
		if distance >= drag_threshold:
			_mouse_drag_recognized = true
		else:
			return false  # Not yet a drag, let motion pass through

	var delta := event.position - _mouse_last_pos
	_mouse_last_pos = event.position

	# Track for inertia
	_record_position_sample(event.position)

	# Apply pan (with limits if enabled)
	_apply_scroll_delta(-delta * pan_sensitivity)

	return true  # Consume motion events once drag is recognized


func _zoom_at_point(point: Vector2, factor: float) -> void:
	"""Zoom centered on a specific point (mouse cursor)."""
	var old_scale := current_scale
	current_scale = clampf(current_scale * factor, min_scale, max_scale)

	if absf(current_scale - old_scale) < 0.001:
		return

	if scroll_limits_enabled:
		# For bounded scrolling, just clamp to limits - don't adjust scroll position
		# The "keep point stationary" math causes jumps when scroll_offset is large
		if is_finite(scroll_min.x) and is_finite(scroll_max.x):
			scroll_offset.x = clampf(scroll_offset.x, scroll_min.x, scroll_max.x)
		if is_finite(scroll_min.y) and is_finite(scroll_max.y):
			scroll_offset.y = clampf(scroll_offset.y, scroll_min.y, scroll_max.y)
	else:
		# For infinite canvas, adjust scroll to keep point under cursor stationary
		var scale_ratio := current_scale / old_scale
		var point_offset := point - get_viewport_rect().size / 2.0
		scroll_offset = scroll_offset * scale_ratio + point_offset * (1.0 - scale_ratio)

	scroll_changed.emit(scroll_offset)
	scale_changed.emit(current_scale)


func _process(delta: float) -> void:
	# Apply inertia when no active touches
	if _touch_state.is_empty() and not _mouse_dragging:
		if inertia_enabled and _velocity.length() > inertia_stop_threshold:
			_apply_scroll_delta(-_velocity * delta)

			# Exponential decay
			_velocity = _velocity.move_toward(Vector2.ZERO, _velocity.length() * inertia_decay * delta)

			# If limits enabled and velocity died, check for snap-back
			if scroll_limits_enabled and _velocity.length() <= inertia_stop_threshold:
				_snap_back_if_overscrolled()
		elif scroll_limits_enabled and _is_overscrolled():
			# No velocity but still overscrolled - continue snap back
			_snap_back_if_overscrolled()
		elif _velocity.length() <= inertia_stop_threshold:
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

	# Velocity = direction of movement = newest - oldest (not inverted)
	return (newest_pos - oldest_pos) / time_delta


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
	_touch_start_positions.clear()
	_gesture_recognized = false
	_base_touch_state.clear()
	_mouse_dragging = false
	_mouse_drag_recognized = false
	# Clear velocity tracking state (prevents stale samples affecting next gesture)
	_last_positions.clear()
	_last_times.clear()
	scroll_changed.emit(scroll_offset)
	scale_changed.emit(current_scale)


# =============================================================================
# Scroll Limits API
# =============================================================================

func set_scroll_limits(min_val: Vector2, max_val: Vector2) -> void:
	"""Set scroll boundaries. Use INF/-INF for unbounded axes."""
	scroll_min = min_val
	scroll_max = max_val
	scroll_limits_enabled = true


func scroll_to(offset: Vector2, animated: bool = false) -> void:
	"""Scroll to a specific offset, optionally animated."""
	var target := offset
	if scroll_limits_enabled:
		target.x = clampf(target.x, scroll_min.x, scroll_max.x)
		target.y = clampf(target.y, scroll_min.y, scroll_max.y)

	if animated:
		var tween := create_tween()
		tween.tween_property(self, "scroll_offset", target, 0.3) \
			.set_trans(Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_OUT)
		tween.tween_callback(func(): scroll_changed.emit(scroll_offset))
	else:
		scroll_offset = target
		scroll_changed.emit(scroll_offset)


# =============================================================================
# Scroll Limits Internal
# =============================================================================

func _apply_scroll_delta(delta: Vector2) -> void:
	"""Apply scroll delta, with rubber-banding at limits if enabled."""
	if not scroll_limits_enabled:
		scroll_offset += delta
		scroll_changed.emit(scroll_offset)
		return

	var new_offset := scroll_offset + delta

	# Apply rubber-banding at boundaries
	if rubber_band_enabled:
		# X axis
		if is_finite(scroll_min.x) and new_offset.x < scroll_min.x:
			new_offset.x = scroll_offset.x + delta.x * rubber_band_factor
			new_offset.x = maxf(new_offset.x, scroll_min.x - rubber_band_max)
		elif is_finite(scroll_max.x) and new_offset.x > scroll_max.x:
			new_offset.x = scroll_offset.x + delta.x * rubber_band_factor
			new_offset.x = minf(new_offset.x, scroll_max.x + rubber_band_max)

		# Y axis
		if is_finite(scroll_min.y) and new_offset.y < scroll_min.y:
			new_offset.y = scroll_offset.y + delta.y * rubber_band_factor
			new_offset.y = maxf(new_offset.y, scroll_min.y - rubber_band_max)
		elif is_finite(scroll_max.y) and new_offset.y > scroll_max.y:
			new_offset.y = scroll_offset.y + delta.y * rubber_band_factor
			new_offset.y = minf(new_offset.y, scroll_max.y + rubber_band_max)
	else:
		# Hard clamp without rubber-banding
		if is_finite(scroll_min.x):
			new_offset.x = maxf(new_offset.x, scroll_min.x)
		if is_finite(scroll_max.x):
			new_offset.x = minf(new_offset.x, scroll_max.x)
		if is_finite(scroll_min.y):
			new_offset.y = maxf(new_offset.y, scroll_min.y)
		if is_finite(scroll_max.y):
			new_offset.y = minf(new_offset.y, scroll_max.y)

	scroll_offset = new_offset
	scroll_changed.emit(scroll_offset)


func _is_overscrolled() -> bool:
	"""Check if currently scrolled past limits."""
	if not scroll_limits_enabled:
		return false

	if is_finite(scroll_min.x) and scroll_offset.x < scroll_min.x:
		return true
	if is_finite(scroll_max.x) and scroll_offset.x > scroll_max.x:
		return true
	if is_finite(scroll_min.y) and scroll_offset.y < scroll_min.y:
		return true
	if is_finite(scroll_max.y) and scroll_offset.y > scroll_max.y:
		return true

	return false


func _snap_back_if_overscrolled() -> void:
	"""Animate back to valid scroll range if overscrolled."""
	var target := scroll_offset

	# Clamp to valid range
	if is_finite(scroll_min.x) and scroll_offset.x < scroll_min.x:
		target.x = scroll_min.x
	elif is_finite(scroll_max.x) and scroll_offset.x > scroll_max.x:
		target.x = scroll_max.x

	if is_finite(scroll_min.y) and scroll_offset.y < scroll_min.y:
		target.y = scroll_min.y
	elif is_finite(scroll_max.y) and scroll_offset.y > scroll_max.y:
		target.y = scroll_max.y

	if target != scroll_offset:
		# Smooth lerp back to valid position
		scroll_offset = scroll_offset.lerp(target, snap_back_lerp)
		if scroll_offset.distance_to(target) < 1.0:
			scroll_offset = target
		scroll_changed.emit(scroll_offset)
