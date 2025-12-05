class_name FeedTouchController
extends Control

## Handles touch/mouse gestures for vertical carousel scrolling with free-scroll behavior.
## Based on BackgroundTouchController but simplified for 1D vertical navigation.
## Designed for web export compatibility across all platforms.

signal scroll_changed(offset: float)      # Vertical scroll offset
signal item_tapped(index: int)            # Tap on current item
signal gesture_started()
signal gesture_ended()

# Configuration
@export var inertia_enabled: bool = true
@export var inertia_decay: float = 5.0    # Higher = faster slowdown
@export var inertia_stop_threshold: float = 1.0  # px/sec before stopping
@export var drag_threshold: float = 10.0  # px movement before considered a drag
@export var rubber_band_factor: float = 0.3  # Resistance at boundaries
@export var rubber_band_max: float = 100.0  # Max overscroll in pixels

# State
var scroll_offset: float = 0.0           # Current scroll position (pixels)
var current_index: int = 0               # Approximate current item (for tap detection)
var total_items: int = 0                 # Total items in feed
var max_scroll: float = 0.0              # Maximum scroll offset

# Touch tracking
var _gesture_recognized: bool = false    # True once movement exceeds threshold

# Inertia
var _velocity: float = 0.0
var _last_positions: Array[float] = []   # For velocity smoothing (Y only)
var _last_times: Array[float] = []
const VELOCITY_SAMPLES: int = 5
const VELOCITY_MAX_AGE: float = 0.1      # seconds

# Mouse state
var _mouse_dragging: bool = false
var _mouse_drag_recognized: bool = false
var _mouse_start_y: float = 0.0
var _mouse_last_y: float = 0.0


func _ready() -> void:
	# Use PASS to allow taps to reach items underneath
	mouse_filter = Control.MOUSE_FILTER_PASS


func _gui_input(event: InputEvent) -> void:
	# Handle mouse events (works for both desktop and mobile via emulation)
	if event is InputEventMouseButton:
		var should_accept := _handle_mouse_button(event as InputEventMouseButton)
		if should_accept:
			accept_event()
	elif event is InputEventMouseMotion:
		var should_accept := _handle_mouse_motion(event as InputEventMouseMotion)
		if should_accept:
			accept_event()


func _handle_mouse_button(event: InputEventMouseButton) -> bool:
	# Left click for drag/scroll
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_dragging = true
			_mouse_drag_recognized = false
			_mouse_start_y = event.position.y
			_mouse_last_y = event.position.y
			_stop_inertia()
			gesture_started.emit()
			# Don't consume mouse down - let clicks reach items
			return false
		else:
			_mouse_dragging = false
			var was_drag := _mouse_drag_recognized
			if _mouse_drag_recognized:
				_start_inertia()
			else:
				# Was a tap - emit signal with current index
				item_tapped.emit(current_index)
			_mouse_drag_recognized = false
			gesture_ended.emit()
			return was_drag

	# Scroll wheel for scrolling
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_apply_scroll_delta(-50.0)
		return true
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_apply_scroll_delta(50.0)
		return true

	return false


func _handle_mouse_motion(event: InputEventMouseMotion) -> bool:
	if not _mouse_dragging:
		return false

	# Check if drag exceeds threshold
	if not _mouse_drag_recognized:
		var distance := absf(event.position.y - _mouse_start_y)
		if distance >= drag_threshold:
			_mouse_drag_recognized = true
		else:
			return false  # Not yet a drag

	var delta_y := event.position.y - _mouse_last_y
	_mouse_last_y = event.position.y

	# Track for inertia
	_record_position_sample(event.position.y)

	# Apply scroll (inverted - drag down moves content up, showing next items)
	_apply_scroll_delta(-delta_y)

	return true


func _apply_scroll_delta(delta: float) -> void:
	"""Apply scroll delta with rubber-banding at boundaries."""
	var new_offset := scroll_offset + delta

	# Apply rubber band effect at boundaries
	if new_offset < 0.0:
		# Past the beginning - apply resistance
		new_offset = scroll_offset + delta * rubber_band_factor
		new_offset = maxf(new_offset, -rubber_band_max)
	elif new_offset > max_scroll:
		# Past the end - apply resistance
		new_offset = scroll_offset + delta * rubber_band_factor
		new_offset = minf(new_offset, max_scroll + rubber_band_max)

	scroll_offset = new_offset
	scroll_changed.emit(scroll_offset)


func _process(delta: float) -> void:
	if not inertia_enabled:
		return

	# Apply inertia when not dragging
	if not _mouse_dragging:
		if absf(_velocity) > inertia_stop_threshold:
			_apply_scroll_delta(_velocity * delta)

			# Exponential decay
			_velocity = move_toward(_velocity, 0.0, absf(_velocity) * inertia_decay * delta)

			# Rubber band snap-back when velocity dies and we're overscrolled
			if absf(_velocity) <= inertia_stop_threshold:
				_snap_back_if_overscrolled()
		elif scroll_offset < 0.0 or scroll_offset > max_scroll:
			# Still overscrolled but no velocity - continue snap back
			_snap_back_if_overscrolled()


func _snap_back_if_overscrolled() -> void:
	"""Animate back to valid scroll range if overscrolled."""
	var target: float = scroll_offset

	if scroll_offset < 0.0:
		target = 0.0
	elif scroll_offset > max_scroll:
		target = max_scroll

	if target != scroll_offset:
		# Smooth snap back
		scroll_offset = lerp(scroll_offset, target, 0.15)
		if absf(scroll_offset - target) < 1.0:
			scroll_offset = target
		scroll_changed.emit(scroll_offset)


func _record_position_sample(pos_y: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_last_positions.append(pos_y)
	_last_times.append(now)

	while _last_positions.size() > VELOCITY_SAMPLES:
		_last_positions.pop_front()
		_last_times.pop_front()


func _calculate_velocity() -> float:
	"""Calculate smoothed velocity from recent position samples."""
	if _last_positions.size() < 2:
		return 0.0

	var now := Time.get_ticks_msec() / 1000.0

	# Find oldest valid sample
	var oldest_idx := 0
	for i in range(_last_times.size()):
		if now - _last_times[i] <= VELOCITY_MAX_AGE:
			oldest_idx = i
			break

	if oldest_idx >= _last_positions.size() - 1:
		return 0.0

	var oldest_pos := _last_positions[oldest_idx]
	var newest_pos := _last_positions[-1]
	var time_delta := _last_times[-1] - _last_times[oldest_idx]

	if time_delta < 0.001:
		return 0.0

	# Velocity = direction of movement (inverted for scroll feel)
	return -(newest_pos - oldest_pos) / time_delta


func _start_inertia() -> void:
	_velocity = _calculate_velocity()
	_last_positions.clear()
	_last_times.clear()


func _stop_inertia() -> void:
	_velocity = 0.0
	_last_positions.clear()
	_last_times.clear()


# =============================================================================
# Public API
# =============================================================================

func set_total_items(count: int) -> void:
	"""Set total number of items in the carousel."""
	total_items = count


func set_max_scroll(max_val: float) -> void:
	"""Set the maximum scroll offset (total content height - viewport height)."""
	max_scroll = maxf(0.0, max_val)


func scroll_to_offset(offset: float, animated: bool = false) -> void:
	"""Scroll to a specific offset."""
	offset = clampf(offset, 0.0, max_scroll)

	if animated:
		# Simple animated scroll
		var tween := create_tween()
		tween.tween_property(self, "scroll_offset", offset, 0.3) \
			.set_trans(Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_OUT)
		tween.tween_callback(func(): scroll_changed.emit(scroll_offset))
	else:
		scroll_offset = offset
		scroll_changed.emit(scroll_offset)


func reset() -> void:
	"""Reset controller to initial state."""
	scroll_offset = 0.0
	current_index = 0
	_velocity = 0.0
	_mouse_dragging = false
	_mouse_drag_recognized = false
	_last_positions.clear()
	_last_times.clear()
	scroll_changed.emit(scroll_offset)
