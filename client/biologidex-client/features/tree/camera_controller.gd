class_name TreeCameraController
extends Node

## Camera controller for tree visualization.
## Handles pan, zoom, and touch gestures with direct input response.
## Attach as child of Camera2D or reference camera via export.

signal view_changed(position: Vector2, zoom: float)

@export var camera: Camera2D

# Zoom configuration
@export_group("Zoom")
@export var min_zoom: float = 0.1
@export var max_zoom: float = 10.0
@export var zoom_step: float = 0.1
## Multiplier for pinch-to-zoom sensitivity (1.0 = normal)
@export var pinch_sensitivity: float = 1.0
## Multiplier for scroll wheel zoom sensitivity (1.0 = normal)
@export var scroll_sensitivity: float = 1.0

# Pan configuration
@export_group("Pan")
@export var drag_threshold: float = 10.0
## Multiplier for pan/drag sensitivity (1.0 = normal, >1 = faster)
@export var pan_sensitivity: float = 1.0

# Touch/mouse tracking
var _is_dragging: bool = false
var _drag_recognized: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _last_mouse_pos: Vector2 = Vector2.ZERO

# Multi-touch for pinch zoom
var _touches: Dictionary = {}  # {index: position}
var _pinch_base_distance: float = 0.0
var _pinch_base_zoom: float = 1.0
var _pinch_base_center: Vector2 = Vector2.ZERO


func _ready() -> void:
	if not camera:
		camera = get_parent() as Camera2D
	if not camera:
		push_error("[CameraController] No Camera2D found")
		return


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
				_zoom_at_point(event.position, 1.0 + zoom_step * scroll_sensitivity)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom_at_point(event.position, 1.0 - zoom_step * scroll_sensitivity)


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

	# Pan: move camera opposite to drag direction (direct, no smoothing)
	camera.position -= delta * pan_sensitivity / camera.zoom.x
	_emit_view_changed()
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
		# Direct pan (no smoothing)
		camera.position -= event.relative * pan_sensitivity / camera.zoom.x
		_emit_view_changed()
		get_viewport().set_input_as_handled()


func _start_drag(pos: Vector2) -> void:
	_is_dragging = true
	_drag_recognized = false
	_drag_start = pos
	_last_mouse_pos = pos


func _end_drag() -> void:
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
	_drag_recognized = true  # Pinch is always a gesture


func _process_pinch() -> void:
	var positions := _touches.values()
	if positions.size() < 2 or _pinch_base_distance < 10.0:
		return

	var p1: Vector2 = positions[0]
	var p2: Vector2 = positions[1]
	var current_distance := p1.distance_to(p2)
	var current_center := (p1 + p2) / 2.0

	# Apply pinch sensitivity: scale_factor deviates from 1.0 by (diff * sensitivity)
	var raw_scale := current_distance / _pinch_base_distance
	var scale_factor := 1.0 + (raw_scale - 1.0) * pinch_sensitivity
	var new_zoom := clampf(_pinch_base_zoom * scale_factor, min_zoom, max_zoom)

	# Zoom at pinch center (direct, no smoothing)
	var viewport_center := get_viewport().get_visible_rect().size / 2.0
	var screen_offset := current_center - viewport_center
	var world_point_before := camera.position + screen_offset / camera.zoom

	camera.zoom = Vector2(new_zoom, new_zoom)

	var world_point_after := camera.position + screen_offset / camera.zoom
	camera.position += world_point_before - world_point_after

	_emit_view_changed()
	get_viewport().set_input_as_handled()


func _zoom_at_point(screen_pos: Vector2, factor: float) -> void:
	var viewport_center := get_viewport().get_visible_rect().size / 2.0
	var screen_offset := screen_pos - viewport_center

	# Get world point under cursor before zoom
	var world_point_before := camera.position + screen_offset / camera.zoom

	# Apply zoom
	var new_zoom := clampf(camera.zoom.x * factor, min_zoom, max_zoom)
	camera.zoom = Vector2(new_zoom, new_zoom)

	# Get world point under cursor after zoom and adjust position
	var world_point_after := camera.position + screen_offset / camera.zoom
	camera.position += world_point_before - world_point_after

	_emit_view_changed()


func _emit_view_changed() -> void:
	view_changed.emit(camera.position, camera.zoom.x)


# =============================================================================
# Public API
# =============================================================================

func center_on(world_pos: Vector2, _animated: bool = true) -> void:
	"""Center camera on a world position."""
	camera.position = world_pos
	_emit_view_changed()


func set_zoom(new_zoom: float, _animated: bool = true) -> void:
	"""Set zoom level."""
	var clamped := clampf(new_zoom, min_zoom, max_zoom)
	camera.zoom = Vector2(clamped, clamped)
	_emit_view_changed()


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
	camera.position = Vector2.ZERO
	camera.zoom = Vector2(2.0, 2.0)
	_emit_view_changed()
