extends Control

# Dex Gallery - Browse through discovered animals in creation_index order

@onready var back_button: Button = $Panel/MarginContainer/VBoxContainer/Header/BackButton
@onready var dex_number_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/"Dex Number"
@onready var record_image: Control = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage
@onready var bordered_container: AspectRatioContainer = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio
@onready var bordered_image: TextureRect = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio/ImageBorder/Image
@onready var record_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio/ImageBorder/RecordMargin/RecordBackground/RecordTextMargin/RecordLabel
@onready var simple_image: TextureRect = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/Image
@onready var previous_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/HBoxContainer/PreviousButton
@onready var next_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/HBoxContainer/NextButton

var current_index: int = -1
var current_image_width: float = 0.0
var current_image_height: float = 0.0


func _ready() -> void:
	print("[Dex] Scene loaded")

	# Check authentication
	if not TokenManager.is_logged_in():
		print("[Dex] ERROR: User not logged in")
		NavigationManager.go_back()
		return

	# Connect buttons
	back_button.pressed.connect(_on_back_pressed)
	previous_button.pressed.connect(_on_previous_pressed)
	next_button.pressed.connect(_on_next_pressed)

	# Connect to database signals
	DexDatabase.record_added.connect(_on_record_added)

	# Load first record
	_load_first_record()


func _load_first_record() -> void:
	"""Load the first record (lowest creation_index)"""
	var first_index := DexDatabase.get_first_index()

	if first_index >= 0:
		_display_record(first_index)
	else:
		_show_empty_state()


func _show_empty_state() -> void:
	"""Show UI when no records exist"""
	current_index = -1
	dex_number_label.text = "No animals discovered yet!"
	record_image.visible = false
	previous_button.disabled = true
	next_button.disabled = true
	print("[Dex] No records in database")


func _display_record(creation_index: int) -> void:
	"""Display a specific record"""
	var record := DexDatabase.get_record(creation_index)

	if record.is_empty():
		print("[Dex] ERROR: Record not found: ", creation_index)
		return

	current_index = creation_index

	# Update dex number
	dex_number_label.text = "Dex #%d" % creation_index
	print("[Dex] Displaying record #", creation_index)

	# Load and display image
	var image_path: String = record.get("cached_image_path", "")
	if image_path.length() > 0 and FileAccess.file_exists(image_path):
		_load_and_display_image(image_path)
	else:
		print("[Dex] WARNING: Image not found: ", image_path)
		record_image.visible = false

	# Update animal name label
	var scientific_name: String = record.get("scientific_name", "")
	var common_name: String = record.get("common_name", "")

	var display_text := ""
	if scientific_name.length() > 0:
		display_text = scientific_name
		if common_name.length() > 0:
			display_text += " - " + common_name
	elif common_name.length() > 0:
		display_text = common_name
	else:
		display_text = "Unknown"

	record_label.text = display_text

	# Update navigation buttons
	_update_navigation_buttons()


func _load_and_display_image(path: String) -> void:
	"""Load image from local cache and display it"""
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[Dex] Failed to open image file: ", path)
		return

	var data := file.get_buffer(file.get_length())
	file.close()

	var image := Image.new()
	var error := image.load_png_from_buffer(data)

	if error != OK:
		push_error("[Dex] Failed to load PNG image: ", error)
		return

	# Create texture
	var texture := ImageTexture.create_from_image(image)

	# Update image dimensions
	current_image_width = float(image.get_width())
	current_image_height = float(image.get_height())

	# Calculate aspect ratio
	if current_image_height > 0.0:
		var aspect_ratio: float = current_image_width / current_image_height
		bordered_container.ratio = aspect_ratio
		print("[Dex] Image loaded: ", current_image_width, "x", current_image_height, " (aspect: ", aspect_ratio, ")")

	# Display in bordered version
	bordered_image.texture = texture
	simple_image.visible = false
	bordered_container.visible = true
	record_image.visible = true

	# Update size after layout
	await get_tree().process_frame
	_update_record_image_size()


func _update_record_image_size() -> void:
	"""Update RecordImage's custom_minimum_size to match AspectRatioContainer's calculated height"""
	var available_width: float = float(record_image.get_parent_control().size.x)

	# Set max width to 2/3 of available width
	var max_card_width: float = available_width * 0.67

	# Cap width at actual image width (don't upscale)
	var max_width: float = min(current_image_width, max_card_width)
	var display_width: float = min(available_width, max_width)

	# Calculate required height based on aspect ratio
	var aspect_ratio: float = bordered_container.ratio
	if aspect_ratio > 0.0:
		var required_height: float = display_width / aspect_ratio
		record_image.custom_minimum_size = Vector2(display_width, required_height)

		# Center the image if smaller than available width
		if display_width < available_width:
			record_image.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		else:
			record_image.size_flags_horizontal = Control.SIZE_FILL

		print("[Dex] Updated RecordImage size - Display: ", display_width, " Height: ", required_height)


func _update_navigation_buttons() -> void:
	"""Enable/disable navigation buttons based on current position"""
	if current_index < 0:
		previous_button.disabled = true
		next_button.disabled = true
		return

	# Check if there's a previous record
	var prev_index := DexDatabase.get_previous_index(current_index)
	previous_button.disabled = (prev_index < 0)

	# Check if there's a next record
	var next_index := DexDatabase.get_next_index(current_index)
	next_button.disabled = (next_index < 0)


func _on_previous_pressed() -> void:
	"""Navigate to previous record"""
	if current_index < 0:
		return

	var prev_index := DexDatabase.get_previous_index(current_index)
	if prev_index >= 0:
		print("[Dex] Navigating to previous: #", prev_index)
		_display_record(prev_index)
	else:
		print("[Dex] Already at first record")


func _on_next_pressed() -> void:
	"""Navigate to next record"""
	if current_index < 0:
		return

	var next_index := DexDatabase.get_next_index(current_index)
	if next_index >= 0:
		print("[Dex] Navigating to next: #", next_index)
		_display_record(next_index)
	else:
		print("[Dex] Already at last record")


func _on_back_pressed() -> void:
	"""Navigate back to previous scene"""
	print("[Dex] Back button pressed")
	NavigationManager.go_back()


func _on_record_added(creation_index: int) -> void:
	"""Handle new record added to database"""
	print("[Dex] New record added: #", creation_index)

	# If we're currently showing empty state, load the new record
	if current_index < 0:
		_display_record(creation_index)
	else:
		# Update navigation buttons in case new record affects them
		_update_navigation_buttons()
