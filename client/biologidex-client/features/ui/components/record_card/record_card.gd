class_name RecordCard extends Control

# Reusable dex record card component
# Displays animal entry with image, border, label, and interactive elements
# Replaces RecordImage controls in camera.gd and dex.gd

signal card_clicked(entry_id: String)
signal favorite_toggled(entry_id: String, is_favorite: bool)
signal card_long_pressed(entry_id: String)

# Configuration
@export var show_favorite_button: bool = true
@export var show_index_badge: bool = false
@export var enable_interaction: bool = true
@export var card_size: Vector2 = Vector2(200, 280)

# UI Elements (will be wired from scene or created programmatically)
@onready var card_panel: Panel = $CardPanel
@onready var image_container: AspectRatioContainer = $CardPanel/MarginContainer/VBoxContainer/ImageContainer
@onready var image_border: Panel = $CardPanel/MarginContainer/VBoxContainer/ImageContainer/ImageBorder
@onready var card_image: TextureRect = $CardPanel/MarginContainer/VBoxContainer/ImageContainer/ImageBorder/Image
@onready var label_container: Panel = $CardPanel/MarginContainer/VBoxContainer/ImageContainer/ImageBorder/LabelContainer
@onready var card_label: Label = $CardPanel/MarginContainer/VBoxContainer/ImageContainer/ImageBorder/LabelContainer/Label
@onready var info_container: VBoxContainer = $CardPanel/MarginContainer/VBoxContainer/InfoContainer
@onready var name_label: Label = $CardPanel/MarginContainer/VBoxContainer/InfoContainer/NameLabel
@onready var metadata_label: Label = $CardPanel/MarginContainer/VBoxContainer/InfoContainer/MetadataLabel
@onready var favorite_button: Button = $CardPanel/MarginContainer/VBoxContainer/InfoContainer/FavoriteButton
@onready var index_badge: Label = $CardPanel/IndexBadge

# Data
var entry_id: String = ""
var entry_data: Dictionary = {}
var is_favorite: bool = false
var creation_index: int = -1

# Interaction state
var click_timer: Timer = null
var long_press_duration: float = 0.5
var is_pressed: bool = false


func _ready() -> void:
	_setup_ui()
	_setup_interaction()


# ============================================================================
# Public API - Data
# ============================================================================

func set_entry_data(data: Dictionary) -> void:
	"""
	Set entry data and update display.

	Expected data format:
	{
		"id": "uuid",
		"animal": {
			"creation_index": 123,
			"scientific_name": "Species name",
			"common_name": "Common name",
			...
		},
		"image_url": "url",
		"is_favorite": true,
		"notes": "...",
		...
	}
	"""
	entry_data = data
	entry_id = data.get("id", "")
	is_favorite = data.get("is_favorite", false)

	# Extract animal data
	var animal = data.get("animal", {})
	creation_index = animal.get("creation_index", -1)

	_update_display()


func set_image_texture(texture: Texture2D) -> void:
	"""Set card image texture directly"""
	if card_image:
		card_image.texture = texture


func set_image_from_path(path: String) -> void:
	"""Load and set image from file path"""
	var image = Image.new()
	var error = image.load(path)

	if error == OK:
		var texture = ImageTexture.create_from_image(image)
		set_image_texture(texture)
	else:
		push_error("[RecordCard] Failed to load image from path: %s" % path)


func set_image_from_data(data: PackedByteArray) -> void:
	"""Load and set image from byte data"""
	var image = Image.new()
	var error = image.load_png_from_buffer(data)

	if error != OK:
		error = image.load_jpg_from_buffer(data)

	if error == OK:
		var texture = ImageTexture.create_from_image(image)
		set_image_texture(texture)
	else:
		push_error("[RecordCard] Failed to load image from data")


func set_label_text(text: String) -> void:
	"""Set the label text (displayed on image border)"""
	if card_label:
		card_label.text = text


func set_name_text(text: String) -> void:
	"""Set the name label (below image)"""
	if name_label:
		name_label.text = text


func set_metadata_text(text: String) -> void:
	"""Set metadata text (below name)"""
	if metadata_label:
		metadata_label.text = text
		metadata_label.visible = not text.is_empty()


func set_favorite(favorite: bool) -> void:
	"""Set favorite state"""
	is_favorite = favorite
	_update_favorite_button()


# ============================================================================
# Public API - Configuration
# ============================================================================

func set_card_size(size: Vector2) -> void:
	"""Set card size"""
	card_size = size
	custom_minimum_size = size


func set_show_favorite_button(show: bool) -> void:
	"""Show/hide favorite button"""
	show_favorite_button = show
	if favorite_button:
		favorite_button.visible = show


func set_show_index_badge(show: bool) -> void:
	"""Show/hide creation index badge"""
	show_index_badge = show
	if index_badge:
		index_badge.visible = show and creation_index >= 0


func set_enable_interaction(enable: bool) -> void:
	"""Enable/disable card interaction"""
	enable_interaction = enable


# ============================================================================
# Internal Methods
# ============================================================================

func _setup_ui() -> void:
	"""Setup initial UI state"""
	custom_minimum_size = card_size

	if favorite_button:
		favorite_button.visible = show_favorite_button
		if not favorite_button.pressed.is_connected(_on_favorite_pressed):
			favorite_button.pressed.connect(_on_favorite_pressed)

	if index_badge:
		index_badge.visible = show_index_badge and creation_index >= 0

	_update_favorite_button()


func _setup_interaction() -> void:
	"""Setup interaction handlers"""
	if not enable_interaction:
		return

	# Setup click timer for long press detection
	click_timer = Timer.new()
	click_timer.wait_time = long_press_duration
	click_timer.one_shot = true
	click_timer.timeout.connect(_on_long_press_timer_timeout)
	add_child(click_timer)


func _update_display() -> void:
	"""Update card display from entry data"""
	if entry_data.is_empty():
		return

	# Update labels
	var animal = entry_data.get("animal", {})
	var common_name = animal.get("common_name", "")
	var scientific_name = animal.get("scientific_name", "")

	# Card label (on image)
	if card_label:
		var label_text = common_name if not common_name.is_empty() else scientific_name
		card_label.text = label_text

	# Name label (below image)
	if name_label:
		name_label.text = common_name if not common_name.is_empty() else scientific_name

	# Metadata (creation index, date, etc.)
	if metadata_label and creation_index >= 0:
		metadata_label.text = "No. %d" % creation_index
		metadata_label.visible = true

	# Index badge
	if index_badge and show_index_badge and creation_index >= 0:
		index_badge.text = str(creation_index)
		index_badge.visible = true

	# Favorite state
	_update_favorite_button()

	# Load image if URL provided
	var image_url = entry_data.get("image_url", "")
	if not image_url.is_empty():
		# TODO: Implement async image loading from URL
		pass


func _update_favorite_button() -> void:
	"""Update favorite button appearance"""
	if not favorite_button:
		return

	# Update button text/icon
	favorite_button.text = "★" if is_favorite else "☆"


# ============================================================================
# Event Handlers
# ============================================================================

func _gui_input(event: InputEvent) -> void:
	"""Handle card interaction"""
	if not enable_interaction:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Start long press timer
				is_pressed = true
				if click_timer:
					click_timer.start()
			else:
				# Released - check if it was a click or long press
				is_pressed = false
				if click_timer and not click_timer.is_stopped():
					# Was a click (not long press)
					click_timer.stop()
					_on_card_clicked()


func _on_card_clicked() -> void:
	"""Handle card click"""
	card_clicked.emit(entry_id)
	print("[RecordCard] Card clicked: %s" % entry_id)


func _on_favorite_pressed() -> void:
	"""Handle favorite button press"""
	is_favorite = not is_favorite
	_update_favorite_button()
	favorite_toggled.emit(entry_id, is_favorite)
	print("[RecordCard] Favorite toggled: %s = %s" % [entry_id, is_favorite])


func _on_long_press_timer_timeout() -> void:
	"""Handle long press"""
	if is_pressed:
		card_long_pressed.emit(entry_id)
		print("[RecordCard] Card long pressed: %s" % entry_id)