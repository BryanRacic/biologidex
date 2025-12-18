extends Button
class_name RecenterButton

## RecenterButton - Button that appears when camera is off-center.
##
## Connect to a PaperCameraScene and this button will automatically show/hide
## based on the camera's distance from the center position.

## Signal emitted when user presses the button to recenter
signal recenter_requested()

## Distance threshold (in world units) - considered "centered" if within this distance
@export var center_threshold: float = 100.0

## Target center position in world space
@export var center_position: Vector2 = Vector2.ZERO

## Duration of fade animation in seconds
@export var fade_duration: float = 0.2

## The connected camera
var _camera: PaperCameraScene = null

## Current visibility state
var _is_showing: bool = false

## Active tween for fade animation
var _fade_tween: Tween = null


func _ready() -> void:
	# Start hidden
	visible = false
	modulate.a = 0.0

	# Connect button press
	pressed.connect(_on_pressed)


## Connect to a PaperCameraScene to track view changes
func connect_to_camera(camera: PaperCameraScene) -> void:
	if _camera and _camera.view_changed.is_connected(_on_view_changed):
		_camera.view_changed.disconnect(_on_view_changed)

	_camera = camera
	if _camera:
		_camera.view_changed.connect(_on_view_changed)
		# Check initial state
		_update_visibility(_camera.get_camera_position())


## Disconnect from camera
func disconnect_from_camera() -> void:
	if _camera and _camera.view_changed.is_connected(_on_view_changed):
		_camera.view_changed.disconnect(_on_view_changed)
	_camera = null


## Set the center position to recenter to
func set_center_position(pos: Vector2) -> void:
	center_position = pos
	if _camera:
		_update_visibility(_camera.get_camera_position())


## Check if the camera is currently considered centered
func is_centered() -> bool:
	if not _camera:
		return true
	return _camera.get_camera_position().distance_to(center_position) <= center_threshold


## Get the connected camera
func get_connected_camera() -> PaperCameraScene:
	return _camera


func _on_view_changed(camera_pos: Vector2, _zoom: float) -> void:
	_update_visibility(camera_pos)


func _update_visibility(camera_pos: Vector2) -> void:
	var distance := camera_pos.distance_to(center_position)
	var should_show := distance > center_threshold

	if should_show != _is_showing:
		_animate_visibility(should_show)


func _animate_visibility(should_show: bool) -> void:
	_is_showing = should_show

	# Cancel any existing tween
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

	_fade_tween = create_tween()

	if should_show:
		visible = true
		_fade_tween.tween_property(self, "modulate:a", 1.0, fade_duration)
	else:
		_fade_tween.tween_property(self, "modulate:a", 0.0, fade_duration)
		_fade_tween.tween_callback(func(): visible = false)


func _on_pressed() -> void:
	recenter_requested.emit()


func _exit_tree() -> void:
	disconnect_from_camera()