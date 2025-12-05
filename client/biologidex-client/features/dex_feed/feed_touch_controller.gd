class_name FeedTouchController
extends Control

## Handles touch/mouse gestures for carousel scrolling with pan and zoom.
## Based on BackgroundTouchController with vertical scrolling emphasis and horizontal bounds.
## Supports pinch-to-zoom and scroll wheel zoom like the tree view.
## Designed for web export compatibility across all platforms.

signal scroll_changed(offset: Vector2)      # 2D scroll offset
signal scale_changed(scale: float)          # Zoom scale
signal item_tapped(index: int)              # Tap on current item
signal gesture_started()
signal gesture_ended()

# Configuration
@export var inertia_enabled: bool = true
@export var inertia_decay: float = 2.0      # Higher = faster slowdown (lower = more momentum)
@export var inertia_stop_threshold: float = 0.5  # px/sec before stopping
@export var drag_threshold: float = 10.0    # px movement before considered a drag
@export var rubber_band_factor: float = 0.3 # Resistance at boundaries
@export var rubber_band_max: float = 100.0  # Max overscroll in pixels
@export var pan_sensitivity: float = 1.0    # Pan speed multiplier

# Zoom configuration
@export var min_scale: float = 0.5
@export var max_scale: float = 3.0
@export var zoom_wheel_factor: float = 1.1  # Scroll wheel zoom step

# Horizontal scroll bounds (as ratio of viewport width)
@export var horizontal_bound_ratio: float = 0.5  # ±50% of viewport width

# State
var scroll_offset: Vector2 = Vector2.ZERO   # Current scroll position (pixels)
var current_scale: float = 1.0              # Current zoom scale
var current_index: int = 0                  # Approximate current item (for tap detection)
var total_items: int = 0                    # Total items in feed
var max_scroll_y: float = 0.0               # Maximum vertical scroll offset

# Touch tracking
var _gesture_recognized: bool = false       # True once movement exceeds threshold
var _touch_state: Dictionary = {}           # {index: Vector2} for multi-touch
var _touch_start_positions: Dictionary = {} # {index: Vector2} initial positions

# Pinch zoom state
var _base_touch_state: Dictionary = {}      # Positions when pinch started
var _base_scroll: Vector2 = Vector2.ZERO
var _base_scale: float = 1.0
var _base_pinch_distance: float = 0.0

# Inertia
var _velocity: Vector2 = Vector2.ZERO
var _last_positions: Array[Vector2] = []    # For velocity smoothing
var _last_times: Array[float] = []
const VELOCITY_SAMPLES: int = 5
const VELOCITY_MAX_AGE: float = 0.1         # seconds

# Mouse state
var _mouse_dragging: bool = false
var _mouse_drag_recognized: bool = false
var _mouse_start_pos: Vector2 = Vector2.ZERO
var _mouse_last_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Use PASS to allow taps to reach items underneath
	mouse_filter = Control.MOUSE_FILTER_PASS


func _gui_input(event: InputEvent) -> void:
	# Handle touch events for pinch zoom
	if event is InputEventScreenTouch:
		var should_accept := _handle_screen_touch(event as InputEventScreenTouch)
		if should_accept:
			accept_event()
	elif event is InputEventScreenDrag:
		var should_accept := _handle_screen_drag(event as InputEventScreenDrag)
		if should_accept:
			accept_event()
	# Handle mouse events (works for both desktop and mobile via emulation)
	elif event is InputEventMouseButton:
		var should_accept := _handle_mouse_button(event as InputEventMouseButton)
		if should_accept:
			accept_event()
	elif event is InputEventMouseMotion:
		var should_accept := _handle_mouse_motion(event as InputEventMouseMotion)
		if should_accept:
			accept_event()


# =============================================================================
# Touch Event Handling (for pinch zoom)
# =============================================================================

func _handle_screen_touch(event: InputEventScreenTouch) -> bool:
	if event.pressed:
		_touch_state[event.index] = event.position
		_touch_start_positions[event.index] = event.position

		# First finger - stop inertia
		if _touch_state.size() == 1:
			_stop_inertia()

		# Two fingers - start pinch mode
		if _touch_state.size() == 2:
			_base_touch_state.clear()  # Will be set on first pinch movement

		return false  # Don't consume yet
	else:
		# Finger released
		_touch_state.erase(event.index)
		_touch_start_positions.erase(event.index)

		# All fingers released
		if _touch_state.is_empty():
			_base_touch_state.clear()
			_start_inertia()

		return false


func _handle_screen_drag(event: InputEventScreenDrag) -> bool:
	if not _touch_state.has(event.index):
		return false

	_touch_state[event.index] = event.position

	# Two-finger pinch zoom
	if _touch_state.size() == 2:
		_handle_pinch_zoom()
		return true

	return false


func _handle_pinch_zoom() -> void:
	var keys := _touch_state.keys()
	if keys.size() < 2:
		return

	var p1: Vector2 = _touch_state[keys[0]]
	var p2: Vector2 = _touch_state[keys[1]]
	var current_distance := p1.distance_to(p2)
	var current_center := (p1 + p2) / 2.0

	# Initialize base state on first pinch movement
	if _base_touch_state.size() < 2:
		_base_touch_state = _touch_state.duplicate()
		_base_scale = current_scale
		_base_scroll = scroll_offset
		_base_pinch_distance = current_distance
		return

	# Calculate new scale
	var scale_factor := current_distance / _base_pinch_distance
	var new_scale := clampf(_base_scale * scale_factor, min_scale, max_scale)

	# Apply zoom centered on pinch center (no panning during pinch to reduce jitter)
	var old_scale := current_scale
	current_scale = new_scale

	# Adjust scroll to zoom toward pinch center
	var bp1: Vector2 = _base_touch_state[keys[0]]
	var bp2: Vector2 = _base_touch_state[keys[1]]
	var base_center := (bp1 + bp2) / 2.0
	var scale_ratio := current_scale / old_scale
	var viewport_center := size / 2.0
	var point_offset := base_center - viewport_center
	scroll_offset = _base_scroll * scale_ratio + point_offset * (1.0 - scale_ratio)

	# Apply bounds
	_apply_horizontal_bounds()

	scroll_changed.emit(scroll_offset)
	scale_changed.emit(current_scale)


# =============================================================================
# Mouse Event Handling
# =============================================================================

func _handle_mouse_button(event: InputEventMouseButton) -> bool:
	# Left click for drag/scroll
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_dragging = true
			_mouse_drag_recognized = false
			_mouse_start_pos = event.position
			_mouse_last_pos = event.position
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

	# Scroll wheel for zooming (like tree view)
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_zoom_at_point(event.position, zoom_wheel_factor)
		return true
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_zoom_at_point(event.position, 1.0 / zoom_wheel_factor)
		return true

	return false


func _handle_mouse_motion(event: InputEventMouseMotion) -> bool:
	if not _mouse_dragging:
		return false

	# Disable panning when multiple fingers are touching (pinch mode)
	if _touch_state.size() >= 2:
		return false

	# Check if drag exceeds threshold (considering both axes)
	if not _mouse_drag_recognized:
		var distance := event.position.distance_to(_mouse_start_pos)
		if distance >= drag_threshold:
			_mouse_drag_recognized = true
		else:
			return false  # Not yet a drag

	var delta := event.position - _mouse_last_pos
	_mouse_last_pos = event.position

	# Track for inertia
	_record_position_sample(event.position)

	# Apply scroll (inverted - drag moves content opposite direction)
	_apply_scroll_delta(-delta * pan_sensitivity)

	return true


func _zoom_at_point(point: Vector2, factor: float) -> void:
	"""Zoom centered on a specific screen point (mouse cursor)."""
	var old_scale := current_scale
	current_scale = clampf(current_scale * factor, min_scale, max_scale)

	if current_scale == old_scale:
		return

	# Keep the point under cursor stationary
	var scale_ratio := current_scale / old_scale
	var viewport_center := size / 2.0
	var point_offset := point - viewport_center
	scroll_offset = scroll_offset * scale_ratio + point_offset * (1.0 - scale_ratio)

	# Apply bounds
	_apply_horizontal_bounds()

	scroll_changed.emit(scroll_offset)
	scale_changed.emit(current_scale)


# =============================================================================
# Scroll Application
# =============================================================================

func _apply_scroll_delta(delta: Vector2) -> void:
	"""Apply scroll delta with rubber-banding at boundaries."""
	var new_offset := scroll_offset + delta

	# Vertical bounds with rubber-banding
	if new_offset.y < 0.0:
		new_offset.y = scroll_offset.y + delta.y * rubber_band_factor
		new_offset.y = maxf(new_offset.y, -rubber_band_max)
	elif new_offset.y > max_scroll_y:
		new_offset.y = scroll_offset.y + delta.y * rubber_band_factor
		new_offset.y = minf(new_offset.y, max_scroll_y + rubber_band_max)

	# Horizontal bounds with rubber-banding
	var max_horizontal := size.x * horizontal_bound_ratio
	if new_offset.x < -max_horizontal:
		new_offset.x = scroll_offset.x + delta.x * rubber_band_factor
		new_offset.x = maxf(new_offset.x, -max_horizontal - rubber_band_max)
	elif new_offset.x > max_horizontal:
		new_offset.x = scroll_offset.x + delta.x * rubber_band_factor
		new_offset.x = minf(new_offset.x, max_horizontal + rubber_band_max)

	scroll_offset = new_offset
	scroll_changed.emit(scroll_offset)


func _apply_horizontal_bounds() -> void:
	"""Clamp horizontal scroll to bounds."""
	var max_horizontal := size.x * horizontal_bound_ratio
	scroll_offset.x = clampf(scroll_offset.x, -max_horizontal, max_horizontal)


# =============================================================================
# Process Loop (Inertia)
# =============================================================================

func _process(delta: float) -> void:
	if not inertia_enabled:
		return

	# Apply inertia when not dragging
	if not _mouse_dragging and _touch_state.is_empty():
		if _velocity.length() > inertia_stop_threshold:
			_apply_scroll_delta(_velocity * delta)

			# Exponential decay
			_velocity = _velocity.move_toward(Vector2.ZERO, _velocity.length() * inertia_decay * delta)

			# Rubber band snap-back when velocity dies and we're overscrolled
			if _velocity.length() <= inertia_stop_threshold:
				_snap_back_if_overscrolled()
		elif _is_overscrolled():
			# Still overscrolled but no velocity - continue snap back
			_snap_back_if_overscrolled()


func _is_overscrolled() -> bool:
	"""Check if currently outside valid scroll bounds."""
	var max_horizontal := size.x * horizontal_bound_ratio
	return scroll_offset.y < 0.0 or scroll_offset.y > max_scroll_y or \
		   scroll_offset.x < -max_horizontal or scroll_offset.x > max_horizontal


func _snap_back_if_overscrolled() -> void:
	"""Animate back to valid scroll range if overscrolled."""
	var target := scroll_offset
	var max_horizontal := size.x * horizontal_bound_ratio

	# Vertical snap back
	if scroll_offset.y < 0.0:
		target.y = 0.0
	elif scroll_offset.y > max_scroll_y:
		target.y = max_scroll_y

	# Horizontal snap back
	if scroll_offset.x < -max_horizontal:
		target.x = -max_horizontal
	elif scroll_offset.x > max_horizontal:
		target.x = max_horizontal

	if target != scroll_offset:
		# Smooth snap back
		scroll_offset = scroll_offset.lerp(target, 0.15)
		if scroll_offset.distance_to(target) < 1.0:
			scroll_offset = target
		scroll_changed.emit(scroll_offset)


# =============================================================================
# Velocity Tracking
# =============================================================================

func _record_position_sample(pos: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_last_positions.append(pos)
	_last_times.append(now)

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

	# Velocity = direction of movement (inverted for scroll feel)
	return -(newest_pos - oldest_pos) / time_delta


func _start_inertia() -> void:
	_velocity = _calculate_velocity()
	_last_positions.clear()
	_last_times.clear()


func _stop_inertia() -> void:
	_velocity = Vector2.ZERO
	_last_positions.clear()
	_last_times.clear()


# =============================================================================
# Public API
# =============================================================================

func set_total_items(count: int) -> void:
	"""Set total number of items in the carousel."""
	total_items = count


func set_max_scroll(max_val: float) -> void:
	"""Set the maximum vertical scroll offset (total content height - viewport height)."""
	max_scroll_y = maxf(0.0, max_val)


func scroll_to_offset(offset: Vector2, animated: bool = false) -> void:
	"""Scroll to a specific offset."""
	var max_horizontal := size.x * horizontal_bound_ratio
	offset.y = clampf(offset.y, 0.0, max_scroll_y)
	offset.x = clampf(offset.x, -max_horizontal, max_horizontal)

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


func set_zoom_scale(new_scale: float) -> void:
	"""Set the zoom scale."""
	current_scale = clampf(new_scale, min_scale, max_scale)
	scale_changed.emit(current_scale)


func reset() -> void:
	"""Reset controller to initial state."""
	scroll_offset = Vector2.ZERO
	current_scale = 1.0
	current_index = 0
	_velocity = Vector2.ZERO
	_mouse_dragging = false
	_mouse_drag_recognized = false
	_touch_state.clear()
	_touch_start_positions.clear()
	_base_touch_state.clear()
	_last_positions.clear()
	_last_times.clear()
	scroll_changed.emit(scroll_offset)
	scale_changed.emit(current_scale)
