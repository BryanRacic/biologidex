extends Button
## FeedListItem - Display a single entry in the dex feed
## Uses DexImageLoader for unified image loading with cache/download support.

# Entry data
var entry_data: Dictionary = {}

# UI References
@onready var dex_record_image: Control = $DexRecordImage
@onready var dex_image_container: AspectRatioContainer = $DexRecordImage/ImageBorderAspectRatio
@onready var bordered_image: TextureRect = $DexRecordImage/ImageBorderAspectRatio/ImageBorder/BorderedImage
@onready var simple_image: TextureRect = $DexRecordImage/SimpleImage
@onready var record_label: Label = $DexRecordImage/ImageBorderAspectRatio/ImageBorder/RecordMargin/RecordBackground/RecordTextMargin/RecordLabel

# Signals
signal item_pressed(entry: Dictionary)


func _ready() -> void:
	# Hide the simple image overlay (we only want the bordered version)
	if simple_image:
		simple_image.visible = false

	# Connect button press
	pressed.connect(_on_item_pressed)


func setup(entry: Dictionary) -> void:
	"""Setup the feed item with entry data"""
	entry_data = entry
	_populate_ui()
	_load_image()


func _populate_ui() -> void:
	"""Populate UI elements with entry data"""
	var scientific: String = entry_data.get("scientific_name", "Unknown Species")
	var common: String = entry_data.get("common_name", "")
	var owner: String = entry_data.get("owner_username", "Unknown")
	var creation_index: int = entry_data.get("creation_index", -1)
	var catch_date: String = entry_data.get("catch_date", "")

	# Set record label with species name and catch info
	if record_label:
		# Format species name
		var species_line := scientific
		if not common.is_empty():
			species_line += " - %s" % common

		# Format catch info (username and date on separate lines)
		var username_line := owner

		var date_line := ""
		if not catch_date.is_empty():
			# Format date nicely (take just the date part, not time)
			var date_parts := catch_date.split("T")
			if date_parts.size() > 0:
				date_line = date_parts[0]

		# Combine lines: species, username, date
		record_label.text = species_line + "\n" + username_line + "\n" + date_line

	# Set tooltip with full info
	var tooltip_info := "%s" % scientific
	if not common.is_empty():
		tooltip_info += " (%s)" % common
	tooltip_info += "\n#%03d - Caught by %s" % [creation_index, owner]
	if not catch_date.is_empty():
		var date_parts := catch_date.split("T")
		if date_parts.size() > 0:
			tooltip_info += " on " + date_parts[0]

	tooltip_text = tooltip_info


func _load_image() -> void:
	"""Load the image using DexImageLoader service"""
	var owner_id: String = entry_data.get("owner_id", "self")

	# Use DexImageLoader for unified cache/download handling
	DexImageLoader.load_image(entry_data, owner_id, _on_image_loaded, self)


func _on_image_loaded(result) -> void:
	"""Handle image load result from DexImageLoader"""
	if not is_instance_valid(self):
		return

	if result.success:
		if bordered_image:
			bordered_image.texture = result.texture
			# Update entry data with cached path for future reference
			if not result.cached_path.is_empty():
				entry_data["cached_image_path"] = result.cached_path
	else:
		_set_placeholder_image()


func _set_placeholder_image() -> void:
	"""Set a placeholder image when real image is unavailable"""
	if bordered_image:
		bordered_image.texture = DexImageLoader.create_placeholder(256, Color(0.2, 0.2, 0.2))


func _on_item_pressed() -> void:
	"""Handle item button press"""
	item_pressed.emit(entry_data)
