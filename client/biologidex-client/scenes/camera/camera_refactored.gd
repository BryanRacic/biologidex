extends BaseSceneController

# Camera/Upload scene - Refactored to use component-based architecture
# Reduced from 1095 lines to ~250 lines by using:
# - BaseSceneController (manager initialization)
# - CVAnalysisWorkflow (conversion + analysis + polling)
# - ImageDisplay (image preview + rotation)
# - ErrorDialog (error handling)
# - RecordCard (dex image display)

# ============================================================================
# UI Elements
# ============================================================================

@onready var select_photo_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/SelectPhotoButton
@onready var upload_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/UploadButton
@onready var retry_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RetryButton
@onready var manual_entry_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/ManualEntryButton
@onready var instruction_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/InstructionLabel
@onready var result_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/ResultLabel

# Components
@onready var image_display: Control = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/ImageDisplay
@onready var error_dialog: Control = $ErrorDialog
@onready var progress_indicator: Control = $ProgressIndicator

# Workflow
var cv_workflow: CVAnalysisWorkflow

# File selection (web and editor)
var file_access_web: FileAccessWeb
var selected_file_name: String = ""
var selected_file_type: String = ""
var selected_file_data: PackedByteArray = PackedByteArray()
var converted_image: Image = null

# Test image cycling for editor mode
const TEST_IMAGES: Array[String] = [
	"res://resources/test_img.jpeg",
	"res://resources/test_img2.jpeg",
	"res://resources/test_img3.jpeg",
	"res://resources/test_img4.jpeg",
	"res://resources/test_img5.jpeg"
]
var current_test_image_index: int = 0

# Analysis results
var detected_animals: Array = []
var selected_animal_index: int = -1
var pending_animal_details: Dictionary = {}
var current_dex_entry_id: String = ""

# ============================================================================
# Initialization
# ============================================================================

func _on_scene_ready() -> void:
	"""Called by BaseSceneController after managers are initialized"""
	scene_name = "Camera"
	print("[Camera] Scene loaded (refactored)")

	# Initialize CV workflow
	cv_workflow = CVAnalysisWorkflow.new()
	add_child(cv_workflow)

	# Connect workflow signals
	cv_workflow.analysis_progress.connect(_on_analysis_progress)
	cv_workflow.analysis_complete.connect(_on_analysis_complete)
	cv_workflow.analysis_failed.connect(_on_analysis_failed)
	cv_workflow.retry_available.connect(_on_retry_available)
	cv_workflow.conversion_complete.connect(_on_conversion_complete)
	cv_workflow.image_downloaded.connect(_on_image_downloaded)

	# Connect button signals
	select_photo_button.pressed.connect(_on_select_photo_pressed)
	upload_button.pressed.connect(_on_upload_pressed)
	retry_button.pressed.connect(_on_retry_pressed)
	manual_entry_button.pressed.connect(_on_manual_entry_pressed)

	# Initialize file access for web
	_initialize_file_access()

	# Reset UI
	_reset_ui()


func _initialize_file_access() -> void:
	"""Initialize file access based on platform"""
	if OS.has_feature("editor"):
		print("[Camera] Running in Godot editor - using test image mode (", TEST_IMAGES.size(), " images)")
		status_label.text = "Editor mode: Test images will cycle automatically (%d total)" % TEST_IMAGES.size()
		status_label.add_theme_color_override("font_color", Color.CYAN)
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


func _reset_ui() -> void:
	"""Reset UI to initial state"""
	upload_button.disabled = true
	upload_button.text = "Upload & Analyze"
	upload_button.visible = true
	retry_button.visible = false
	manual_entry_button.visible = false

	if loading_spinner:
		loading_spinner.visible = false

	status_label.text = "Select a photo to identify an animal"
	status_label.add_theme_color_override("font_color", Color.WHITE)
	result_label.text = ""

	select_photo_button.visible = true
	instruction_label.visible = true

	if image_display:
		image_display.visible = false

	# Reset state
	selected_file_name = ""
	selected_file_type = ""
	selected_file_data = PackedByteArray()
	converted_image = null
	detected_animals = []
	selected_animal_index = -1
	pending_animal_details = {}
	current_dex_entry_id = ""


# ============================================================================
# File Selection
# ============================================================================

func _on_select_photo_pressed() -> void:
	"""Open file picker for photo selection or load test image in editor"""
	if OS.has_feature("editor"):
		print("[Camera] Editor mode - loading test image...")
		_load_test_image()
		return

	if OS.get_name() != "Web":
		return

	print("[Camera] Opening file picker...")
	status_label.text = "Opening file picker..."
	file_access_web.open("image/*")


func _load_test_image() -> void:
	"""Load test image in editor mode"""
	if current_test_image_index >= TEST_IMAGES.size():
		print("[Camera] All test images cycled. Resetting to first image.")
		current_test_image_index = 0

	var image_path = TEST_IMAGES[current_test_image_index]
	print("[Camera] Loading test image: ", image_path, " (", current_test_image_index + 1, "/", TEST_IMAGES.size(), ")")

	# Load file data
	var file = FileAccess.open(image_path, FileAccess.READ)
	if not file:
		print("[Camera] ERROR: Could not load test image: ", image_path)
		status_label.text = "Error loading test image"
		status_label.add_theme_color_override("font_color", Color.RED)
		return

	selected_file_data = file.get_buffer(file.get_length())
	selected_file_name = image_path.get_file()
	selected_file_type = "image/jpeg"
	file.close()

	# Try to load image for preview
	var image := Image.new()
	var load_error := image.load_from_file(image_path)

	if load_error == OK:
		var texture := ImageTexture.create_from_image(image)

		# Show image using ImageDisplay component
		if image_display:
			# TODO: Use ImageDisplay component's load_from_image method
			# For now, manually set texture (needs ImageDisplay refactor)
			image_display.visible = true

		status_label.text = "Test image %d/%d loaded (%d KB)" % [current_test_image_index + 1, TEST_IMAGES.size(), selected_file_data.size() / 1024]
		status_label.add_theme_color_override("font_color", Color.GREEN)

		select_photo_button.visible = false
		instruction_label.visible = false
	else:
		status_label.text = "⚠️ Cannot preview image, but file loaded (%d KB)" % [selected_file_data.size() / 1024]
		status_label.add_theme_color_override("font_color", Color.YELLOW)

	upload_button.disabled = false
	upload_button.text = "Upload & Analyze"
	print("[Camera] Test image ready for upload")


# File access callbacks
func _on_file_load_started(file_name: String) -> void:
	print("[Camera] File load started: ", file_name)
	status_label.text = "Loading file: %s" % file_name


func _on_file_loaded(file_name: String, file_type: String, base64_data: String) -> void:
	"""Called when file is fully loaded from web file picker"""
	print("[Camera] File loaded: ", file_name, " Type: ", file_type, " Size: ", base64_data.length())

	# Convert base64 to binary
	selected_file_data = Marshalls.base64_to_raw(base64_data)
	selected_file_name = file_name
	selected_file_type = file_type

	# Try to load image for preview
	var image := Image.new()
	var load_error: int = -1

	# Try different formats
	if "png" in file_type.to_lower() or file_name.to_lower().ends_with(".png"):
		load_error = image.load_png_from_buffer(selected_file_data)
	elif "jpeg" in file_type.to_lower() or "jpg" in file_type.to_lower() or file_name.to_lower().ends_with(".jpg") or file_name.to_lower().ends_with(".jpeg"):
		load_error = image.load_jpg_from_buffer(selected_file_data)
	elif "webp" in file_type.to_lower() or file_name.to_lower().ends_with(".webp"):
		load_error = image.load_webp_from_buffer(selected_file_data)

	if load_error == OK:
		# Successfully loaded for preview
		if image_display:
			# TODO: Use ImageDisplay component's load_from_image method
			image_display.visible = true

		status_label.text = "Photo selected: %s (%d KB)" % [file_name, selected_file_data.size() / 1024]
		status_label.add_theme_color_override("font_color", Color.GREEN)
		print("[Camera] Image loaded for preview (", image.get_width(), "x", image.get_height(), ")")

		select_photo_button.visible = false
		instruction_label.visible = false
	else:
		# Cannot preview, but still allow upload
		status_label.text = "⚠️ Cannot preview this format, but you can still upload it"
		status_label.add_theme_color_override("font_color", Color.YELLOW)
		print("[Camera] Cannot preview image format, but allowing upload")

	upload_button.disabled = false
	upload_button.text = "Upload & Analyze"
	print("[Camera] File ready for upload - Size: ", selected_file_data.size(), " bytes")


func _on_file_progress(bytes_loaded: int, bytes_total: int) -> void:
	var progress = (float(bytes_loaded) / float(bytes_total)) * 100.0
	print("[Camera] File load progress: ", progress, "%")


func _on_file_error(error_msg: String) -> void:
	print("[Camera] File load error: ", error_msg)
	show_error("File load failed", error_msg, 0)


func _on_file_cancelled() -> void:
	print("[Camera] File selection cancelled")
	status_label.text = "File selection cancelled"


# ============================================================================
# CV Analysis Workflow
# ============================================================================

func _on_upload_pressed() -> void:
	"""Start CV analysis workflow"""
	if selected_file_data.size() == 0:
		print("[Camera] ERROR: No file selected")
		return

	print("[Camera] Starting CV analysis...")

	# Disable buttons during analysis
	upload_button.disabled = true
	select_photo_button.disabled = true
	retry_button.visible = false

	# Show loading
	if loading_spinner:
		loading_spinner.visible = true

	# Get any transformations from image display (rotation, etc.)
	var transformations = {}
	# TODO: Get rotation from ImageDisplay component if implemented

	# Start analysis using workflow component
	cv_workflow.start_analysis_from_data(selected_file_data, transformations)


func _on_analysis_progress(stage: String, message: String, progress: float) -> void:
	"""Handle analysis progress updates"""
	print("[Camera] Analysis progress: ", stage, " - ", message, " (", progress * 100, "%)")
	status_label.text = message

	if progress_indicator:
		progress_indicator.visible = true
		# TODO: Update progress indicator (needs ProgressIndicator refactor)


func _on_conversion_complete(conversion_id_val: String) -> void:
	"""Handle successful image conversion"""
	print("[Camera] Image conversion complete: ", conversion_id_val)
	status_label.text = "Image converted, downloading..."


func _on_image_downloaded(image_data: PackedByteArray) -> void:
	"""Handle downloaded converted image"""
	print("[Camera] Converted image downloaded: ", image_data.size(), " bytes")

	# Load image for later use in dex entry
	converted_image = Image.new()
	var load_error = converted_image.load_png_from_buffer(image_data)

	if load_error != OK:
		print("[Camera] ERROR: Could not load converted image")
		converted_image = null
		return

	# Update preview with converted image (replaces original)
	# TODO: Update ImageDisplay component with converted image
	print("[Camera] Converted image loaded: ", converted_image.get_width(), "x", converted_image.get_height())

	status_label.text = "Analyzing image with AI..."


func _on_analysis_complete(job_model: AnalysisJobModel) -> void:
	"""Handle successful CV analysis completion"""
	print("[Camera] Analysis complete!")

	if loading_spinner:
		loading_spinner.visible = false

	if progress_indicator:
		progress_indicator.visible = false

	status_label.text = "Analysis complete!"
	status_label.add_theme_color_override("font_color", Color.GREEN)

	# Get detected animals
	detected_animals = []
	for animal_dict in job_model.detected_animals:
		detected_animals.append(animal_dict)

	print("[Camera] Detected %d animals" % detected_animals.size())

	# Handle results based on animal count
	if detected_animals.size() == 0:
		# No animals detected
		_handle_no_animals_detected()
	elif detected_animals.size() == 1:
		# Single animal - auto-select
		selected_animal_index = 0
		_process_selected_animal(detected_animals[0])
	else:
		# Multiple animals - show selection UI
		_show_animal_selection_popup(detected_animals)


func _on_analysis_failed(error_type: String, message: String, code: int) -> void:
	"""Handle CV analysis failure"""
	print("[Camera] Analysis failed: ", error_type, " - ", message, " (code: ", code, ")")

	if loading_spinner:
		loading_spinner.visible = false

	if progress_indicator:
		progress_indicator.visible = false

	# Hide upload button, show retry button
	upload_button.visible = false
	retry_button.visible = true
	retry_button.disabled = false

	# Show error dialog
	if error_dialog:
		if error_type == "API_ERROR":
			error_dialog.show_api_error(code, message, "The CV analysis failed")
		else:
			error_dialog.show_network_error("Connection failed. Please try again.")


func _on_retry_available() -> void:
	"""Handle retry availability"""
	print("[Camera] Retry available")
	retry_button.disabled = false


func _on_retry_pressed() -> void:
	"""Retry the failed analysis"""
	print("[Camera] Retrying analysis...")

	# Hide retry button, show upload button in loading state
	retry_button.visible = false
	upload_button.visible = true
	upload_button.disabled = true
	upload_button.text = "Retrying..."

	if loading_spinner:
		loading_spinner.visible = true

	# Retry the analysis
	cv_workflow.retry_analysis()


# ============================================================================
# Analysis Results Handling
# ============================================================================

func _handle_no_animals_detected() -> void:
	"""Handle case where no animals were detected"""
	status_label.text = "No animals detected"
	status_label.add_theme_color_override("font_color", Color.ORANGE)
	result_label.text = "Try manual entry or upload a different image"

	upload_button.visible = false
	manual_entry_button.visible = true
	manual_entry_button.disabled = false
	select_photo_button.disabled = false


func _show_animal_selection_popup(animals: Array) -> void:
	"""Show popup for selecting from multiple detected animals"""
	print("[Camera] Showing animal selection popup for %d animals" % animals.size())

	# TODO: Create proper AnimalSelectionPopup component
	# For now, auto-select first animal as fallback
	print("[Camera] WARNING: Animal selection popup not implemented yet, auto-selecting first")
	selected_animal_index = 0
	_process_selected_animal(animals[0])


func _process_selected_animal(animal_details: Dictionary) -> void:
	"""Display CV results and prepare for dex entry creation"""
	print("[Camera] Processing selected animal")

	pending_animal_details = animal_details

	# Extract names for display
	var common_name: String = str(animal_details.get("common_name", ""))
	var scientific_name: String = str(animal_details.get("scientific_name", ""))

	# Display results
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

	status_label.text = "Analysis complete! Click 'Create Dex Entry' to save."
	status_label.add_theme_color_override("font_color", Color.GREEN)

	# Update buttons
	upload_button.text = "Create Dex Entry"
	upload_button.disabled = false
	upload_button.visible = true
	upload_button.pressed.disconnect(_on_upload_pressed)
	upload_button.pressed.connect(_on_create_dex_entry_pressed)

	manual_entry_button.visible = true
	manual_entry_button.disabled = false

	select_photo_button.visible = false


# ============================================================================
# Dex Entry Creation
# ============================================================================

func _on_create_dex_entry_pressed() -> void:
	"""Create dex entry from analysis results"""
	print("[Camera] Creating dex entry...")

	# Get animal ID
	var animal_id_value = pending_animal_details.get("animal_id")
	if animal_id_value == null:
		animal_id_value = pending_animal_details.get("id")

	if animal_id_value == null:
		print("[Camera] ERROR: No animal ID in pending details")
		show_error("Error: Missing animal data", "", 0)
		return

	var animal_id: String = str(animal_id_value)
	var creation_index: int = int(pending_animal_details.get("creation_index", 0))
	var scientific_name: String = str(pending_animal_details.get("scientific_name", ""))
	var common_name: String = str(pending_animal_details.get("common_name", ""))

	# Update UI
	upload_button.disabled = true
	show_loading("Creating dex entry...")

	# Save image to local cache
	var cached_path := _cache_dex_image(creation_index)

	# Add to local database
	var record_dict = {
		"creation_index": creation_index,
		"scientific_name": scientific_name,
		"common_name": common_name,
		"cached_image_path": cached_path,
		"animal_id": animal_id
	}
	DexDatabase.add_record_from_dict(record_dict, "self")
	print("[Camera] Added to local database: #%d with animal_id: %s" % [creation_index, animal_id])

	# Create server-side entry
	var job_id = cv_workflow.job_id  # Get job ID from workflow
	APIManager.dex.create_entry(
		animal_id,
		job_id,
		"",  # notes
		"friends",  # visibility
		_on_dex_entry_created
	)


func _cache_dex_image(creation_index: int) -> String:
	"""Cache the dex image locally"""
	if converted_image == null:
		print("[Camera] WARNING: No converted image to cache")
		return ""

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
	var cached_path = "%s%d.png" % [cache_dir, creation_index]
	var png_data = converted_image.save_png_to_buffer()
	var file = FileAccess.open(cached_path, FileAccess.WRITE)
	if file:
		file.store_buffer(png_data)
		file.close()
		print("[Camera] Saved image to cache: ", cached_path)

	return cached_path


func _on_dex_entry_created(response: Dictionary, code: int) -> void:
	"""Handle dex entry creation response"""
	hide_loading()

	if code == 200 or code == 201:
		current_dex_entry_id = str(response.get("id", ""))
		print("[Camera] Dex entry created successfully: ", current_dex_entry_id)

		# Update local database with server entry ID
		var creation_index = int(pending_animal_details.get("creation_index", 0))
		if creation_index > 0:
			var user_id = TokenManager.get_user_id()
			var record = DexDatabase.get_record_for_user(creation_index, user_id)
			if not record.is_empty():
				record["dex_entry_id"] = current_dex_entry_id
				DexDatabase.add_record_from_dict(record, user_id)
				print("[Camera] Stored dex_entry_id in local database")

		show_success("Dex entry created!")

		# Reset for new upload
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
		show_error("Failed to create entry", error_msg, code)
		upload_button.disabled = false


# ============================================================================
# Manual Entry
# ============================================================================

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
	"""Handle manual entry update"""
	print("[Camera] Manual entry updated with taxonomy: ", taxonomy_data.get("scientific_name", ""))

	# Update pending_animal_details with the new animal data
	var animal_details = taxonomy_data.get("animal", {})
	if animal_details.is_empty():
		animal_details = taxonomy_data

	if not animal_details.is_empty():
		pending_animal_details = animal_details
		print("[Camera] Updated pending_animal_details with manual selection")

		var scientific_name = animal_details.get("scientific_name", "")
		var common_name = animal_details.get("common_name", "")

		# Update the result label
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


# ============================================================================
# Lifecycle
# ============================================================================

func _exit_tree() -> void:
	"""Cleanup when scene exits"""
	if cv_workflow:
		cv_workflow.cancel_analysis()