class_name FeedCarouselRenderer
extends Control

## Manages a pool of DexRecordImage instances for efficient carousel rendering.
## Only 3 images are ever loaded at once (previous, current, next).
## Based on TreeRenderer pooling pattern but specialized for 1D vertical navigation.

signal image_ready(index: int)
signal image_loading(index: int)
signal item_pressed(entry: Dictionary)

const POOL_SIZE: int = 3
const DEX_RECORD_IMAGE_SCENE = preload("res://features/ui/components/dex_record_image/dex_record_image.tscn")

# Pool management
var _image_pool: Array[DexRecordImage] = []
var _active_assignments: Dictionary = {}  # {pool_index: data_index}
var _loading_states: Dictionary = {}      # {pool_index: SlotState}

# Data
var _entries: Array[Dictionary] = []
var _scroll_offset: float = 0.0
var _item_height: float = 600.0
var _visible_height: float = 720.0
var _item_margin: float = 20.0  # Vertical margin between items
var _current_index: int = 0

# Slot states
enum SlotState { EMPTY, LOADING, READY, ERROR }


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
		add_child(dex_image)
		_image_pool.append(dex_image)
		_loading_states[i] = SlotState.EMPTY

		# Connect image loaded signal with pool index
		dex_image.image_loaded.connect(_on_image_loaded.bind(i))

	print("[FeedCarouselRenderer] Pool created with %d images" % POOL_SIZE)


# =============================================================================
# Public API
# =============================================================================

func setup(container_height: float, item_height: float, margin: float = 20.0) -> void:
	"""Configure carousel dimensions."""
	_visible_height = container_height
	_item_height = item_height
	_item_margin = margin
	print("[FeedCarouselRenderer] Configured: height=%.0f, item=%.0f, margin=%.0f" % [container_height, item_height, margin])


func set_entries(entries: Array[Dictionary]) -> void:
	"""Set the data entries to display."""
	_entries = entries
	_clear_all_assignments()
	print("[FeedCarouselRenderer] Set %d entries" % entries.size())


func update_scroll(offset: float, current_idx: int) -> void:
	"""Update based on scroll position. Called by touch controller."""
	_scroll_offset = offset
	_current_index = current_idx

	if _entries.is_empty():
		return

	# Calculate which indices should be visible
	var visible_indices: Array[int] = []
	for i in range(maxi(0, current_idx - 1), mini(_entries.size(), current_idx + 2)):
		visible_indices.append(i)

	# Update pool assignments
	_update_pool_assignments(visible_indices)

	# Position all active images
	_position_active_images()


func get_entry_at_index(index: int) -> Dictionary:
	"""Get entry data at specific index."""
	if index >= 0 and index < _entries.size():
		return _entries[index]
	return {}


func get_current_entry() -> Dictionary:
	"""Get the currently centered entry."""
	return get_entry_at_index(_current_index)


func clear() -> void:
	"""Clear all entries and deactivate pool."""
	_entries.clear()
	_clear_all_assignments()


# =============================================================================
# Pool Management
# =============================================================================

func _update_pool_assignments(visible_indices: Array[int]) -> void:
	"""Update which pool slots show which data indices."""
	# Find which pool slots are showing indices we no longer need
	var slots_to_reassign: Array[int] = []
	var indices_needing_slots: Array[int] = visible_indices.duplicate()

	# Check current assignments
	for pool_idx in _active_assignments:
		var current_data_idx: int = _active_assignments[pool_idx]
		if current_data_idx in visible_indices:
			# Still visible - keep assignment, remove from needed list
			indices_needing_slots.erase(current_data_idx)
		else:
			# No longer visible - mark for reassignment
			slots_to_reassign.append(pool_idx)

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
	print("[FeedCarouselRenderer] Assigned entry %d to pool slot %d" % [data_idx, pool_idx])


func _position_active_images() -> void:
	"""Position all active images based on current scroll offset."""
	var center_y := _visible_height / 2.0

	for pool_idx in _active_assignments:
		var data_idx: int = _active_assignments[pool_idx]
		var img: DexRecordImage = _image_pool[pool_idx]

		# Calculate Y position relative to scroll
		# When scroll_offset = data_idx * item_height, item should be centered
		var item_center_offset := float(data_idx) * (_item_height + _item_margin)
		var relative_y := item_center_offset - _scroll_offset

		# Position so item center is at the calculated position
		var target_y := center_y + relative_y - _item_height / 2.0

		# Calculate horizontal centering
		var target_x := (size.x - img.size.x) / 2.0 if size.x > img.size.x else 0.0

		img.position = Vector2(target_x, target_y)
		img.custom_minimum_size = Vector2(size.x * 0.9, _item_height)  # 90% width
		img.size = Vector2(size.x * 0.9, _item_height)

		# Apply anchor positioning
		img.anchors_preset = Control.PRESET_CENTER_TOP
		img.position.x = (size.x - size.x * 0.9) / 2.0  # Center horizontally


func _clear_all_assignments() -> void:
	"""Clear all pool assignments and hide images."""
	for pool_idx in range(_image_pool.size()):
		var img: DexRecordImage = _image_pool[pool_idx]
		img.visible = false
		img.clear_texture()
		_loading_states[pool_idx] = SlotState.EMPTY

	_active_assignments.clear()


func _get_pool_idx_for_data(data_idx: int) -> int:
	"""Find which pool index is assigned to a data index, or -1 if none."""
	for pool_idx in _active_assignments:
		if _active_assignments[pool_idx] == data_idx:
			return pool_idx
	return -1


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
		print("[FeedCarouselRenderer] Image ready for entry %d" % data_idx)
	else:
		_loading_states[pool_idx] = SlotState.ERROR
		print("[FeedCarouselRenderer] Image load failed for entry %d" % data_idx)


# =============================================================================
# Input Handling (for item press detection)
# =============================================================================

func _gui_input(event: InputEvent) -> void:
	# We don't handle input directly - the touch controller does
	# Item pressed events are emitted by the main controller
	pass


func emit_item_pressed_for_index(index: int) -> void:
	"""Called by the main controller when an item is tapped."""
	var entry := get_entry_at_index(index)
	if not entry.is_empty():
		item_pressed.emit(entry)
