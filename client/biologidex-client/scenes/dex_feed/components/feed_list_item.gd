extends PanelContainer
## FeedListItem - Display a single entry in the dex feed

# Entry data
var entry_data: Dictionary = {}

# UI References
@onready var user_name: Label = $MarginContainer/VBoxContainer/HeaderRow/UserName
@onready var catch_date: Label = $MarginContainer/VBoxContainer/HeaderRow/CatchDate
@onready var favorite_button: Button = $MarginContainer/VBoxContainer/HeaderRow/FavoriteButton
@onready var dex_image_container: AspectRatioContainer = $MarginContainer/VBoxContainer/ContentRow/DexImageContainer
@onready var dex_image: TextureRect = $MarginContainer/VBoxContainer/ContentRow/DexImageContainer/DexImage
@onready var scientific_name: Label = $MarginContainer/VBoxContainer/ContentRow/InfoPanel/ScientificName
@onready var common_name: Label = $MarginContainer/VBoxContainer/ContentRow/InfoPanel/CommonName
@onready var dex_number: Label = $MarginContainer/VBoxContainer/ContentRow/InfoPanel/DexNumber
@onready var view_button: Button = $MarginContainer/VBoxContainer/ActionRow/ViewInDexButton

# Services
var DexDatabase

# Signals
signal favorite_toggled(entry_id: String, is_favorite: bool)
signal view_in_dex_pressed(entry: Dictionary)


func _ready() -> void:
	# Initialize services
	DexDatabase = get_node("/root/DexDatabase")

	# Connect button signals
	if favorite_button:
		favorite_button.pressed.connect(_on_favorite_button_pressed)
	if view_button:
		view_button.pressed.connect(_on_view_button_pressed)


func setup(entry: Dictionary) -> void:
	"""Setup the feed item with entry data"""
	entry_data = entry
	_populate_ui()
	_load_image()


func _populate_ui() -> void:
	"""Populate UI elements with entry data"""
	# User name
	if user_name:
		user_name.text = entry_data.get("owner_username", "Unknown")

	# Catch date
	if catch_date:
		var date_string: String = entry_data.get("catch_date", "")
		catch_date.text = _format_date(date_string)

	# Scientific name
	if scientific_name:
		scientific_name.text = entry_data.get("scientific_name", "Unknown Species")

	# Common name
	if common_name:
		var common: String = entry_data.get("common_name", "")
		if common.is_empty():
			common_name.text = ""
			common_name.visible = false
		else:
			common_name.text = common
			common_name.visible = true

	# Dex number
	if dex_number:
		var creation_index: int = entry_data.get("creation_index", -1)
		if creation_index >= 0:
			dex_number.text = "#%03d" % creation_index
		else:
			dex_number.text = "#???"

	# Favorite button
	_update_favorite_button(entry_data.get("is_favorite", false))


func _load_image() -> void:
	"""Load the image from cache or download if necessary"""
	var cached_path: String = entry_data.get("cached_image_path", "")

	# Try to load from cache first
	if not cached_path.is_empty() and FileAccess.file_exists(cached_path):
		_load_image_from_path(cached_path)
		return

	# If not cached, try to download
	var image_url: String = entry_data.get("dex_compatible_url", "")
	if not image_url.is_empty():
		_download_image(image_url)
	else:
		_set_placeholder_image()


func _load_image_from_path(path: String) -> void:
	"""Load image from local file path"""
	var image := Image.load_from_file(path)
	if image:
		var texture := ImageTexture.create_from_image(image)
		if dex_image:
			dex_image.texture = texture
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
	var texture := ImageTexture.create_from_image(image)
	if dex_image:
		dex_image.texture = texture

	# Cache the image for future use
	var owner_id: String = entry_data.get("owner_id", "")
	var image_url: String = entry_data.get("dex_compatible_url", "")

	if not owner_id.is_empty() and not image_url.is_empty():
		var cached_path: String = DexDatabase.cache_image(image_url, body, owner_id)
		entry_data["cached_image_path"] = cached_path
		print("[FeedListItem] Image cached at: ", cached_path)


func _set_placeholder_image() -> void:
	"""Set a placeholder image when real image is unavailable"""
	if dex_image:
		# Create a simple placeholder texture
		var placeholder_image := Image.create(256, 256, false, Image.FORMAT_RGB8)
		placeholder_image.fill(Color(0.2, 0.2, 0.2))  # Dark gray
		var texture := ImageTexture.create_from_image(placeholder_image)
		dex_image.texture = texture


func _format_date(iso_date: String) -> String:
	"""Convert ISO date to readable format"""
	if iso_date.is_empty():
		return "Unknown date"

	# Parse ISO format: YYYY-MM-DDTHH:MM:SS.sssZ
	var parts := iso_date.split("T")
	if parts.size() == 0:
		return iso_date

	var date_part := parts[0]
	var date_components := date_part.split("-")

	if date_components.size() != 3:
		return iso_date

	var year := date_components[0]
	var month := date_components[1]
	var day := date_components[2]

	# Return format: MM/DD/YYYY
	return "%s/%s/%s" % [month, day, year]


func _update_favorite_button(is_favorite: bool) -> void:
	"""Update the favorite button appearance"""
	if not favorite_button:
		return

	if is_favorite:
		favorite_button.text = "★"  # Filled star
		favorite_button.modulate = Color.YELLOW
	else:
		favorite_button.text = "☆"  # Empty star
		favorite_button.modulate = Color.WHITE


func _on_favorite_button_pressed() -> void:
	"""Handle favorite button press"""
	var entry_id: String = entry_data.get("dex_entry_id", "")
	if entry_id.is_empty():
		print("[FeedListItem] ERROR: No entry ID for favorite toggle")
		return

	# Toggle favorite state locally
	entry_data["is_favorite"] = not entry_data.get("is_favorite", false)
	_update_favorite_button(entry_data["is_favorite"])

	# Emit signal for parent to handle API call
	favorite_toggled.emit(entry_id, entry_data["is_favorite"])


func _on_view_button_pressed() -> void:
	"""Handle view in dex button press"""
	print("[FeedListItem] View in dex pressed for entry #%d" % entry_data.get("creation_index", -1))
	view_in_dex_pressed.emit(entry_data)
