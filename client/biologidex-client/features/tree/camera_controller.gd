class_name TreeCameraController
extends Node

## Camera controller for tree visualization.
## Handles pan, zoom, touch gestures, and smooth animations.
## Attach as child of Camera2D or reference camera via export.

signal view_changed(position: Vector2, zoom: float)

@export var camera: Camera2D

# Zoom configuration
@export_group("Zoom")
@export var min_zoom: float = 0.1
@export var max_zoom: float = 10.0
@export var zoom_step: float = 0.1
@export var zoom_smoothing: float = 0.15

# Pan configuration
@export_group("Pan")
@export var pan_smoothing: float = 0.15
@export var drag_threshold: float = 10.0

# Inertia configuration
@export_group("Inertia")
@export var inertia_enabled: bool = true
@export var inertia_decay: float = 5.0
@export var inertia_stop_threshold: float = 1.0

# Goal state (where we want to be)
var _position_goal: Vector2 = Vector2.ZERO
var _zoom_goal: Vector2 = Vector2.ONE

# SmoothDamp state
var _position_velocity: Vector2 = Vector2.ZERO
var _zoom_velocity: Vector2 = Vector2.ZERO

# Touch/mouse tracking
var _is_dragging: bool = false
var _drag_recognized: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _zoom_focus_point: Vector2 = Vector2.ZERO

# Multi-touch for pinch zoom
var _touches: Dictionary = {}  # {index: position}
var _pinch_base_distance: float = 0.0
var _pinch_base_zoom: float = 1.0

# Velocity tracking for inertia
var _velocity_samples: Array[Vector2] = []
var _velocity_times: Array[float] = []
var _velocity: Vector2 = Vector2.ZERO
const VELOCITY_SAMPLE_COUNT: int = 5
const VELOCITY_MAX_AGE: float = 0.1


func _ready() -> void:
	if not camera:
		camera = get_parent() as Camera2D
	if not camera:
		push_error("[CameraController] No Camera2D found")
		return

	_position_goal = camera.position
	_zoom_goal = camera.zoom


func _process(delta: float) -> void:
	if not camera:
		return

	var old_position := camera.position
	var old_zoom := camera.zoom

	# Smooth zoom with cursor-centric adjustment
	var pre_zoom_world := _screen_to_world(_zoom_focus_point)
	camera.zoom = _smooth_damp_vec2(camera.zoom, _zoom_goal, _zoom_velocity, zoom_smoothing, delta)
	var post_zoom_world := _screen_to_world(_zoom_focus_point)

	# Adjust position to keep zoom focus point stationary
	var zoom_offset := pre_zoom_world - post_zoom_world
	_position_goal += zoom_offset

	# Apply inertia when not dragging
	if not _is_dragging and inertia_enabled:
		if _velocity.length() > inertia_stop_threshold:
			_position_goal -= _velocity * delta
			_velocity = _velocity.move_toward(Vector2.ZERO, _velocity.length() * inertia_decay * delta)
		else:
			_velocity = Vector2.ZERO

	# Smooth pan
	camera.position = _smooth_damp_vec2(camera.position, _position_goal, _position_velocity, pan_smoothing, delta)

	# Emit signal if view changed
	if camera.position != old_position or camera.zoom != old_zoom:
		view_changed.emit(camera.position, camera.zoom.x)


func _input(event: InputEvent) -> void:
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
			else:
				_end_drag()
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom_at_point(event.position, 1.0 + zoom_step)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom_at_point(event.position, 1.0 - zoom_step)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _is_dragging:
		return

	var distance := event.position.distance_to(_drag_start)
	if not _drag_recognized and distance >= drag_threshold:
		_drag_recognized = true

	if not _drag_recognized:
		return

	var delta := event.position - _last_mouse_pos
	_last_mouse_pos = event.position

	# Record for velocity calculation
	_record_velocity_sample(event.position)

	# Pan: move camera opposite to drag direction
	_position_goal -= delta / camera.zoom.x
	get_viewport().set_input_as_handled()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_start_drag(event.position)
		elif _touches.size() == 2:
			_start_pinch()
	else:
		_touches.erase(event.index)
		if _touches.size() < 2:
			_pinch_base_distance = 0.0
		if _touches.is_empty():
			_end_drag()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return

	_touches[event.index] = event.position

	if _touches.size() >= 2:
		_process_pinch()
	elif _touches.size() == 1 and _drag_recognized:
		_record_velocity_sample(event.position)
		_position_goal -= event.relative / camera.zoom.x
		get_viewport().set_input_as_handled()


func _start_drag(pos: Vector2) -> void:
	_is_dragging = true
	_drag_recognized = false
	_drag_start = pos
	_last_mouse_pos = pos
	_velocity = Vector2.ZERO
	_velocity_samples.clear()
	_velocity_times.clear()


func _end_drag() -> void:
	if _drag_recognized:
		_calculate_velocity()
	_is_dragging = false
	_drag_recognized = false


func _start_pinch() -> void:
	var positions := _touches.values()
	if positions.size() < 2:
		return
	_pinch_base_distance = (positions[0] as Vector2).distance_to(positions[1] as Vector2)
	_pinch_base_zoom = camera.zoom.x
	_drag_recognized = true  # Pinch is always a gesture


func _process_pinch() -> void:
	var positions := _touches.values()
	if positions.size() < 2 or _pinch_base_distance < 10.0:
		return

	var p1: Vector2 = positions[0]
	var p2: Vector2 = positions[1]
	var current_distance := p1.distance_to(p2)
	var center := (p1 + p2) / 2.0

	var scale_factor := current_distance / _pinch_base_distance
	var new_zoom := clampf(_pinch_base_zoom * scale_factor, min_zoom, max_zoom)

	_zoom_focus_point = center - get_viewport().get_visible_rect().size / 2.0
	_zoom_goal = Vector2(new_zoom, new_zoom)

	get_viewport().set_input_as_handled()


func _zoom_at_point(screen_pos: Vector2, factor: float) -> void:
	_zoom_focus_point = screen_pos - get_viewport().get_visible_rect().size / 2.0
	var new_zoom := clampf(camera.zoom.x * factor, min_zoom, max_zoom)
	_zoom_goal = Vector2(new_zoom, new_zoom)


func _screen_to_world(screen_offset: Vector2) -> Vector2:
	"""Convert screen offset (relative to center) to world position."""
	return camera.position + screen_offset / camera.zoom


func _record_velocity_sample(pos: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_velocity_samples.append(pos)
	_velocity_times.append(now)
	while _velocity_samples.size() > VELOCITY_SAMPLE_COUNT:
		_velocity_samples.pop_front()
		_velocity_times.pop_front()


func _calculate_velocity() -> void:
	if _velocity_samples.size() < 2:
		_velocity = Vector2.ZERO
		return

	var now := Time.get_ticks_msec() / 1000.0
	var oldest_idx := 0
	for i in range(_velocity_times.size()):
		if now - _velocity_times[i] <= VELOCITY_MAX_AGE:
			oldest_idx = i
			break

	if oldest_idx >= _velocity_samples.size() - 1:
		_velocity = Vector2.ZERO
		return

	var time_delta := _velocity_times[-1] - _velocity_times[oldest_idx]
	if time_delta < 0.001:
		_velocity = Vector2.ZERO
		return

	# Velocity in screen space, will be applied opposite to pan direction
	_velocity = (_velocity_samples[-1] - _velocity_samples[oldest_idx]) / time_delta / camera.zoom.x


func _smooth_damp_vec2(current: Vector2, target: Vector2, velocity: Vector2, smooth_time: float, delta: float) -> Vector2:
	"""Unity-style SmoothDamp for buttery smooth motion."""
	if smooth_time <= 0.0:
		return target

	var omega := 2.0 / smooth_time
	var x := omega * delta
	var exp_factor := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)

	var change := current - target
	var temp := (velocity + omega * change) * delta
	velocity = (velocity - omega * temp) * exp_factor
	return target + (change + temp) * exp_factor


# =============================================================================
# Public API
# =============================================================================

func center_on(world_pos: Vector2, animated: bool = true) -> void:
	"""Center camera on a world position."""
	if animated:
		_position_goal = world_pos
	else:
		_position_goal = world_pos
		camera.position = world_pos
		_position_velocity = Vector2.ZERO


func set_zoom(new_zoom: float, animated: bool = true) -> void:
	"""Set zoom level."""
	var clamped := clampf(new_zoom, min_zoom, max_zoom)
	if animated:
		_zoom_goal = Vector2(clamped, clamped)
	else:
		_zoom_goal = Vector2(clamped, clamped)
		camera.zoom = _zoom_goal
		_zoom_velocity = Vector2.ZERO


func get_current_zoom() -> float:
	return camera.zoom.x if camera else 1.0


func get_view_rect() -> Rect2:
	"""Get current view rectangle in world coordinates."""
	if not camera:
		return Rect2()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var half_size: Vector2 = viewport_size / (2.0 * camera.zoom.x)
	return Rect2(camera.position - half_size, half_size * 2.0)


func reset() -> void:
	"""Reset camera to default state."""
	_position_goal = Vector2.ZERO
	_zoom_goal = Vector2(2.0, 2.0)
	_velocity = Vector2.ZERO
	if camera:
		camera.position = Vector2.ZERO
		camera.zoom = Vector2(2.0, 2.0)
	_position_velocity = Vector2.ZERO
	_zoom_velocity = Vector2.ZERO
