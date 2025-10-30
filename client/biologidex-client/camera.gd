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

var file_access_web: FileAccessWeb
var selected_file_name: String = ""
var selected_file_type: String = ""
var selected_file_data: PackedByteArray = PackedByteArray()
var current_job_id: String = ""
var status_check_timer: Timer
var current_image_width: float = 0.0
var current_image_height: float = 0.0
var pending_base64_data: String = ""  # For browser decoder callback


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
		print("[Camera] Running in Godot editor - using test image mode")
		status_label.text = "Editor mode: Test image will be loaded automatically"
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


func _load_image_via_browser(base64_data: String, mime_type: String) -> Image:
	"""
	Re-encode image as PNG using browser's native decoder via JavaScriptBridge.
	This converts problematic JPEG files into PNG format that Godot can load reliably.
	Returns null and starts async conversion.
	"""
	# Only available on Web platform
	if OS.get_name() != "Web":
		return null

	print("[Camera] Starting browser image re-encoding (JPEG → PNG)...")

	# Store base64 data for callback reference
	pending_base64_data = base64_data

	# Create data URL
	var data_url := "data:%s;base64,%s" % [mime_type, base64_data]

	# Inject helper function into global scope if not already present
	JavaScriptBridge.eval("""
		if (typeof window._godot_reencode_image === 'undefined') {
			window._godot_reencode_image = function(dataUrl, callback) {
				const img = new Image();

				img.onload = function() {
					try {
						// Create canvas to re-render the image
						const canvas = document.createElement('canvas');
						canvas.width = img.width;
						canvas.height = img.height;

						const ctx = canvas.getContext('2d');
						ctx.drawImage(img, 0, 0);

						// Convert to PNG data URL
						const pngDataUrl = canvas.toDataURL('image/png');

						// Extract base64 from data:image/png;base64,XXXXX
						const base64 = pngDataUrl.split(',')[1];

						console.log('[Browser] Re-encoded image as PNG:', img.width, 'x', img.height);
						callback(base64);
					} catch (e) {
						console.error('Canvas error:', e);
						callback('');  // Error result
					}
				};

				img.onerror = function() {
					console.error('Failed to load image');
					callback('');  // Error result
				};

				img.src = dataUrl;
			};
		}
	""", true)

	# Create callback for when image is re-encoded
	var callback := JavaScriptBridge.create_callback(_on_browser_image_reencoded)

	# Start re-encoding (this is asynchronous in JavaScript)
	var js_window = JavaScriptBridge.get_interface("window")
	js_window._godot_reencode_image(data_url, callback)

	# Return null - actual processing happens in callback
	return null


func _on_browser_image_reencoded(args: Array) -> void:
	"""Callback when browser finishes re-encoding the image as PNG"""
	if args.size() < 1:
		print("[Camera] Browser re-encoder callback: invalid args")
		_on_browser_reencode_failed()
		return

	var png_base64: String = str(args[0])

	if png_base64.length() == 0:
		print("[Camera] Browser re-encoder failed")
		_on_browser_reencode_failed()
		return

	print("[Camera] Browser re-encoded image to PNG (", png_base64.length(), " chars)")

	# Convert base64 to binary
	var png_data := Marshalls.base64_to_raw(png_base64)

	print("[Camera] PNG data size: ", png_data.size(), " bytes")

	# Load with Godot's PNG decoder (should always work)
	var image := Image.new()
	var image_error := image.load_png_from_buffer(png_data)

	if image_error != OK:
		print("[Camera] ERROR: Failed to load re-encoded PNG: ", image_error)
		_on_browser_reencode_failed()
		return

	print("[Camera] Successfully loaded re-encoded PNG!")

	# Create texture and display
	var texture := ImageTexture.create_from_image(image)

	# Store image dimensions
	current_image_width = float(image.get_width())
	current_image_height = float(image.get_height())

	# Show simple preview (no border) on initial load
	simple_image.texture = texture
	simple_image.visible = true
	bordered_container.visible = false
	record_image.visible = true

	# Update status
	status_label.text = "Photo selected: %s (%d KB)" % [selected_file_name, selected_file_data.size() / 1024]
	status_label.add_theme_color_override("font_color", Color.GREEN)
	progress_label.text = ""

	print("[Camera] Browser re-encoding completed successfully")


func _on_browser_reencode_failed() -> void:
	"""Called when browser re-encoding fails - continue with fallback"""
	print("[Camera] Falling back to Godot's built-in decoder...")
	_load_image_with_godot_decoder()


func _load_image_with_godot_decoder() -> void:
	"""Load image using Godot's built-in decoders (fallback method)"""
	var image := Image.new()
	var image_error := ERR_FILE_UNRECOGNIZED

	# Detect format from magic bytes (file header signatures)
	var format := _detect_image_format(selected_file_data)
	print("[Camera] Detected image format: ", format, " (MIME type: ", selected_file_type, ")")

	# Load using detected format
	match format:
		"png":
			image_error = image.load_png_from_buffer(selected_file_data)
		"jpeg":
			image_error = image.load_jpg_from_buffer(selected_file_data)
		"webp":
			image_error = image.load_webp_from_buffer(selected_file_data)
		"bmp":
			image_error = image.load_bmp_from_buffer(selected_file_data)
		_:
			# Unknown format - try common formats
			print("[Camera] Unknown format, trying PNG then JPEG...")
			image_error = image.load_png_from_buffer(selected_file_data)
			if image_error != OK:
				image_error = image.load_jpg_from_buffer(selected_file_data)

	if image_error == OK and image != null:
		var texture := ImageTexture.create_from_image(image)

		# Store image dimensions
		current_image_width = float(image.get_width())
		current_image_height = float(image.get_height())

		# Show simple preview (no border) on initial load
		simple_image.texture = texture
		simple_image.visible = true
		bordered_container.visible = false

		record_image.visible = true
		print("[Camera] Image loaded into simple preview (", current_image_width, "x", current_image_height, ")")

		# Update UI
		status_label.text = "Photo selected: %s (%d KB)" % [selected_file_name, selected_file_data.size() / 1024]
		status_label.add_theme_color_override("font_color", Color.GREEN)
		progress_label.text = ""
	else:
		# Failed to load image for preview
		print("[Camera] WARNING: Failed to load image for preview (error code: ", image_error, ")")
		print("[Camera] This can happen with some JPEG files that have uncommon encoding.")
		print("[Camera] Upload will still work - the server can handle these files.")

		# Hide preview but allow upload to continue
		record_image.visible = false
		simple_image.visible = false
		bordered_container.visible = false

		# Update UI
		status_label.text = "Photo selected (preview unavailable): %s (%d KB)" % [selected_file_name, selected_file_data.size() / 1024]
		status_label.add_theme_color_override("font_color", Color.YELLOW)
		progress_label.text = "Preview failed, but upload will work"

	upload_button.disabled = false
	print("[Camera] File ready for upload - Size: ", selected_file_data.size(), " bytes")


func _detect_image_format(data: PackedByteArray) -> String:
	"""Detect image format from magic bytes (file header signature)"""
	if data.size() < 4:
		return "unknown"

	# PNG: 89 50 4E 47 (hex) = 137 80 78 71 (decimal)
	if data.size() >= 4 and data[0] == 0x89 and data[1] == 0x50 and data[2] == 0x4E and data[3] == 0x47:
		return "png"

	# JPEG: FF D8 FF (all JPEG variants start with these 3 bytes)
	if data.size() >= 3 and data[0] == 0xFF and data[1] == 0xD8 and data[2] == 0xFF:
		return "jpeg"

	# WebP: RIFF ... WEBP (check for "RIFF" at start and "WEBP" at offset 8)
	if data.size() >= 12:
		# Check for "RIFF" (52 49 46 46)
		if data[0] == 0x52 and data[1] == 0x49 and data[2] == 0x46 and data[3] == 0x46:
			# Check for "WEBP" at offset 8 (57 45 42 50)
			if data[8] == 0x57 and data[9] == 0x45 and data[10] == 0x42 and data[11] == 0x50:
				return "webp"

	# BMP: 42 4D (hex) = "BM" (ASCII)
	if data.size() >= 2 and data[0] == 0x42 and data[1] == 0x4D:
		return "bmp"

	return "unknown"


func _on_file_load_started(file_name: String) -> void:
	"""Called when file starts loading"""
	print("[Camera] File load started: ", file_name)
	status_label.text = "Loading file: %s" % file_name
	progress_label.text = ""


func _on_file_loaded(file_name: String, file_type: String, base64_data: String) -> void:
	"""Called when file is fully loaded"""
	print("[Camera] File loaded: ", file_name, " Type: ", file_type, " Size: ", base64_data.length())

	# Convert base64 to binary
	selected_file_data = Marshalls.base64_to_raw(base64_data)
	selected_file_name = file_name
	selected_file_type = file_type

	# On Web platform, try browser re-encoding first (async)
	if OS.get_name() == "Web":
		print("[Camera] Web platform detected - using browser re-encoding...")
		_load_image_via_browser(base64_data, file_type)
		# Callback will handle the rest - don't continue here
		# Still enable upload button so user can proceed even if preview fails
		upload_button.disabled = false
		status_label.text = "Loading preview..."
		status_label.add_theme_color_override("font_color", Color.WHITE)
		return

	# Non-web platform: Use Godot's built-in decoders
	print("[Camera] Non-web platform, using Godot's built-in decoders...")
	_load_image_with_godot_decoder()


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
	const TEST_IMAGE_PATH := "res://resources/test_img.jpeg"

	print("[Camera] Loading test image from: ", TEST_IMAGE_PATH)
	status_label.text = "Loading test image..."

	# Load image file
	var image := Image.new()
	var load_error := image.load(TEST_IMAGE_PATH)

	if load_error != OK:
		print("[Camera] ERROR: Failed to load test image: ", load_error)
		status_label.text = "Error: Could not load test image"
		status_label.add_theme_color_override("font_color", Color.RED)
		return

	# Convert image to PNG bytes for upload
	selected_file_data = image.save_png_to_buffer()
	selected_file_name = "test_img.jpeg"
	selected_file_type = "image/jpeg"

	print("[Camera] Test image loaded - Size: ", selected_file_data.size(), " bytes")

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

	# Update UI
	status_label.text = "Test image loaded (%d KB)" % [selected_file_data.size() / 1024]
	status_label.add_theme_color_override("font_color", Color.GREEN)
	upload_button.disabled = false

	print("[Camera] Test image ready for upload")


func _update_record_image_size() -> void:
	"""Update RecordImage's custom_minimum_size to match AspectRatioContainer's calculated height"""
	# Get the available width from the parent container
	var available_width: float = float(record_image.get_parent_control().size.x)

	# Cap width at actual image width (don't upscale beyond native resolution)
	var max_width: float = current_image_width
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

	# Upload via API
	APIManager.create_vision_job(
		selected_file_data,
		selected_file_name,
		selected_file_type,
		access_token,
		_on_upload_completed
	)


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

	# Switch from simple preview to bordered display with label
	if simple_image.texture != null:
		# Get image from simple preview
		var texture := simple_image.texture
		bordered_image.texture = texture

		# Calculate aspect ratio from the texture
		var img_width: float = float(texture.get_width())
		var img_height: float = float(texture.get_height())
		if img_height > 0.0:
			var aspect_ratio: float = img_width / img_height
			bordered_container.ratio = aspect_ratio
			print("[Camera] Image aspect ratio: ", aspect_ratio)

		# Hide simple preview, show bordered version
		simple_image.visible = false
		bordered_container.visible = true

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

	# Re-enable buttons for another upload
	upload_button.disabled = false
	select_photo_button.disabled = false


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