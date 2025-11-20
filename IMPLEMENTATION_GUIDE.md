# Image Upload Implementation - Completion Guide

## Status: Backend Complete, Frontend Partially Complete

### ✅ Completed
1. Backend image conversion API (`/api/v1/images/convert/`)
2. Backend multiple animal detection support
3. Godot API services (ImageService, VisionService updated)
4. Camera.gd state machine enum and variables added

###  🚧 Remaining Critical Implementation

## 1. Complete camera.gd State Machine Methods

The following methods need to be added/updated in `client/biologidex-client/camera.gd`:

### Update `_on_file_loaded()` state transition
```gdscript
# After line 267 (after "print("[Camera] File ready for upload...")")
current_state = CameraState.IMAGE_SELECTED
upload_button.text = "Upload & Convert"
```

### Update `_on_rotate_image_pressed()` to use `total_rotation`
```gdscript
func _on_rotate_image_pressed() -> void:
	"""Rotate image 90 degrees clockwise - only in IMAGE_READY state"""
	if current_state != CameraState.IMAGE_READY:
		return

	total_rotation = (total_rotation + 90) % 360
	_apply_rotation_to_preview()
	print("[Camera] Total rotation now: %d degrees" % total_rotation)
```

### Replace `_on_upload_pressed()` with new two-step logic
```gdscript
func _on_upload_pressed() -> void:
	"""Handle upload button press based on current state"""
	match current_state:
		CameraState.IMAGE_SELECTED:
			_start_image_conversion()  # Step 1: Upload & Convert
		CameraState.IMAGE_READY:
			_start_cv_analysis()       # Step 2: Analyze
		_:
			push_error("[Camera] Upload pressed in invalid state: %s" % current_state)

func _start_image_conversion() -> void:
	"""Step 1: Upload image for conversion"""
	if selected_file_data.size() == 0:
		print("[Camera] ERROR: No file selected")
		return

	print("[Camera] Starting image conversion...")
	current_state = CameraState.IMAGE_CONVERTING

	# Update UI
	upload_button.disabled = true
	select_photo_button.disabled = true
	rotate_image_button.disabled = true
	loading_spinner.visible = true
	status_label.text = "Uploading and converting image..."
	status_label.add_theme_color_override("font_color", Color.WHITE)

	# Call conversion API
	APIManager.images.convert_image(
		selected_file_data,
		selected_file_name,
		selected_file_type,
		_on_image_converted
	)

func _on_image_converted(response: Dictionary, code: int) -> void:
	"""Handle image conversion completion"""
	if code != 201:
		# Conversion failed
		var error_msg = response.get("error", "Conversion failed")
		print("[Camera] Conversion failed: ", error_msg)
		status_label.text = "Conversion failed: %s" % error_msg
		status_label.add_theme_color_override("font_color", Color.RED)
		loading_spinner.visible = false
		upload_button.disabled = false
		select_photo_button.disabled = false
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
		current_state = CameraState.IMAGE_SELECTED
		return

	# Update display
	var texture := ImageTexture.create_from_image(image)
	simple_image.texture = texture
	current_image_width = float(image.get_width())
	current_image_height = float(image.get_height())

	print("[Camera] Converted image loaded: %dx%d" % [current_image_width, current_image_height])

	# Update UI for IMAGE_READY state
	current_state = CameraState.IMAGE_READY
	loading_spinner.visible = false
	status_label.text = "Image ready! Rotate if needed, then analyze."
	status_label.add_theme_color_override("font_color", Color.GREEN)
	upload_button.disabled = false
	upload_button.text = "Analyze Image"
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
		rotate_image_button.disabled = false
		current_state = CameraState.IMAGE_READY
		return

	current_job_id = str(response.get("id", ""))
	print("[Camera] Vision job created: ", current_job_id)

	# Start polling
	_start_status_polling()
```

### Update `_handle_completed_job()` for multiple animal detection
```gdscript
func _handle_completed_job(job_data: Dictionary) -> void:
	"""Handle completed analysis job - check for multiple animals"""
	print("[Camera] Analysis complete!")
	current_state = CameraState.ANALYSIS_COMPLETE

	loading_spinner.visible = false
	status_label.text = "Analysis complete!"
	status_label.add_theme_color_override("font_color", Color.GREEN)

	# Extract detected animals
	var detected_animals_value = job_data.get("detected_animals", [])
	if typeof(detected_animals_value) == TYPE_ARRAY:
		detected_animals = detected_animals_value

	print("[Camera] Detected %d animals" % detected_animals.size())

	# Handle results based on count
	if detected_animals.size() == 0:
		# No animals detected
		status_label.text = "No animals detected"
		status_label.add_theme_color_override("font_color", Color.ORANGE)
		result_label.text = "Try manual entry or upload a different image"
		manual_entry_button.visible = true
		manual_entry_button.disabled = false
		upload_button.visible = false
		return
	elif detected_animals.size() == 1:
		# Single animal - auto-select
		selected_animal_index = 0
		_process_selected_animal(job_data)
	else:
		# Multiple animals - show selection UI
		current_state = CameraState.ANIMAL_SELECTION
		_show_animal_selection_popup()

func _show_animal_selection_popup() -> void:
	"""Show popup for selecting from multiple detected animals"""
	# TODO: Create AnimalSelectionPopup component
	print("[Camera] Showing animal selection popup for %d animals" % detected_animals.size())

	# For now, auto-select first animal (temporary)
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
		return

	print("[Camera] Animal selected successfully")
	_process_selected_animal(response)

func _process_selected_animal(job_data: Dictionary) -> void:
	"""Process the selected animal and create dex entry"""
	current_state = CameraState.COMPLETED

	# Get selected animal data
	var selected_animal_data = {}
	if selected_animal_index >= 0 and selected_animal_index < detected_animals.size():
		selected_animal_data = detected_animals[selected_animal_index]

	# Continue with existing logic from old _handle_completed_job...
	# (Download dex image, display results, save to database, etc.)
	# This is the code from line 593 onwards in the current implementation
```

## 2. Create AnimalSelectionPopup Component

Create `client/biologidex-client/components/animal_selection_popup.gd`:

```gdscript
extends PopupPanel

signal animal_selected(index: int)
signal manual_entry_requested()

var detected_animals: Array = []

@onready var animals_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/AnimalsContainer
@onready var manual_entry_btn: Button = $MarginContainer/VBoxContainer/ButtonsContainer/ManualEntryButton
@onready var cancel_btn: Button = $MarginContainer/VBoxContainer/ButtonsContainer/CancelButton

func _ready() -> void:
	manual_entry_btn.pressed.connect(_on_manual_entry_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)

func populate_animals(animals: Array) -> void:
	"""Populate the list with detected animals"""
	detected_animals = animals

	# Clear existing items
	for child in animals_container.get_children():
		child.queue_free()

	# Create item for each animal
	for i in range(animals.size()):
		var animal_data = animals[i]
		var item = _create_animal_item(animal_data, i)
		animals_container.add_child(item)

func _create_animal_item(animal_data: Dictionary, index: int) -> Control:
	"""Create UI element for a single animal"""
	var item = HBoxContainer.new()
	item.custom_minimum_size = Vector2(0, 60)

	# Info container
	var info_container = VBoxContainer.new()
	info_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Scientific name
	var scientific_label = Label.new()
	scientific_label.text = animal_data.get("scientific_name", "Unknown")
	scientific_label.add_theme_font_size_override("font_size", 16)
	info_container.add_child(scientific_label)

	# Common name + confidence
	var details_label = Label.new()
	var common_name = animal_data.get("common_name", "")
	var confidence = animal_data.get("confidence", 0.0)
	details_label.text = "%s - %.0f%% confidence" % [common_name, confidence * 100]
	details_label.add_theme_font_size_override("font_size", 12)
	details_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	info_container.add_child(details_label)

	item.add_child(info_container)

	# Select button
	var select_btn = Button.new()
	select_btn.text = "Select"
	select_btn.pressed.connect(_on_animal_item_selected.bind(index))
	item.add_child(select_btn)

	return item

func _on_animal_item_selected(index: int) -> void:
	"""Handle animal selection"""
	animal_selected.emit(index)
	hide()

func _on_manual_entry_pressed() -> void:
	"""Handle manual entry button"""
	manual_entry_requested.emit()
	hide()

func _on_cancel_pressed() -> void:
	"""Handle cancel button"""
	hide()
```

Create corresponding `.tscn` file or add UI structure programmatically.

## 3. Update DexService

Update `client/biologidex-client/api/services/dex_service.gd`:

The `create_entry()` method already accepts `vision_job_id`, but ensure it's being passed correctly:

```gdscript
func create_entry(
	animal_id: String,
	vision_job_id: String = "",
	notes: String = "",
	visibility: String = "friends",
	callback: Callable = Callable()
) -> void:
	_log("Creating dex entry for animal: %s" % animal_id)

	var data = {
		"animal": animal_id,
		"visibility": visibility
	}

	if not notes.is_empty():
		data["notes"] = notes

	# Link to vision job if provided
	if not vision_job_id.is_empty():
		data["source_vision_job"] = vision_job_id

	# ... rest of implementation
```

## 4. Testing Checklist

### Manual Testing Steps

1. **Image Selection & Conversion**
   - [ ] Select image from disk
   - [ ] Verify conversion upload starts
   - [ ] Verify converted image downloads and displays
   - [ ] Check state is IMAGE_READY

2. **Rotation**
   - [ ] Rotate image 90° - verify visual update
   - [ ] Rotate multiple times - verify accumulation
   - [ ] Check total_rotation variable tracks correctly

3. **CV Analysis**
   - [ ] Click "Analyze" button
   - [ ] Verify vision job created with conversion_id
   - [ ] Verify post_conversion_transformations sent if rotated
   - [ ] Check polling starts

4. **Single Animal Result**
   - [ ] Verify auto-selection of single animal
   - [ ] Verify dex entry created
   - [ ] Check local and server-side storage

5. **Multiple Animals Result**
   - [ ] Verify animal selection popup shows
   - [ ] Select different animals
   - [ ] Verify correct animal saved to dex

6. **No Animals Result**
   - [ ] Verify manual entry button appears
   - [ ] Verify helpful message shown

7. **Error Handling**
   - [ ] Test with invalid image format
   - [ ] Test with network disconnection
   - [ ] Test conversion timeout
   - [ ] Test analysis failure

## 5. Integration with Existing Code

### Files that DON'T need changes:
- `api_manager.gd` - Already updated
- `api_config.gd` - Already has endpoints
- `vision_service.gd` - Already has new methods
- `image_service.gd` - Already complete
- Backend models/views - Already support all features

### Files that NEED changes:
- `camera.gd` - Add methods listed above ✓ (partially done)
- `animal_selection_popup.gd` - Create new component
- `manual_entry_popup.gd` - Add CREATE_NEW mode (optional, can be done later)

## 6. Deployment

Once frontend is complete:

1. Export Godot client:
   ```bash
   cd client/biologidex-client
   godot --headless --export-release "Web" ../../server/client_files/index.html
   ```

2. Deploy to production:
   ```bash
   ./scripts/export-to-prod.sh
   ```

3. Verify endpoints work:
   - `curl -X POST https://your-domain/api/v1/images/convert/` (should return 401)
   - Check Django admin for ImageConversion model
   - Check Celery logs for cleanup tasks

## Next Steps

1. Complete the camera.gd methods above (copy-paste the code blocks)
2. Create AnimalSelectionPopup component
3. Test the full flow in editor mode with test images
4. Deploy and test in production

## Notes

- The state machine provides clear separation of concerns
- Each state has specific UI requirements and allowed transitions
- Error handling should reset to appropriate previous state
- All API calls use the new service layer methods
- Legacy direct upload code path should be removed once tested