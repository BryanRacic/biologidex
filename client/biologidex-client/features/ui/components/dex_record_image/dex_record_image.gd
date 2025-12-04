class_name DexRecordImage
extends AspectRatioContainer
## DexRecordImage - Reusable component for displaying dex entry images with labels.
## Provides unified API for image loading, label formatting, and display modes.
## Uses proportional sizing so the component looks identical at any display size.

# =============================================================================
# Proportional Sizing Constants
# =============================================================================
# All sizes are calculated as percentages of the smaller dimension (width or height)
# These ratios create a consistent "card" look at any size.
# Derived to look good at both 80px (tree) and 400px (dex) displays.

const BORDER_RATIO: float = 0.04       # 4% - gives 3px at 80px, 16px at 400px
const FONT_RATIO: float = 0.02       
const LABEL_MARGIN_RATIO: float = 0.05 # 5% - bottom margin for label
const TEXT_PADDING_RATIO: float = 0.02 # 2% - padding inside label background
const LABEL_BG_EXPAND_RATIO: float = 0.04 # 4% - label extends past border

# Minimum and maximum values to prevent extreme sizes
const MIN_BORDER: int = 2
const MIN_FONT: int = 8
const MIN_MARGIN: int = 2
const MAX_BORDER: int = 24
const MAX_FONT: int = 64
const MAX_MARGIN: int = 20

# =============================================================================
# Internal Node References
# =============================================================================

var _bordered_container: PanelContainer
var _bordered_image: TextureRect
var _record_label: Label
var _record_margin: MarginContainer
var _text_margin: MarginContainer
var _label_background: PanelContainer
var _simple_image: TextureRect

# Style resources (created once, updated dynamically)
var _border_style: StyleBoxFlat
var _label_bg_style: StyleBoxFlat
var _label_settings: LabelSettings

# =============================================================================
# Entry Data Storage
# =============================================================================

var _entry_data: Dictionary = {}
var _user_id: String = ""

# =============================================================================
# Signals
# =============================================================================

signal image_loaded(success: bool)
signal image_load_failed


func _ready() -> void:
	# Get node references
	_bordered_container = get_node_or_null("ImageBorder")
	_bordered_image = get_node_or_null("ImageBorder/BorderedImage")
	_record_margin = get_node_or_null("ImageBorder/RecordMargin")
	_label_background = get_node_or_null("ImageBorder/RecordMargin/RecordBackground")
	_text_margin = get_node_or_null("ImageBorder/RecordMargin/RecordBackground/RecordTextMargin")
	_record_label = get_node_or_null("ImageBorder/RecordMargin/RecordBackground/RecordTextMargin/RecordLabel")
	_simple_image = get_node_or_null("SimpleImage")

	# Create dynamic style resources
	_setup_dynamic_styles()

	# Connect to resize signal for proportional updates
	resized.connect(_on_resized)

	# Apply initial proportional sizes after a frame (to get accurate size)
	await get_tree().process_frame
	_apply_proportional_sizes()


func _setup_dynamic_styles() -> void:
	"""Create style resources that will be updated dynamically."""
	print("[DexRecordImage] _setup_dynamic_styles: _bordered_container=%s, _record_label=%s" % [_bordered_container, _record_label])
	# Border style - cream colored frame around the image
	_border_style = StyleBoxFlat.new()
	_border_style.bg_color = Color(0.9, 0.88, 0.85, 1.0)
	_border_style.border_color = Color(0.9, 0.88, 0.85, 1.0)  # Match bg for seamless border
	if _bordered_container:
		_bordered_container.add_theme_stylebox_override("panel", _border_style)
		print("[DexRecordImage] Applied border style override")

	# Label background style
	_label_bg_style = StyleBoxFlat.new()
	_label_bg_style.bg_color = Color(0.9605384, 1.007952, 0.9881963, 0.88235295)
	if _label_background:
		_label_background.add_theme_stylebox_override("panel", _label_bg_style)

	# Label settings
	_label_settings = LabelSettings.new()
	_label_settings.font_color = Color(0, 0, 0, 1)
	if _record_label:
		_record_label.label_settings = _label_settings
		print("[DexRecordImage] Applied label settings")


func _on_resized() -> void:
	"""Handle component resize - update proportional sizes."""
	_apply_proportional_sizes()


func _apply_proportional_sizes() -> void:
	"""Calculate and apply sizes based on current component dimensions."""
	# Use max dimension so aspect ratio doesn't affect font/border sizes
	var base_dim := maxf(size.x, size.y)
	print("[DexRecordImage] _apply_proportional_sizes called, size=%s, base_dim=%s" % [size, base_dim])
	if base_dim < 20.0:
		return  # Too small to render meaningfully

	# Border width and content margin (content margin pushes image inward to show border)
	var border_width := clampi(int(base_dim * BORDER_RATIO), MIN_BORDER, MAX_BORDER)
	print("[DexRecordImage] Calculated: border=%d, font=%d" % [border_width, clampi(int(base_dim * FONT_RATIO), MIN_FONT, MAX_FONT)])
	_border_style.border_width_left = border_width
	_border_style.border_width_top = border_width
	_border_style.border_width_right = border_width
	_border_style.border_width_bottom = border_width
	_border_style.content_margin_left = float(border_width)
	_border_style.content_margin_top = float(border_width)
	_border_style.content_margin_right = float(border_width)
	_border_style.content_margin_bottom = float(border_width)

	# Font size
	var font_size := clampi(int(base_dim * FONT_RATIO), MIN_FONT, MAX_FONT)
	_label_settings.font_size = font_size

	# Label margin (bottom margin that positions label above border)
	var label_margin := clampi(int(base_dim * LABEL_MARGIN_RATIO), MIN_MARGIN, MAX_MARGIN)
	if _record_margin:
		_record_margin.add_theme_constant_override("margin_bottom", label_margin)

	# Text padding inside label background
	var text_padding := clampi(int(base_dim * TEXT_PADDING_RATIO), MIN_MARGIN, MAX_MARGIN)
	if _text_margin:
		_text_margin.add_theme_constant_override("margin_left", text_padding)
		_text_margin.add_theme_constant_override("margin_top", text_padding)
		_text_margin.add_theme_constant_override("margin_right", text_padding)
		_text_margin.add_theme_constant_override("margin_bottom", text_padding)

	# Label background expand margin (extends past the border edge)
	var expand_margin := clampi(int(base_dim * LABEL_BG_EXPAND_RATIO), MIN_MARGIN, MAX_MARGIN)
	_label_bg_style.expand_margin_right = float(expand_margin)


# =============================================================================
# Public API - Entry Data
# =============================================================================

func set_entry_data(data: Dictionary, user_id: String = "") -> void:
	"""Set entry data and update label. Call load_image() separately to load the image."""
	_entry_data = data
	_user_id = user_id
	_update_label_from_entry()


func get_entry_data() -> Dictionary:
	"""Get the current entry data."""
	return _entry_data


func get_user_id() -> String:
	"""Get the current user ID."""
	return _user_id


# =============================================================================
# Public API - Image Loading
# =============================================================================

func load_image_from_entry() -> void:
	"""Load image using DexImageLoader service based on current entry data."""
	if _entry_data.is_empty():
		_set_placeholder()
		return

	var loader = _get_image_loader()
	if loader:
		loader.load_image(_entry_data, _user_id, _on_image_loaded, self)
	else:
		_set_placeholder()


func set_texture(texture: Texture2D) -> void:
	"""Directly set texture on the bordered image."""
	if _bordered_image:
		_bordered_image.texture = texture


func set_simple_texture(texture: Texture2D) -> void:
	"""Directly set texture on the simple image (for preview mode)."""
	if _simple_image:
		_simple_image.texture = texture


func get_simple_texture() -> Texture2D:
	"""Get the current simple image texture."""
	if _simple_image:
		return _simple_image.texture
	return null


func update_aspect_ratio(width: float, height: float) -> void:
	"""Update container aspect ratio from image dimensions."""
	if height > 0:
		ratio = width / height


func clear_texture() -> void:
	"""Clear textures from both image displays."""
	if _bordered_image:
		_bordered_image.texture = null
	if _simple_image:
		_simple_image.texture = null


# =============================================================================
# Public API - Display Modes
# =============================================================================

func show_bordered() -> void:
	"""Show bordered card mode with label, hide simple preview."""
	if _simple_image:
		_simple_image.visible = false
	if _bordered_container:
		_bordered_container.visible = true


func show_simple() -> void:
	"""Show simple preview mode, hide bordered card."""
	if _simple_image:
		_simple_image.visible = true
	if _bordered_container:
		_bordered_container.visible = false


func copy_simple_to_bordered() -> void:
	"""Copy simple image texture to bordered image."""
	if _simple_image and _bordered_image and _simple_image.texture:
		_bordered_image.texture = _simple_image.texture


# =============================================================================
# Public API - Label
# =============================================================================

func set_label_text(species_line: String, username_line: String, date_line: String) -> void:
	"""Set label text with explicit values (for camera scene with live data)."""
	if _record_label:
		_record_label.text = species_line + "\n" + username_line + "\n" + date_line


func update_label_from_data(scientific_name: String, common_name: String, username: String, catch_date: String) -> void:
	"""Update label from individual data fields."""
	if not _record_label:
		return

	var species_line := _format_species_line(scientific_name, common_name)
	var username_line := username if not username.is_empty() else "Unknown User"
	var date_line := _format_date(catch_date)

	_record_label.text = species_line + "\n" + username_line + "\n" + date_line


# =============================================================================
# Public API - Node Access (for special cases like rotation)
# =============================================================================

func get_simple_image() -> TextureRect:
	"""Get direct access to simple image TextureRect (for rotation, etc.)."""
	return _simple_image


func get_bordered_image() -> TextureRect:
	"""Get direct access to bordered image TextureRect."""
	return _bordered_image


func get_record_label() -> Label:
	"""Get direct access to record label."""
	return _record_label


func get_bordered_container() -> PanelContainer:
	"""Get direct access to bordered container."""
	return _bordered_container


# =============================================================================
# Public API - Mouse Filter
# =============================================================================

func set_mouse_passthrough(enabled: bool) -> void:
	"""Set mouse filter to IGNORE on this control and all children.
	Use this for contexts like tree view where pan/zoom should work over images."""
	var filter := Control.MOUSE_FILTER_IGNORE if enabled else Control.MOUSE_FILTER_STOP
	_set_mouse_filter_recursive(self, filter)


func _set_mouse_filter_recursive(node: Node, filter: Control.MouseFilter) -> void:
	"""Recursively set mouse filter on all Control descendants."""
	if node is Control:
		node.mouse_filter = filter
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter)


# =============================================================================
# Public API - Placeholder
# =============================================================================

func set_placeholder(size_val: int = 256, color: Color = Color(0.3, 0.3, 0.3)) -> void:
	"""Set a placeholder image."""
	_set_placeholder(size_val, color)


# =============================================================================
# Private - Label Formatting
# =============================================================================

func _update_label_from_entry() -> void:
	"""Update label from current entry data."""
	if not _record_label:
		return

	var scientific: String = _entry_data.get("scientific_name", "")
	var common: String = _entry_data.get("common_name", "")
	var owner: String = _entry_data.get("owner_username", "")
	var catch_date: String = _entry_data.get("catch_date", _entry_data.get("updated_at", ""))

	var species_line := _format_species_line(scientific, common)
	var username_line := owner if not owner.is_empty() else "Unknown User"
	var date_line := _format_date(catch_date)

	_record_label.text = species_line + "\n" + username_line + "\n" + date_line


func _format_species_line(scientific: String, common: String) -> String:
	"""Format species line: 'Scientific name - common name'"""
	var line := scientific if not scientific.is_empty() else "Unknown"
	if not common.is_empty():
		if scientific.is_empty():
			line = common
		else:
			line += " - " + common
	return line


func _format_date(iso_date: String) -> String:
	"""Extract date portion from ISO format timestamp."""
	if iso_date.is_empty():
		return ""
	var date_parts := iso_date.split("T")
	if date_parts.size() > 0:
		return date_parts[0]
	return ""


# =============================================================================
# Private - Image Loading
# =============================================================================

func _get_image_loader():
	"""Get DexImageLoader singleton."""
	return get_node_or_null("/root/DexImageLoader")


func _on_image_loaded(result) -> void:
	"""Handle image load result from DexImageLoader."""
	if not is_instance_valid(self):
		return

	if result.success:
		set_texture(result.texture)
		update_aspect_ratio(float(result.image.get_width()), float(result.image.get_height()))
		show_bordered()

		# Re-apply proportional sizes after aspect ratio change
		_apply_proportional_sizes()

		# Update entry data with cached path
		if not result.cached_path.is_empty():
			_entry_data["cached_image_path"] = result.cached_path

		image_loaded.emit(true)
	else:
		_set_placeholder()
		image_load_failed.emit()
		image_loaded.emit(false)


func _set_placeholder(size_val: int = 256, color: Color = Color(0.3, 0.3, 0.3)) -> void:
	"""Set a placeholder image when real image is unavailable."""
	var loader = _get_image_loader()
	if loader:
		set_texture(loader.create_placeholder(size_val, color))
	else:
		# Fallback if loader unavailable
		var placeholder := Image.create(size_val, size_val, false, Image.FORMAT_RGB8)
		placeholder.fill(color)
		var texture := ImageTexture.create_from_image(placeholder)
		set_texture(texture)

	ratio = 1.0
	show_bordered()
