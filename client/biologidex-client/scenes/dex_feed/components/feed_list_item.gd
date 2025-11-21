extends Button
## FeedListItem - Display a single entry in the dex feed

# Entry data
var entry_data: Dictionary = {}

# UI References
@onready var dex_record_image: Control = $DexRecordImage
@onready var dex_image_container: AspectRatioContainer = $DexRecordImage/ImageBorderAspectRatio
@onready var bordered_image: TextureRect = $DexRecordImage/ImageBorderAspectRatio/ImageBorder/Image
@onready var simple_image: TextureRect = $DexRecordImage/Image
@onready var record_label: Label = $DexRecordImage/ImageBorderAspectRatio/ImageBorder/RecordMargin/RecordBackground/RecordTextMargin/RecordLabel

# Services
var DexDatabase

# Signals
signal item_pressed(entry: Dictionary)


func _ready() -> void:
	# Initialize services
	DexDatabase = get_node("/root/DexDatabase")

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

	# Set record label
	if record_label:
		var label_text := scientific
		if not common.is_empty():
			label_text += " - %s" % common
		record_label.text = label_text

	# Set tooltip with full info including owner
	var tooltip_info := "%s" % scientific
	if not common.is_empty():
		tooltip_info += " (%s)" % common
	tooltip_info += "\n#%03d - Caught by %s" % [creation_index, owner]

	tooltip_text = tooltip_info


func _load_image() -> void:
	"""Load the image from cache or download if necessary"""
	var cached_path: String = entry_data.get("cached_image_path", "")
	print("[FeedListItem] Loading image, cached_path: ", cached_path)

	# Try to load from cache first
	if not cached_path.is_empty() and FileAccess.file_exists(cached_path):
		print("[FeedListItem] Loading from cache: ", cached_path)
		_load_image_from_path(cached_path)
		return

	# If not cached, try to download
	var image_url: String = entry_data.get("dex_compatible_url", "")
	if not image_url.is_empty():
		print("[FeedListItem] Cache miss, downloading: ", image_url)
		_download_image(image_url)
	else:
		_set_placeholder_image()


func _load_image_from_path(path: String) -> void:
	"""Load image from local file path"""
	print("[FeedListItem] Loading from path: ", path)
	print("[FeedListItem] bordered_image is null: ", bordered_image == null)

	var image := Image.load_from_file(path)
	if image:
		print("[FeedListItem] Image loaded successfully, size: ", image.get_size())
		var texture := ImageTexture.create_from_image(image)
		if bordered_image:
			bordered_image.texture = texture
			print("[FeedListItem] Texture set to bordered_image")
		else:
			print("[FeedListItem] ERROR: bordered_image is null!")
	else:
		print("[FeedListItem] Failed to load image from: ", path)
		_set_placeholder_image()


func _download_image(url: String) -> void:
	"""Download image from server and cache it"""
	print("[FeedListItem] Downloading image: ", url)

	var http_request := HTTPRequest.new()
	add_child(http_request)
	http_request.accept_gzip = false  # Important for web export
	http_request.request_completed.connect(_on_image_downloaded.bind(http_request))

	var error := http_request.request(url)
	if error != OK:
		print("[FeedListItem] ERROR: Failed to start download: ", error)
		http_request.queue_free()
		_set_placeholder_image()


func _on_image_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest) -> void:
	"""Handle image download completion"""
	http_request.queue_free()

	if response_code != 200:
		print("[FeedListItem] ERROR: Image download failed with code: ", response_code)
		_set_placeholder_image()
		return

	if body.size() == 0:
		print("[FeedListItem] ERROR: Downloaded image is empty")
		_set_placeholder_image()
		return

	# Load image from buffer
	var image := Image.new()
	var load_error := image.load_png_from_buffer(body)

	if load_error != OK:
		print("[FeedListItem] ERROR: Failed to load PNG from buffer: ", load_error)
		_set_placeholder_image()
		return

	# Display the image
	print("[FeedListItem] Downloaded image size: ", image.get_size())
	var texture := ImageTexture.create_from_image(image)
	if bordered_image:
		bordered_image.texture = texture
		print("[FeedListItem] Texture set to bordered_image from download")
	else:
		print("[FeedListItem] ERROR: bordered_image is null in download callback!")

	# Cache the image for future use
	var owner_id: String = entry_data.get("owner_id", "")
	var image_url: String = entry_data.get("dex_compatible_url", "")
	var creation_index: int = entry_data.get("creation_index", -1)

	if not owner_id.is_empty() and not image_url.is_empty() and creation_index >= 0:
		var cached_path: String = DexDatabase.cache_image(image_url, body, owner_id)
		entry_data["cached_image_path"] = cached_path
		print("[FeedListItem] Image cached at: ", cached_path)

		# Update the DexDatabase record with the cached path
		var record: Dictionary = DexDatabase.get_record_for_user(creation_index, owner_id)
		if not record.is_empty():
			record["cached_image_path"] = cached_path
			DexDatabase.add_record_from_dict(record, owner_id)
			print("[FeedListItem] Updated DexDatabase record with cached path")

			# Verify the update worked
			var updated_record: Dictionary = DexDatabase.get_record_for_user(creation_index, owner_id)
			print("[FeedListItem] Verified cached_path in DB: ", updated_record.get("cached_image_path", "EMPTY"))


func _set_placeholder_image() -> void:
	"""Set a placeholder image when real image is unavailable"""
	if bordered_image:
		# Create a simple placeholder texture
		var placeholder_image := Image.create(256, 256, false, Image.FORMAT_RGB8)
		placeholder_image.fill(Color(0.2, 0.2, 0.2))  # Dark gray
		var texture := ImageTexture.create_from_image(placeholder_image)
		bordered_image.texture = texture


func _on_item_pressed() -> void:
	"""Handle item button press"""
	print("[FeedListItem] Item pressed for entry #%d" % entry_data.get("creation_index", -1))
	item_pressed.emit(entry_data)
