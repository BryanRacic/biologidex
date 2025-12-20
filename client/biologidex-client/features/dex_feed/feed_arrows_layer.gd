class_name FeedArrowsLayer
extends Node2D

## FeedArrowsLayer - Navigation arrows for feed (Node2D-based).
##
## COORDINATE SPACES:
## - Arrows are positioned in FEED-LOCAL space
## - Arrow positions are recalculated each frame to appear at fixed SCREEN positions
## - Uses _input() for click detection (more reliable across coordinate spaces)
##
## NAVIGATION:
## - Tracks explicit _current_index for predictable prev/next navigation
## - Up/Down arrows always navigate by exactly one entry

const FeedArrowClass = preload("res://features/dex_feed/feed_arrow.gd")

signal navigate_to_entry(entry_index: int)

# =============================================================================
# Configuration References
# =============================================================================

var config: FeedConfig = null:
	set(value):
		if config and config.config_changed.is_connected(_on_config_changed):
			config.config_changed.disconnect(_on_config_changed)
		config = value
		if config:
			config.config_changed.connect(_on_config_changed)
			_visibility_dirty = true

var view_state: FeedViewState = null:
	set(value):
		if view_state and view_state.view_changed.is_connected(_on_view_changed):
			view_state.view_changed.disconnect(_on_view_changed)
		view_state = value
		if view_state:
			view_state.view_changed.connect(_on_view_changed)
			_visibility_dirty = true

# =============================================================================
# Arrow Instances
# =============================================================================

var _up_arrow: FeedArrow = null
var _down_arrow: FeedArrow = null

# =============================================================================
# State
# =============================================================================

## Current entry index (for navigation)
var _current_index: int = 0

## Total number of entries in the feed
var _total_entries: int = 0

## Y positions of each entry (top edge) in feed-local space
var _entry_positions: Array[float] = []

## Dirty flag for throttled updates
var _visibility_dirty: bool = false

## Minimum interval between arrow updates (seconds)
const MIN_UPDATE_INTERVAL: float = 0.05

## Last update timestamp
var _last_update_time: float = 0.0

## Last navigation timestamp (debounce double-clicks)
var _last_nav_time: float = 0.0

## Minimum interval between navigations (prevents double-trigger from mouse+touch)
const MIN_NAV_INTERVAL: float = 0.3

# =============================================================================
# Initialization
# =============================================================================

func _ready() -> void:
	# Create default config if not provided
	if not config:
		config = FeedConfig.create_default()
	if not view_state:
		view_state = FeedViewState.new()

	_setup_arrows()


func _setup_arrows() -> void:
	"""Create the up and down arrow instances."""
	_up_arrow = FeedArrowClass.new()
	_up_arrow.name = "UpArrow"
	_up_arrow.direction = FeedArrow.Direction.UP
	add_child(_up_arrow)

	_down_arrow = FeedArrowClass.new()
	_down_arrow.name = "DownArrow"
	_down_arrow.direction = FeedArrow.Direction.DOWN
	add_child(_down_arrow)


# =============================================================================
# Input Handling
# =============================================================================

func _input(event: InputEvent) -> void:
	"""Handle input for arrow clicks/taps."""
	if not visible or not view_state:
		return

	var screen_pos: Vector2 = Vector2.ZERO
	var is_click := false

	# Check for mouse clicks
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			screen_pos = event.position
			is_click = true

	# Check for touch events
	elif event is InputEventScreenTouch:
		if event.pressed:
			screen_pos = event.position
			is_click = true

	if is_click:
		# Convert screen position to feed-local space
		var local_pos: Vector2 = view_state.screen_to_feed_local(screen_pos)

		# Check if up arrow was hit
		if _up_arrow.visible and _up_arrow.contains_point(local_pos):
			_navigate_up()
			get_viewport().set_input_as_handled()
			return

		# Check if down arrow was hit
		if _down_arrow.visible and _down_arrow.contains_point(local_pos):
			_navigate_down()
			get_viewport().set_input_as_handled()
			return


# =============================================================================
# Public API
# =============================================================================

## Set entry layout data (called after layout is computed).
## total: Total number of entries
## positions: Y positions of each entry's top edge in feed-local space
func set_entries_data(total: int, positions: Array[float]) -> void:
	_total_entries = total
	_entry_positions = positions
	_current_index = 0  # Reset to first entry
	_visibility_dirty = true


## Called when visible entries change (for compatibility).
## Does NOT reset _current_index - navigation is purely index-based.
func set_visible_indices(_indices: Array[int]) -> void:
	# Don't modify _current_index here - it's managed by navigation only
	# This prevents the view update from undoing arrow navigation
	_visibility_dirty = true


## Clear all arrow state
func clear() -> void:
	_up_arrow.deactivate()
	_down_arrow.deactivate()
	_current_index = 0
	_total_entries = 0
	_entry_positions.clear()


# =============================================================================
# Arrow Visibility Logic
# =============================================================================

func _process(_delta: float) -> void:
	"""Update arrows if dirty flag is set."""
	if _visibility_dirty:
		_update_arrows()


func _update_arrows() -> void:
	"""Calculate arrow visibility and positions."""
	if not _visibility_dirty:
		return

	# Throttle updates
	var current_time := Time.get_ticks_msec() / 1000.0
	if current_time - _last_update_time < MIN_UPDATE_INTERVAL:
		return

	_visibility_dirty = false
	_last_update_time = current_time

	# Early exit if no data
	if _total_entries == 0 or not view_state or not config:
		_up_arrow.deactivate()
		_down_arrow.deactivate()
		return

	# Calculate arrow size (inversely scaled with zoom so it appears constant on screen)
	var arrow_size: float = config.size / view_state.current_scale

	# Calculate screen positions we want arrows to appear at
	var viewport_size: Vector2 = view_state.viewport_size
	var edge_distance: float = config.arrow_edge_distance

	# Arrows appear at right side, 25% (up) and 75% (down) of viewport height
	var screen_x: float = viewport_size.x - edge_distance - config.size / 2.0
	var up_screen_y: float = viewport_size.y * 0.25
	var down_screen_y: float = viewport_size.y * 0.75

	# Convert to feed-local positions
	var up_local: Vector2 = view_state.screen_to_feed_local(Vector2(screen_x, up_screen_y))
	var down_local: Vector2 = view_state.screen_to_feed_local(Vector2(screen_x, down_screen_y))

	# Get color and opacity from config
	var arrow_color: Color = config.arrow_color
	var arrow_opacity: float = config.arrow_opacity

	# Show up arrow if there are entries before current
	if _current_index > 0:
		_up_arrow.activate(up_local, arrow_size, arrow_color, arrow_opacity)
	else:
		_up_arrow.deactivate()

	# Show down arrow if there are entries after current
	if _current_index < _total_entries - 1:
		_down_arrow.activate(down_local, arrow_size, arrow_color, arrow_opacity)
	else:
		_down_arrow.deactivate()


# =============================================================================
# Navigation
# =============================================================================

func _navigate_up() -> void:
	"""Navigate to the previous entry."""
	# Debounce to prevent double-trigger from mouse+touch events
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_nav_time < MIN_NAV_INTERVAL:
		return
	_last_nav_time = now

	if _current_index > 0:
		_current_index -= 1
		navigate_to_entry.emit(_current_index)
		_visibility_dirty = true


func _navigate_down() -> void:
	"""Navigate to the next entry."""
	# Debounce to prevent double-trigger from mouse+touch events
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_nav_time < MIN_NAV_INTERVAL:
		return
	_last_nav_time = now

	if _current_index < _total_entries - 1:
		_current_index += 1
		navigate_to_entry.emit(_current_index)
		_visibility_dirty = true


# =============================================================================
# Signal Handlers
# =============================================================================

func _on_config_changed() -> void:
	"""Handle config changes."""
	_visibility_dirty = true


func _on_view_changed() -> void:
	"""Handle view state changes."""
	_visibility_dirty = true
