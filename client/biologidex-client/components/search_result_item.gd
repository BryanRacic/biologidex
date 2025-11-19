extends PanelContainer

## SearchResultItem - Displays a single taxonomy search result

signal result_selected(taxonomy_data: Dictionary)

@onready var scientific_name_label: Label = $MarginContainer/VBoxContainer/ScientificNameLabel
@onready var common_name_label: Label = $MarginContainer/VBoxContainer/CommonNameLabel
@onready var hierarchy_label: Label = $MarginContainer/VBoxContainer/HierarchyLabel

var taxonomy_data: Dictionary = {}
var is_selected: bool = false

func _ready() -> void:
	# Make clickable
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

func set_taxonomy_data(data: Dictionary) -> void:
	"""Set the taxonomy data and update display"""
	taxonomy_data = data
	_update_display()

func _update_display() -> void:
	"""Update the visual display with taxonomy data"""
	var scientific_name = taxonomy_data.get("scientific_name", "Unknown")

	# Get common name
	var common_name = ""
	var common_names = taxonomy_data.get("common_names", [])
	if common_names is Array and common_names.size() > 0:
		var first_common = common_names[0]
		if typeof(first_common) == TYPE_DICTIONARY:
			common_name = first_common.get("name", "")
		else:
			common_name = str(first_common)

	# Display as "Common Name - Scientific Name" format
	if not common_name.is_empty():
		scientific_name_label.text = common_name + " - " + scientific_name
		common_name_label.visible = false
	else:
		# Fallback to just scientific name if no common name
		scientific_name_label.text = scientific_name
		common_name_label.visible = false

	# Taxonomic hierarchy (tertiary)
	var hierarchy_parts = []
	var kingdom = taxonomy_data.get("kingdom", "")
	var phylum = taxonomy_data.get("phylum", "")
	var animal_class = taxonomy_data.get("class_name", "")
	var order = taxonomy_data.get("order", "")
	var family = taxonomy_data.get("family", "")
	var genus = taxonomy_data.get("genus", "")

	if not kingdom.is_empty():
		hierarchy_parts.append(kingdom)
	if not phylum.is_empty():
		hierarchy_parts.append(phylum)
	if not animal_class.is_empty():
		hierarchy_parts.append(animal_class)
	if not order.is_empty():
		hierarchy_parts.append(order)
	if not family.is_empty():
		hierarchy_parts.append(family)
	if not genus.is_empty() and genus != scientific_name:
		hierarchy_parts.append(genus)

	if hierarchy_parts.size() > 0:
		hierarchy_label.text = " › ".join(hierarchy_parts)
		hierarchy_label.visible = true
	else:
		hierarchy_label.visible = false

func set_selected(selected: bool) -> void:
	"""Update selection state"""
	is_selected = selected
	if is_selected:
		# Highlight selected item
		add_theme_stylebox_override("panel", _create_selected_style())
	else:
		# Normal style
		remove_theme_stylebox_override("panel")

func _create_selected_style() -> StyleBoxFlat:
	"""Create a highlighted style for selected items"""
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.4, 0.8, 0.3)  # Blue tint
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.5, 1.0, 1.0)  # Bright blue border
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _on_gui_input(event: InputEvent) -> void:
	"""Handle input events"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			print("[SearchResultItem] Selected: ", taxonomy_data.get("scientific_name", ""))
			result_selected.emit(taxonomy_data)
