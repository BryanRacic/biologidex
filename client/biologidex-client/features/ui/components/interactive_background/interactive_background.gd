class_name InteractiveBackground
extends Control

## Reusable interactive paper background component with pan/zoom support.
## Self-contained: just instance this scene, no additional wiring needed.
## Uses BackgroundTouchController for gesture handling.

@onready var background: ColorRect = $Background
@onready var touch_controller: BackgroundTouchController = $TouchController

var _shader_material: ShaderMaterial


func _ready() -> void:
	# Get shader material from background
	_shader_material = background.material as ShaderMaterial

	if not _shader_material:
		push_error("[InteractiveBackground] Background must have a ShaderMaterial")
		return

	# Connect touch controller signals to update shader
	touch_controller.scroll_changed.connect(_on_scroll_changed)
	touch_controller.scale_changed.connect(_on_scale_changed)

	# Initialize viewport size for shader
	# Set immediately with current value, then verify after first frame
	_update_viewport_size()
	await get_tree().process_frame
	_update_viewport_size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_viewport_size()


func _update_viewport_size() -> void:
	"""Update shader with current viewport dimensions for world-space coordinate conversion."""
	if _shader_material:
		_shader_material.set_shader_parameter("viewport_size", get_viewport_rect().size)


func _on_scroll_changed(offset: Vector2) -> void:
	_shader_material.set_shader_parameter("scroll", offset)
	print("[InteractiveBackground] scroll=%s" % offset)


func _on_scale_changed(new_scale: float) -> void:
	_shader_material.set_shader_parameter("scale", new_scale)
	print("[InteractiveBackground] scale=%.2f" % new_scale)


func _update_viewport_size() -> void:
	"""Update shader with current viewport dimensions for world-space coordinate conversion."""
	if _shader_material:
		var vp_size = get_viewport_rect().size
		_shader_material.set_shader_parameter("viewport_size", vp_size)
		print("[InteractiveBackground] viewport_size=%s" % vp_size)


func reset() -> void:
	"""Reset scroll and scale to defaults."""
	touch_controller.reset()
