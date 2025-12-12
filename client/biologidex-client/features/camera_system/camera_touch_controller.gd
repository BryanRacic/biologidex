class_name CameraTouchController
extends Node

## Unified touch/mouse controller for Camera2D-based scenes.
## Supports both infinite canvas and bounded scroll modes.
## Merges features from BackgroundTouchController and TreeCameraController.

signal view_changed(position: Vector2, zoom: float)
signal tap_detected(screen_position: Vector2)
signal gesture_started()
signal gesture_ended()

# Camera reference (set by parent)
@export var camera: Camera2D

# Feature toggles
var pan_enabled: bool = true
var zoom_enabled: bool = true

# Zoom configuration
var min_zoom: float = 0.1
var max_zoom: float = 10.0
var zoom_step: float = 0.1
var pinch_sensitivity: float = 1.0
var scroll_sensitivity: float = 1.0

# Pan configuration
var drag_threshold: float = 10.0
var pan_sensitivity: float = 1.0

# Inertia
var inertia_enabled: bool = false
var inertia_decay: float = 5.0
var inertia_stop_threshold: float = 1.0
var _velocity: Vector2 = Vector2.ZERO
var _last_positions: Array[Vector2] = []
var _last_times: Array[float] = []
const VELOCITY_SAMPLES: int = 5
const VELOCITY_MAX_AGE: float = 0.1

# Scroll limits (for bounded modes like feeds)
var scroll_limits_enabled: bool = false
var scroll_min: Vector2 = Vector2(-INF, -INF)
var scroll_max: Vector2 = Vector2(INF, INF)
var rubber_band_enabled: bool = true
var rubber_band_factor: float = 0.3
var rubber_band_max: float = 100.0
var snap_back_lerp: float = 0.15

# Touch/mouse tracking
var _is_dragging: bool = false
var _drag_recognized: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _last_mouse_pos: Vector2 = Vector2.ZERO

# Multi-touch for pinch zoom
var _touches: Dictionary = {}
var _pinch_base_distance: float = 0.0
var _pinch_base_zoom: float = 1.0
var _pinch_base_center: Vector2 = Vector2.ZERO
var _pinch_base_camera_pos: Vector2 = Vector2.ZERO


func _input(event: InputEvent) -> void:
	if not camera:
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag(event.position)
				gesture_started.emit()
			else:
				var was_drag := _drag_recognized
				_end_drag()
				if not was_drag:
					tap_detected.emit(event.position)
				gesture_ended.emit()
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed and zoom_enabled:
				_zoom_at_point(event.position, 1.0 + zoom_step * scroll_sensitivity)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed and zoom_enabled:
				_zoom_at_point(event.position, 1.0 - zoom_step * scroll_sensitivity)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _is_dragging or not pan_enabled:
		return

	var distance := event.position.distance_to(_drag_start)
	if not _drag_recognized and distance >= drag_threshold:
		_drag_recognized = true
		_stop_inertia()

	if not _drag_recognized:
		return

	var delta := event.position - _last_mouse_pos
	_last_mouse_pos = event.position

	# Record for inertia
	_record_position_sample(event.position)

	# Apply pan (with limits if enabled)
	_apply_pan_delta(-delta * pan_sensitivity / camera.zoom.x)
	get_viewport().set_input_as_handled()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_start_drag(event.position)
			gesture_started.emit()
		elif _touches.size() == 2 and zoom_enabled:
			_start_pinch()
	else:
		_touches.erase(event.index)
		if _touches.size() < 2:
			_pinch_base_distance = 0.0
		if _touches.is_empty():
			var was_drag := _drag_recognized
			_end_drag()
			if not was_drag:
				tap_detected.emit(event.position)
			gesture_ended.emit()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return

	_touches[event.index] = event.position

	if _touches.size() >= 2 and zoom_enabled:
		_process_pinch()
	elif _touches.size() == 1:
		# Check threshold for single-finger drag
		var distance := event.position.distance_to(_drag_start)
		if not _drag_recognized and distance >= drag_threshold:
			_drag_recognized = true
			_stop_inertia()

		if _drag_recognized and pan_enabled:
			_record_position_sample(event.position)
			_apply_pan_delta(-event.relative * pan_sensitivity / camera.zoom.x)
			get_viewport().set_input_as_handled()


func _start_drag(pos: Vector2) -> void:
	_is_dragging = true
	_drag_recognized = false
	_drag_start = pos
	_last_mouse_pos = pos


func _end_drag() -> void:
	if _drag_recognized and inertia_enabled:
		_start_inertia()
	_is_dragging = false
	_drag_recognized = false


func _start_pinch() -> void:
	var positions := _touches.values()
	if positions.size() < 2:
		return
	var p1: Vector2 = positions[0]
	var p2: Vector2 = positions[1]
	_pinch_base_distance = p1.distance_to(p2)
	_pinch_base_zoom = camera.zoom.x
	_pinch_base_center = (p1 + p2) / 2.0
	_pinch_base_camera_pos = camera.position
	_drag_recognized = true


func _process_pinch() -> void:
	var positions := _touches.values()
	if positions.size() < 2 or _pinch_base_distance < 10.0:
		return

	var p1: Vector2 = positions[0]
	var p2: Vector2 = positions[1]
	var current_distance := p1.distance_to(p2)
	var current_center := (p1 + p2) / 2.0

	# Calculate zoom
	var raw_scale := current_distance / _pinch_base_distance
	var scale_factor := 1.0 + (raw_scale - 1.0) * pinch_sensitivity
	var new_zoom := clampf(_pinch_base_zoom * scale_factor, min_zoom, max_zoom)

	# Apply zoom at pinch center (cursor-centric)
	var viewport_center := get_viewport().get_visible_rect().size / 2.0
	var screen_offset := current_center - viewport_center
	var world_before := _pinch_base_camera_pos + screen_offset / _pinch_base_zoom

	camera.zoom = Vector2(new_zoom, new_zoom)

	var world_after := camera.position + screen_offset / camera.zoom.x

	# Also handle pan from pinch center movement
	var center_delta := current_center - _pinch_base_center
	var pan_world := -center_delta / camera.zoom.x

	camera.position = world_before - screen_offset / camera.zoom.x + pan_world

	_emit_view_changed()
	get_viewport().set_input_as_handled()


func _zoom_at_point(screen_pos: Vector2, factor: float) -> void:
	var viewport_center := get_viewport().get_visible_rect().size / 2.0
	var screen_offset := screen_pos - viewport_center

	var world_before := camera.position + screen_offset / camera.zoom

	var new_zoom := clampf(camera.zoom.x * factor, min_zoom, max_zoom)
	camera.zoom = Vector2(new_zoom, new_zoom)

	var world_after := camera.position + screen_offset / camera.zoom
	camera.position += world_before - world_after

	_emit_view_changed()


func _apply_pan_delta(world_delta: Vector2) -> void:
	var new_pos := camera.position + world_delta

	if scroll_limits_enabled:
		if rubber_band_enabled:
			# Apply rubber-banding at limits
			if is_finite(scroll_min.x) and new_pos.x < scroll_min.x:
				new_pos.x = camera.position.x + world_delta.x * rubber_band_factor
				new_pos.x = maxf(new_pos.x, scroll_min.x - rubber_band_max / camera.zoom.x)
			elif is_finite(scroll_max.x) and new_pos.x > scroll_max.x:
				new_pos.x = camera.position.x + world_delta.x * rubber_band_factor
				new_pos.x = minf(new_pos.x, scroll_max.x + rubber_band_max / camera.zoom.x)

			if is_finite(scroll_min.y) and new_pos.y < scroll_min.y:
				new_pos.y = camera.position.y + world_delta.y * rubber_band_factor
				new_pos.y = maxf(new_pos.y, scroll_min.y - rubber_band_max / camera.zoom.x)
			elif is_finite(scroll_max.y) and new_pos.y > scroll_max.y:
				new_pos.y = camera.position.y + world_delta.y * rubber_band_factor
				new_pos.y = minf(new_pos.y, scroll_max.y + rubber_band_max / camera.zoom.x)
		else:
			# Hard clamp
			if is_finite(scroll_min.x):
				new_pos.x = maxf(new_pos.x, scroll_min.x)
			if is_finite(scroll_max.x):
				new_pos.x = minf(new_pos.x, scroll_max.x)
			if is_finite(scroll_min.y):
				new_pos.y = maxf(new_pos.y, scroll_min.y)
			if is_finite(scroll_max.y):
				new_pos.y = minf(new_pos.y, scroll_max.y)

	camera.position = new_pos
	_emit_view_changed()


func _process(delta: float) -> void:
	if not camera:
		return

	# Apply inertia
	if _touches.is_empty() and not _is_dragging:
		if inertia_enabled and _velocity.length() > inertia_stop_threshold:
			_apply_pan_delta(-_velocity * delta / camera.zoom.x)
			_velocity = _velocity.move_toward(Vector2.ZERO, _velocity.length() * inertia_decay * delta)
		elif scroll_limits_enabled and _is_overscrolled():
			_snap_back()
		else:
			_velocity = Vector2.ZERO


func _is_overscrolled() -> bool:
	if not scroll_limits_enabled:
		return false
	if is_finite(scroll_min.x) and camera.position.x < scroll_min.x:
		return true
	if is_finite(scroll_max.x) and camera.position.x > scroll_max.x:
		return true
	if is_finite(scroll_min.y) and camera.position.y < scroll_min.y:
		return true
	if is_finite(scroll_max.y) and camera.position.y > scroll_max.y:
		return true
	return false


func _snap_back() -> void:
	var target := camera.position

	if is_finite(scroll_min.x) and camera.position.x < scroll_min.x:
		target.x = scroll_min.x
	elif is_finite(scroll_max.x) and camera.position.x > scroll_max.x:
		target.x = scroll_max.x

	if is_finite(scroll_min.y) and camera.position.y < scroll_min.y:
		target.y = scroll_min.y
	elif is_finite(scroll_max.y) and camera.position.y > scroll_max.y:
		target.y = scroll_max.y

	if target != camera.position:
		camera.position = camera.position.lerp(target, snap_back_lerp)
		if camera.position.distance_to(target) < 1.0:
			camera.position = target
		_emit_view_changed()


func _record_position_sample(pos: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_last_positions.append(pos)
	_last_times.append(now)
	while _last_positions.size() > VELOCITY_SAMPLES:
		_last_positions.pop_front()
		_last_times.pop_front()


func _calculate_velocity() -> Vector2:
	if _last_positions.size() < 2:
		return Vector2.ZERO

	var now := Time.get_ticks_msec() / 1000.0
	var oldest_idx := 0
	for i in range(_last_times.size()):
		if now - _last_times[i] <= VELOCITY_MAX_AGE:
			oldest_idx = i
			break

	if oldest_idx >= _last_positions.size() - 1:
		return Vector2.ZERO

	var oldest := _last_positions[oldest_idx]
	var newest := _last_positions[-1]
	var dt := _last_times[-1] - _last_times[oldest_idx]

	if dt < 0.001:
		return Vector2.ZERO

	return (newest - oldest) / dt


func _start_inertia() -> void:
	_velocity = _calculate_velocity()
	_last_positions.clear()
	_last_times.clear()


func _stop_inertia() -> void:
	_velocity = Vector2.ZERO
	_last_positions.clear()
	_last_times.clear()


func _emit_view_changed() -> void:
	view_changed.emit(camera.position, camera.zoom.x)


# =============================================================================
# Public API
# =============================================================================

func center_on(world_pos: Vector2) -> void:
	camera.position = world_pos
	_emit_view_changed()


func set_zoom(new_zoom: float) -> void:
	var clamped := clampf(new_zoom, min_zoom, max_zoom)
	camera.zoom = Vector2(clamped, clamped)
	_emit_view_changed()


func get_current_zoom() -> float:
	return camera.zoom.x if camera else 1.0


func get_view_rect() -> Rect2:
	if not camera:
		return Rect2()
	var viewport_size := get_viewport().get_visible_rect().size
	var half_size := viewport_size / (2.0 * camera.zoom.x)
	return Rect2(camera.position - half_size, half_size * 2.0)


func reset() -> void:
	camera.position = Vector2.ZERO
	camera.zoom = Vector2(1.0, 1.0)
	_velocity = Vector2.ZERO
	_emit_view_changed()
