class_name TreeNavigationArrowsLayer
extends Node2D

## TreeNavigationArrowsLayer - Manages navigation arrow buttons on tree edges.
##
## Only shows arrows for the node closest to the screen center, allowing
## quick navigation to connected nodes. Arrows are pooled for performance
## and positioned in tree-local (world) space.

const TreeNavigationArrowClass = preload("res://features/tree_visualization/tree_navigation_arrow.gd")

## Emitted when user clicks an arrow to navigate to a node
signal navigate_to_node(node_id: String, world_position: Vector2)

# =============================================================================
# Configuration
# =============================================================================

## Size of arrow buttons in tree-local units
var arrow_size: float = 20.0

## Distance from node center to place arrow (tree-local units)
var arrow_distance_from_node: float = 60.0

## Pool size for arrow instances
const ARROW_POOL_SIZE: int = 200

## Opacity of arrow buttons
var arrow_opacity: float = 1

## Color tint for arrows (modulate)
var arrow_color: Color = Color(0, 0, 0, 1.0)

## Minimum edge length to show arrows (shorter edges get no arrows)
var min_edge_length_for_arrows: float = 120.0

## Extra offset when placing arrows near nodes with dex images (tree-local units)
var dex_image_offset: float = 500.0  # Accounts for ~1000 size dex images

# =============================================================================
# State
# =============================================================================

## Pool of reusable arrow instances
var _arrow_pool: Array = []  # Array of TreeNavigationArrow

## Currently active arrows (keyed by unique edge+direction ID)
var _active_arrows: Dictionary = {}  # {arrow_key: TreeNavigationArrow}

## View state (updated by TreeVisualization)
var _scroll_offset: Vector2 = Vector2.ZERO
var _current_scale: float = 1.0
var _viewport_center: Vector2 = Vector2.ZERO
var _viewport_size: Vector2 = Vector2(1280, 720)
var _tree_scale: float = 1.0

## Reference to tree data for edge/node information
var _tree_data: TreeDataModels.TreeData = null

## Extended positions for nodes with dex images
var _extended_positions: Dictionary = {}

## Diff circle exclusion zone (arrows won't appear inside this area)
var _diff_circle_enabled: bool = false
var _diff_circle_center: Vector2 = Vector2.ZERO
var _diff_circle_radius: float = 0.0

## Visibility dirty flag for throttled updates
var _visibility_dirty: bool = false


func _ready() -> void:
	# Create arrow pool
	_setup_arrow_pool()
	print("[TreeNavigationArrowsLayer] Initialized with pool size %d" % ARROW_POOL_SIZE)


func _setup_arrow_pool() -> void:
	"""Pre-create pool of arrow instances."""
	for i in range(ARROW_POOL_SIZE):
		var arrow = TreeNavigationArrowClass.new()
		arrow.name = "NavArrow_%d" % i
		add_child(arrow)
		_arrow_pool.append(arrow)


func _input(event: InputEvent) -> void:
	"""Handle input events for arrow clicking."""
	if not visible or _active_arrows.is_empty():
		return

	var screen_pos: Vector2 = Vector2.ZERO
	var is_click := false

	# Handle mouse click
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			screen_pos = event.position
			is_click = true

	# Handle touch
	elif event is InputEventScreenTouch:
		if event.pressed:
			screen_pos = event.position
			is_click = true

	if is_click:
		var clicked_arrow = _get_arrow_at_screen_pos(screen_pos)
		if clicked_arrow:
			_trigger_navigation(clicked_arrow)
			get_viewport().set_input_as_handled()


func _get_arrow_at_screen_pos(screen_pos: Vector2):
	"""Find which arrow (if any) was clicked at the given screen position."""
	# Convert screen position to tree-local coordinates
	var local_pos := _screen_to_tree_local(screen_pos)

	# Check active arrows
	for arrow in _active_arrows.values():
		if arrow.contains_point(local_pos):
			return arrow

	return null


func _screen_to_tree_local(screen_pos: Vector2) -> Vector2:
	"""Convert screen position to tree-local coordinates."""
	# screen -> world -> tree-local
	var world_pos = (screen_pos - _viewport_center) / _current_scale + _scroll_offset
	return world_pos / _tree_scale


func _trigger_navigation(arrow) -> void:
	"""Handle arrow click - emit navigation signal."""
	var target_pos: Vector2 = arrow.target_position
	var world_pos: Vector2 = target_pos * _tree_scale
	navigate_to_node.emit(arrow.target_node_id, world_pos)
	print("[TreeNavigationArrowsLayer] Navigate to node %s at world pos %s" % [arrow.target_node_id, world_pos])


func _get_available_arrow():
	"""Get an inactive arrow from the pool. Returns null if none available."""
	for arrow in _arrow_pool:
		if not arrow.is_active():
			return arrow
	return null


func _deactivate_all_arrows() -> void:
	"""Deactivate all arrows (return to pool)."""
	for arrow in _arrow_pool:
		if arrow.is_active():
			arrow.deactivate()
	_active_arrows.clear()


# =============================================================================
# Public API
# =============================================================================

func set_tree_data(data: TreeDataModels.TreeData, extended_pos: Dictionary) -> void:
	"""Set tree data for arrow placement."""
	_tree_data = data
	_extended_positions = extended_pos
	_visibility_dirty = true


func set_tree_scale(new_scale: float) -> void:
	"""Set tree scale factor."""
	if abs(_tree_scale - new_scale) > 0.001:
		_tree_scale = new_scale
		_visibility_dirty = true


func set_diff_circle(enabled: bool, center: Vector2, radius: float) -> void:
	"""Configure diff circle exclusion zone."""
	_diff_circle_enabled = enabled
	_diff_circle_center = center
	_diff_circle_radius = radius
	_visibility_dirty = true


func update_view(scroll: Vector2, zoom: float, center: Vector2) -> void:
	"""Update view parameters (called when transform changes)."""
	if not is_inside_tree():
		return

	_scroll_offset = scroll
	_current_scale = zoom
	_viewport_center = center
	_viewport_size = get_viewport_rect().size
	_visibility_dirty = true


func update_arrows() -> void:
	"""Update arrow positions and visibility based on current view."""
	if not _visibility_dirty or not _tree_data:
		return

	_visibility_dirty = false
	_update_visible_arrows()


func clear() -> void:
	"""Clear all arrows."""
	_deactivate_all_arrows()
	_tree_data = null
	_extended_positions.clear()


# =============================================================================
# Arrow Placement Logic
# =============================================================================

func _find_closest_node_to_center() -> TreeDataModels.TaxonomicNode:
	"""Find the node closest to the current viewport center."""
	if not _tree_data or _tree_data.nodes.is_empty():
		return null

	# Viewport center in tree-local coordinates
	var center_tree_local := _scroll_offset / _tree_scale

	var closest_node: TreeDataModels.TaxonomicNode = null
	var closest_dist: float = INF

	for node in _tree_data.nodes:
		# Get effective position (extended if has dex image)
		var node_pos: Vector2 = node.position
		if _extended_positions.has(node.id):
			node_pos = _extended_positions[node.id]

		var dist := node_pos.distance_to(center_tree_local)
		if dist < closest_dist:
			closest_dist = dist
			closest_node = node

	return closest_node


func _get_edges_for_node(node_id: String) -> Array:
	"""Get all edges connected to a specific node."""
	var edges: Array = []
	for edge in _tree_data.edges:
		if edge.source == node_id or edge.target == node_id:
			edges.append(edge)
	return edges


func _update_visible_arrows() -> void:
	"""Update which arrows are visible based on current view."""
	if not _tree_data:
		return

	# Find the node closest to screen center
	var center_node: TreeDataModels.TaxonomicNode = _find_closest_node_to_center()
	if not center_node:
		_deactivate_all_arrows()
		return

	var view_rect := _get_view_rect()

	# Track which arrows should be active this frame
	var needed_arrows: Dictionary = {}  # {arrow_key: arrow_data}

	# Only process edges connected to the centered node
	var edges := _get_edges_for_node(center_node.id)

	for edge in edges:
		var source_node := _tree_data.get_node_by_id(edge.source)
		var target_node := _tree_data.get_node_by_id(edge.target)

		if not source_node or not target_node:
			continue

		# Get actual positions (use extended position for nodes with dex images)
		var source_pos: Vector2 = source_node.position
		var target_pos: Vector2 = target_node.position

		if _extended_positions.has(target_node.id):
			target_pos = _extended_positions[target_node.id]
		if _extended_positions.has(source_node.id):
			source_pos = _extended_positions[source_node.id]

		# Calculate edge properties
		var edge_vec := target_pos - source_pos
		var edge_length := edge_vec.length()

		# Skip very short edges
		if edge_length < min_edge_length_for_arrows:
			continue

		var direction := edge_vec.normalized()

		# Check if either endpoint has a dex image (requires extra offset)
		var source_has_image := _extended_positions.has(source_node.id)
		var target_has_image := _extended_positions.has(target_node.id)

		# Check if either endpoint is at the diff circle center (root node)
		var source_at_diff_center := _diff_circle_enabled and source_pos.distance_to(_diff_circle_center) < 1.0
		var target_at_diff_center := _diff_circle_enabled and target_pos.distance_to(_diff_circle_center) < 1.0

		# Calculate arrow positions along the edge
		# Base distance from node, plus extra offset if node has dex image
		var base_dist := arrow_distance_from_node
		var max_arrow_dist := edge_length * 0.4  # Don't go past 40% of edge length

		# Arrow near source, pointing toward target (only if source is the centered node)
		if source_node.id == center_node.id:
			var source_offset := base_dist
			if source_has_image:
				source_offset += dex_image_offset
			# If source is at diff circle center, place arrow just outside diff circle
			if source_at_diff_center:
				source_offset = maxf(source_offset, _diff_circle_radius + 20.0)
			source_offset = minf(source_offset, max_arrow_dist)

			var arrow_pos_to_target := source_pos + direction * source_offset
			if _is_position_valid(arrow_pos_to_target, view_rect):
				var arrow_key := "%s_to_%s" % [edge.source, edge.target]
				needed_arrows[arrow_key] = {
					"position": arrow_pos_to_target,
					"target_pos": target_pos,
					"target_id": edge.target,
					"direction": direction
				}

		# Arrow near target, pointing toward source (only if target is the centered node)
		if target_node.id == center_node.id:
			var target_offset := base_dist
			if target_has_image:
				target_offset += dex_image_offset
			# If target is at diff circle center, place arrow just outside diff circle
			if target_at_diff_center:
				target_offset = maxf(target_offset, _diff_circle_radius + 20.0)
			target_offset = minf(target_offset, max_arrow_dist)

			var arrow_pos_to_source := target_pos - direction * target_offset
			if _is_position_valid(arrow_pos_to_source, view_rect):
				var arrow_key := "%s_to_%s" % [edge.target, edge.source]
				needed_arrows[arrow_key] = {
					"position": arrow_pos_to_source,
					"target_pos": source_pos,
					"target_id": edge.source,
					"direction": -direction
				}

	# Deactivate arrows that are no longer needed
	var to_deactivate: Array[String] = []
	for key in _active_arrows:
		if not needed_arrows.has(key):
			to_deactivate.append(key)

	for key in to_deactivate:
		var arrow = _active_arrows[key]
		arrow.deactivate()
		_active_arrows.erase(key)

	# Activate/update needed arrows
	for key in needed_arrows:
		var data: Dictionary = needed_arrows[key]

		if _active_arrows.has(key):
			# Update existing arrow
			var arrow = _active_arrows[key]
			arrow.activate(
				data.position,
				data.target_pos,
				data.target_id,
				data.direction,
				arrow_size
			)
		else:
			# Activate new arrow from pool
			var arrow = _get_available_arrow()
			if not arrow:
				continue  # Pool exhausted

			arrow.activate(
				data.position,
				data.target_pos,
				data.target_id,
				data.direction,
				arrow_size
			)
			arrow.modulate = arrow_color
			arrow.modulate.a = arrow_opacity
			_active_arrows[key] = arrow


func _is_position_valid(pos: Vector2, view_rect: Rect2) -> bool:
	"""Check if a position is valid for arrow placement."""
	# Must be in view
	if not view_rect.has_point(pos):
		return false

	return true


func _get_view_rect() -> Rect2:
	"""Get current view rectangle in tree-local coordinates."""
	var combined_scale := _current_scale * _tree_scale
	var margin := 100.0 / combined_scale  # Screen pixel margin
	var half_size := (_viewport_size / 2.0) / combined_scale + Vector2(margin, margin)
	var center := _scroll_offset / _tree_scale

	return Rect2(center - half_size, half_size * 2)
