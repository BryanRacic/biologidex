extends Button
## FeedListItem - Display a single entry in the dex feed
## Uses DexRecordImage component for unified display and image loading.

# Entry data
var entry_data: Dictionary = {}

# UI References - DexRecordImage component handles internal structure
@onready var dex_record_image: DexRecordImage = $DexRecordImage

# Signals
signal item_pressed(entry: Dictionary)


func _ready() -> void:
	# Connect button press
	pressed.connect(_on_item_pressed)

	# Connect image load signal for updating cached path
	dex_record_image.image_loaded.connect(_on_image_loaded)


func setup(entry: Dictionary) -> void:
	"""Setup the feed item with entry data"""
	entry_data = entry
	var owner_id: String = entry_data.get("owner_id", "self")

	# Use DexRecordImage component for display and image loading
	dex_record_image.set_entry_data(entry_data, owner_id)
	dex_record_image.load_image_from_entry()

	# Set tooltip with full info
	_update_tooltip()


func _update_tooltip() -> void:
	"""Update tooltip with entry details"""
	var scientific: String = entry_data.get("scientific_name", "Unknown Species")
	var common: String = entry_data.get("common_name", "")
	var owner: String = entry_data.get("owner_username", "Unknown")
	var creation_index: int = entry_data.get("creation_index", -1)
	var catch_date: String = entry_data.get("catch_date", "")

	var tooltip_info := "%s" % scientific
	if not common.is_empty():
		tooltip_info += " (%s)" % common
	tooltip_info += "\n#%03d - Caught by %s" % [creation_index, owner]
	if not catch_date.is_empty():
		var date_parts := catch_date.split("T")
		if date_parts.size() > 0:
			tooltip_info += " on " + date_parts[0]

	tooltip_text = tooltip_info


func _on_image_loaded(success: bool) -> void:
	"""Handle image load completion from DexRecordImage component"""
	if not is_instance_valid(self):
		return

	if success:
		# Update entry data with cached path from component
		var component_data: Dictionary = dex_record_image.get_entry_data()
		var cached_path: String = component_data.get("cached_image_path", "")
		if not cached_path.is_empty():
			entry_data["cached_image_path"] = cached_path


func _on_item_pressed() -> void:
	"""Handle item button press"""
	item_pressed.emit(entry_data)
