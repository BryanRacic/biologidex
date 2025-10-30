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
@onready var aspect_ratio_container: AspectRatioContainer = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/AspectRatioContainer
@onready var record_texture: TextureRect = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/AspectRatioContainer/ImageBorder/Image

var file_access_web: FileAccessWeb
var selected_file_name: String = ""
var selected_file_type: String = ""
var selected_file_data: PackedByteArray = PackedByteArray()
var current_job_id: String = ""
var status_check_timer: Timer


func _ready() -> void:
	print("[Camera] Scene loaded")

	# Check authentication
	if not TokenManager.is_logged_in():
		print("[Camera] ERROR: User not logged in")
		NavigationManager.go_back()
		return

	# Initialize UI state
	_reset_ui()

	# Initialize FileAccessWeb plugin (only works on HTML5)
	if OS.get_name() == "Web":
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
	progress_label.text = ""
	status_label.text = "Select a photo to identify an animal"
	status_label.add_theme_color_override("font_color", Color.WHITE)
	result_label.text = ""
	selected_file_name = ""
	selected_file_type = ""
	selected_file_data = PackedByteArray()


func _on_select_photo_pressed() -> void:
	"""Open file picker for photo selection"""
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

	# Convert base64 to binary
	selected_file_data = Marshalls.base64_to_raw(base64_data)
	selected_file_name = file_name
	selected_file_type = file_type

	# Load image into RecordImage
	var image := Image.new()
	var image_error := image.load_png_from_buffer(selected_file_data)
	if image_error != OK:
		image_error = image.load_jpg_from_buffer(selected_file_data)

	if image_error == OK:
		var texture := ImageTexture.create_from_image(image)
		record_texture.texture = texture

		# Update aspect ratio container to match image
		var img_width: float = float(image.get_width())
		var img_height: float = float(image.get_height())
		if img_height > 0.0:
			var aspect_ratio: float = img_width / img_height
			aspect_ratio_container.ratio = aspect_ratio
			print("[Camera] Image aspect ratio: ", aspect_ratio)

		record_image.visible = true
		print("[Camera] Image loaded into preview")
	else:
		print("[Camera] ERROR: Failed to load image for preview: ", image_error)

	# Update UI
	status_label.text = "Photo selected: %s (%d KB)" % [file_name, selected_file_data.size() / 1024]
	status_label.add_theme_color_override("font_color", Color.GREEN)
	upload_button.disabled = false
	progress_label.text = ""

	print("[Camera] File ready for upload - Size: ", selected_file_data.size(), " bytes")


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

	# Display results
	var result_text := "Identified: %s" % prediction
	if confidence > 0.0:
		result_text += "\nConfidence: %.1f%%" % (confidence * 100.0)

	if animal_details.size() > 0:
		var common_name_value = animal_details.get("common_name")
		var common_name: String = "" if common_name_value == null else str(common_name_value)
		if common_name.length() > 0:
			result_text += "\nCommon name: %s" % common_name

	result_label.text = result_text
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