extends PopupPanel

## ManualEntryPopup - Search and select taxonomy records manually

signal entry_updated(taxonomy_data: Dictionary)
signal popup_closed()

@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/Header/TitleLabel
@onready var close_button: Button = $Panel/MarginContainer/VBoxContainer/Header/CloseButton
@onready var genus_input: LineEdit = $Panel/MarginContainer/VBoxContainer/SearchForm/GenusContainer/GenusInput
@onready var species_input: LineEdit = $Panel/MarginContainer/VBoxContainer/SearchForm/SpeciesContainer/SpeciesInput
@onready var common_name_input: LineEdit = $Panel/MarginContainer/VBoxContainer/SearchForm/CommonNameContainer/CommonNameInput
@onready var search_button: Button = $Panel/MarginContainer/VBoxContainer/SearchForm/ButtonContainer/SearchButton
@onready var back_button: Button = $Panel/MarginContainer/VBoxContainer/SearchForm/ButtonContainer/BackButton
@onready var results_label: Label = $Panel/MarginContainer/VBoxContainer/ResultsContainer/ResultsLabel
@onready var results_list: VBoxContainer = $Panel/MarginContainer/VBoxContainer/ResultsContainer/ScrollContainer/ResultsList
@onready var loading_label: Label = $Panel/MarginContainer/VBoxContainer/ResultsContainer/LoadingLabel
@onready var selected_label: Label = $Panel/MarginContainer/VBoxContainer/SelectionContainer/SelectedLabel
@onready var submit_button: Button = $Panel/MarginContainer/VBoxContainer/SelectionContainer/SubmitButton

# Properties
var current_dex_entry_id: String = ""
var selected_taxonomy: Dictionary = {}
var prefill_data: Dictionary = {}
var search_result_item_scene: PackedScene = preload("res://components/search_result_item.tscn")
var current_results: Array = []
var selected_item: Control = null

func _ready() -> void:
	print("[ManualEntryPopup] Popup ready")

	# Connect buttons
	close_button.pressed.connect(_on_close_pressed)
	search_button.pressed.connect(_on_search_pressed)
	back_button.pressed.connect(_on_back_pressed)
	submit_button.pressed.connect(_on_submit_pressed)

	# Connect Enter key on inputs to trigger search
	genus_input.text_submitted.connect(_on_text_submitted)
	species_input.text_submitted.connect(_on_text_submitted)
	common_name_input.text_submitted.connect(_on_text_submitted)

	# Initialize UI state
	submit_button.disabled = true
	loading_label.visible = false
	results_label.visible = false

	# Pre-fill if data provided
	if not prefill_data.is_empty():
		_prefill_inputs()

func _prefill_inputs() -> void:
	"""Pre-fill input fields with existing data"""
	if prefill_data.has("genus"):
		genus_input.text = str(prefill_data["genus"])
	if prefill_data.has("species"):
		species_input.text = str(prefill_data["species"])
	if prefill_data.has("common_name"):
		common_name_input.text = str(prefill_data["common_name"])

func _on_text_submitted(_text: String) -> void:
	"""Handle Enter key press in any input field"""
	_on_search_pressed()

func _on_search_pressed() -> void:
	"""Perform taxonomy search"""
	var genus = genus_input.text.strip_edges()
	var species = species_input.text.strip_edges()
	var common_name = common_name_input.text.strip_edges()

	# Validate input
	if genus.is_empty() and species.is_empty() and common_name.is_empty():
		_show_error("Please enter at least one search term")
		return

	print("[ManualEntryPopup] Searching for: genus=%s, species=%s, common_name=%s" % [genus, species, common_name])

	# Show loading state
	loading_label.visible = true
	loading_label.text = "Searching..."
	results_label.visible = false
	search_button.disabled = true
	_clear_results()

	# Perform search
	APIManager.taxonomy.search(
		"",
		genus,
		species,
		common_name,
		"",
		"",
		20,
		_on_search_completed
	)

func _on_search_completed(response: Dictionary, code: int) -> void:
	"""Handle search results"""
	loading_label.visible = false
	search_button.disabled = false

	if code != 200:
		var error_msg = response.get("error", "Search failed")
		_show_error("Search failed: " + error_msg)
		return

	var results = response.get("results", [])
	var count = response.get("count", 0)

	print("[ManualEntryPopup] Search completed: %d results" % count)

	if count == 0:
		_show_error("No results found. Try different search terms.")
		return

	# Display results
	_display_results(results)

func _display_results(results: Array) -> void:
	"""Display search results in the list"""
	_clear_results()
	current_results = results

	results_label.visible = true
	results_label.text = "Results: %d found" % results.size()

	for result in results:
		var item = search_result_item_scene.instantiate()
		results_list.add_child(item)
		item.set_taxonomy_data(result)
		item.result_selected.connect(_on_result_selected)

func _clear_results() -> void:
	"""Clear all result items"""
	for child in results_list.get_children():
		child.queue_free()
	current_results = []
	selected_item = null

func _on_result_selected(taxonomy_data: Dictionary) -> void:
	"""Handle result selection"""
	print("[ManualEntryPopup] Result selected: ", taxonomy_data.get("scientific_name", ""))

	selected_taxonomy = taxonomy_data

	# Update selection visuals
	if selected_item:
		selected_item.set_selected(false)

	# Find and highlight the selected item
	for child in results_list.get_children():
		if child.taxonomy_data == taxonomy_data:
			child.set_selected(true)
			selected_item = child
			break

	# Update selected label
	var scientific_name = taxonomy_data.get("scientific_name", "Unknown")
	var common_names = taxonomy_data.get("common_names", [])
	var display_text = scientific_name

	if common_names is Array and common_names.size() > 0:
		var first_common = common_names[0]
		var common_name = ""
		if typeof(first_common) == TYPE_DICTIONARY:
			common_name = first_common.get("name", "")
		else:
			common_name = str(first_common)
		if not common_name.is_empty():
			display_text += " - " + common_name

	selected_label.text = "Selected: " + display_text
	submit_button.disabled = false

func _on_submit_pressed() -> void:
	"""Submit the selected taxonomy"""
	if selected_taxonomy.is_empty():
		_show_error("Please select a result first")
		return

	print("[ManualEntryPopup] Submitting selection")

	# If we have a dex entry ID, update it
	if not current_dex_entry_id.is_empty():
		_update_dex_entry()
	else:
		# Just emit the taxonomy data for the caller to handle
		entry_updated.emit(selected_taxonomy)
		_close_popup()

func _update_dex_entry() -> void:
	"""Update the dex entry with the new animal"""
	# Get the taxonomy ID to look up or create the animal
	var taxonomy_id = selected_taxonomy.get("id", "")

	if taxonomy_id.is_empty():
		_show_error("Invalid taxonomy selection")
		return

	# First, we need to look up or create an Animal from this taxonomy
	# We'll use the animals service to do this
	var scientific_name = selected_taxonomy.get("scientific_name", "")
	var common_names = selected_taxonomy.get("common_names", [])
	var common_name = ""

	if common_names is Array and common_names.size() > 0:
		var first_common = common_names[0]
		if typeof(first_common) == TYPE_DICTIONARY:
			common_name = first_common.get("name", "")
		else:
			common_name = str(first_common)

	# Prepare additional taxonomy data
	var additional_data = {
		"kingdom": selected_taxonomy.get("kingdom", ""),
		"phylum": selected_taxonomy.get("phylum", ""),
		"class_name": selected_taxonomy.get("class_name", ""),
		"order": selected_taxonomy.get("order", ""),
		"family": selected_taxonomy.get("family", ""),
		"genus": selected_taxonomy.get("genus", ""),
		"species": selected_taxonomy.get("specific_epithet", ""),
	}

	print("[ManualEntryPopup] Looking up or creating animal: ", scientific_name)

	# Create/lookup the animal
	APIManager.animals.lookup_or_create(
		scientific_name,
		common_name,
		additional_data,
		_on_animal_lookup_completed
	)

func _on_animal_lookup_completed(response: Dictionary, code: int) -> void:
	"""Handle animal lookup/creation response"""
	if code != 200:
		var error_msg = response.get("error", "Failed to create animal")
		_show_error("Error: " + error_msg)
		return

	var animal = response.get("animal", {})
	var animal_id = animal.get("id", "")

	if animal_id.is_empty():
		_show_error("Failed to get animal ID")
		return

	print("[ManualEntryPopup] Animal ready, updating dex entry: ", animal_id)

	# Now update the dex entry with this animal
	var update_data = {
		"animal": animal_id
	}

	APIManager.dex.update_entry(
		current_dex_entry_id,
		update_data,
		_on_dex_entry_updated
	)

func _on_dex_entry_updated(response: Dictionary, code: int) -> void:
	"""Handle dex entry update response"""
	if code != 200:
		var error_msg = response.get("error", "Failed to update entry")
		_show_error("Update failed: " + error_msg)
		return

	print("[ManualEntryPopup] Dex entry updated successfully")

	# Emit success signal with the full response
	entry_updated.emit(response)
	_close_popup()

func _show_error(message: String) -> void:
	"""Show error message to user"""
	results_label.visible = true
	results_label.text = "⚠ " + message
	results_label.add_theme_color_override("font_color", Color.ORANGE_RED)
	print("[ManualEntryPopup] ERROR: ", message)

func _on_back_pressed() -> void:
	"""Handle back button"""
	_close_popup()

func _on_close_pressed() -> void:
	"""Handle close button"""
	_close_popup()

func _close_popup() -> void:
	"""Close the popup"""
	print("[ManualEntryPopup] Closing popup")
	popup_closed.emit()
	queue_free()
