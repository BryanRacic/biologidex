extends BaseSceneNode
## EditEntry - Full-screen scene for editing/creating dex entries
##
## Modes:
## - "edit": Modify existing entry (animal ID, image, delete)
## - "create": Manual entry creation without CV analysis

# ============================================================================
# State
# ============================================================================

enum State { IDLE, EDITING_ANIMAL, UPLOADING_IMAGE, SAVING, CONFIRMING_DELETE, ERROR }

var current_state: State = State.IDLE
var mode: String = "edit"  # "edit" or "create"

# Entry data
var dex_entry_id: String = ""
var creation_index: int = -1
var current_animal_id: String = ""
var current_animal_data: Dictionary = {}
var original_entry_data: Dictionary = {}

# Pending changes
var pending_animal_id: String = ""
var pending_animal_data: Dictionary = {}
var pending_image_conversion_id: String = ""
var pending_image_texture: Texture2D = null
var pending_image_data: PackedByteArray = PackedByteArray()
var pending_image_file_name: String = ""
var pending_image_file_type: String = ""
var has_unsaved_changes: bool = false

# Navigation
var return_scene: String = "res://scenes/dex/dex.tscn"
var return_context: Dictionary = {}

# ============================================================================
# UI References (initialized via explicit paths for web export)
# ============================================================================

var _paper_camera: PaperCameraScene = null

# Header
var back_button_ref: Button = null
var title_label: Label = null

# Image section
var record_image: DexRecordImage = null
var replace_image_button: Button = null
var rotate_image_button: Button = null

# Animal section
var current_animal_label: Label = null
var change_animal_button: Button = null
var taxonomy_search_panel: Control = null
var genus_input: LineEdit = null
var species_input: LineEdit = null
var common_name_input: LineEdit = null
var search_button: Button = null
var search_results_scroll: ScrollContainer = null
var search_results_list: VBoxContainer = null
var select_animal_button: Button = null

# Action buttons
var save_button: Button = null
var cancel_button: Button = null

# Danger zone
var delete_section: Control = null
var delete_button: Button = null
var delete_confirmation_panel: Control = null
var confirm_delete_button: Button = null
var cancel_delete_button: Button = null

# Components
var file_selector: FileSelector = null
var search_result_item_scene: PackedScene = preload("res://scenes/social/components/search_result_item.tscn")

# ============================================================================
# Initialization
# ============================================================================

func _on_scene_ready() -> void:
	scene_name = "EditEntry"
	print("[EditEntry] Scene ready")

	# Initialize PaperCameraScene
	_paper_camera = $PaperCameraScene

	# Initialize UI nodes using explicit paths (web export workaround)
	_init_ui_references()

	# Connect UI signals
	_connect_ui_signals()

	# Create file selector component
	file_selector = FileSelector.new()
	add_child(file_selector)
	file_selector.file_selected.connect(_on_file_selected)
	file_selector.file_load_error.connect(_on_file_load_error)

	# Handle navigation context
	_handle_navigation_context()

	# Load entry data if editing
	if mode == "edit" and not dex_entry_id.is_empty():
		_load_entry_data()
	elif mode == "create":
		_setup_create_mode()


func _init_ui_references() -> void:
	"""Initialize UI node references using explicit paths (web export safe)"""
	var ui_layer = $EditEntryUILayer/UIContainer

	# Header
	back_button_ref = ui_layer.get_node("VBoxContainer/Header/BackButton")
	title_label = ui_layer.get_node("VBoxContainer/Header/TitleLabel")

	# Content area
	var scroll_content = ui_layer.get_node("VBoxContainer/ContentArea/ScrollContent")

	# Image section
	var image_section = scroll_content.get_node("ImageSection")
	record_image = image_section.get_node("RecordImage")
	var buttons_hbox = image_section.get_node("ButtonsHBox")
	replace_image_button = buttons_hbox.get_node("ReplaceImageButton")
	rotate_image_button = buttons_hbox.get_node("RotateImageButton")

	# Animal section
	var animal_section = scroll_content.get_node("AnimalSection")
	current_animal_label = animal_section.get_node("CurrentAnimalLabel")
	change_animal_button = animal_section.get_node("ChangeAnimalButton")
	taxonomy_search_panel = animal_section.get_node("TaxonomySearchPanel")
	var search_inputs = taxonomy_search_panel.get_node("SearchInputs")
	genus_input = search_inputs.get_node("GenusInput")
	species_input = search_inputs.get_node("SpeciesInput")
	common_name_input = search_inputs.get_node("CommonNameInput")
	search_button = search_inputs.get_node("SearchButton")
	search_results_scroll = taxonomy_search_panel.get_node("SearchResultsScroll")
	search_results_list = search_results_scroll.get_node("SearchResultsList")
	select_animal_button = taxonomy_search_panel.get_node("SelectAnimalButton")

	# Action buttons
	var action_buttons = scroll_content.get_node("ActionButtons")
	save_button = action_buttons.get_node("SaveButton")
	cancel_button = action_buttons.get_node("CancelButton")

	# Danger zone
	delete_section = scroll_content.get_node("DangerZone")
	delete_button = delete_section.get_node("DeleteButton")
	delete_confirmation_panel = delete_section.get_node("DeleteConfirmationPanel")
	var button_row = delete_confirmation_panel.get_node("ButtonRow")
	confirm_delete_button = button_row.get_node("ConfirmDeleteButton")
	cancel_delete_button = button_row.get_node("CancelDeleteButton")

	# Loading overlay (wired to BaseSceneNode's loading_spinner)
	loading_spinner = $LoadingOverlay


func _connect_ui_signals() -> void:
	"""Connect all UI button signals"""
	back_button_ref.pressed.connect(_on_back_pressed)
	replace_image_button.pressed.connect(_on_replace_image_pressed)
	rotate_image_button.pressed.connect(_on_rotate_image_pressed)
	change_animal_button.pressed.connect(_on_change_animal_pressed)
	search_button.pressed.connect(_on_search_pressed)
	select_animal_button.pressed.connect(_on_select_animal_pressed)
	save_button.pressed.connect(_on_save_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	confirm_delete_button.pressed.connect(_on_confirm_delete_pressed)
	cancel_delete_button.pressed.connect(_on_cancel_delete_pressed)

	# Search input enter key
	genus_input.text_submitted.connect(_on_search_input_submitted)
	species_input.text_submitted.connect(_on_search_input_submitted)
	common_name_input.text_submitted.connect(_on_search_input_submitted)


func _handle_navigation_context() -> void:
	"""Extract navigation context from NavigationManager"""
	if not NavigationManager.has_context():
		return

	var context: Dictionary = NavigationManager.get_context()

	mode = context.get("mode", "edit")
	dex_entry_id = context.get("dex_entry_id", "")
	creation_index = context.get("creation_index", -1)
	return_scene = context.get("return_scene", "res://scenes/dex/dex.tscn")
	return_context = context.get("return_context", {})

	# For create mode with pre-loaded image
	if mode == "create":
		var converted_image: Image = context.get("converted_image", null)
		if converted_image:
			pending_image_texture = ImageTexture.create_from_image(converted_image)

	NavigationManager.clear_context()


# ============================================================================
# Mode Setup
# ============================================================================

func _load_entry_data() -> void:
	"""Load existing entry data from local database and server"""
	title_label.text = "Edit Entry"
	delete_section.visible = true
	delete_confirmation_panel.visible = false

	# First try local database
	var local_record: Dictionary = DexDatabase.get_record_for_user(creation_index, "self")
	if not local_record.is_empty():
		_populate_from_record(local_record)
		return

	# Fall back to server fetch
	show_loading("Loading entry...")
	APIManager.dex.get_my_entries(_on_entries_loaded)


func _on_entries_loaded(response: Dictionary, code: int) -> void:
	hide_loading()

	if code != 200:
		show_error("Load failed", "Could not load entry data")
		return

	for entry in response.get("results", []):
		if str(entry.get("id", "")) == dex_entry_id:
			_populate_from_server_entry(entry)
			return

	show_error("Entry not found", "The entry could not be found")


func _populate_from_record(record: Dictionary) -> void:
	"""Populate UI from local DexDatabase record"""
	current_animal_id = record.get("animal_id", "")
	current_animal_data = {
		"scientific_name": record.get("scientific_name", ""),
		"common_name": record.get("common_name", ""),
		"genus": record.get("genus", ""),
		"species": record.get("species", "")
	}
	original_entry_data = record.duplicate()

	# Update UI
	_update_animal_display()
	record_image.set_entry_data(record, "self")
	record_image.load_image_from_entry()
	record_image.show_bordered()
	record_image.visible = true


func _populate_from_server_entry(entry: Dictionary) -> void:
	"""Populate UI from server entry data"""
	current_animal_id = str(entry.get("animal", ""))
	var animal_details = entry.get("animal_details", {})
	current_animal_data = {
		"scientific_name": animal_details.get("scientific_name", ""),
		"common_name": animal_details.get("common_name", ""),
		"genus": animal_details.get("genus", ""),
		"species": animal_details.get("species", "")
	}
	original_entry_data = entry.duplicate()

	_update_animal_display()

	# Construct entry data for DexRecordImage
	var entry_data = {
		"dex_compatible_url": entry.get("display_image_url", entry.get("dex_compatible_url", "")),
		"scientific_name": current_animal_data.get("scientific_name", ""),
		"common_name": current_animal_data.get("common_name", ""),
		"owner_username": entry.get("owner_username", TokenManager.get_username()),
		"catch_date": entry.get("catch_date", "")
	}

	record_image.set_entry_data(entry_data, "self")
	record_image.load_image_from_entry()
	record_image.show_bordered()
	record_image.visible = true


func _setup_create_mode() -> void:
	"""Setup UI for manual entry creation"""
	title_label.text = "New Entry"
	delete_section.visible = false
	save_button.text = "Create Entry"

	# Show taxonomy search immediately
	taxonomy_search_panel.visible = true
	change_animal_button.visible = false
	current_animal_label.text = "Select an animal below"

	# Show pending image if provided
	if pending_image_texture:
		record_image.set_simple_texture(pending_image_texture)
		record_image.show_simple()
		record_image.visible = true


# ============================================================================
# Animal Editing
# ============================================================================

func _update_animal_display() -> void:
	"""Update the current animal label"""
	var display_animal = pending_animal_data if not pending_animal_data.is_empty() else current_animal_data
	var sci_name = display_animal.get("scientific_name", "Unknown")
	var common = display_animal.get("common_name", "")

	if common.is_empty():
		current_animal_label.text = sci_name
	else:
		current_animal_label.text = "%s (%s)" % [sci_name, common]

	# Show indicator if changed
	if not pending_animal_id.is_empty() and pending_animal_id != current_animal_id:
		current_animal_label.text += " [Changed]"
		has_unsaved_changes = true


func _on_change_animal_pressed() -> void:
	"""Show taxonomy search panel"""
	_set_state(State.EDITING_ANIMAL)
	taxonomy_search_panel.visible = true
	change_animal_button.visible = false

	# Pre-fill with current data
	genus_input.text = current_animal_data.get("genus", "")
	species_input.text = current_animal_data.get("species", "")
	common_name_input.text = current_animal_data.get("common_name", "")


func _on_search_input_submitted(_text: String) -> void:
	_on_search_pressed()


func _on_search_pressed() -> void:
	"""Perform taxonomy search"""
	var genus = genus_input.text.strip_edges()
	var species = species_input.text.strip_edges()
	var common = common_name_input.text.strip_edges()

	if genus.is_empty() and species.is_empty() and common.is_empty():
		show_error("Search Error", "Enter at least one search term")
		return

	show_loading("Searching...")
	_clear_search_results()

	APIManager.taxonomy.search("", genus, species, common, "", "", 20, _on_search_completed)


func _on_search_completed(response: Dictionary, code: int) -> void:
	hide_loading()

	if code != 200:
		show_error("Search Failed", response.get("error", "Unknown error"))
		return

	var results = response.get("results", [])
	if results.is_empty():
		show_error("No Results", "No matching species found. Try different terms.")
		return

	_display_search_results(results)


func _display_search_results(results: Array) -> void:
	"""Display taxonomy search results"""
	_clear_search_results()
	search_results_scroll.visible = true
	select_animal_button.disabled = true

	for result in results:
		var item = search_result_item_scene.instantiate()
		search_results_list.add_child(item)
		item.set_taxonomy_data(result)
		item.result_selected.connect(_on_search_result_selected)


func _clear_search_results() -> void:
	for child in search_results_list.get_children():
		child.queue_free()
	search_results_scroll.visible = false


func _on_search_result_selected(taxonomy_data: Dictionary) -> void:
	"""Handle selection of a taxonomy search result"""
	# Highlight selected
	for child in search_results_list.get_children():
		if child.has_method("set_selected"):
			child.set_selected(child.taxonomy_data == taxonomy_data)

	pending_animal_data = taxonomy_data
	select_animal_button.disabled = false


func _on_select_animal_pressed() -> void:
	"""Confirm animal selection and lookup/create Animal record"""
	if pending_animal_data.is_empty():
		return

	show_loading("Looking up animal...")

	var scientific_name = pending_animal_data.get("scientific_name", "")
	var common_names = pending_animal_data.get("common_names", [])
	var common_name = ""

	if common_names is Array and common_names.size() > 0:
		var first = common_names[0]
		if typeof(first) == TYPE_DICTIONARY:
			common_name = first.get("name", "")
		else:
			common_name = str(first)

	var additional = {
		"kingdom": pending_animal_data.get("kingdom", ""),
		"phylum": pending_animal_data.get("phylum", ""),
		"class_name": pending_animal_data.get("class_name", ""),
		"order": pending_animal_data.get("order", ""),
		"family": pending_animal_data.get("family", ""),
		"genus": pending_animal_data.get("genus", ""),
		"species": pending_animal_data.get("specific_epithet", "")
	}

	APIManager.animals.lookup_or_create(scientific_name, common_name, additional, _on_animal_lookup_completed)


func _on_animal_lookup_completed(response: Dictionary, code: int) -> void:
	hide_loading()

	if code != 200:
		show_error("Error", response.get("error", "Failed to find/create animal"))
		return

	var animal = response.get("animal", {})
	pending_animal_id = str(animal.get("id", ""))
	pending_animal_data["id"] = pending_animal_id
	pending_animal_data["scientific_name"] = animal.get("scientific_name", "")
	pending_animal_data["common_name"] = animal.get("common_name", "")

	# Collapse search panel
	taxonomy_search_panel.visible = false
	change_animal_button.visible = true

	_update_animal_display()
	_set_state(State.IDLE)


# ============================================================================
# Image Editing
# ============================================================================

func _on_replace_image_pressed() -> void:
	"""Open file picker to select new image"""
	file_selector.open_file_picker()


func _on_file_selected(file_name: String, file_type: String, file_data: PackedByteArray) -> void:
	"""Handle new image selection"""
	print("[EditEntry] New image selected: %s (%d bytes)" % [file_name, file_data.size()])

	# Store file info for conversion
	pending_image_data = file_data
	pending_image_file_name = file_name
	pending_image_file_type = file_type

	# Upload for conversion
	_set_state(State.UPLOADING_IMAGE)
	show_loading("Converting image...")

	APIManager.images.convert_image(file_data, file_name, file_type, _on_image_converted)


func _on_image_converted(response: Dictionary, code: int) -> void:
	if code != 200 and code != 201:
		hide_loading()
		show_error("Upload Failed", response.get("error", "Image conversion failed"))
		_set_state(State.IDLE)
		return

	pending_image_conversion_id = str(response.get("id", ""))

	# Download converted image for preview
	APIManager.images.download_converted_image(pending_image_conversion_id, _on_converted_image_downloaded)


func _on_converted_image_downloaded(response: Dictionary, code: int) -> void:
	hide_loading()

	if code != 200:
		show_error("Download Failed", "Could not download converted image")
		_set_state(State.IDLE)
		return

	var image_data: PackedByteArray = response.get("data", PackedByteArray())
	if image_data.is_empty():
		_set_state(State.IDLE)
		return

	var image = Image.new()
	if image.load_png_from_buffer(image_data) == OK:
		pending_image_texture = ImageTexture.create_from_image(image)
		record_image.set_simple_texture(pending_image_texture)
		record_image.show_simple()
		has_unsaved_changes = true

	_set_state(State.IDLE)


func _on_file_load_error(error: String) -> void:
	show_error("File Error", error)


func _on_rotate_image_pressed() -> void:
	"""Rotate the current image 90 degrees clockwise"""
	var texture_to_rotate: Texture2D = null

	if pending_image_texture != null:
		texture_to_rotate = pending_image_texture
	else:
		texture_to_rotate = record_image.get_simple_texture()

	if texture_to_rotate:
		var image = texture_to_rotate.get_image()
		image.rotate_90(CLOCKWISE)
		pending_image_texture = ImageTexture.create_from_image(image)
		record_image.set_simple_texture(pending_image_texture)
		record_image.show_simple()
		has_unsaved_changes = true


# ============================================================================
# Save/Cancel/Delete
# ============================================================================

func _on_save_pressed() -> void:
	"""Save all pending changes"""
	if mode == "create":
		_create_new_entry()
	else:
		_update_existing_entry()


func _create_new_entry() -> void:
	"""Create a new dex entry (manual entry mode)"""
	if pending_animal_id.is_empty():
		show_error("No Animal", "Please select an animal first")
		return

	_set_state(State.SAVING)
	show_loading("Creating entry...")

	# Use dex service to create entry
	# Note: For manual entry, we pass empty vision_job_id
	APIManager.dex.create_entry(
		pending_animal_id,
		"",  # No vision job
		"",  # No notes
		"friends",
		_on_entry_created
	)


func _on_entry_created(response: Dictionary, code: int) -> void:
	hide_loading()

	if code != 200 and code != 201:
		show_error("Create Failed", response.get("error", "Could not create entry"))
		_set_state(State.IDLE)
		return

	print("[EditEntry] Entry created successfully")

	# Trigger sync and navigate back
	APIManager.dex.sync_user_dex("self")
	_navigate_back()


func _update_existing_entry() -> void:
	"""Update the existing dex entry"""
	if not has_unsaved_changes:
		_navigate_back()
		return

	_set_state(State.SAVING)
	show_loading("Saving changes...")

	var update_data: Dictionary = {}

	# Include animal change if different
	if not pending_animal_id.is_empty() and pending_animal_id != current_animal_id:
		update_data["animal"] = pending_animal_id

	# Include image change if we have a new conversion
	if not pending_image_conversion_id.is_empty():
		update_data["source_conversion"] = pending_image_conversion_id

	if update_data.is_empty():
		hide_loading()
		_navigate_back()
		return

	APIManager.dex.update_entry(dex_entry_id, update_data, _on_entry_update_completed)


func _on_entry_update_completed(response: Dictionary, code: int) -> void:
	hide_loading()

	if code != 200:
		show_error("Save Failed", response.get("error", "Could not save changes"))
		_set_state(State.IDLE)
		return

	print("[EditEntry] Entry updated successfully")

	# Store the dex_entry_id so we can navigate back to it
	return_context["dex_entry_id"] = dex_entry_id

	# Trigger sync to update local database
	APIManager.dex.sync_user_dex("self")

	_navigate_back()


func _on_cancel_pressed() -> void:
	"""Cancel changes and go back"""
	# Note: Could add "discard changes?" confirmation here
	_navigate_back()


# ============================================================================
# Delete Functionality
# ============================================================================

func _on_delete_pressed() -> void:
	"""Show delete confirmation"""
	_set_state(State.CONFIRMING_DELETE)
	delete_confirmation_panel.visible = true
	delete_button.visible = false


func _on_cancel_delete_pressed() -> void:
	"""Cancel deletion"""
	_set_state(State.IDLE)
	delete_confirmation_panel.visible = false
	delete_button.visible = true


func _on_confirm_delete_pressed() -> void:
	"""Execute deletion"""
	show_loading("Deleting entry...")

	APIManager.dex.delete_entry(dex_entry_id, _on_delete_completed)


func _on_delete_completed(response: Dictionary, code: int) -> void:
	hide_loading()

	# 204 No Content is success for DELETE
	if code != 204 and code != 200:
		show_error("Delete Failed", response.get("error", "Could not delete entry"))
		_set_state(State.IDLE)
		delete_confirmation_panel.visible = false
		delete_button.visible = true
		return

	print("[EditEntry] Entry deleted successfully")

	# Remove from local database
	if creation_index >= 0:
		DexDatabase.remove_record(creation_index, "self")

	# Clear return context so we don't try to navigate to deleted entry
	return_context = {}

	_navigate_back()


# ============================================================================
# Navigation
# ============================================================================

func _navigate_back() -> void:
	"""Navigate back to the return scene with appropriate context"""
	if not return_context.is_empty():
		NavigationManager.set_context(return_context)

	NavigationManager.navigate_to(return_scene)


# ============================================================================
# State Management
# ============================================================================

func _set_state(new_state: State) -> void:
	current_state = new_state

	# Update UI based on state
	match new_state:
		State.IDLE:
			save_button.disabled = false
			cancel_button.disabled = false
		State.EDITING_ANIMAL:
			save_button.disabled = true
		State.UPLOADING_IMAGE, State.SAVING:
			save_button.disabled = true
			cancel_button.disabled = true
		State.CONFIRMING_DELETE:
			save_button.disabled = true
			cancel_button.disabled = true
		State.ERROR:
			save_button.disabled = false
			cancel_button.disabled = false
