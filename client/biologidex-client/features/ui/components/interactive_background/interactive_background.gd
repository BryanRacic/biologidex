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


func _on_scroll_changed(offset: Vector2) -> void:
	_shader_material.set_shader_parameter("scroll", offset)


func _on_scale_changed(new_scale: float) -> void:
	_shader_material.set_shader_parameter("scale", new_scale)


func reset() -> void:
	"""Reset scroll and scale to defaults."""
	touch_controller.reset()
