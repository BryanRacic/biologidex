class_name FeedCarouselRenderer
extends Control

## Manages a pool of DexRecordImage instances for efficient carousel rendering.
## Only 3 images are ever loaded at once (previous, current, next).
## Applies randomization to spacing, size, offset, and rotation for organic scrapbook feel.

signal image_ready(index: int)
signal image_loading(index: int)
signal item_pressed(entry: Dictionary)
signal layout_calculated(total_height: float)  # Emitted when entry layout is computed

const POOL_SIZE: int = 5  # Slightly larger pool to handle varied spacing
const DEX_RECORD_IMAGE_SCENE = preload("res://features/ui/components/dex_record_image/dex_record_image.tscn")

# =============================================================================
# Randomization Configuration (export for editor tweaking)
# =============================================================================

@export_group("Spacing")
## Minimum vertical space between record images (pixels)
@export var min_space: float = 100.0
## Maximum additional random space added to min_space (pixels)
@export var max_rand_space: float = 60.0

@export_group("Size Variation")
## Maximum random size adjustment (+/- percentage, e.g., 0.15 = 15%)
@export var max_rand_size: float = 0.0

@export_group("Position Variation")
## Maximum random horizontal offset (+/- percentage of container width)
@export var max_rand_offset: float = 0.1

@export_group("Rotation Variation")
## Maximum random rotation (+/- degrees)
@export var max_rand_rotate: float = 8.0

# =============================================================================
# Pool Management
# =============================================================================

var _image_pool: Array[DexRecordImage] = []
var _active_assignments: Dictionary = {}  # {pool_index: data_index}
var _loading_states: Dictionary = {}      # {pool_index: SlotState}

# Slot states
enum SlotState { EMPTY, LOADING, READY, ERROR }

# =============================================================================
# Entry Data & Layout
# =============================================================================

## Default aspect ratio for layout calculations (width/height)
## Most phone photos are 4:3 (1.33) or 3:2 (1.5). Using 4:3 as default.
const DEFAULT_ASPECT_RATIO: float = 1.33

var _entries: Array[Dictionary] = []
var _scroll_offset: float = 0.0

# Per-entry random values (cached so they stay consistent)
# Each entry: { "spacing": float, "size_mult": float, "x_offset": float, "rotation": float }
var _entry_randoms: Array[Dictionary] = []

# Computed layout positions (Y position of each entry's top edge)
var _entry_positions: Array[float] = []
var _total_content_height: float = 0.0


func _ready() -> void:
	# Wait a frame to get accurate size
	await get_tree().process_frame
	_setup_pool()


func _setup_pool() -> void:
	"""Pre-create pool of DexRecordImage instances."""
	for i in range(POOL_SIZE):
		var dex_image: DexRecordImage = DEX_RECORD_IMAGE_SCENE.instantiate()
		dex_image.name = "PooledImage_%d" % i
		dex_image.visible = false
		dex_image.mouse_filter = Control.MOUSE_FILTER_STOP
		# Enable pivot for rotation
		dex_image.pivot_offset = dex_image.size / 2.0
		add_child(dex_image)
		_image_pool.append(dex_image)
		_loading_states[i] = SlotState.EMPTY

		# Connect image loaded signal with pool index
		dex_image.image_loaded.connect(_on_image_loaded.bind(i))

	print("[FeedCarouselRenderer] Pool created with %d images" % POOL_SIZE)


# =============================================================================
# Public API
# =============================================================================

func setup(container_width: float, container_height: float) -> void:
	"""Configure carousel dimensions. Item dimensions are calculated from actual size."""
	# Note: container_width/height are passed for logging but actual size is used dynamically
	var calculated_height := _get_base_item_height()
	print("[FeedCarouselRenderer] Configured: %.0fx%.0f, calculated item_height=%.0f" % [container_width, container_height, calculated_height])


func set_entries(entries: Array[Dictionary]) -> void:
	"""Set the data entries to display and compute layout."""
	_entries = entries
	_clear_all_assignments()
	_generate_random_values()
	_compute_layout()
	print("[FeedCarouselRenderer] Set %d entries, total height=%.0f" % [entries.size(), _total_content_height])


func update_scroll(offset: float) -> void:
	"""Update based on scroll position. Called by touch controller."""
	_scroll_offset = offset

	if _entries.is_empty():
		return

	# Determine which entries are visible
	var visible_indices := _get_visible_indices()

	# Update pool assignments
	_update_pool_assignments(visible_indices)

	# Position all active images
	_position_active_images()


func get_entry_at_index(index: int) -> Dictionary:
	"""Get entry data at specific index."""
	if index >= 0 and index < _entries.size():
		return _entries[index]
	return {}


func get_entry_at_position(y_pos: float) -> int:
	"""Get the entry index at a given Y position (in actual pixels)."""
	for i in range(_entry_positions.size()):
		var entry_top: float = _entry_positions[i]
		var entry_height: float = _get_entry_height(i)
		if y_pos >= entry_top and y_pos < entry_top + entry_height:
			return i
	return -1


func get_total_content_height() -> float:
	"""Get total scrollable content height."""
	return _total_content_height


func clear() -> void:
	"""Clear all entries and deactivate pool."""
	_entries.clear()
	_entry_randoms.clear()
	_entry_positions.clear()
	_total_content_height = 0.0
	_clear_all_assignments()


# =============================================================================
# Random Value Generation
# =============================================================================

func _generate_random_values() -> void:
	"""Generate and cache random values for each entry."""
	_entry_randoms.clear()

	for i in range(_entries.size()):
		var rand_data := {
			# Random additional spacing after this entry
			"spacing": randf() * max_rand_space,
			# Size multiplier: 1.0 +/- max_rand_size
			"size_mult": 1.0 + randf_range(-max_rand_size, max_rand_size),
			# X offset as ratio of container width
			"x_offset": randf_range(-max_rand_offset, max_rand_offset),
			# Rotation in degrees
			"rotation": randf_range(-max_rand_rotate, max_rand_rotate)
		}
		_entry_randoms.append(rand_data)


func _compute_layout() -> void:
	"""Compute Y positions for all entries based on their sizes and spacing."""
	_entry_positions.clear()

	var current_y: float = min_space  # Start with initial padding

	for i in range(_entries.size()):
		_entry_positions.append(current_y)

		# Calculate this entry's height
		var entry_height := _get_entry_height(i)

		# Add spacing after this entry
		var spacing := min_space
		if i < _entry_randoms.size():
			spacing += _entry_randoms[i].spacing

		current_y += entry_height + spacing

	_total_content_height = current_y
	# Emit in base coordinates - caller scales if needed
	layout_calculated.emit(_total_content_height)


func _get_base_item_width() -> float:
	"""Get the base width for items (90% of actual container width)."""
	assert(size.x > 0, "FeedCarouselRenderer: size.x must be > 0. Ensure renderer is added to scene tree before use.")
	return size.x * 0.9


func _get_base_item_height() -> float:
	"""Get the base height for items, calculated from width and default aspect ratio."""
	return _get_base_item_width() / DEFAULT_ASPECT_RATIO


func _get_entry_height(index: int) -> float:
	"""Get the height of an entry including size randomization."""
	var size_mult := 1.0
	if index < _entry_randoms.size():
		size_mult = _entry_randoms[index].size_mult
	return _get_base_item_height() * size_mult


func _get_entry_width(index: int) -> float:
	"""Get the width of an entry including size randomization."""
	var size_mult := 1.0
	if index < _entry_randoms.size():
		size_mult = _entry_randoms[index].size_mult
	return _get_base_item_width() * size_mult


# =============================================================================
# Visibility Determination
# =============================================================================

func _get_visible_indices() -> Array[int]:
	"""Determine which entry indices are currently visible."""
	var visible: Array[int] = []

	# View bounds with buffer (half screen above, 1.5 screens below)
	var view_top := _scroll_offset - size.y * 0.5
	var view_bottom := _scroll_offset + size.y * 1.5

	for i in range(_entry_positions.size()):
		var entry_top: float = _entry_positions[i]
		var entry_height := _get_entry_height(i)
		var entry_bottom := entry_top + entry_height

		# Check if entry overlaps view
		if entry_bottom >= view_top and entry_top <= view_bottom:
			visible.append(i)

	return visible


# =============================================================================
# Pool Management
# =============================================================================

func _update_pool_assignments(visible_indices: Array[int]) -> void:
	"""Update which pool slots show which data indices."""
	var slots_to_reassign: Array[int] = []
	var indices_needing_slots: Array[int] = visible_indices.duplicate()

	# Check current assignments
	for pool_idx in _active_assignments:
		var current_data_idx: int = _active_assignments[pool_idx]
		if current_data_idx in visible_indices:
			indices_needing_slots.erase(current_data_idx)
		else:
			slots_to_reassign.append(pool_idx)
			# Hide the image being recycled
			_image_pool[pool_idx].visible = false

	# Include unused pool slots
	for i in range(_image_pool.size()):
		if not _active_assignments.has(i) and i not in slots_to_reassign:
			slots_to_reassign.append(i)

	# Assign slots to indices that need them
	for data_idx in indices_needing_slots:
		if slots_to_reassign.is_empty():
			break

		var pool_idx: int = slots_to_reassign.pop_front()
		_assign_entry_to_slot(data_idx, pool_idx)


func _assign_entry_to_slot(data_idx: int, pool_idx: int) -> void:
	"""Assign an entry to a pool slot and start loading."""
	if pool_idx < 0 or pool_idx >= _image_pool.size():
		return
	if data_idx < 0 or data_idx >= _entries.size():
		return

	var img: DexRecordImage = _image_pool[pool_idx]
	var entry: Dictionary = _entries[data_idx]

	# Clear previous state
	img.clear_texture()

	# Update assignment tracking
	_active_assignments[pool_idx] = data_idx
	_loading_states[pool_idx] = SlotState.LOADING

	# Configure DexRecordImage with entry data
	var owner_id: String = entry.get("owner_id", "self")
	img.set_entry_data(entry, owner_id)
	img.load_image_from_entry()
	img.visible = true

	image_loading.emit(data_idx)


func _position_active_images() -> void:
	"""Position all active images based on current scroll offset and randomization."""
	for pool_idx in _active_assignments:
		var data_idx: int = _active_assignments[pool_idx]
		var img: DexRecordImage = _image_pool[pool_idx]

		if data_idx >= _entry_positions.size():
			continue

		# Get entry's Y position (in actual pixels)
		var entry_y: float = _entry_positions[data_idx]

		# Convert to screen space: entry position minus scroll offset
		var screen_y := entry_y - _scroll_offset

		# Get dimensions (already in actual pixels from _get_entry_* functions)
		var entry_width := _get_entry_width(data_idx)
		var entry_height := _get_entry_height(data_idx)

		# Get random offset (as ratio of container width)
		var x_offset_ratio := 0.0
		var rotation := 0.0
		if data_idx < _entry_randoms.size():
			x_offset_ratio = _entry_randoms[data_idx].x_offset
			rotation = _entry_randoms[data_idx].rotation

		# Calculate X position (centered with random offset)
		var base_x := (size.x - entry_width) / 2.0
		var x_offset_px := x_offset_ratio * size.x
		var final_x := base_x + x_offset_px

		# Apply position and size
		img.position = Vector2(final_x, screen_y)
		img.custom_minimum_size = Vector2(entry_width, entry_height)
		img.size = Vector2(entry_width, entry_height)

		# DON'T override ratio - let DexRecordImage set it from loaded image
		# The AspectRatioContainer will constrain content to the image's natural ratio

		# Apply rotation (around center)
		img.pivot_offset = Vector2(entry_width / 2.0, entry_height / 2.0)
		img.rotation_degrees = rotation


func _clear_all_assignments() -> void:
	"""Clear all pool assignments and hide images."""
	for pool_idx in range(_image_pool.size()):
		var img: DexRecordImage = _image_pool[pool_idx]
		img.visible = false
		img.clear_texture()
		img.rotation_degrees = 0.0
		_loading_states[pool_idx] = SlotState.EMPTY

	_active_assignments.clear()


# =============================================================================
# Signal Handlers
# =============================================================================

func _on_image_loaded(success: bool, pool_idx: int) -> void:
	"""Handle image load completion from DexRecordImage."""
	if not _active_assignments.has(pool_idx):
		return

	var data_idx: int = _active_assignments[pool_idx]

	if success:
		_loading_states[pool_idx] = SlotState.READY
		image_ready.emit(data_idx)
	else:
		_loading_states[pool_idx] = SlotState.ERROR


func emit_item_pressed_for_index(index: int) -> void:
	"""Called by the main controller when an item is tapped."""
	var entry := get_entry_at_index(index)
	if not entry.is_empty():
		item_pressed.emit(entry)
