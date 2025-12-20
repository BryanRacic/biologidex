class_name JournalTabs extends Control
## Bullet journal-style tabbed navigation component.
##
## Features notebook divider tabs with rounded tops and customizable styling.
## Tabs are drawn with custom 2D drawing for a handcrafted look.
##
## Usage:
##   var tabs = JournalTabs.new()
##   tabs.add_tab("feed", "Dex Feed")
##   tabs.add_tab("friends", "Friends")
##   tabs.tab_changed.connect(_on_tab_changed)
##   parent.add_child(tabs)

# =============================================================================
# Signals
# =============================================================================

## Emitted when the active tab changes
signal tab_changed(tab_id: String)

# =============================================================================
# Export Variables
# =============================================================================

@export_group("Tab Appearance")
## Height of tabs in pixels
@export var tab_height: float = 70.0:
	set(value):
		tab_height = value
		queue_redraw()
## Minimum width of each tab
@export var tab_min_width: float = 200.0:
	set(value):
		tab_min_width = value
		queue_redraw()
## Corner radius for tab tops
@export var corner_radius: float = 16.0:
	set(value):
		corner_radius = value
		queue_redraw()
## Horizontal gap between tabs
@export var tab_gap: float = 8.0:
	set(value):
		tab_gap = value
		queue_redraw()
## How much the active tab extends above inactive tabs
@export var active_lift: float = 8.0:
	set(value):
		active_lift = value
		queue_redraw()

@export_group("Colors")
## Background color for active tab
@export var active_bg_color: Color = Color(0.98, 0.96, 0.92, 1.0):
	set(value):
		active_bg_color = value
		queue_redraw()
## Background color for inactive tabs
@export var inactive_bg_color: Color = Color(0.9, 0.88, 0.84, 1.0):
	set(value):
		inactive_bg_color = value
		queue_redraw()
## Border color for tabs
@export var border_color: Color = Color(0.3, 0.25, 0.2, 0.8):
	set(value):
		border_color = value
		queue_redraw()
## Border width
@export var border_width: float = 2.0:
	set(value):
		border_width = value
		queue_redraw()
## Text color for active tab
@export var active_text_color: Color = Color(0.15, 0.1, 0.05, 1.0):
	set(value):
		active_text_color = value
		queue_redraw()
## Text color for inactive tabs
@export var inactive_text_color: Color = Color(0.4, 0.35, 0.3, 1.0):
	set(value):
		inactive_text_color = value
		queue_redraw()
## Hover color overlay
@export var hover_color: Color = Color(0.0, 0.0, 0.0, 0.05):
	set(value):
		hover_color = value
		queue_redraw()
## Color of the bottom border line extending across full width
@export var bottom_line_color: Color = Color(0.3, 0.25, 0.2, 0.6):
	set(value):
		bottom_line_color = value
		queue_redraw()

@export_group("Typography")
## Font size for tab labels
@export var font_size: int = 48:
	set(value):
		font_size = value
		queue_redraw()

# =============================================================================
# Internal State
# =============================================================================

## Tab data storage [{id: String, label: String}]
var _tabs: Array[Dictionary] = []
## Currently active tab ID
var _active_tab_id: String = ""
## Currently hovered tab index (-1 if none)
var _hovered_tab_index: int = -1
## Cached tab rectangles for hit detection
var _tab_rects: Array[Rect2] = []

# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, tab_height + active_lift)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_EXIT:
			_hovered_tab_index = -1
			queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_update_hover(motion.position)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(button.position)

# =============================================================================
# Public API
# =============================================================================

## Add a new tab with the given ID and label
func add_tab(tab_id: String, label: String) -> void:
	_tabs.append({"id": tab_id, "label": label})

	# Set first tab as active by default
	if _active_tab_id.is_empty():
		_active_tab_id = tab_id

	custom_minimum_size.x = _calculate_total_width()
	queue_redraw()


## Remove a tab by ID
func remove_tab(tab_id: String) -> void:
	for i in range(_tabs.size()):
		if _tabs[i].id == tab_id:
			_tabs.remove_at(i)
			break

	# If we removed the active tab, switch to first available
	if _active_tab_id == tab_id and _tabs.size() > 0:
		_active_tab_id = _tabs[0].id
		tab_changed.emit(_active_tab_id)

	custom_minimum_size.x = _calculate_total_width()
	queue_redraw()


## Set the active tab by ID
func set_active_tab(tab_id: String) -> void:
	if _active_tab_id == tab_id:
		return

	# Verify tab exists
	var found := false
	for tab in _tabs:
		if tab.id == tab_id:
			found = true
			break

	if found:
		_active_tab_id = tab_id
		tab_changed.emit(_active_tab_id)
		queue_redraw()


## Get the currently active tab ID
func get_active_tab() -> String:
	return _active_tab_id


## Get all tab IDs
func get_tab_ids() -> Array[String]:
	var ids: Array[String] = []
	for tab in _tabs:
		ids.append(tab.id)
	return ids


## Clear all tabs
func clear_tabs() -> void:
	_tabs.clear()
	_active_tab_id = ""
	_tab_rects.clear()
	queue_redraw()

# =============================================================================
# Drawing
# =============================================================================

func _draw() -> void:
	if _tabs.is_empty():
		return

	var total_width := size.x
	var available_width := total_width - (tab_gap * (_tabs.size() - 1))
	var tab_width := maxf(tab_min_width, available_width / _tabs.size())

	# Calculate starting X to center tabs
	var total_tabs_width := (tab_width * _tabs.size()) + (tab_gap * (_tabs.size() - 1))
	var start_x := (total_width - total_tabs_width) / 2.0

	# Rebuild tab rects array with correct size (fixes out-of-order drawing issue)
	_tab_rects.clear()
	for i in range(_tabs.size()):
		_tab_rects.append(Rect2())

	# Draw bottom line first (beneath tabs)
	var bottom_y := size.y - border_width / 2.0
	draw_line(Vector2(0, bottom_y), Vector2(total_width, bottom_y), bottom_line_color, border_width)

	# Draw tabs from left to right (inactive first, active last for proper layering)
	var active_index := -1
	for i in range(_tabs.size()):
		if _tabs[i].id == _active_tab_id:
			active_index = i
			continue
		_draw_tab(i, start_x + i * (tab_width + tab_gap), tab_width, false)

	# Draw active tab last (on top)
	if active_index >= 0:
		_draw_tab(active_index, start_x + active_index * (tab_width + tab_gap), tab_width, true)


func _draw_tab(index: int, x: float, width: float, is_active: bool) -> void:
	var tab_data: Dictionary = _tabs[index]
	var is_hovered := _hovered_tab_index == index

	# Calculate tab position and size
	var lift := active_lift if is_active else 0.0
	var y := active_lift - lift  # Active tabs start higher
	var height := tab_height + lift

	# Store rect for hit detection (array is pre-sized in _draw)
	_tab_rects[index] = Rect2(x, y, width, height)

	# Background color
	var bg_color := active_bg_color if is_active else inactive_bg_color
	if is_hovered and not is_active:
		bg_color = bg_color.blend(hover_color)

	# Draw tab shape (rounded top, square bottom)
	var points := _create_tab_points(x, y, width, height)
	draw_colored_polygon(points, bg_color)

	# Draw border (only top and sides, not bottom for active tab)
	_draw_tab_border(x, y, width, height, is_active)

	# Draw label
	var text_color := active_text_color if is_active else inactive_text_color
	_draw_tab_label(tab_data.label, x, y, width, height, text_color)


func _create_tab_points(x: float, y: float, width: float, height: float) -> PackedVector2Array:
	## Create the polygon points for a tab shape (rounded top corners, square bottom)
	var points := PackedVector2Array()
	var r := minf(corner_radius, minf(width / 2.0, height / 2.0))
	var segments := 8  # Segments for corner arcs

	# Start at bottom-left and go clockwise
	points.append(Vector2(x, y + height))  # Bottom-left
	points.append(Vector2(x, y + r))  # Left side up to corner

	# Top-left rounded corner
	for i in range(segments + 1):
		var angle := PI + (PI / 2.0) * (float(i) / segments)
		points.append(Vector2(x + r + r * cos(angle), y + r + r * sin(angle)))

	# Top edge
	points.append(Vector2(x + width - r, y))

	# Top-right rounded corner
	for i in range(segments + 1):
		var angle := -PI / 2.0 + (PI / 2.0) * (float(i) / segments)
		points.append(Vector2(x + width - r + r * cos(angle), y + r + r * sin(angle)))

	# Right side down to bottom
	points.append(Vector2(x + width, y + height))  # Bottom-right

	return points


func _draw_tab_border(x: float, y: float, width: float, height: float, is_active: bool) -> void:
	## Draw the border lines for a tab
	var r := minf(corner_radius, minf(width / 2.0, height / 2.0))
	var segments := 8

	# Left side (from bottom up)
	if is_active:
		# For active tab, don't draw bottom portion of sides
		pass
	else:
		draw_line(Vector2(x, y + height), Vector2(x, y + r), border_color, border_width)

	draw_line(Vector2(x, y + height - 2), Vector2(x, y + r), border_color, border_width)

	# Top-left corner arc
	var prev_point := Vector2(x, y + r)
	for i in range(1, segments + 1):
		var angle := PI + (PI / 2.0) * (float(i) / segments)
		var point := Vector2(x + r + r * cos(angle), y + r + r * sin(angle))
		draw_line(prev_point, point, border_color, border_width)
		prev_point = point

	# Top edge
	draw_line(Vector2(x + r, y), Vector2(x + width - r, y), border_color, border_width)

	# Top-right corner arc
	prev_point = Vector2(x + width - r, y)
	for i in range(1, segments + 1):
		var angle := -PI / 2.0 + (PI / 2.0) * (float(i) / segments)
		var point := Vector2(x + width - r + r * cos(angle), y + r + r * sin(angle))
		draw_line(prev_point, point, border_color, border_width)
		prev_point = point

	# Right side (from corner down)
	draw_line(Vector2(x + width, y + r), Vector2(x + width, y + height - 2), border_color, border_width)


func _draw_tab_label(label: String, x: float, y: float, width: float, height: float, color: Color) -> void:
	## Draw the tab label centered in the tab
	var font := ThemeDB.fallback_font

	# Get text size
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)

	# Calculate centered position
	var text_x := x + (width - text_size.x) / 2.0
	var text_y := y + (height + text_size.y * 0.7) / 2.0  # Adjust for baseline

	draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

# =============================================================================
# Input Handling
# =============================================================================

func _update_hover(pos: Vector2) -> void:
	var new_hover := -1
	for i in range(_tab_rects.size()):
		if _tab_rects[i].has_point(pos):
			new_hover = i
			break

	if new_hover != _hovered_tab_index:
		_hovered_tab_index = new_hover
		queue_redraw()


func _handle_click(pos: Vector2) -> void:
	for i in range(_tab_rects.size()):
		if _tab_rects[i].has_point(pos):
			var tab_id: String = _tabs[i].id
			if tab_id != _active_tab_id:
				_active_tab_id = tab_id
				tab_changed.emit(_active_tab_id)
				queue_redraw()
			break

# =============================================================================
# Utilities
# =============================================================================

func _calculate_total_width() -> float:
	if _tabs.is_empty():
		return 0.0
	return tab_min_width * _tabs.size() + tab_gap * (_tabs.size() - 1)
