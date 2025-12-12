class_name PaperCameraScene
extends Node2D

## Unified Camera2D-based scene component with paper background.
## Provides pan/zoom/touch handling for all scenes.
## Instance this scene and add content to get_content_container() or get_ui_container().

# =============================================================================
# Camera Settings
# =============================================================================

@export_group("Camera")
@export var initial_zoom: float = 1.0
@export var min_zoom: float = 0.1
@export var max_zoom: float = 10.0
@export var zoom_enabled: bool = true
@export var pan_enabled: bool = true

# =============================================================================
# Touch Controller Settings
# =============================================================================

@export_group("Touch & Gestures")
@export var drag_threshold: float = 10.0
@export var pan_sensitivity: float = 1.0
@export var zoom_step: float = 0.1
@export var pinch_sensitivity: float = 1.0
@export var scroll_sensitivity: float = 1.0

# =============================================================================
# Inertia Settings
# =============================================================================

@export_group("Inertia")
@export var inertia_enabled: bool = false
@export var inertia_decay: float = 5.0
@export var inertia_stop_threshold: float = 1.0

# =============================================================================
# Scroll Limits (for bounded scrolling like feeds)
# =============================================================================

@export_group("Scroll Limits")
@export var scroll_limits_enabled: bool = false
@export var scroll_min: Vector2 = Vector2(-INF, -INF)
@export var scroll_max: Vector2 = Vector2(INF, INF)
@export var rubber_band_enabled: bool = true
@export var rubber_band_factor: float = 0.3
@export var rubber_band_max: float = 100.0
@export var snap_back_lerp: float = 0.15

# =============================================================================
# Paper Appearance
# =============================================================================

@export_group("Paper Grid")
@export_range(8.0, 64.0, 0.5) var grid_scale: float = 22.0:
	set(value):
		grid_scale = value
		_update_shader_param("grid_scale", value)

@export_range(0.5, 3.0, 0.1) var grid_line_px: float = 0.5:
	set(value):
		grid_line_px = value
		_update_shader_param("line_px", value)

@export var grid_line_color: Color = Color(0.55, 0.53, 0.5, 1.0):
	set(value):
		grid_line_color = value
		_update_shader_param("line_color", Vector4(value.r, value.g, value.b, 1.0))

@export_range(0.0, 0.6, 0.01) var grid_line_alpha: float = 0.07:
	set(value):
		grid_line_alpha = value
		_update_shader_param("line_alpha", value)

@export_group("Paper Base")
@export var paper_color: Color = Color(0.85, 0.82, 0.78, 1.0):
	set(value):
		paper_color = value
		_update_shader_param("paper_color", Vector4(value.r, value.g, value.b, 1.0))

@export_range(0.0, 0.15, 0.001) var paper_noise_amount: float = 0.05:
	set(value):
		paper_noise_amount = value
		_update_shader_param("paper_noise_amount", value)

@export_range(0.05, 1.5, 0.01) var paper_noise_scale: float = 0.35:
	set(value):
		paper_noise_scale = value
		_update_shader_param("paper_noise_scale", value)

@export_group("Paper Speckles")
@export_range(0.0, 0.30, 0.001) var speckle_amount: float = 0.064:
	set(value):
		speckle_amount = value
		_update_shader_param("speckle_amount", value)

@export_range(0.25, 3.0, 0.01) var speckle_density: float = 1.68:
	set(value):
		speckle_density = value
		_update_shader_param("speckle_density", value)

@export_range(0.5, 6.0, 0.01) var speckle_scale: float = 6.0:
	set(value):
		speckle_scale = value
		_update_shader_param("speckle_scale", value)

@export_group("Paper Fibers")
@export_range(0.0, 0.20, 0.001) var fiber_amount: float = 0.111:
	set(value):
		fiber_amount = value
		_update_shader_param("fiber_amount", value)

@export_range(0.2, 4.0, 0.01) var fiber_scale: float = 0.57:
	set(value):
		fiber_scale = value
		_update_shader_param("fiber_scale", value)

# =============================================================================
# Node References - using explicit paths due to web export unique name issues
# =============================================================================

@onready var camera: Camera2D = $Camera2D
@onready var camera_controller: CameraTouchController = $Camera2D/CameraController
@onready var world_content: Node2D = $WorldContent
@onready var paper_background: Polygon2D = $WorldContent/PaperBackground
@onready var content_container: Node2D = $WorldContent/ContentContainer
@onready var ui_container: Control = $UILayer/UIContainer

# =============================================================================
# Signals
# =============================================================================

signal view_changed(position: Vector2, zoom: float)
signal tap_detected(world_position: Vector2)
signal gesture_started()
signal gesture_ended()


func _ready() -> void:
	# Configure camera controller
	camera_controller.camera = camera
	camera_controller.min_zoom = min_zoom if zoom_enabled else 1.0
	camera_controller.max_zoom = max_zoom if zoom_enabled else 1.0
	camera_controller.drag_threshold = drag_threshold
	camera_controller.pan_sensitivity = pan_sensitivity
	camera_controller.zoom_step = zoom_step
	camera_controller.pinch_sensitivity = pinch_sensitivity
	camera_controller.scroll_sensitivity = scroll_sensitivity
	camera_controller.inertia_enabled = inertia_enabled
	camera_controller.inertia_decay = inertia_decay
	camera_controller.inertia_stop_threshold = inertia_stop_threshold
	camera_controller.scroll_limits_enabled = scroll_limits_enabled
	camera_controller.scroll_min = scroll_min
	camera_controller.scroll_max = scroll_max
	camera_controller.rubber_band_enabled = rubber_band_enabled
	camera_controller.rubber_band_factor = rubber_band_factor
	camera_controller.rubber_band_max = rubber_band_max
	camera_controller.snap_back_lerp = snap_back_lerp
	camera_controller.pan_enabled = pan_enabled
	camera_controller.zoom_enabled = zoom_enabled

	# Connect controller signals
	camera_controller.view_changed.connect(_on_view_changed)
	camera_controller.tap_detected.connect(_on_tap_detected)
	camera_controller.gesture_started.connect(func(): gesture_started.emit())
	camera_controller.gesture_ended.connect(func(): gesture_ended.emit())

	# Set initial zoom
	camera.zoom = Vector2(initial_zoom, initial_zoom)

	# Sync shader parameters
	_sync_all_shader_params()


func _on_view_changed(pos: Vector2, zoom: float) -> void:
	view_changed.emit(pos, zoom)


func _on_tap_detected(screen_pos: Vector2) -> void:
	# Convert screen position to world position
	var viewport_center := get_viewport_rect().size / 2.0
	var world_pos := (screen_pos - viewport_center) / camera.zoom.x + camera.position
	tap_detected.emit(world_pos)


func _sync_all_shader_params() -> void:
	var mat := paper_background.material as ShaderMaterial
	if not mat:
		return

	mat.set_shader_parameter("grid_scale", grid_scale)
	mat.set_shader_parameter("line_px", grid_line_px)
	mat.set_shader_parameter("line_color", Vector4(grid_line_color.r, grid_line_color.g, grid_line_color.b, 1.0))
	mat.set_shader_parameter("line_alpha", grid_line_alpha)
	mat.set_shader_parameter("paper_color", Vector4(paper_color.r, paper_color.g, paper_color.b, 1.0))
	mat.set_shader_parameter("paper_noise_amount", paper_noise_amount)
	mat.set_shader_parameter("paper_noise_scale", paper_noise_scale)
	mat.set_shader_parameter("speckle_amount", speckle_amount)
	mat.set_shader_parameter("speckle_density", speckle_density)
	mat.set_shader_parameter("speckle_scale", speckle_scale)
	mat.set_shader_parameter("fiber_amount", fiber_amount)
	mat.set_shader_parameter("fiber_scale", fiber_scale)


func _update_shader_param(param: String, value: Variant) -> void:
	if not is_inside_tree() or not paper_background:
		return
	var mat := paper_background.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter(param, value)


# =============================================================================
# Public API
# =============================================================================

func center_on(world_pos: Vector2, animated: bool = false) -> void:
	if animated:
		var tween := create_tween()
		tween.tween_property(camera, "position", world_pos, 0.3).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func(): view_changed.emit(camera.position, camera.zoom.x))
	else:
		camera.position = world_pos
		view_changed.emit(camera.position, camera.zoom.x)


func set_zoom(new_zoom: float, animated: bool = false) -> void:
	var clamped := clampf(new_zoom, min_zoom, max_zoom)
	if animated:
		var tween := create_tween()
		tween.tween_property(camera, "zoom", Vector2(clamped, clamped), 0.3).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func(): view_changed.emit(camera.position, camera.zoom.x))
	else:
		camera.zoom = Vector2(clamped, clamped)
		view_changed.emit(camera.position, camera.zoom.x)


func get_current_zoom() -> float:
	return camera.zoom.x


func get_zoom() -> float:
	return camera.zoom.x


func get_camera_position() -> Vector2:
	return camera.position


func get_view_rect() -> Rect2:
	if not is_inside_tree():
		return Rect2()
	var viewport_size := get_viewport_rect().size
	var half_size := viewport_size / (2.0 * camera.zoom.x)
	return Rect2(camera.position - half_size, half_size * 2.0)


func scroll_to(offset: Vector2, animated: bool = false) -> void:
	center_on(offset, animated)


func reset() -> void:
	camera.position = Vector2.ZERO
	camera.zoom = Vector2(initial_zoom, initial_zoom)
	view_changed.emit(camera.position, camera.zoom.x)


func get_content_container() -> Node2D:
	return content_container


func get_ui_container() -> Control:
	return ui_container


func set_scroll_limits(min_val: Vector2, max_val: Vector2) -> void:
	scroll_min = min_val
	scroll_max = max_val
	camera_controller.scroll_min = min_val
	camera_controller.scroll_max = max_val
	camera_controller.scroll_limits_enabled = true
	scroll_limits_enabled = true
