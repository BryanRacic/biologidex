extends Control

# Camera/Upload scene - Handles photo selection and upload for CV analysis
# Uses godot-file-access-web plugin for HTML5 file access

@onready var select_photo_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/SelectPhotoButton
@onready var upload_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/UploadButton
@onready var status_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/StatusLabel
@onready var progress_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/ProgressLabel
@onready var loading_spinner: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/LoadingSpinner
@onready var result_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/ResultLabel
@onready var back_button: Button = $Panel/MarginContainer/VBoxContainer/Header/BackButton
@onready var record_image: Control = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage
@onready var simple_image: TextureRect = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/Image
@onready var bordered_container: AspectRatioContainer = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio
@onready var bordered_image: TextureRect = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio/ImageBorder/Image
@onready var record_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio/ImageBorder/RecordMargin/RecordBackground/RecordTextMargin/RecordLabel

# Rotation controls (will be created programmatically)
var rotation_controls_container: HBoxContainer
var rotate_left_button: Button
var rotate_right_button: Button

var file_access_web: FileAccessWeb
var selected_file_name: String = ""
var selected_file_type: String = ""
var selected_file_data: PackedByteArray = PackedByteArray()
var current_job_id: String = ""
var status_check_timer: Timer
var current_image_width: float = 0.0
var current_image_height: float = 0.0
var unsupported_format_warning: bool = false
var dex_compatible_url: String = ""
var cached_dex_image: Image = null

# Image rotation state
var current_rotation: int = 0  # Track rotation angle (0, 90, 180, 270)
var pending_transformations: Dictionary = {}  # Track all image modifications

# Test image cycling for editor mode
const TEST_IMAGES: Array[String] = [
	"res://resources/test_img.jpeg",
	"res://resources/test_img2.jpeg",
	"res://resources/test_img3.jpeg",
	"res://resources/test_img4.jpeg",
	"res://resources/test_img5.jpeg"
]
var current_test_image_index: int = 0


func _ready() -> void:
	print("[Camera] Scene loaded")

	# Check authentication
	if not TokenManager.is_logged_in():
		print("[Camera] ERROR: User not logged in")
		NavigationManager.go_back()
		return

	# Initialize UI state
	_reset_ui()

	# Check if running in editor
	if OS.has_feature("editor"):
		print("[Camera] Running in Godot editor - using test image mode (", TEST_IMAGES.size(), " images)")
		status_label.text = "Editor mode: Test images will cycle automatically (%d total)" % TEST_IMAGES.size()
		status_label.add_theme_color_override("font_color", Color.CYAN)
	# Initialize FileAccessWeb plugin (only works on HTML5)
	elif OS.get_name() == "Web":
		file_access_web = FileAccessWeb.new()
		file_access_web.load_started.connect(_on_file_load_started)
		file_access_web.loaded.connect(_on_file_loaded)
		file_access_web.progress.connect(_on_file_progress)
		file_access_web.error.connect(_on_file_error)
		file_access_web.upload_cancelled.connect(_on_file_cancelled)
		print("[Camera] FileAccessWeb initialized")
	else:
		print("[Camera] WARNING: Not running on Web platform, file upload will not work")
		status_label.text = "File upload only works on HTML5 builds"
		status_label.add_theme_color_override("font_color", Color.ORANGE)
		select_photo_button.disabled = true

	# Connect buttons
	select_photo_button.pressed.connect(_on_select_photo_pressed)
	upload_button.pressed.connect(_on_upload_pressed)
	back_button.pressed.connect(_on_back_pressed)

	# Create rotation controls programmatically
	_create_rotation_controls()

	# Create timer for status polling
	status_check_timer = Timer.new()
	add_child(status_check_timer)
	status_check_timer.timeout.connect(_check_job_status)


func _reset_ui() -> void:
	"""Reset UI to initial state"""
	upload_button.disabled = true
	loading_spinner.visible = false
	record_image.visible = false
	simple_image.visible = false
	bordered_container.visible = false
	progress_label.text = ""
	status_label.text = "Select a photo to identify an animal"
	status_label.add_theme_color_override("font_color", Color.WHITE)
	result_label.text = ""
	selected_file_name = ""
	selected_file_type = ""
	selected_file_data = PackedByteArray()
	current_rotation = 0
	pending_transformations = {}
	if rotation_controls_container:
		rotation_controls_container.visible = false


func _create_rotation_controls() -> void:
	"""Create rotation control buttons programmatically"""
	# Find the ContentContainer to add rotation controls to
	var content_container = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer

	# Create HBoxContainer for rotation buttons
	rotation_controls_container = HBoxContainer.new()
	rotation_controls_container.name = "RotationControls"
	rotation_controls_container.visible = false
	rotation_controls_container.alignment = BoxContainer.ALIGNMENT_CENTER

	# Add some spacing at the top
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	rotation_controls_container.add_child(spacer)

	# Create Rotate Left button
	rotate_left_button = Button.new()
	rotate_left_button.text = "Rotate Left ⟲"
	rotate_left_button.custom_minimum_size = Vector2(150, 44)
	rotate_left_button.pressed.connect(_on_rotate_left)
	rotation_controls_container.add_child(rotate_left_button)

	# Add spacer between buttons
	var button_spacer = Control.new()
	button_spacer.custom_minimum_size = Vector2(20, 0)
	rotation_controls_container.add_child(button_spacer)

	# Create Rotate Right button
	rotate_right_button = Button.new()
	rotate_right_button.text = "Rotate Right ⟳"
	rotate_right_button.custom_minimum_size = Vector2(150, 44)
	rotate_right_button.pressed.connect(_on_rotate_right)
	rotation_controls_container.add_child(rotate_right_button)

	# Add to content container (after RecordImage)
	content_container.add_child(rotation_controls_container)
	content_container.move_child(rotation_controls_container, content_container.get_child_count() - 1)

	print("[Camera] Rotation controls created")


func _on_rotate_left() -> void:
	"""Rotate image 90 degrees counter-clockwise"""
	current_rotation = (current_rotation - 90) % 360
	if current_rotation < 0:
		current_rotation += 360
	_apply_rotation_to_preview()
	pending_transformations["rotation"] = current_rotation
	print("[Camera] Rotated left to %d degrees" % current_rotation)


func _on_rotate_right() -> void:
	"""Rotate image 90 degrees clockwise"""
	current_rotation = (current_rotation + 90) % 360
	_apply_rotation_to_preview()
	pending_transformations["rotation"] = current_rotation
	print("[Camera] Rotated right to %d degrees" % current_rotation)


func _apply_rotation_to_preview() -> void:
	"""Apply visual rotation to the image preview"""
	# Apply rotation to both simple and bordered images
	simple_image.rotation_degrees = current_rotation
	bordered_image.rotation_degrees = current_rotation

	# Swap width/height for aspect ratio if rotated 90 or 270 degrees
	if current_rotation == 90 or current_rotation == 270:
		# Swap dimensions
		var temp: float = current_image_width
		current_image_width = current_image_height
		current_image_height = temp

	# Update the record image size with new dimensions
	_update_record_image_size()


func _on_select_photo_pressed() -> void:
	"""Open file picker for photo selection or load test image in editor"""
	# Editor mode - load test image directly
	if OS.has_feature("editor"):
		print("[Camera] Editor mode - loading test image...")
		_load_test_image()
		return

	# Web export mode - use file picker
	if OS.get_name() != "Web":
		return

	print("[Camera] Opening file picker...")
	status_label.text = "Opening file picker..."
	file_access_web.open("image/*")


func _on_file_load_started(file_name: String) -> void:
	"""Called when file starts loading"""
	print("[Camera] File load started: ", file_name)
	status_label.text = "Loading file: %s" % file_name
	progress_label.text = ""


func _on_file_loaded(file_name: String, file_type: String, base64_data: String) -> void:
	"""Called when file is fully loaded"""
	print("[Camera] File loaded: ", file_name, " Type: ", file_type, " Size: ", base64_data.length())

	# Convert base64 to binary - store ORIGINAL data (no conversion)
	selected_file_data = Marshalls.base64_to_raw(base64_data)
	selected_file_name = file_name
	selected_file_type = file_type

	# Try to load image for preview using robust loading
	var preview_result := _attempt_image_preview(selected_file_data, file_type)

	if preview_result.success:
		# Successfully loaded for preview
		var texture := ImageTexture.create_from_image(preview_result.image)

		# Store image dimensions
		current_image_width = float(preview_result.image.get_width())
		current_image_height = float(preview_result.image.get_height())

		# Show simple preview (no border) on initial load
		simple_image.texture = texture
		simple_image.visible = true
		bordered_container.visible = false
		record_image.visible = true

		unsupported_format_warning = false
		status_label.text = "Photo selected: %s (%d KB)" % [file_name, selected_file_data.size() / 1024]
		status_label.add_theme_color_override("font_color", Color.GREEN)

		print("[Camera] Image loaded into simple preview (", current_image_width, "x", current_image_height, ")")
	else:
		# Cannot preview, but still allow upload
		_show_format_warning()
		unsupported_format_warning = true

		status_label.text = "⚠️ Cannot preview this format, but you can still upload it"
		status_label.add_theme_color_override("font_color", Color.YELLOW)

		print("[Camera] Cannot preview image format, but allowing upload")

	# Enable upload button regardless of preview success
	upload_button.disabled = false
	upload_button.text = "Upload for Analysis"
	progress_label.text = ""

	# Show rotation controls when image is loaded successfully
	if preview_result.success and rotation_controls_container:
		rotation_controls_container.visible = true
		current_rotation = 0  # Reset rotation
		pending_transformations = {}  # Clear transformations

	print("[Camera] File ready for upload - Size: ", selected_file_data.size(), " bytes")


func _attempt_image_preview(data: PackedByteArray, mime_type: String) -> Dictionary:
	"""Try to load image for preview. Returns {success: bool, image: Image}."""
	var result := {"success": false, "image": null}

	var image := Image.new()
	var load_error := ERR_FILE_UNRECOGNIZED

	# Try loading based on MIME type
	if mime_type.to_lower().contains("jpeg") or mime_type.to_lower().contains("jpg"):
		print("[Camera] Attempting JPEG load based on MIME type: ", mime_type)
		load_error = image.load_jpg_from_buffer(data)
	elif mime_type.to_lower().contains("png"):
		print("[Camera] Attempting PNG load based on MIME type: ", mime_type)
		load_error = image.load_png_from_buffer(data)
	elif mime_type.to_lower().contains("webp"):
		print("[Camera] Attempting WebP load based on MIME type: ", mime_type)
		load_error = image.load_webp_from_buffer(data)
	elif mime_type.to_lower().contains("bmp"):
		print("[Camera] Attempting BMP load based on MIME type: ", mime_type)
		load_error = image.load_bmp_from_buffer(data)
	else:
		# Unknown type - try common formats
		print("[Camera] Unknown MIME type, trying PNG then JPEG: ", mime_type)
		load_error = image.load_png_from_buffer(data)
		if load_error != OK:
			load_error = image.load_jpg_from_buffer(data)
		if load_error != OK:
			load_error = image.load_webp_from_buffer(data)

	if load_error == OK and not image.is_empty():
		result.success = true
		result.image = image
		print("[Camera] Successfully loaded image for preview")
	else:
		print("[Camera] Failed to load image for preview: ", load_error)

	return result


func _show_format_warning() -> void:
	"""Display warning that image cannot be previewed."""
	# Hide the image preview
	simple_image.visible = false
	bordered_container.visible = false
	record_image.visible = false

	print("[Camera] Showing format warning - image cannot be previewed")


func _on_file_progress(current_bytes: int, total_bytes: int) -> void:
	"""Called during file loading"""
	var progress := float(current_bytes) / float(total_bytes) * 100.0
	progress_label.text = "Loading: %.1f%%" % progress


func _on_file_error() -> void:
	"""Called on file load error"""
	print("[Camera] ERROR: File load failed")
	status_label.text = "Error loading file. Please try again."
	status_label.add_theme_color_override("font_color", Color.RED)
	progress_label.text = ""


func _on_file_cancelled() -> void:
	"""Called when file selection is cancelled"""
	print("[Camera] File selection cancelled")
	status_label.text = "File selection cancelled"
	status_label.add_theme_color_override("font_color", Color.ORANGE)
	progress_label.text = ""


func _load_test_image() -> void:
	"""Load test image from resources (editor mode only)"""
	if current_test_image_index >= TEST_IMAGES.size():
		print("[Camera] All test images uploaded! Resetting to first image.")
		current_test_image_index = 0

	var test_image_path: String = TEST_IMAGES[current_test_image_index]
	var file_name: String = test_image_path.get_file()

	print("[Camera] Loading test image [", current_test_image_index + 1, "/", TEST_IMAGES.size(), "]: ", test_image_path)
	status_label.text = "Loading test image %d/%d..." % [current_test_image_index + 1, TEST_IMAGES.size()]

	# Load raw file bytes - NO CONVERSION to keep original format
	var file := FileAccess.open(test_image_path, FileAccess.READ)
	if not file:
		print("[Camera] ERROR: Failed to open test image file: ", test_image_path)
		status_label.text = "Error: Could not load test image"
		status_label.add_theme_color_override("font_color", Color.RED)
		return

	selected_file_data = file.get_buffer(file.get_length())
	file.close()

	selected_file_name = file_name
	selected_file_type = "image/jpeg"

	print("[Camera] Test image loaded - Size: ", selected_file_data.size(), " bytes (original JPEG)")

	# Load image for preview display only
	var image := Image.new()
	var load_error := image.load(test_image_path)

	if load_error == OK:
		# Display in simple preview (no border) on initial load
		var texture := ImageTexture.create_from_image(image)

		# Store image dimensions
		current_image_width = float(image.get_width())
		current_image_height = float(image.get_height())

		simple_image.texture = texture
		simple_image.visible = true
		bordered_container.visible = false
		record_image.visible = true

		print("[Camera] Test image loaded into simple preview (", current_image_width, "x", current_image_height, ")")

		# Update UI - success
		status_label.text = "Test image %d/%d loaded (%d KB)" % [current_test_image_index + 1, TEST_IMAGES.size(), selected_file_data.size() / 1024]
		status_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		# Show warning in UI (not just console)
		print("[Camera] WARNING: Could not load test image for preview, but file data loaded")
		status_label.text = "⚠️ Cannot preview image, but file loaded (%d KB)" % [selected_file_data.size() / 1024]
		status_label.add_theme_color_override("font_color", Color.YELLOW)

	upload_button.disabled = false
	print("[Camera] Test image ready for upload (original JPEG format)")


func _update_record_image_size() -> void:
	"""Update RecordImage's custom_minimum_size to match AspectRatioContainer's calculated height"""
	# Get the available width from the parent container
	var available_width: float = float(record_image.get_parent_control().size.x)

	# Set max width to 2/3 of available width for better card display
	var max_card_width: float = available_width * 0.67

	# Cap width at actual image width (don't upscale beyond native resolution)
	var max_width: float = min(current_image_width, max_card_width)
	var display_width: float = min(available_width, max_width)

	# Calculate required height based on aspect ratio
	var aspect_ratio: float = bordered_container.ratio
	if aspect_ratio > 0.0:
		var required_height: float = display_width / aspect_ratio
		record_image.custom_minimum_size = Vector2(display_width, required_height)

		# Center the image if it's smaller than available width
		if display_width < available_width:
			record_image.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		else:
			record_image.size_flags_horizontal = Control.SIZE_FILL

		print("[Camera] Updated RecordImage size - Available: ", available_width, " Display: ", display_width, " Height: ", required_height)


func _on_upload_pressed() -> void:
	"""Upload selected photo for CV analysis"""
	if selected_file_data.size() == 0:
		print("[Camera] ERROR: No file selected")
		return

	print("[Camera] Starting upload...")

	# Update UI for upload
	upload_button.disabled = true
	select_photo_button.disabled = true
	loading_spinner.visible = true
	status_label.text = "Uploading image..."
	status_label.add_theme_color_override("font_color", Color.WHITE)
	result_label.text = ""

	# Get access token
	var access_token := TokenManager.get_access_token()

	# Upload via API with transformations
	APIManager.create_vision_job(
		selected_file_data,
		selected_file_name,
		selected_file_type,
		access_token,
		_on_upload_completed,
		pending_transformations  # Pass rotation and other transformations
	)

	print("[Camera] Uploading with transformations: ", JSON.stringify(pending_transformations))


func _on_upload_completed(response: Dictionary, code: int) -> void:
	"""Handle upload completion"""
	if code == 201:
		# Upload successful, job created
		var id_value = response.get("id")
		current_job_id = "" if id_value == null else str(id_value)

		var status_value = response.get("status")
		var job_status: String = "unknown" if status_value == null else str(status_value)

		print("[Camera] Upload successful! Job ID: ", current_job_id, " Status: ", job_status)

		status_label.text = "Upload successful! Analyzing image..."
		status_label.add_theme_color_override("font_color", Color.GREEN)

		# Start polling for job status
		_start_status_polling()
	else:
		# Upload failed
		var error_msg := "Upload failed"

		if response.has("detail"):
			error_msg = str(response["detail"])
		elif response.has("error"):
			error_msg = str(response["error"])
		elif code == 401:
			error_msg = "Authentication failed. Please login again."
		elif code == 0:
			error_msg = "Cannot connect to server"

		print("[Camera] Upload failed: ", error_msg)

		status_label.text = "Upload failed: %s" % error_msg
		status_label.add_theme_color_override("font_color", Color.RED)
		loading_spinner.visible = false
		upload_button.disabled = false
		select_photo_button.disabled = false


func _start_status_polling() -> void:
	"""Start polling for job status"""
	print("[Camera] Starting status polling for job: ", current_job_id)
	status_check_timer.wait_time = 2.0  # Check every 2 seconds
	status_check_timer.start()
	_check_job_status()  # Check immediately


func _check_job_status() -> void:
	"""Check current job status"""
	if current_job_id.length() == 0:
		return

	print("[Camera] Checking job status: ", current_job_id)

	var access_token := TokenManager.get_access_token()

	APIManager.get_vision_job(
		current_job_id,
		access_token,
		_on_status_checked
	)


func _on_status_checked(response: Dictionary, code: int) -> void:
	"""Handle status check response"""
	if code != 200:
		print("[Camera] Status check failed: ", code)
		return

	var status_value = response.get("status")
	var job_status: String = "unknown" if status_value == null else str(status_value)
	print("[Camera] Job status: ", job_status)

	match job_status:
		"pending", "processing":
			# Still processing
			status_label.text = "Analyzing image... (%s)" % job_status
		"completed":
			# Analysis complete!
			_stop_status_polling()
			_handle_completed_job(response)
		"failed":
			# Analysis failed
			_stop_status_polling()
			var error_value = response.get("error_message")
			var error_msg: String = "Unknown error" if error_value == null else str(error_value)
			print("[Camera] Job failed: ", error_msg)
			status_label.text = "Analysis failed: %s" % error_msg
			status_label.add_theme_color_override("font_color", Color.RED)
			loading_spinner.visible = false
			upload_button.disabled = false
			select_photo_button.disabled = false


func _handle_completed_job(job_data: Dictionary) -> void:
	"""Handle completed analysis job"""
	print("[Camera] Analysis complete!")

	loading_spinner.visible = false
	status_label.text = "Analysis complete!"
	status_label.add_theme_color_override("font_color", Color.GREEN)

	# Extract results - handle all potential null values
	var prediction_value = job_data.get("parsed_prediction")
	var prediction: String = "Unknown" if prediction_value == null else str(prediction_value)

	var confidence_value = job_data.get("confidence_score")
	var confidence: float = 0.0
	if confidence_value != null:
		confidence = float(confidence_value)

	# Handle null animal_details
	var animal_details_value = job_data.get("animal_details")
	var animal_details: Dictionary = {}
	if animal_details_value != null and typeof(animal_details_value) == TYPE_DICTIONARY:
		animal_details = animal_details_value

	print("[Camera] Prediction: ", prediction)
	print("[Camera] Confidence: ", confidence)
	print("[Camera] Animal details: ", animal_details)

	# Download and cache dex-compatible image
	var dex_url_value = job_data.get("dex_compatible_url")
	if dex_url_value != null and str(dex_url_value).length() > 0:
		dex_compatible_url = str(dex_url_value)
		print("[Camera] Dex-compatible URL found: ", dex_compatible_url)
		status_label.text = "Downloading processed image..."

		# Try to load from cache first
		cached_dex_image = _load_cached_image(dex_compatible_url)

		if cached_dex_image == null:
			# Download and cache
			await _download_and_cache_dex_image(dex_compatible_url)
		else:
			print("[Camera] Using cached dex-compatible image")
	else:
		print("[Camera] WARNING: No dex_compatible_url in response, using preview image")
		status_label.text = "Analysis complete! (using preview image)"

	# Determine which image to display
	var display_image: Image = null
	if cached_dex_image != null:
		display_image = cached_dex_image
		print("[Camera] Using dex-compatible image for display")
	elif simple_image.texture != null:
		# Fallback to preview image if dex image not available
		display_image = simple_image.texture.get_image()
		print("[Camera] Using preview image for display")

	# Switch from simple preview to bordered display with label
	if display_image != null:
		var texture := ImageTexture.create_from_image(display_image)
		bordered_image.texture = texture

		# Calculate aspect ratio from the image and UPDATE current dimensions
		var img_width: float = float(display_image.get_width())
		var img_height: float = float(display_image.get_height())

		# Update current image dimensions for sizing calculations
		current_image_width = img_width
		current_image_height = img_height

		if img_height > 0.0:
			var aspect_ratio: float = img_width / img_height
			bordered_container.ratio = aspect_ratio
			print("[Camera] Image aspect ratio: ", aspect_ratio, " (", img_width, "x", img_height, ")")

		# Hide simple preview, show bordered version
		simple_image.visible = false
		bordered_container.visible = true
		record_image.visible = true  # Ensure parent is visible

		# Update RecordImage's minimum size to accommodate the aspect ratio
		await get_tree().process_frame
		_update_record_image_size()

	# Update RecordLabel with animal information
	var common_name: String = ""
	var scientific_name: String = ""
	var kingdom: String = ""
	var phylum: String = ""
	var animal_class: String = ""
	var order: String = ""
	var family: String = ""

	if animal_details.size() > 0:
		var common_name_value = animal_details.get("common_name")
		common_name = "" if common_name_value == null else str(common_name_value)

		var scientific_name_value = animal_details.get("scientific_name")
		scientific_name = "" if scientific_name_value == null else str(scientific_name_value)

		var kingdom_value = animal_details.get("kingdom")
		kingdom = "" if kingdom_value == null else str(kingdom_value)

		var phylum_value = animal_details.get("phylum")
		phylum = "" if phylum_value == null else str(phylum_value)

		var class_value = animal_details.get("class_name")
		animal_class = "" if class_value == null else str(class_value)

		var order_value = animal_details.get("order")
		order = "" if order_value == null else str(order_value)

		var family_value = animal_details.get("family")
		family = "" if family_value == null else str(family_value)

		# Format: "Scientific name - common name"
		var record_text := ""

		# Use scientific name
		if scientific_name.length() > 0:
			record_text = scientific_name

		# Add common name
		if common_name.length() > 0:
			if record_text.length() > 0:
				record_text += " - " + common_name
			else:
				record_text = common_name

		# Fallback if no data
		if record_text.length() == 0:
			record_text = "Unknown"

		record_label.text = record_text
		print("[Camera] Updated RecordLabel: ", record_text)

	# Display detailed results - use same format as RecordLabel
	var result_text := ""

	# Format: "Scientific name - common name"
	if scientific_name.length() > 0:
		result_text = scientific_name
		if common_name.length() > 0:
			result_text += " - " + common_name
	elif common_name.length() > 0:
		result_text = common_name
	else:
		result_text = "Unknown"

	result_label.text = result_text.strip_edges()
	result_label.add_theme_color_override("font_color", Color.GREEN)

	# Save to local dex database if we have all required info
	if animal_details.size() > 0:
		var creation_index_value = animal_details.get("creation_index")
		if creation_index_value != null:
			var creation_index: int = int(creation_index_value)

			# Get the cached image path
			var cached_path := ""
			if dex_compatible_url.length() > 0:
				cached_path = "user://dex_cache/" + dex_compatible_url.md5_text() + ".png"

			# Add to database
			DexDatabase.add_record(
				creation_index,
				scientific_name,
				common_name,
				cached_path
			)

			print("[Camera] Saved to local dex database: #", creation_index)
		else:
			print("[Camera] WARNING: No creation_index in animal_details, not saving to dex")
	else:
		print("[Camera] WARNING: No animal_details, not saving to dex")

	# Re-enable buttons for another upload
	upload_button.disabled = false
	select_photo_button.disabled = false

	# In editor mode, automatically load the next test image
	if OS.has_feature("editor"):
		current_test_image_index += 1
		print("[Camera] Editor mode: Auto-loading next test image in 1 second...")
		await get_tree().create_timer(1.0).timeout
		_load_test_image()


func _stop_status_polling() -> void:
	"""Stop polling for job status"""
	print("[Camera] Stopping status polling")
	status_check_timer.stop()


func _on_back_pressed() -> void:
	"""Navigate back to home"""
	print("[Camera] Back button pressed")
	_stop_status_polling()
	NavigationManager.go_back()


func _exit_tree() -> void:
	"""Cleanup when scene exits"""
	_stop_status_polling()


func _download_and_cache_dex_image(url: String) -> void:
	"""Download the dex-compatible image and cache it locally."""
	if url.length() == 0:
		print("[Camera] No dex-compatible URL provided")
		return

	print("[Camera] Downloading dex-compatible image: ", url)

	var http := HTTPRequest.new()
	add_child(http)

	var headers := []
	if TokenManager.is_logged_in():
		headers.append("Authorization: Bearer " + TokenManager.get_access_token())

	http.request(url, headers)
	var response_array = await http.request_completed

	# Parse response
	var result_code: int = int(response_array[1])  # HTTP status code
	var body: PackedByteArray = response_array[3]  # Response body

	if result_code == 200 and body.size() > 0:
		# Load the PNG image
		var image := Image.new()
		var error := image.load_png_from_buffer(body)

		if error == OK:
			cached_dex_image = image

			# Save to user://dex_cache/ for persistence
			_save_cached_image(url, body)

			print("[Camera] Dex image cached successfully (", image.get_width(), "x", image.get_height(), ")")
		else:
			push_error("[Camera] Failed to load dex image: ", error)
	else:
		push_error("[Camera] Failed to download dex image: HTTP ", result_code)

	http.queue_free()


func _save_cached_image(url: String, data: PackedByteArray) -> void:
	"""Save cached image to local storage."""
	var cache_dir := "user://dex_cache/"
	var dir := DirAccess.open("user://")

	if not dir.dir_exists("dex_cache"):
		dir.make_dir("dex_cache")

	# Use URL hash as filename
	var filename := cache_dir + url.md5_text() + ".png"
	var file := FileAccess.open(filename, FileAccess.WRITE)
	if file:
		file.store_buffer(data)
		file.close()
		print("[Camera] Cached image saved to: ", filename)
	else:
		push_error("[Camera] Failed to save cached image to: ", filename)


func _load_cached_image(url: String) -> Image:
	"""Load previously cached image if available."""
	if url.length() == 0:
		return null

	var filename := "user://dex_cache/" + url.md5_text() + ".png"

	if FileAccess.file_exists(filename):
		var file := FileAccess.open(filename, FileAccess.READ)
		if file:
			var data := file.get_buffer(file.get_length())
			file.close()

			var image := Image.new()
			if image.load_png_from_buffer(data) == OK:
				print("[Camera] Loaded cached image from: ", filename)
				return image

	return null
