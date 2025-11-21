class_name ImageDisplay extends Control

# Reusable image display component with rotation, aspect ratio, and different display modes
# Extracted from camera.gd and dex.gd

signal image_loaded(image: Image)
signal image_cleared
signal rotation_changed(total_rotation: int)
signal image_clicked

enum DisplayMode {
	SIMPLE,      # Simple TextureRect
	BORDERED,    # Image with decorative border (for dex cards)
	GALLERY      # Gallery view with metadata
}

# Configuration
@export var display_mode: DisplayMode = DisplayMode.SIMPLE
@export var enable_rotation: bool = true
@export var maintain_aspect_ratio: bool = true
@export var max_size: Vector2 = Vector2(800, 600)

# UI Elements (will be created programmatically or wired from scene)
@onready var simple_image: TextureRect = $SimpleImage
@onready var bordered_container: AspectRatioContainer = $BorderedContainer
@onready var bordered_image: TextureRect = $BorderedContainer/Border/Image
@onready var label_container: Control = $BorderedContainer/Border/LabelContainer
@onready var image_label: Label = $BorderedContainer/Border/LabelContainer/Label

# State
var current_image: Image = null
var current_texture: ImageTexture = null
var total_rotation: int = 0  # 0, 90, 180, 270
var original_image_data: PackedByteArray = PackedByteArray()


func _ready() -> void:
	_setup_display_mode()


# ============================================================================
# Public API - Image Loading
# ============================================================================

func load_image_from_path(path: String) -> bool:
	"""Load image from file path"""
	var image = Image.new()
	var error = image.load(path)

	if error != OK:
		push_error("[ImageDisplay] Failed to load image from path: %s (error: %d)" % [path, error])
		return false

	return load_image(image)


func load_image_from_data(data: PackedByteArray) -> bool:
	"""Load image from byte data"""
	if data.is_empty():
		push_error("[ImageDisplay] Cannot load image from empty data")
		return false

	var image = Image.new()
	var error = image.load_png_from_buffer(data)

	if error != OK:
		# Try JPEG
		error = image.load_jpg_from_buffer(data)

	if error != OK:
		# Try WebP
		error = image.load_webp_from_buffer(data)

	if error != OK:
		push_error("[ImageDisplay] Failed to load image from data (error: %d)" % error)
		return false

	original_image_data = data
	return load_image(image)


func load_image(image: Image) -> bool:
	"""Load an Image object"""
	if not image:
		push_error("[ImageDisplay] Cannot load null image")
		return false

	current_image = image
	total_rotation = 0

	# Create texture
	current_texture = ImageTexture.create_from_image(image)

	# Display image
	_display_image()

	image_loaded.emit(image)
	return true


func clear_image() -> void:
	"""Clear the currently displayed image"""
	current_image = null
	current_texture = null
	total_rotation = 0
	original_image_data = PackedByteArray()

	if simple_image:
		simple_image.texture = null
	if bordered_image:
		bordered_image.texture = null

	image_cleared.emit()


# ============================================================================
# Public API - Rotation
# ============================================================================

func rotate_image_clockwise() -> bool:
	"""Rotate image 90 degrees clockwise"""
	if not enable_rotation or not current_image:
		return false

	# Rotate the image
	current_image.rotate_90(CLOCKWISE)

	# Update rotation angle
	total_rotation = (total_rotation + 90) % 360

	# Recreate texture
	current_texture = ImageTexture.create_from_image(current_image)

	# Redisplay
	_display_image()

	rotation_changed.emit(total_rotation)
	print("[ImageDisplay] Rotated to %d degrees" % total_rotation)
	return true


func rotate_image_counter_clockwise() -> bool:
	"""Rotate image 90 degrees counter-clockwise"""
	if not enable_rotation or not current_image:
		return false

	# Rotate the image
	current_image.rotate_90(COUNTERCLOCKWISE)

	# Update rotation angle
	total_rotation = (total_rotation - 90 + 360) % 360

	# Recreate texture
	current_texture = ImageTexture.create_from_image(current_image)

	# Redisplay
	_display_image()

	rotation_changed.emit(total_rotation)
	print("[ImageDisplay] Rotated to %d degrees" % total_rotation)
	return true


func reset_rotation() -> void:
	"""Reset rotation to 0 degrees"""
	if total_rotation == 0 or not current_image:
		return

	# Reload from original data if available
	if not original_image_data.is_empty():
		load_image_from_data(original_image_data)
	else:
		# Rotate back manually
		while total_rotation != 0:
			rotate_image_counter_clockwise()


func get_rotation() -> int:
	"""Get current rotation angle"""
	return total_rotation


# ============================================================================
# Public API - Display Configuration
# ============================================================================

func set_display_mode(mode: DisplayMode) -> void:
	"""Change display mode"""
	display_mode = mode
	_setup_display_mode()
	_display_image()


func set_label(text: String) -> void:
	"""Set label text (for bordered mode)"""
	if image_label:
		image_label.text = text


func set_max_size(size: Vector2) -> void:
	"""Set maximum display size"""
	max_size = size
	_display_image()


# ============================================================================
# Public API - Getters
# ============================================================================

func get_image() -> Image:
	"""Get current Image object"""
	return current_image


func get_image_data() -> PackedByteArray:
	"""Get image as PNG byte data"""
	if not current_image:
		return PackedByteArray()

	return current_image.save_png_to_buffer()


func get_image_size() -> Vector2:
	"""Get current image dimensions"""
	if not current_image:
		return Vector2.ZERO

	return Vector2(current_image.get_width(), current_image.get_height())


func has_image() -> bool:
	"""Check if an image is loaded"""
	return current_image != null


# ============================================================================
# Internal Methods
# ============================================================================

func _setup_display_mode() -> void:
	"""Setup UI for current display mode"""
	if not is_inside_tree():
		return

	match display_mode:
		DisplayMode.SIMPLE:
			if simple_image:
				simple_image.visible = true
			if bordered_container:
				bordered_container.visible = false

		DisplayMode.BORDERED:
			if simple_image:
				simple_image.visible = false
			if bordered_container:
				bordered_container.visible = true

		DisplayMode.GALLERY:
			# TODO: Implement gallery mode
			pass


func _display_image() -> void:
	"""Display current image in appropriate mode"""
	if not current_texture:
		return

	match display_mode:
		DisplayMode.SIMPLE:
			if simple_image:
				simple_image.texture = current_texture
				_update_simple_image_size()

		DisplayMode.BORDERED:
			if bordered_image:
				bordered_image.texture = current_texture
				_update_bordered_image_size()

		DisplayMode.GALLERY:
			# TODO: Implement gallery mode
			pass


func _update_simple_image_size() -> void:
	"""Update simple image size constraints"""
	if not simple_image or not current_image:
		return

	if maintain_aspect_ratio:
		simple_image.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		simple_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	else:
		simple_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		simple_image.stretch_mode = TextureRect.STRETCH_SCALE


func _update_bordered_image_size() -> void:
	"""Update bordered image size constraints"""
	if not bordered_image or not current_image:
		return

	# AspectRatioContainer will handle aspect ratio
	bordered_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bordered_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# Update aspect ratio
	if bordered_container:
		var img_size = get_image_size()
		if img_size.y > 0:
			bordered_container.ratio = img_size.x / img_size.y


# ============================================================================
# Event Handlers
# ============================================================================

func _gui_input(event: InputEvent) -> void:
	"""Handle input events"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		image_clicked.emit()