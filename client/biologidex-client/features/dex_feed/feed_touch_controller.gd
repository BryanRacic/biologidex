class_name FeedTouchController
extends Control

## Handles touch/mouse gestures for vertical carousel scrolling with snap-to-item behavior.
## Based on BackgroundTouchController but simplified for 1D vertical navigation.
## Designed for web export compatibility across all platforms.

signal scroll_changed(offset: float)      # Vertical scroll offset
signal snap_started(target_index: int)    # Snap animation beginning
signal snap_completed(index: int)         # Snap animation finished
signal item_tapped(index: int)            # Tap on current item
signal gesture_started()
signal gesture_ended()

# Configuration
@export var item_height: float = 600.0    # Height of each carousel item
@export var snap_threshold: float = 0.3   # % of item height to trigger snap to next
@export var inertia_enabled: bool = true
@export var inertia_decay: float = 5.0    # Higher = faster slowdown
@export var inertia_stop_threshold: float = 50.0  # px/sec before starting snap
@export var snap_duration: float = 0.25   # Tween duration for snap animation
@export var drag_threshold: float = 10.0  # px movement before considered a drag
@export var rubber_band_factor: float = 0.3  # Resistance at boundaries

# State
var scroll_offset: float = 0.0           # Current scroll position (pixels)
var current_index: int = 0               # Current centered item index
var total_items: int = 0                 # Total items in feed

# Touch tracking
var _touch_state: Dictionary = {}        # { index: Vector2 position }
var _touch_start_y: float = 0.0          # Y position where touch began
var _gesture_recognized: bool = false    # True once movement exceeds threshold
var _base_scroll: float = 0.0            # Scroll at gesture start

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

# Animation state
var _snap_tween: Tween = null
var _is_snapping: bool = false


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
			_base_scroll = scroll_offset
			_stop_inertia()
			_cancel_snap()
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
	var max_offset := float(max(0, total_items - 1)) * item_height

	# Apply rubber band effect at boundaries
	if new_offset < 0.0:
		# Past the beginning - apply resistance
		new_offset = scroll_offset + delta * rubber_band_factor
		new_offset = maxf(new_offset, -item_height * 0.5)
	elif new_offset > max_offset:
		# Past the end - apply resistance
		new_offset = scroll_offset + delta * rubber_band_factor
		new_offset = minf(new_offset, max_offset + item_height * 0.5)

	scroll_offset = new_offset
	_update_current_index()
	scroll_changed.emit(scroll_offset)


func _update_current_index() -> void:
	"""Update current_index based on scroll position."""
	if item_height > 0 and total_items > 0:
		current_index = clampi(roundi(scroll_offset / item_height), 0, total_items - 1)


func _process(delta: float) -> void:
	if not inertia_enabled:
		return

	# Apply inertia when not dragging and not snapping
	if not _mouse_dragging and not _is_snapping:
		if absf(_velocity) > inertia_stop_threshold:
			_apply_scroll_delta(_velocity * delta)

			# Exponential decay
			_velocity = move_toward(_velocity, 0.0, absf(_velocity) * inertia_decay * delta)
		elif absf(_velocity) > 0.0:
			# Velocity dropped below threshold - start snap
			_velocity = 0.0
			_start_snap()


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

	# If velocity is very low, immediately snap
	if absf(_velocity) <= inertia_stop_threshold:
		_velocity = 0.0
		_start_snap()


func _stop_inertia() -> void:
	_velocity = 0.0
	_last_positions.clear()
	_last_times.clear()


func _start_snap() -> void:
	"""Snap to nearest item based on current position and velocity."""
	if total_items == 0:
		return

	var raw_index := scroll_offset / item_height if item_height > 0 else 0.0
	var target_index: int

	# Determine snap direction based on position within item
	var fractional := raw_index - floorf(raw_index)

	if fractional > snap_threshold and fractional < (1.0 - snap_threshold):
		# In the middle - snap to nearest
		target_index = roundi(raw_index)
	elif fractional >= (1.0 - snap_threshold):
		# Near the next item
		target_index = ceili(raw_index)
	else:
		# Near the current item
		target_index = floori(raw_index)

	target_index = clampi(target_index, 0, total_items - 1)
	_animate_to_index(target_index)


func _animate_to_index(index: int) -> void:
	"""Animate scroll to center on specific index."""
	_cancel_snap()
	_is_snapping = true

	var target_offset := float(index) * item_height
	snap_started.emit(index)

	_snap_tween = create_tween()
	_snap_tween.tween_property(self, "scroll_offset", target_offset, snap_duration) \
		.set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_OUT)
	_snap_tween.tween_callback(_on_snap_completed.bind(index))

	# Also tween-update scroll_changed signal
	_snap_tween.parallel().tween_method(_emit_scroll_changed, scroll_offset, target_offset, snap_duration)


func _emit_scroll_changed(offset: float) -> void:
	scroll_offset = offset
	_update_current_index()
	scroll_changed.emit(offset)


func _on_snap_completed(index: int) -> void:
	_is_snapping = false
	current_index = index
	snap_completed.emit(index)


func _cancel_snap() -> void:
	if _snap_tween and _snap_tween.is_valid():
		_snap_tween.kill()
	_snap_tween = null
	_is_snapping = false


# =============================================================================
# Public API
# =============================================================================

func set_total_items(count: int) -> void:
	"""Set total number of items in the carousel."""
	total_items = count
	_update_current_index()


func scroll_to_index(index: int, animated: bool = true) -> void:
	"""Scroll to center on a specific item index."""
	if total_items == 0:
		return

	index = clampi(index, 0, total_items - 1)

	if animated:
		_animate_to_index(index)
	else:
		scroll_offset = float(index) * item_height
		current_index = index
		scroll_changed.emit(scroll_offset)


func get_visible_range() -> Vector2i:
	"""Returns (first_visible, last_visible) indices that should be rendered."""
	if total_items == 0:
		return Vector2i(-1, -1)

	# Calculate which items are potentially visible
	# (current - 1) to (current + 1) covers transitions
	var first := maxi(0, current_index - 1)
	var last := mini(total_items - 1, current_index + 1)

	return Vector2i(first, last)


func get_item_offset(index: int) -> float:
	"""Get the Y offset for an item at given index relative to scroll position.
	Returns the position where the item's center should be placed."""
	return float(index) * item_height - scroll_offset


func reset() -> void:
	"""Reset controller to initial state."""
	scroll_offset = 0.0
	current_index = 0
	_velocity = 0.0
	_mouse_dragging = false
	_mouse_drag_recognized = false
	_cancel_snap()
	_last_positions.clear()
	_last_times.clear()
	scroll_changed.emit(scroll_offset)
