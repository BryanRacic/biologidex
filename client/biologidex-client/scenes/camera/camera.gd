extends Control

# Camera/Upload scene - Handles photo selection and upload for CV analysis
# Uses godot-file-access-web plugin for HTML5 file access

# Services
var TokenManager
var NavigationManager
var APIManager
var DexDatabase

# UI Elements
@onready var select_photo_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/SelectPhotoButton
@onready var upload_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/UploadButton
@onready var manual_entry_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/ManualEntryButton
@onready var status_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/StatusLabel
@onready var progress_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/ProgressLabel
@onready var loading_spinner: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/LoadingSpinner
@onready var result_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/ResultLabel
@onready var instruction_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/InstructionLabel
@onready var rotate_image_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RotateImageButton
@onready var back_button: Button = $Panel/MarginContainer/VBoxContainer/Header/BackButton
@onready var record_image: Control = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage
@onready var simple_image: TextureRect = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/Image
@onready var bordered_container: AspectRatioContainer = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio
@onready var bordered_image: TextureRect = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio/ImageBorder/Image
@onready var record_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio/ImageBorder/RecordMargin/RecordBackground/RecordTextMargin/RecordLabel

# State machine for camera workflow
enum CameraState {
	IDLE,                    # No image selected
	IMAGE_SELECTED,          # User selected file from disk
	IMAGE_CONVERTING,        # Uploading to /images/convert/
	IMAGE_READY,             # Downloaded converted image, can rotate/analyze
	ANALYZING,               # CV analysis in progress
	ANALYSIS_COMPLETE,       # Analysis done, have results
	ANIMAL_SELECTION,        # Multiple animals detected, showing selection UI
	COMPLETED                # Final state, dex entry created
}

var current_state: CameraState = CameraState.IDLE

var file_access_web: FileAccessWeb
var selected_file_name: String = ""
var selected_file_type: String = ""
var selected_file_data: PackedByteArray = PackedByteArray()
var conversion_id: String = ""                # UUID from image conversion
var converted_image_data: PackedByteArray     # Downloaded PNG data
var current_job_id: String = ""
var current_dex_entry_id: String = ""
var status_check_timer: Timer
var current_image_width: float = 0.0
var current_image_height: float = 0.0
var unsupported_format_warning: bool = false
var cached_dex_image: Image = null

# Image rotation state (client-side only, sent with CV analysis)
var total_rotation: int = 0  # Cumulative rotation angle (0, 90, 180, 270)
var detected_animals: Array = []              # List from CV analysis
var selected_animal_index: int = -1           # User's choice
var pending_animal_details: Dictionary = {}   # Animal data from CV, pending dex entry creation

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

	# Initialize services (with fallback to autoloads)
	_initialize_services()

	# Check authentication
	if not TokenManager.is_logged_in():
		print("[Camera] ERROR: User not logged in")
		NavigationManager.go_back()
		return


func _initialize_services() -> void:
	"""Initialize service references from autoloads"""
	TokenManager = get_node("/root/TokenManager")
	NavigationManager = get_node("/root/NavigationManager")
	APIManager = get_node("/root/APIManager")
	DexDatabase = get_node("/root/DexDatabase")

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
	manual_entry_button.pressed.connect(_on_manual_entry_pressed)
	rotate_image_button.pressed.connect(_on_rotate_image_pressed)
	back_button.pressed.connect(_on_back_pressed)

	# Create timer for status polling
	status_check_timer = Timer.new()
	add_child(status_check_timer)
	status_check_timer.timeout.connect(_check_job_status)


func _reset_ui() -> void:
	"""Reset UI to initial state"""
	current_state = CameraState.IDLE
	upload_button.disabled = true
	upload_button.text = "Upload & Convert"
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
	conversion_id = ""
	converted_image_data = PackedByteArray()
	total_rotation = 0
	detected_animals = []
	selected_animal_index = -1

	# Show initial buttons
	select_photo_button.visible = true
	instruction_label.visible = true
	rotate_image_button.visible = false


func _on_rotate_image_pressed() -> void:
	"""Rotate image 90 degrees clockwise - only works in IMAGE_READY state"""
	if current_state != CameraState.IMAGE_READY and current_state != CameraState.IMAGE_SELECTED:
		return

	total_rotation = (total_rotation + 90) % 360
	_apply_rotation_to_preview()
	print("[Camera] Rotated to %d degrees" % total_rotation)


func _apply_rotation_to_preview() -> void:
	"""Apply visual rotation to the displayed converted image"""
	# Get the current texture and extract the image
	var current_texture := simple_image.texture as ImageTexture
	if not current_texture:
		print("[Camera] ERROR: No texture to rotate")
		return

	var image := current_texture.get_image()
	if not image:
		print("[Camera] ERROR: Could not get image from texture")
		return

	# Rotate the image data 90 degrees clockwise
	image.rotate_90(CLOCKWISE)

	# Create new texture from rotated image
	var new_texture := ImageTexture.create_from_image(image)
	simple_image.texture = new_texture

	# Update cached image (this is what we'll use for dex entry)
	cached_dex_image = image

	# Update dimensions (they swap with each 90° rotation)
	var temp: float = current_image_width
	current_image_width = current_image_height
	current_image_height = temp

	print("[Camera] Rotated display to %dx%d (total rotation: %d degrees)" % [current_image_width, current_image_height, total_rotation])

	# Update aspect ratio for the bordered container (for future use)
	if current_image_height > 0.0:
		var aspect_ratio: float = current_image_width / current_image_height
		bordered_container.ratio = aspect_ratio

	# Note: We don't call _update_record_image_size() here because:
	# - simple_image is visible (not bordered_container)
	# - simple_image uses stretch_mode = 5 (Keep Aspect Centered) which handles sizing automatically


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

	# Update visibility: Hide select/instruction, show rotation button when preview succeeds
	if preview_result.success:
		select_photo_button.visible = false
		instruction_label.visible = false
		rotate_image_button.visible = true
		rotate_image_button.disabled = false  # Re-enable rotation button
		total_rotation = 0  # Reset rotation
		current_state = CameraState.IMAGE_SELECTED  # Update state

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

		# Hide select/instruction, show rotation button on successful load
		select_photo_button.visible = false
		instruction_label.visible = false
		rotate_image_button.visible = true
		rotate_image_button.disabled = false  # Re-enable rotation button
		total_rotation = 0  # Reset rotation
		current_state = CameraState.IMAGE_SELECTED  # Update state
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
	"""Handle upload button press based on current state"""
	match current_state:
		CameraState.IMAGE_SELECTED:
			if selected_file_data.size() == 0:
				print("[Camera] ERROR: No file selected")
				return
			_start_image_conversion()  # Step 1: Upload & Convert
		CameraState.IMAGE_READY:
			_start_cv_analysis()       # Step 2: Analyze
		CameraState.COMPLETED:
			_create_dex_entry()        # Step 3: Create Dex Entry
		_:
			push_error("[Camera] Upload pressed in invalid state: %s" % current_state)


func _start_image_conversion() -> void:
	"""Step 1: Upload image for conversion"""
	print("[Camera] Starting image conversion...")
	current_state = CameraState.IMAGE_CONVERTING

	# Update UI
	upload_button.disabled = true
	select_photo_button.disabled = true
	rotate_image_button.disabled = true
	loading_spinner.visible = true
	status_label.text = "Uploading and converting image..."
	status_label.add_theme_color_override("font_color", Color.WHITE)
	result_label.text = ""

	# Call conversion API
	APIManager.images.convert_image(
		selected_file_data,
		selected_file_name,
		selected_file_type,
		_on_image_converted
	)


func _on_image_converted(response: Dictionary, code: int) -> void:
	"""Handle image conversion completion"""
	if code != 201 and code != 200:
		# Conversion failed
		var error_msg = response.get("error", "Conversion failed")
		print("[Camera] Conversion failed: ", error_msg)
		status_label.text = "Conversion failed: %s" % error_msg
		status_label.add_theme_color_override("font_color", Color.RED)
		loading_spinner.visible = false
		upload_button.disabled = false
		select_photo_button.disabled = false
		rotate_image_button.disabled = false
		current_state = CameraState.IMAGE_SELECTED
		return

	# Store conversion ID
	conversion_id = response.get("id", "")
	print("[Camera] Image converted! ID: ", conversion_id)

	status_label.text = "Downloading converted image..."

	# Download converted image
	APIManager.images.download_converted_image(
		conversion_id,
		_on_converted_image_downloaded
	)


func _on_converted_image_downloaded(response: Dictionary, code: int) -> void:
	"""Handle downloaded converted image"""
	if code != 200:
		var error_msg = response.get("error", "Download failed")
		print("[Camera] Download failed: ", error_msg)
		status_label.text = "Download failed: %s" % error_msg
		status_label.add_theme_color_override("font_color", Color.RED)
		loading_spinner.visible = false
		upload_button.disabled = false
		select_photo_button.disabled = false
		rotate_image_button.disabled = false
		current_state = CameraState.IMAGE_SELECTED
		return

	# Get image data
	converted_image_data = response.get("data", PackedByteArray())

	if converted_image_data.size() == 0:
		print("[Camera] ERROR: Empty converted image data")
		status_label.text = "Error: Empty image data"
		status_label.add_theme_color_override("font_color", Color.RED)
		loading_spinner.visible = false
		upload_button.disabled = false
		select_photo_button.disabled = false
		rotate_image_button.disabled = false
		current_state = CameraState.IMAGE_SELECTED
		return

	# Load and display converted image
	var image := Image.new()
	var load_error := image.load_png_from_buffer(converted_image_data)

	if load_error != OK:
		print("[Camera] ERROR: Could not load converted image")
		status_label.text = "Error loading converted image"
		status_label.add_theme_color_override("font_color", Color.RED)
		loading_spinner.visible = false
		upload_button.disabled = false
		select_photo_button.disabled = false
		rotate_image_button.disabled = false
		current_state = CameraState.IMAGE_SELECTED
		return

	# CRITICAL: Replace the preview with the converted image
	var texture := ImageTexture.create_from_image(image)
	simple_image.texture = texture
	current_image_width = float(image.get_width())
	current_image_height = float(image.get_height())

	# Store the converted image for later use (dex entry creation)
	cached_dex_image = image

	print("[Camera] Converted image loaded and displayed: %dx%d" % [current_image_width, current_image_height])

	# Update UI for IMAGE_READY state
	current_state = CameraState.IMAGE_READY
	loading_spinner.visible = false
	status_label.text = "Image ready! Rotate if needed, then click Analyze."
	status_label.add_theme_color_override("font_color", Color.GREEN)
	upload_button.disabled = false
	upload_button.text = "Analyze Image"
	select_photo_button.disabled = false
	rotate_image_button.disabled = false
	total_rotation = 0  # Reset rotation tracker


func _start_cv_analysis() -> void:
	"""Step 2: Submit for CV analysis"""
	if conversion_id.is_empty():
		print("[Camera] ERROR: No conversion_id available")
		return

	print("[Camera] Starting CV analysis...")
	current_state = CameraState.ANALYZING

	# Update UI
	upload_button.disabled = true
	select_photo_button.disabled = true
	rotate_image_button.disabled = true
	loading_spinner.visible = true
	status_label.text = "Analyzing image..."
	status_label.add_theme_color_override("font_color", Color.WHITE)

	# Build post-conversion transformations
	var post_transformations = {}
	if total_rotation > 0:
		post_transformations["rotation"] = total_rotation
		print("[Camera] Sending rotation: %d degrees" % total_rotation)

	# Call vision API with conversion_id
	APIManager.vision.create_vision_job_from_conversion(
		conversion_id,
		_on_vision_job_created,
		post_transformations
	)


func _on_vision_job_created(response: Dictionary, code: int) -> void:
	"""Handle vision job creation"""
	if code != 200 and code != 201:
		var error_msg = response.get("error", "Failed to create vision job")
		print("[Camera] Vision job creation failed: ", error_msg)
		status_label.text = "Analysis failed: %s" % error_msg
		status_label.add_theme_color_override("font_color", Color.RED)
		loading_spinner.visible = false
		upload_button.disabled = false
		upload_button.text = "Analyze Image"
		select_photo_button.disabled = false
		rotate_image_button.disabled = false
		current_state = CameraState.IMAGE_READY
		return

	current_job_id = str(response.get("id", ""))
	print("[Camera] Vision job created: ", current_job_id)

	# Start polling
	_start_status_polling()


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

	APIManager.vision.get_vision_job(
		current_job_id,
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
	"""Handle completed analysis job - support multiple animal detection"""
	print("[Camera] Analysis complete!")
	current_state = CameraState.ANALYSIS_COMPLETE

	loading_spinner.visible = false
	status_label.text = "Analysis complete!"
	status_label.add_theme_color_override("font_color", Color.GREEN)

	# Extract detected animals list (NEW multi-animal support)
	var detected_animals_value = job_data.get("detected_animals", [])
	if typeof(detected_animals_value) == TYPE_ARRAY:
		detected_animals = detected_animals_value
	else:
		detected_animals = []

	print("[Camera] Detected %d animals" % detected_animals.size())

	# Handle results based on animal count
	if detected_animals.size() == 0:
		# No animals detected - allow manual entry
		status_label.text = "No animals detected"
		status_label.add_theme_color_override("font_color", Color.ORANGE)
		result_label.text = "Try manual entry or upload a different image"
		upload_button.visible = false
		manual_entry_button.visible = true
		manual_entry_button.disabled = false
		select_photo_button.disabled = false
		rotate_image_button.visible = false
		return
	elif detected_animals.size() == 1:
		# Single animal - auto-select and continue
		selected_animal_index = 0
		print("[Camera] Single animal detected, auto-selecting")
	else:
		# Multiple animals - show selection UI
		current_state = CameraState.ANIMAL_SELECTION
		_show_animal_selection_popup()
		return

	# Process the selected animal (either single or user-selected)
	_process_selected_animal(job_data)


func _show_animal_selection_popup() -> void:
	"""Show popup for selecting from multiple detected animals"""
	print("[Camera] Showing animal selection popup for %d animals" % detected_animals.size())

	# TODO: Create proper AnimalSelectionPopup component
	# For now, auto-select first animal as fallback
	print("[Camera] WARNING: Animal selection popup not implemented yet, auto-selecting first")
	selected_animal_index = 0

	# Call select_animal API
	APIManager.vision.select_animal(
		current_job_id,
		selected_animal_index,
		_on_animal_selected
	)


func _on_animal_selected(response: Dictionary, code: int) -> void:
	"""Handle animal selection response"""
	if code != 200:
		var error_msg = response.get("error", "Selection failed")
		print("[Camera] Animal selection failed: ", error_msg)
		status_label.text = "Selection failed: %s" % error_msg
		status_label.add_theme_color_override("font_color", Color.RED)
		upload_button.disabled = false
		select_photo_button.disabled = false
		return

	print("[Camera] Animal selected successfully")
	_process_selected_animal(response)


func _process_selected_animal(job_data: Dictionary) -> void:
	"""Display CV results and show 'Create Dex Entry' button (without showing dex image yet)"""
	print("[Camera] Displaying analysis results")

	# Get selected animal data from detected_animals array
	var animal_details: Dictionary = {}
	if selected_animal_index >= 0 and selected_animal_index < detected_animals.size():
		animal_details = detected_animals[selected_animal_index]
		print("[Camera] Processing selected animal at index %d" % selected_animal_index)

		# Merge with root animal_details if available (has creation_index and full data)
		var root_animal_details = job_data.get("animal_details")
		if root_animal_details != null and typeof(root_animal_details) == TYPE_DICTIONARY:
			# Check if the animal IDs match
			var detected_id = animal_details.get("animal_id", "")
			var root_id = root_animal_details.get("id", "")
			if detected_id == root_id:
				# Merge: root has creation_index, detected has confidence
				print("[Camera] Merging detected_animals with root animal_details")
				animal_details = root_animal_details.duplicate()
				# Keep the animal_id field from detected_animals for consistency
				animal_details["animal_id"] = detected_id

	# Extract animal information
	var confidence_value = job_data.get("confidence_score")
	var confidence: float = 0.0
	if confidence_value != null:
		confidence = float(confidence_value)

	print("[Camera] Confidence: ", confidence)
	print("[Camera] Animal details: ", animal_details)

	# Extract names for display
	var common_name: String = ""
	var scientific_name: String = ""

	if animal_details.size() > 0:
		var common_name_value = animal_details.get("common_name")
		common_name = "" if common_name_value == null else str(common_name_value)

		var scientific_name_value = animal_details.get("scientific_name")
		scientific_name = "" if scientific_name_value == null else str(scientific_name_value)

	# Display results text only (keep simple preview visible)
	var result_text := ""
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

	# Update status and show "Create Dex Entry" button
	status_label.text = "Analysis complete! Click 'Create Dex Entry' to save."
	status_label.add_theme_color_override("font_color", Color.GREEN)
	loading_spinner.visible = false

	# Change upload button to "Create Dex Entry"
	upload_button.text = "Create Dex Entry"
	upload_button.disabled = false
	upload_button.visible = true

	# Store animal data for dex entry creation (don't show dex image yet)
	current_dex_entry_id = ""  # Reset
	pending_animal_details = animal_details  # Store for later dex entry creation

	# Keep simple preview visible, hide rotation button
	select_photo_button.visible = false
	rotate_image_button.visible = false
	manual_entry_button.visible = true  # Allow manual correction

	current_state = CameraState.COMPLETED


func _display_dex_image(scientific_name: String, common_name: String) -> void:
	"""Display the bordered dex image with animal label"""
	print("[Camera] Displaying bordered dex image")

	# Use the cached_dex_image we already have (from converted download + rotation)
	var display_image: Image = cached_dex_image

	if display_image != null:
		var texture := ImageTexture.create_from_image(display_image)
		bordered_image.texture = texture

		# Calculate aspect ratio from the image
		var img_width: float = float(display_image.get_width())
		var img_height: float = float(display_image.get_height())

		# Update dimensions
		current_image_width = img_width
		current_image_height = img_height

		if img_height > 0.0:
			var aspect_ratio: float = img_width / img_height
			bordered_container.ratio = aspect_ratio
			print("[Camera] Image aspect ratio: ", aspect_ratio, " (", img_width, "x", img_height, ")")

		# Format label: "Scientific name - common name"
		var record_text := ""
		if scientific_name.length() > 0:
			record_text = scientific_name
		if common_name.length() > 0:
			if record_text.length() > 0:
				record_text += " - " + common_name
			else:
				record_text = common_name
		if record_text.length() == 0:
			record_text = "Unknown"

		record_label.text = record_text
		print("[Camera] Updated RecordLabel: ", record_text)

		# Hide simple preview, show bordered version
		simple_image.visible = false
		bordered_container.visible = true
		record_image.visible = true

		# Update RecordImage's minimum size
		await get_tree().process_frame
		_update_record_image_size()


func _create_dex_entry() -> void:
	"""Step 3: Create dex entry with vision_job linkage and display bordered dex image"""
	print("[Camera] Creating dex entry...")

	# Get animal ID from pending_animal_details
	# Note: detected_animals uses "animal_id", but manual entry uses "id"
	var animal_id_value = pending_animal_details.get("animal_id")
	if animal_id_value == null:
		animal_id_value = pending_animal_details.get("id")

	if animal_id_value == null:
		print("[Camera] ERROR: No animal ID in pending details")
		print("[Camera] pending_animal_details keys: ", pending_animal_details.keys())
		status_label.text = "Error: Missing animal data"
		status_label.add_theme_color_override("font_color", Color.RED)
		return

	var animal_id: String = str(animal_id_value)
	var creation_index: int = int(pending_animal_details.get("creation_index", 0))
	var scientific_name: String = str(pending_animal_details.get("scientific_name", ""))
	var common_name: String = str(pending_animal_details.get("common_name", ""))

	# NOW display the bordered dex image with label
	_display_dex_image(scientific_name, common_name)

	# Update UI
	upload_button.disabled = true
	loading_spinner.visible = true
	status_label.text = "Creating dex entry..."
	status_label.add_theme_color_override("font_color", Color.WHITE)

	# Save image to local cache
	var cached_path := ""
	if cached_dex_image != null:
		# Save to user://dex_cache/{user_id}/
		var user_id = TokenManager.get_user_id()
		var cache_dir = "user://dex_cache/%s/" % user_id
		var dir = DirAccess.open("user://dex_cache/")
		if not dir:
			dir = DirAccess.open("user://")
			dir.make_dir("dex_cache")
			dir = DirAccess.open("user://dex_cache/")
		if not dir.dir_exists(user_id):
			dir.make_dir(user_id)

		# Use creation_index for filename
		cached_path = "%s%d.png" % [cache_dir, creation_index]
		var png_data = cached_dex_image.save_png_to_buffer()
		var file = FileAccess.open(cached_path, FileAccess.WRITE)
		if file:
			file.store_buffer(png_data)
			file.close()
			print("[Camera] Saved image to cache: ", cached_path)

	# Add to local database with animal_id for future matching
	var record_dict = {
		"creation_index": creation_index,
		"scientific_name": scientific_name,
		"common_name": common_name,
		"cached_image_path": cached_path,
		"animal_id": animal_id  # Store for matching with server entries
	}
	DexDatabase.add_record_from_dict(record_dict, "self")
	print("[Camera] Added to local database: #%d with animal_id: %s" % [creation_index, animal_id])

	# Create server-side entry with vision_job linkage
	APIManager.dex.create_entry(
		animal_id,
		current_job_id,  # vision_job_id
		"",  # notes
		"friends",  # visibility
		_on_dex_entry_final_created
	)


func _on_dex_entry_final_created(response: Dictionary, code: int) -> void:
	"""Handle final dex entry creation"""
	loading_spinner.visible = false

	if code == 200 or code == 201:
		current_dex_entry_id = str(response.get("id", ""))
		print("[Camera] Dex entry created successfully: ", current_dex_entry_id)

		# Update local database with server entry ID for future editing
		var creation_index = int(pending_animal_details.get("creation_index", 0))
		if creation_index > 0:
			var user_id = TokenManager.get_user_id()
			var record = DexDatabase.get_record_for_user(creation_index, user_id)
			if not record.is_empty():
				record["dex_entry_id"] = current_dex_entry_id
				DexDatabase.add_record_from_dict(record, user_id)
				print("[Camera] Stored dex_entry_id in local database")

		status_label.text = "Dex entry created!"
		status_label.add_theme_color_override("font_color", Color.GREEN)

		# Show success and allow new upload
		upload_button.visible = false
		select_photo_button.visible = true
		select_photo_button.disabled = false
		instruction_label.visible = true

		# In editor mode, increment test image index
		if OS.has_feature("editor"):
			current_test_image_index += 1
			print("[Camera] Test image complete. Press 'Select Photo' for next image.")
	else:
		var error_msg = response.get("error", "Unknown error")
		print("[Camera] Failed to create dex entry: ", error_msg)
		status_label.text = "Failed to create entry: %s" % error_msg
		status_label.add_theme_color_override("font_color", Color.RED)
		upload_button.disabled = false


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


func _on_manual_entry_pressed() -> void:
	"""Open manual entry popup for taxonomic search"""
	print("[Camera] Opening manual entry popup")

	# Create and configure popup
	var popup_scene = load("res://scenes/social/components/manual_entry_popup.tscn")
	if not popup_scene:
		print("[Camera] ERROR: Could not load manual entry popup scene")
		return

	var popup = popup_scene.instantiate()

	# Set current dex entry if available
	if not current_dex_entry_id.is_empty():
		popup.current_dex_entry_id = current_dex_entry_id
		print("[Camera] Set dex entry ID: ", current_dex_entry_id)

	# Connect signals
	popup.entry_updated.connect(_on_manual_entry_updated)
	popup.popup_closed.connect(_on_manual_entry_closed)

	# Add to scene and show
	add_child(popup)
	popup.popup_centered(Vector2(600, 500))


func _on_manual_entry_updated(taxonomy_data: Dictionary) -> void:
	"""Handle manual entry update - updates pending_animal_details for later dex creation"""
	print("[Camera] Manual entry updated with taxonomy: ", taxonomy_data.get("scientific_name", ""))

	# Update pending_animal_details with the new animal data
	# The taxonomy_data contains the full animal record from the lookup_or_create call
	var animal_details = taxonomy_data.get("animal", {})
	if animal_details.is_empty():
		# Fallback: use taxonomy_data directly if no nested animal field
		animal_details = taxonomy_data

	if not animal_details.is_empty():
		# Update pending_animal_details so when user clicks "Create Dex Entry", it uses the new animal
		pending_animal_details = animal_details
		print("[Camera] Updated pending_animal_details with manual selection")

		var scientific_name = animal_details.get("scientific_name", "")
		var common_name = animal_details.get("common_name", "")

		# Update the result label to show new selection
		var display_text = scientific_name
		if not common_name.is_empty():
			display_text += " - " + common_name

		if display_text.length() > 0:
			result_label.text = display_text
			result_label.add_theme_color_override("font_color", Color.GREEN)

	status_label.text = "Selection updated! Click 'Create Dex Entry' to save."
	status_label.add_theme_color_override("font_color", Color.GREEN)


func _on_manual_entry_closed() -> void:
	"""Handle manual entry popup closed"""
	print("[Camera] Manual entry popup closed")
