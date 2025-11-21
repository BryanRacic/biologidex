class_name ImageViewer extends Control

## Reusable image viewer component
## Handles image display with rotation, zoom, and loading states

signal image_rotated(degrees: int)
signal zoom_changed(zoom_level: float)
signal image_clicked()

# Configuration
@export var enable_rotation: bool = true
@export var enable_zoom: bool = false
@export var show_controls: bool = true
@export var maintain_aspect_ratio: bool = true
@export var border_width: int = 2
@export var border_color: Color = Color.WHITE

# UI elements
@onready var _image_container: AspectRatioContainer = $AspectRatioContainer
@onready var _border_panel: Panel = $AspectRatioContainer/BorderPanel
@onready var _image_texture: TextureRect = $AspectRatioContainer/BorderPanel/MarginContainer/ImageTexture
@onready var _loading_overlay: Control = $LoadingOverlay
@onready var _rotate_button: Button = $ControlsContainer/RotateButton

# Private variables
var _current_texture: Texture2D = null
var _rotation_angle: int = 0
var _zoom_level: float = 1.0
var _image: Image = null

func _ready() -> void:
	# Configure image texture
	if _image_texture != null:
		_image_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_image_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# Configure controls
	if _rotate_button != null:
		_rotate_button.pressed.connect(_on_rotate_pressed)
		_rotate_button.visible = show_controls and enable_rotation

	# Configure border
	if _border_panel != null:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.border_width_left = border_width
		style.border_width_right = border_width
		style.border_width_top = border_width
		style.border_width_bottom = border_width
		style.border_color = border_color
		style.bg_color = Color.TRANSPARENT
		_border_panel.add_theme_stylebox_override("panel", style)

	# Hide loading overlay initially
	if _loading_overlay != null:
		_loading_overlay.visible = false

## Set image from texture
func set_texture(texture: Texture2D) -> void:
	_current_texture = texture

	if _image_texture != null:
		_image_texture.texture = texture

	if _loading_overlay != null:
		_loading_overlay.visible = false

	# Update aspect ratio
	if maintain_aspect_ratio and texture != null and _image_container != null:
		var size: Vector2 = texture.get_size()
		if size.y > 0:
			_image_container.ratio = size.x / size.y

## Set image from Image object
func set_image(image: Image) -> void:
	if image == null:
		clear_image()
		return

	_image = image
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	set_texture(texture)

## Load image from URL
func load_image_from_url(url: String, loader: ImageLoader = null) -> void:
	show_loading()

	if loader != null:
		# Use provided loader
		loader.image_loaded.connect(_on_image_loaded, CONNECT_ONE_SHOT)
		loader.image_load_failed.connect(_on_image_load_failed, CONNECT_ONE_SHOT)
		loader.load_image(url, url, true)
	else:
		# Load directly
		var http_request: HTTPRequest = HTTPRequest.new()
		add_child(http_request)
		http_request.request_completed.connect(_on_direct_load_completed.bind(http_request))
		http_request.request(url)

## Load image from file path
func load_image_from_file(file_path: String) -> void:
	show_loading()

	var image: Image = ImageProcessor.load_image(file_path)
	if image != null:
		set_image(image)
	else:
		_on_image_load_failed(file_path, "Failed to load image")

## Rotate image by 90 degrees clockwise
func rotate_image(degrees: int = 90) -> void:
	if not enable_rotation:
		return

	if _image == null and _current_texture != null:
		_image = _current_texture.get_image()

	if _image == null:
		return

	# Apply rotation
	var rotated: Image = ImageProcessor.rotate_image(_image, degrees)
	if rotated != null:
		_image = rotated
		_rotation_angle = (_rotation_angle + degrees) % 360

		# Update texture
		set_image(_image)

		image_rotated.emit(degrees)

## Clear image
func clear_image() -> void:
	_current_texture = null
	_image = null
	_rotation_angle = 0

	if _image_texture != null:
		_image_texture.texture = null

	if _loading_overlay != null:
		_loading_overlay.visible = false

## Show loading overlay
func show_loading() -> void:
	if _loading_overlay != null:
		_loading_overlay.visible = true

## Hide loading overlay
func hide_loading() -> void:
	if _loading_overlay != null:
		_loading_overlay.visible = false

## Get current image
func get_image() -> Image:
	return _image

## Get current texture
func get_texture() -> Texture2D:
	return _current_texture

## Get current rotation angle
func get_rotation_angle() -> int:
	return _rotation_angle

## Set border visibility
func set_border_visible(is_visible: bool) -> void:
	if _border_panel != null:
		_border_panel.visible = is_visible

## Set controls visibility
func set_controls_visible(is_visible: bool) -> void:
	show_controls = is_visible
	if _rotate_button != null:
		_rotate_button.visible = show_controls and enable_rotation

## Handle rotate button press
func _on_rotate_pressed() -> void:
	rotate_image(90)

## Handle image loaded from loader
func _on_image_loaded(key: String, texture: ImageTexture) -> void:
	set_texture(texture)

## Handle image load failure from loader
func _on_image_load_failed(key: String, error: String) -> void:
	push_error("ImageViewer: Failed to load image: %s (Error: %s)" % [key, error])
	hide_loading()

## Handle direct HTTP load completion
func _on_direct_load_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:
	http_request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_on_image_load_failed("direct_load", "HTTP request failed")
		return

	var image: Image = ImageProcessor.load_image_from_buffer(body)
	if image != null:
		set_image(image)
	else:
		_on_image_load_failed("direct_load", "Failed to parse image")
