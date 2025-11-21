extends BaseSceneController

# Camera/Upload scene - Highly refactored using component-based architecture
# Reduced from 1095 lines to ~300 lines by using:
# - BaseSceneController (eliminates manager initialization)
# - CVAnalysisWorkflow (eliminates conversion + analysis + polling logic)
# - FileSelector (eliminates file access complexity)
# - ErrorDialog (standardizes error handling)

# ============================================================================
# UI Elements
# ============================================================================

@onready var select_photo_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/SelectPhotoButton
@onready var upload_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/UploadButton
@onready var retry_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RetryButton
@onready var manual_entry_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/ManualEntryButton
@onready var rotate_image_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RotateImageButton
@onready var instruction_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/InstructionLabel
@onready var result_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/ResultLabel

# Image display - dex_record_image component with two modes:
# 1. simple_image: Used for preview during photo selection/rotation
# 2. bordered_display: Used to show final dex record card with label
@onready var record_image: Control = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage
@onready var simple_image: TextureRect = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/Image
@onready var bordered_display: AspectRatioContainer = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio
@onready var bordered_image: TextureRect = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio/ImageBorder/Image
@onready var record_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/RecordImage/ImageBorderAspectRatio/ImageBorder/RecordMargin/RecordBackground/RecordTextMargin/RecordLabel

# Components (programmatically instantiated)
var file_selector: FileSelector
var cv_workflow: CVAnalysisWorkflow

# State
var selected_file_data: PackedByteArray = PackedByteArray()
var converted_image: Image = null
var rotation_angle: int = 0
var pending_animal_details: Dictionary = {}
var current_dex_entry_id: String = ""

# ============================================================================
# Initialization
# ============================================================================

func _on_scene_ready() -> void:
	"""Called by BaseSceneController after managers are initialized"""
	scene_name = "Camera"
	print("[Camera] Scene ready (refactored v2)")

	# Wire up UI elements from scene (BaseSceneController members)
	back_button = $Panel/MarginContainer/VBoxContainer/Header/BackButton
	status_label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/StatusLabel
	loading_spinner = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/LoadingSpinner
	# Connect back button (set after BaseSceneController._setup_common_ui(), so connect manually)
	if back_button and not back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.connect(_on_back_pressed)

	# Create and initialize file selector
	file_selector = FileSelector.new()
	add_child(file_selector)
	file_selector.file_selected.connect(_on_file_selected)
	file_selector.file_load_error.connect(_on_file_load_error)
	file_selector.file_load_cancelled.connect(_on_file_load_cancelled)

	# Create and initialize CV workflow
	cv_workflow = CVAnalysisWorkflow.new()
	add_child(cv_workflow)
	cv_workflow.analysis_progress.connect(_on_analysis_progress)
	cv_workflow.image_downloaded.connect(_on_image_downloaded)
	cv_workflow.analysis_complete.connect(_on_analysis_complete)
	cv_workflow.analysis_failed.connect(_on_analysis_failed)
	cv_workflow.retry_available.connect(_on_retry_available)

	# Connect UI signals
	select_photo_button.pressed.connect(_on_select_photo_pressed)
	upload_button.pressed.connect(_on_upload_pressed)
	retry_button.pressed.connect(_on_retry_pressed)
	rotate_image_button.pressed.connect(_on_rotate_pressed)
	manual_entry_button.pressed.connect(_on_manual_entry_pressed)

	# Initialize UI state
	_reset_ui()

	# Platform-specific status message
	if file_selector.is_editor_mode:
		status_label.text = "Editor mode: Test images available (%d total)" % file_selector.TEST_IMAGES.size()
		status_label.add_theme_color_override("font_color", Color.CYAN)
	elif not file_selector.is_web_mode:
		status_label.text = "File upload only works on HTML5 builds"
		status_label.add_theme_color_override("font_color", Color.ORANGE)
		select_photo_button.disabled = true


func _reset_ui() -> void:
	"""Reset UI to initial state"""
	# Buttons
	upload_button.disabled = true
	upload_button.text = "Upload & Analyze"
	upload_button.visible = false  # Hidden until photo selected
	retry_button.visible = false
	rotate_image_button.visible = false
	manual_entry_button.visible = false
	select_photo_button.visible = true
	instruction_label.visible = true

	# Re-enable select button (unless platform doesn't support it)
	if file_selector and file_selector.is_web_mode:
		select_photo_button.disabled = false
	elif file_selector and file_selector.is_editor_mode:
		select_photo_button.disabled = false
	else:
		select_photo_button.disabled = true

	# Reconnect upload button to original handler
	if upload_button.pressed.is_connected(_on_create_dex_entry):
		upload_button.pressed.disconnect(_on_create_dex_entry)
	if not upload_button.pressed.is_connected(_on_upload_pressed):
		upload_button.pressed.connect(_on_upload_pressed)

	# Labels
	status_label.text = "Select a photo to identify an animal"
	status_label.add_theme_color_override("font_color", Color.WHITE)
	result_label.text = ""

	# Image display - hide bordered dex card, prepare for new photo selection
	record_image.visible = false
	simple_image.texture = null
	bordered_display.visible = false
	simple_image.visible = true

	# Loading indicator
	if loading_spinner:
		loading_spinner.visible = false

	# State
	selected_file_data = PackedByteArray()
	converted_image = null
	rotation_angle = 0
	pending_animal_details = {}
	current_dex_entry_id = ""


# ============================================================================
# File Selection
# ============================================================================

func _on_select_photo_pressed() -> void:
	"""Open file picker"""
	# Reset all state when selecting a new photo
	_reset_ui()

	# Cancel any ongoing analysis
	if cv_workflow:
		cv_workflow.cancel_analysis()

	file_selector.open_file_picker()
	status_label.text = "Opening file picker..."


func _on_file_selected(file_name: String, file_type: String, file_data: PackedByteArray) -> void:
	"""Handle file selection"""
	print("[Camera] File selected: ", file_name, " (", file_data.size(), " bytes)")

	selected_file_data = file_data

	# Hide bordered display, show simple preview
	bordered_display.visible = false
	simple_image.visible = true

	# Try to load for preview
	var preview_success = _load_image_preview(file_data, file_type)

	if preview_success:
		status_label.text = "Photo selected: %s (%d KB)" % [file_name, file_data.size() / 1024]
		status_label.add_theme_color_override("font_color", Color.GREEN)
		select_photo_button.visible = false
		instruction_label.visible = false
		rotate_image_button.visible = true
	else:
		status_label.text = "⚠️ Cannot preview, but you can still upload"
		status_label.add_theme_color_override("font_color", Color.YELLOW)

	upload_button.visible = true
	upload_button.disabled = false
	upload_button.text = "Upload & Analyze"


func _load_image_preview(data: PackedByteArray, file_type: String) -> bool:
	"""Try to load image for preview, returns true if successful"""
	var image := Image.new()
	var load_error: int = -1

	# Try different formats based on type
	if "png" in file_type.to_lower():
		load_error = image.load_png_from_buffer(data)
	elif "jpeg" in file_type.to_lower() or "jpg" in file_type.to_lower():
		load_error = image.load_jpg_from_buffer(data)
	elif "webp" in file_type.to_lower():
		load_error = image.load_webp_from_buffer(data)

	if load_error == OK:
		var texture := ImageTexture.create_from_image(image)
		simple_image.texture = texture
		record_image.visible = true
		print("[Camera] Preview loaded: ", image.get_width(), "x", image.get_height())
		return true

	return false


func _on_file_load_error(error_message: String) -> void:
	"""Handle file load error"""
	print("[Camera] File load error: ", error_message)
	show_error("File load failed", error_message, 0)


func _on_file_load_cancelled() -> void:
	"""Handle file load cancellation"""
	print("[Camera] File selection cancelled")
	status_label.text = "File selection cancelled"


# ============================================================================
# Image Rotation
# ============================================================================

func _on_rotate_pressed() -> void:
	"""Rotate image preview 90 degrees clockwise"""
	if simple_image.texture == null:
		return

	rotation_angle = (rotation_angle + 90) % 360

	var current_texture := simple_image.texture as ImageTexture
	if not current_texture:
		return

	var image := current_texture.get_image()
	if not image:
		return

	# Rotate image
	image.rotate_90(CLOCKWISE)

	# Update texture
	var new_texture := ImageTexture.create_from_image(image)
	simple_image.texture = new_texture

	print("[Camera] Rotated to %d degrees" % rotation_angle)


# ============================================================================
# CV Analysis Workflow
# ============================================================================

func _on_upload_pressed() -> void:
	"""Start CV analysis"""
	if selected_file_data.size() == 0:
		print("[Camera] ERROR: No file selected")
		return

	print("[Camera] Starting CV analysis...")

	# Disable UI during analysis
	upload_button.disabled = true
	select_photo_button.disabled = true
	rotate_image_button.disabled = true
	retry_button.visible = false

	show_loading("Uploading and analyzing image...")

	# Build transformations
	var transformations = {}
	if rotation_angle > 0:
		transformations["rotation"] = rotation_angle

	# Start workflow
	cv_workflow.start_analysis_from_data(selected_file_data, transformations)


func _on_analysis_progress(stage: String, message: String, progress: float) -> void:
	"""Handle analysis progress"""
	status_label.text = message
	print("[Camera] Progress: ", stage, " - ", progress * 100, "%")


func _on_image_downloaded(image_data: PackedByteArray) -> void:
	"""Handle downloaded converted image"""
	print("[Camera] Converted image downloaded: ", image_data.size(), " bytes")

	# Load converted image for dex entry later
	converted_image = Image.new()
	var load_error = converted_image.load_png_from_buffer(image_data)

	if load_error != OK:
		print("[Camera] ERROR: Could not load converted image")
		converted_image = null
		return

	# Update preview with converted image
	var texture := ImageTexture.create_from_image(converted_image)
	simple_image.texture = texture

	print("[Camera] Converted image: ", converted_image.get_width(), "x", converted_image.get_height())


func _on_analysis_complete(job_model: AnalysisJobModel) -> void:
	"""Handle successful analysis"""
	print("[Camera] Analysis complete! Detected ", job_model.get_detected_animal_count(), " animals")

	hide_loading()
	status_label.text = "Analysis complete!"
	status_label.add_theme_color_override("font_color", Color.GREEN)

	# Handle based on number of animals detected
	var animal_count = job_model.get_detected_animal_count()

	if animal_count == 0:
		_handle_no_animals()
	elif animal_count == 1:
		var animal_model: AnimalModel = job_model.detected_animals[0]
		_display_result(animal_model.to_dict())
	else:
		# TODO: Show animal selection UI
		print("[Camera] Multiple animals detected, auto-selecting first")
		var animal_model: AnimalModel = job_model.detected_animals[0]
		_display_result(animal_model.to_dict())


func _on_analysis_failed(error_type: String, message: String, code: int) -> void:
	"""Handle analysis failure"""
	print("[Camera] Analysis failed: ", error_type, " - ", message)

	hide_loading()

	# Show retry button instead of upload
	upload_button.visible = false
	retry_button.visible = true
	retry_button.disabled = false

	# Show error dialog
	if error_dialog:
		if error_type == "API_ERROR":
			error_dialog.show_api_error(code, message, "CV analysis failed")
		else:
			error_dialog.show_network_error("Connection failed. Please try again.")


func _on_retry_available() -> void:
	"""Handle retry availability"""
	retry_button.disabled = false


func _on_retry_pressed() -> void:
	"""Retry failed analysis"""
	print("[Camera] Retrying...")

	retry_button.visible = false
	upload_button.visible = true
	upload_button.disabled = true
	upload_button.text = "Retrying..."

	show_loading("Retrying analysis...")

	cv_workflow.retry_analysis()


# ============================================================================
# Results Handling
# ============================================================================

func _handle_no_animals() -> void:
	"""Handle no animals detected"""
	status_label.text = "No animals detected"
	status_label.add_theme_color_override("font_color", Color.ORANGE)
	result_label.text = "Try manual entry or upload a different image"

	upload_button.visible = false
	manual_entry_button.visible = true
	select_photo_button.disabled = false


func _display_result(animal_dict: Dictionary) -> void:
	"""Display analysis result"""
	pending_animal_details = animal_dict

	var scientific_name: String = str(animal_dict.get("scientific_name", ""))
	var common_name: String = str(animal_dict.get("common_name", ""))

	# Format display text
	var display_text = scientific_name if scientific_name else ""
	if common_name:
		display_text += (" - " + common_name) if display_text else common_name
	if not display_text:
		display_text = "Unknown"

	result_label.text = display_text
	result_label.add_theme_color_override("font_color", Color.GREEN)

	status_label.text = "Click 'Create Dex Entry' to save"
	status_label.add_theme_color_override("font_color", Color.GREEN)

	# Update button to create dex entry
	upload_button.visible = true
	upload_button.text = "Create Dex Entry"
	upload_button.disabled = false
	upload_button.pressed.disconnect(_on_upload_pressed)
	upload_button.pressed.connect(_on_create_dex_entry)

	manual_entry_button.visible = true


# ============================================================================
# Dex Entry Creation
# ============================================================================

func _on_create_dex_entry() -> void:
	"""Create dex entry"""
	print("[Camera] Creating dex entry...")

	# Get animal data
	var animal_id = str(pending_animal_details.get("animal_id", pending_animal_details.get("id", "")))
	if animal_id.is_empty():
		show_error("Missing animal data", "", 0)
		return

	var creation_index: int = int(pending_animal_details.get("creation_index", 0))
	var scientific_name: String = str(pending_animal_details.get("scientific_name", ""))
	var common_name: String = str(pending_animal_details.get("common_name", ""))

	upload_button.disabled = true
	show_loading("Creating dex entry...")

	# Cache image locally
	var cached_path = _cache_image(creation_index)

	# Add to local database
	var record_dict = {
		"creation_index": creation_index,
		"scientific_name": scientific_name,
		"common_name": common_name,
		"cached_image_path": cached_path,
		"animal_id": animal_id,
		"owner_username": TokenManager.get_username(),
		"catch_date": Time.get_datetime_string_from_system(false, true)  # ISO 8601 format
	}
	DexDatabase.add_record_from_dict(record_dict, "self")
	print("[Camera] Added to local database: #%d" % creation_index)

	# Create server entry
	APIManager.dex.create_entry(
		animal_id,
		cv_workflow.job_id,
		"",
		"friends",
		_on_dex_created
	)


func _cache_image(creation_index: int) -> String:
	"""Cache image to local storage"""
	if converted_image == null:
		return ""

	var user_id = TokenManager.get_user_id()
	var cache_dir = "user://dex_cache/%s/" % user_id

	# Ensure directory exists
	var dir = DirAccess.open("user://dex_cache/")
	if not dir:
		dir = DirAccess.open("user://")
		dir.make_dir("dex_cache")
		dir = DirAccess.open("user://dex_cache/")
	if not dir.dir_exists(user_id):
		dir.make_dir(user_id)

	# Save image
	var path = "%s%d.png" % [cache_dir, creation_index]
	var png_data = converted_image.save_png_to_buffer()
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(png_data)
		file.close()
		print("[Camera] Cached image: ", path)

	return path


func _show_dex_record_card() -> void:
	"""Display the dex record card with border and label"""
	# Hide simple preview, show bordered card
	simple_image.visible = false
	bordered_display.visible = true
	record_image.visible = true

	# Copy image to bordered display
	if simple_image.texture:
		bordered_image.texture = simple_image.texture

	# Set label text
	var scientific_name: String = str(pending_animal_details.get("scientific_name", ""))
	var common_name: String = str(pending_animal_details.get("common_name", ""))

	# Format species name
	var species_line = ""
	if scientific_name:
		species_line = scientific_name
	if common_name:
		if species_line:
			species_line += " - " + common_name
		else:
			species_line = common_name

	if not species_line:
		species_line = "Unknown Species"

	# Format catch info (username and date)
	var username = TokenManager.get_username()
	var catch_date = Time.get_datetime_string_from_system(false, true)  # ISO 8601 format
	var catch_info = username if username else "Unknown User"

	# Format date nicely (take just the date part)
	var date_parts = catch_date.split("T")
	if date_parts.size() > 0:
		catch_info += " - " + date_parts[0]

	# Combine lines
	record_label.text = species_line + "\n" + catch_info

	print("[Camera] Showing dex record card: ", species_line)


func _on_dex_created(response: Dictionary, code: int) -> void:
	"""Handle dex entry creation response"""
	hide_loading()

	if code == 200 or code == 201:
		current_dex_entry_id = str(response.get("id", ""))
		print("[Camera] Dex entry created: ", current_dex_entry_id)

		# Update local database with server ID
		var creation_index = int(pending_animal_details.get("creation_index", 0))
		if creation_index > 0:
			var user_id = TokenManager.get_user_id()
			var record = DexDatabase.get_record_for_user(creation_index, user_id)
			if not record.is_empty():
				record["dex_entry_id"] = current_dex_entry_id
				DexDatabase.add_record_from_dict(record, user_id)

		# Show dex record card with border and label
		_show_dex_record_card()

		# Update UI for next upload
		upload_button.visible = false
		select_photo_button.visible = true
		select_photo_button.disabled = false
		rotate_image_button.visible = false
		manual_entry_button.visible = false
		result_label.text = ""

		# Show success message
		status_label.text = "Dex entry created! Select another photo to continue."
		status_label.add_theme_color_override("font_color", Color.GREEN)

		# In editor mode, prepare next test image index (loads when user clicks Select Photo)
		if file_selector.is_editor_mode:
			file_selector.cycle_test_image()
			print("[Camera] Ready for next test image (will load on button press)")
	else:
		var error_msg = response.get("error", "Unknown error")
		show_error("Failed to create entry", error_msg, code)
		upload_button.disabled = false


# ============================================================================
# Manual Entry
# ============================================================================

func _on_manual_entry_pressed() -> void:
	"""Open manual entry popup"""
	print("[Camera] Opening manual entry popup")

	var popup_scene = load("res://features/ui/components/manual_entry_popup/manual_entry_popup.tscn")
	if not popup_scene:
		print("[Camera] ERROR: Could not load manual entry popup")
		return

	var popup = popup_scene.instantiate()

	if not current_dex_entry_id.is_empty():
		popup.current_dex_entry_id = current_dex_entry_id

	popup.entry_updated.connect(_on_manual_entry_updated)
	popup.popup_closed.connect(_on_manual_entry_closed)

	add_child(popup)
	# Show with dynamic sizing (80% of screen, centered)
	popup.show_popup()


func _on_manual_entry_updated(taxonomy_data: Dictionary) -> void:
	"""Handle manual entry update"""
	print("[Camera] Manual entry updated")

	var animal_details = taxonomy_data.get("animal", taxonomy_data)

	if not animal_details.is_empty():
		pending_animal_details = animal_details

		var scientific_name = str(animal_details.get("scientific_name", ""))
		var common_name = str(animal_details.get("common_name", ""))

		var display_text = scientific_name if scientific_name else ""
		if common_name:
			display_text += (" - " + common_name) if display_text else common_name

		if display_text:
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
	"""Cleanup on exit"""
	if cv_workflow:
		cv_workflow.cancel_analysis()
