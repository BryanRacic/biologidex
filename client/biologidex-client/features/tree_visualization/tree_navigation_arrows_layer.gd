class_name TreeNavigationArrowsLayer
extends Node2D

## TreeNavigationArrowsLayer - Manages navigation arrow buttons on tree edges.
##
## Only shows arrows for the node closest to the screen center, allowing
## quick navigation to connected nodes. Arrows are pooled for performance.
##
## COORDINATE SPACES (per CLAUDE.md conventions):
## - All arrow positions are in TREE-LOCAL space (same as node.position)
## - View state uses shared TreeViewState for coordinate conversions
## - Diff circle center/radius are in TREE-LOCAL space

const TreeNavigationArrowClass = preload("res://features/tree_visualization/tree_navigation_arrow.gd")

## Emitted when user clicks an arrow to navigate to a node
## node_id: The target node's ID
## world_position: Target position in WORLD space (for camera navigation)
signal navigate_to_node(node_id: String, world_position: Vector2)

# =============================================================================
# Configuration
# =============================================================================

## Arrow configuration object (shared with TreeVisualization)
var config: TreeArrowConfig = null:
	set(value):
		if config and config.config_changed.is_connected(_on_config_changed):
			config.config_changed.disconnect(_on_config_changed)
		config = value
		if config:
			config.config_changed.connect(_on_config_changed)
			_visibility_dirty = true

## Shared view state (updated by TreeVisualization)
var view_state: TreeViewState = null:
	set(value):
		if view_state and view_state.view_changed.is_connected(_on_view_changed):
			view_state.view_changed.disconnect(_on_view_changed)
		view_state = value
		if view_state:
			view_state.view_changed.connect(_on_view_changed)
			_visibility_dirty = true

# =============================================================================
# Object Pool (optimized with free list)
# =============================================================================

## Pool of reusable arrow instances
var _arrow_pool: Array = []

## Free list for O(1) arrow allocation (indices into _arrow_pool)
var _free_arrows: Array[int] = []

## Currently active arrows (keyed by unique edge+direction ID)
## Values are indices into _arrow_pool
var _active_arrows: Dictionary = {}  # {arrow_key: int}

## Pool exhaustion warning flag (prevent log spam)
var _pool_exhausted_warned: bool = false

# =============================================================================
# State
# =============================================================================

## Reference to tree data for edge/node information
var _tree_data: TreeDataModels.TreeData = null

## Extended positions for nodes with dex images (TREE-LOCAL space)
var _extended_positions: Dictionary = {}

## Diff circle exclusion zone (TREE-LOCAL space)
var _diff_circle_enabled: bool = false
var _diff_circle_center: Vector2 = Vector2.ZERO  ## TREE-LOCAL coordinates
var _diff_circle_radius: float = 0.0  ## TREE-LOCAL units

## Visibility dirty flag for throttled updates
var _visibility_dirty: bool = false

## Minimum time between updates (matches renderer throttling)
const MIN_UPDATE_INTERVAL: float = 0.016  # ~60 FPS cap
var _last_update_time: float = 0.0

# =============================================================================
# Initialization
# =============================================================================

func _ready() -> void:
	# Create default config if none provided
	if not config:
		config = TreeArrowConfig.create_default()

	# Create default view state if none provided
	if not view_state:
		view_state = TreeViewState.new()

	_setup_arrow_pool()
	print("[TreeNavigationArrowsLayer] Initialized with pool size %d" % config.pool_size)


func _setup_arrow_pool() -> void:
	"""Pre-create pool of arrow instances with free list for O(1) allocation."""
	var pool_size: int = config.pool_size if config else 50

	for i in range(pool_size):
		var arrow = TreeNavigationArrowClass.new()
		arrow.name = "NavArrow_%d" % i
		add_child(arrow)
		_arrow_pool.append(arrow)
		_free_arrows.append(i)  # All arrows start in free list


# =============================================================================
# Input Handling
# =============================================================================

func _input(event: InputEvent) -> void:
	"""Handle input events for arrow clicking."""
	# Guard: Check all required state is valid
	if not _is_ready_for_input():
		return

	var screen_pos: Vector2 = Vector2.ZERO  ## SCREEN space
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


func _is_ready_for_input() -> bool:
	"""Check if layer is ready to process input events."""
	if not visible:
		return false
	if _active_arrows.is_empty():
		return false
	if not _tree_data:
		return false
	if not is_inside_tree():
		return false
	if not view_state:
		return false
	if view_state.current_scale <= 0.0:
		return false
	return true


func _get_arrow_at_screen_pos(screen_pos: Vector2):
	"""Find which arrow (if any) was clicked at the given screen position.
	screen_pos: Position in SCREEN space (pixels)
	Returns: TreeNavigationArrow or null"""
	if not view_state:
		return null

	# Convert screen position to tree-local coordinates
	var local_pos: Vector2 = view_state.screen_to_tree_local(screen_pos)

	# Check active arrows
	for arrow_index in _active_arrows.values():
		var arrow = _arrow_pool[arrow_index]
		if arrow.contains_point(local_pos):
			return arrow

	return null


func _trigger_navigation(arrow) -> void:
	"""Handle arrow click - emit navigation signal.
	Converts tree-local position to world space for camera navigation."""
	var target_pos_tree_local: Vector2 = arrow.target_position
	var world_pos: Vector2 = view_state.tree_local_to_world(target_pos_tree_local)
	navigate_to_node.emit(arrow.target_node_id, world_pos)
	print("[TreeNavigationArrowsLayer] Navigate to node %s at world pos %s" % [arrow.target_node_id, world_pos])


# =============================================================================
# Object Pool Management (O(1) allocation with free list)
# =============================================================================

func _get_available_arrow() -> int:
	"""Get an inactive arrow index from the pool using free list.
	Returns: Index into _arrow_pool, or -1 if pool exhausted."""
	if _free_arrows.is_empty():
		if not _pool_exhausted_warned:
			push_warning("[TreeNavigationArrowsLayer] Arrow pool exhausted! Consider increasing pool_size.")
			_pool_exhausted_warned = true
		return -1

	_pool_exhausted_warned = false
	return _free_arrows.pop_back()


func _release_arrow(arrow_index: int) -> void:
	"""Return an arrow to the free list."""
	if arrow_index >= 0 and arrow_index < _arrow_pool.size():
		var arrow = _arrow_pool[arrow_index]
		arrow.deactivate()
		_free_arrows.append(arrow_index)


func _deactivate_all_arrows() -> void:
	"""Deactivate all arrows (return to pool)."""
	for arrow_key in _active_arrows:
		var arrow_index: int = _active_arrows[arrow_key]
		if arrow_index >= 0 and arrow_index < _arrow_pool.size():
			_arrow_pool[arrow_index].deactivate()
			_free_arrows.append(arrow_index)

	_active_arrows.clear()
	_pool_exhausted_warned = false


# =============================================================================
# Public API
# =============================================================================

func set_tree_data(data: TreeDataModels.TreeData, extended_pos: Dictionary) -> void:
	"""Set tree data for arrow placement.
	data: Tree data with nodes and edges
	extended_pos: Dictionary of {node_id: Vector2} extended positions (TREE-LOCAL)"""
	_tree_data = data
	_extended_positions = extended_pos
	_visibility_dirty = true


func set_diff_circle(enabled: bool, center: Vector2, radius: float) -> void:
	"""Configure diff circle exclusion zone.
	center: Circle center in TREE-LOCAL coordinates
	radius: Circle radius in TREE-LOCAL units"""
	_diff_circle_enabled = enabled
	_diff_circle_center = center
	_diff_circle_radius = radius
	_visibility_dirty = true


func update_arrows() -> void:
	"""Update arrow positions and visibility based on current view.
	Uses dirty flag and throttling for performance."""
	if not _visibility_dirty or not _tree_data:
		return

	# Throttle updates
	var current_time := Time.get_ticks_msec() / 1000.0
	if current_time - _last_update_time < MIN_UPDATE_INTERVAL:
		return

	_visibility_dirty = false
	_last_update_time = current_time
	_update_visible_arrows()


func clear() -> void:
	"""Clear all arrows."""
	_deactivate_all_arrows()
	_tree_data = null
	_extended_positions.clear()


# =============================================================================
# Event Handlers
# =============================================================================

func _on_config_changed() -> void:
	"""Handle arrow config changes."""
	_visibility_dirty = true


func _on_view_changed() -> void:
	"""Handle view state changes."""
	_visibility_dirty = true


# =============================================================================
# Update Loop
# =============================================================================

func _process(_delta: float) -> void:
	"""Process deferred visibility updates."""
	if _visibility_dirty and _tree_data:
		update_arrows()


# =============================================================================
# Arrow Placement Logic
# =============================================================================

func _find_closest_node_to_center() -> TreeDataModels.TaxonomicNode:
	"""Find the node closest to the current viewport center.
	Uses TREE-LOCAL coordinates for distance calculation."""
	if not _tree_data or _tree_data.nodes.is_empty():
		return null

	if not view_state:
		return null

	# Viewport center in tree-local coordinates
	var center_tree_local: Vector2 = view_state.get_viewport_center_tree_local()

	var closest_node: TreeDataModels.TaxonomicNode = null
	var closest_dist: float = INF

	for node in _tree_data.nodes:
		# Get effective position (extended if has dex image)
		var node_pos: Vector2 = node.position  ## TREE-LOCAL
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
	"""Update which arrows are visible based on current view.
	Handles diff circle offset correctly to prevent arrows inside the circle."""
	if not _tree_data or not view_state:
		return

	# Find the node closest to screen center
	var center_node: TreeDataModels.TaxonomicNode = _find_closest_node_to_center()
	if not center_node:
		_deactivate_all_arrows()
		return

	var view_rect: Rect2 = view_state.get_view_rect(100.0)  # 100px margin

	# Get arrow config values (with safe defaults)
	var arrow_size: float = config.size if config else 30.0
	var base_dist: float = config.distance_from_node if config else 60.0
	var dex_image_offset: float = config.dex_image_offset if config else 500.0
	var min_edge_length: float = config.min_edge_length if config else 120.0
	var max_edge_fraction: float = config.max_edge_fraction if config else 0.4
	var diff_circle_padding: float = config.diff_circle_padding if config else 30.0

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
		# All positions are in TREE-LOCAL space
		var source_pos: Vector2 = source_node.position
		var target_pos: Vector2 = target_node.position

		if _extended_positions.has(target_node.id):
			target_pos = _extended_positions[target_node.id]
		if _extended_positions.has(source_node.id):
			source_pos = _extended_positions[source_node.id]

		# Calculate edge properties
		var edge_vec: Vector2 = target_pos - source_pos
		var edge_length: float = edge_vec.length()

		# Skip very short edges
		if edge_length < min_edge_length:
			continue

		var direction: Vector2 = edge_vec.normalized()
		var max_arrow_dist: float = edge_length * max_edge_fraction

		# Check if either endpoint has a dex image (requires extra offset)
		var source_has_image: bool = _extended_positions.has(source_node.id)
		var target_has_image: bool = _extended_positions.has(target_node.id)

		# Check if either endpoint is at the diff circle center (root node)
		var source_at_diff_center: bool = _diff_circle_enabled and source_pos.distance_to(_diff_circle_center) < 1.0
		var target_at_diff_center: bool = _diff_circle_enabled and target_pos.distance_to(_diff_circle_center) < 1.0

		# Arrow near source, pointing toward target (only if source is the centered node)
		if source_node.id == center_node.id:
			var arrow_data = _calculate_arrow_placement(
				source_pos, target_pos, direction, edge_length,
				source_has_image, source_at_diff_center,
				base_dist, dex_image_offset, max_arrow_dist,
				arrow_size, diff_circle_padding,
				view_rect
			)

			if arrow_data:
				var arrow_key := "%s_to_%s" % [edge.source, edge.target]
				arrow_data["target_pos"] = target_pos
				arrow_data["target_id"] = edge.target
				arrow_data["direction"] = direction
				needed_arrows[arrow_key] = arrow_data

		# Arrow near target, pointing toward source (only if target is the centered node)
		if target_node.id == center_node.id:
			var arrow_data = _calculate_arrow_placement(
				target_pos, source_pos, -direction, edge_length,
				target_has_image, target_at_diff_center,
				base_dist, dex_image_offset, max_arrow_dist,
				arrow_size, diff_circle_padding,
				view_rect
			)

			if arrow_data:
				var arrow_key := "%s_to_%s" % [edge.target, edge.source]
				arrow_data["target_pos"] = source_pos
				arrow_data["target_id"] = edge.source
				arrow_data["direction"] = -direction
				needed_arrows[arrow_key] = arrow_data

	# Deactivate arrows that are no longer needed
	var to_deactivate: Array[String] = []
	for key in _active_arrows:
		if not needed_arrows.has(key):
			to_deactivate.append(key)

	for key in to_deactivate:
		var arrow_index: int = _active_arrows[key]
		_release_arrow(arrow_index)
		_active_arrows.erase(key)

	# Activate/update needed arrows
	var arrow_opacity: float = config.opacity if config else 0.75
	var arrow_color: Color = config.color if config else Color(0, 0, 0, 1.0)

	for key in needed_arrows:
		var data: Dictionary = needed_arrows[key]

		if _active_arrows.has(key):
			# Update existing arrow
			var arrow_index: int = _active_arrows[key]
			var arrow = _arrow_pool[arrow_index]
			arrow.activate(
				data.position,
				data.target_pos,
				data.target_id,
				data.direction,
				arrow_size
			)
		else:
			# Activate new arrow from pool
			var arrow_index: int = _get_available_arrow()
			if arrow_index < 0:
				continue  # Pool exhausted

			var arrow = _arrow_pool[arrow_index]
			arrow.activate(
				data.position,
				data.target_pos,
				data.target_id,
				data.direction,
				arrow_size
			)
			arrow.modulate = arrow_color
			arrow.modulate.a = arrow_opacity
			_active_arrows[key] = arrow_index


func _calculate_arrow_placement(
	from_pos: Vector2,
	_to_pos: Vector2,
	direction: Vector2,
	edge_length: float,
	has_dex_image: bool,
	at_diff_center: bool,
	base_dist: float,
	dex_offset: float,
	max_dist: float,
	arrow_size: float,
	diff_padding: float,
	view_rect: Rect2
) -> Dictionary:
	"""Calculate arrow placement, handling diff circle offset correctly.

	FIX for Issue 4 & 9: If the node is at the diff circle center, we MUST
	place the arrow outside the circle. We use a more permissive edge fraction
	(80%) for diff circle nodes to ensure arrows are visible on shorter edges.

	Returns: Dictionary with 'position' key, or empty dict if arrow should be skipped."""

	# Start with base offset
	var offset: float = base_dist

	# Add dex image offset if node has image
	if has_dex_image:
		offset += dex_offset

	# Handle diff circle: calculate minimum required offset
	if at_diff_center:
		# Arrow must be placed outside diff circle with proper clearance
		# Include half the arrow size to ensure the entire arrow is visible
		var min_offset_from_circle: float = _diff_circle_radius + (arrow_size / 2.0) + diff_padding

		# Use a more permissive limit for diff circle edges (80% instead of 40%)
		# This ensures arrows are visible even on shorter edges from the root
		var diff_circle_max_dist: float = edge_length * 0.8

		# Check if we can place the arrow outside the circle
		if min_offset_from_circle > diff_circle_max_dist:
			# Edge is too short to place arrow outside diff circle
			# Skip this arrow entirely rather than placing it inside
			return {}

		offset = maxf(offset, min_offset_from_circle)
		# Cap at the permissive limit for diff circle edges
		offset = minf(offset, diff_circle_max_dist)
	else:
		# Apply normal max distance cap for non-diff-circle nodes
		offset = minf(offset, max_dist)

	# Calculate final arrow position (TREE-LOCAL space)
	var arrow_pos: Vector2 = from_pos + direction * offset

	# Validate position is within view
	if not view_rect.has_point(arrow_pos):
		return {}

	return {"position": arrow_pos}
