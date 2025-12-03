@tool
"""
TreeRenderer - High-performance rendering engine for radial taxonomic tree visualization.
Handles batch rendering of nodes, curved edges, and interactions using MultiMeshInstance2D.
Updated to work with external transform control (no internal camera).
"""
extends Node2D
class_name TreeRenderer

const TreeDataModels = preload("res://features/tree/tree_data_models.gd")

# Theme for labels
var _theme: Theme = preload("res://theme.tres")

# =============================================================================
# Signals
# =============================================================================

signal node_selected(node: TreeDataModels.TaxonomicNode)
signal node_hovered(node: TreeDataModels.TaxonomicNode)
signal node_unhovered()

# =============================================================================
# Configuration
# =============================================================================

# Visual settings - Animal nodes
const NODE_SIZE_BASE: float = 20.0
const NODE_SIZE_USER: float = 32.0
const NODE_SIZE_FRIEND: float = 28.0
const NODE_SIZE_DISCOVERER_BONUS: float = 4.0

# Visual settings - Taxonomy nodes
const TAXONOMY_NODE_SIZE: float = 12.0
const COLOR_TAXONOMY: Color = Color(0, 0, 0, 1)
const COLOR_TAXONOMY_HOVER: Color = Color(0.7, 0.7, 0.7, 0.9)

# Rank-specific size multipliers
const RANK_SIZE_MULTIPLIERS = {
	TreeDataModels.TaxonomicRank.ROOT: 1.5,
	TreeDataModels.TaxonomicRank.KINGDOM: 1.4,
	TreeDataModels.TaxonomicRank.PHYLUM: 1.3,
	TreeDataModels.TaxonomicRank.CLASS: 1.2,
	TreeDataModels.TaxonomicRank.ORDER: 1.1,
	TreeDataModels.TaxonomicRank.FAMILY: 1.0,
	TreeDataModels.TaxonomicRank.SUBFAMILY: 0.95,
	TreeDataModels.TaxonomicRank.GENUS: 0.9,
	TreeDataModels.TaxonomicRank.SPECIES: 0.8
}

# Colors - Animal nodes
const COLOR_USER_CAPTURED: Color = Color(0.13, 0.59, 0.95, 1.0)
const COLOR_FRIEND_CAPTURED: Color = Color(0.30, 0.69, 0.31, 1.0)
const COLOR_BOTH_CAPTURED: Color = Color(0.48, 0.12, 0.64, 1.0)
const COLOR_UNCAPTURED: Color = Color(0, 0, 0, 1)
const COLOR_SELECTED: Color = Color(0, 0, 0, 1)
const COLOR_EDGE: Color = Color(0, 0, 0, 1)

# Performance settings
const MAX_VISIBLE_NODES: int = 50000
const CULL_MARGIN_SCREEN: float = 200.0  # Screen-space pixels outside viewport for culling buffer
const BEZIER_SEGMENTS: int = 8

# =============================================================================
# Rendering containers (injected from controller)
# =============================================================================

var edges_container: Node2D = null
var nodes_container: Node2D = null
var labels_container: Node2D = null

# MultiMesh for batch rendering
var nodes_multimesh: MultiMeshInstance2D = null

# =============================================================================
# State
# =============================================================================

class NodeRenderData:
	var node: TreeDataModels.TaxonomicNode
	var position: Vector2
	var color: Color
	var scale: float
	var is_visible: bool = true
	var instance_index: int = -1

	func _init(n: TreeDataModels.TaxonomicNode) -> void:
		node = n
		position = n.position
		scale = 1.0

var tree_data: TreeDataModels.TreeData = null
var render_nodes: Array[NodeRenderData] = []
var visible_nodes: Array[NodeRenderData] = []
var selected_node: TreeDataModels.TaxonomicNode = null
var hovered_node: TreeDataModels.TaxonomicNode = null

# View state (updated by controller)
var _scroll_offset: Vector2 = Vector2.ZERO
var _current_scale: float = 1.0
var _viewport_center: Vector2 = Vector2.ZERO
var _viewport_size: Vector2 = Vector2(1280, 720)

# Spatial indexing for click detection
var nodes_by_position: Dictionary = {}

# Label management
var taxonomy_labels: Dictionary = {}
const MIN_ZOOM_FOR_LABELS: float = 0.3  # Show labels at most zoom levels
const MAX_LABELS: int = 100  # Maximum labels to render at once
const MIN_LABEL_SPACING_SCREEN: float = 60.0  # Minimum screen pixels between label centers

# =============================================================================
# Initialization
# =============================================================================

func _ready() -> void:
	print("[TreeRenderer] Initializing radial renderer")


func setup_containers(edges: Node2D, nodes: Node2D, labels: Node2D) -> void:
	"""Setup rendering containers from controller."""
	edges_container = edges
	nodes_container = nodes
	labels_container = labels

	# Create MultiMesh in nodes container
	_setup_multimesh()

	print("[TreeRenderer] Containers configured")


func _setup_multimesh() -> void:
	"""Setup MultiMeshInstance2D for batch rendering."""
	if not nodes_container:
		return

	nodes_multimesh = MultiMeshInstance2D.new()
	nodes_container.add_child(nodes_multimesh)

	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = false
	multimesh.mesh = _create_circle_mesh(NODE_SIZE_BASE)

	nodes_multimesh.multimesh = multimesh
	nodes_multimesh.z_index = 1

	print("[TreeRenderer] MultiMesh setup complete")


func _create_circle_mesh(radius: float) -> ArrayMesh:
	"""Create a circle mesh for node rendering."""
	var segments = 16
	var vertices = PackedVector2Array()
	var colors = PackedColorArray()
	var indices = PackedInt32Array()

	vertices.append(Vector2.ZERO)
	colors.append(Color.WHITE)

	for i in range(segments + 1):
		var angle = (float(i) / segments) * TAU
		var x = cos(angle) * radius
		var y = sin(angle) * radius
		vertices.append(Vector2(x, y))
		colors.append(Color.WHITE)

	for i in range(segments):
		indices.append(0)
		indices.append(i + 1)
		indices.append(i + 2)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return array_mesh


# =============================================================================
# Public API
# =============================================================================

func render_tree(data: TreeDataModels.TreeData) -> void:
	"""Render the complete tree data."""
	if not data:
		push_error("[TreeRenderer] No tree data provided")
		return

	print("[TreeRenderer] Rendering tree with %d nodes" % data.nodes.size())
	tree_data = data

	render_nodes.clear()
	visible_nodes.clear()
	nodes_by_position.clear()

	# Build render data for all nodes
	for node in data.nodes:
		var render_data = NodeRenderData.new(node)
		render_data.color = _get_node_color(node)
		render_data.scale = _get_node_scale(node)
		render_nodes.append(render_data)

		# Add to spatial index
		var grid_key = _get_grid_key(node.position)
		if not nodes_by_position.has(grid_key):
			nodes_by_position[grid_key] = []
		nodes_by_position[grid_key].append(render_data)

	print("[TreeRenderer] Built render data for %d nodes" % render_nodes.size())

	_update_visible_nodes()
	_update_multimesh()
	_render_radial_edges()
	_render_taxonomy_labels()

	print("[TreeRenderer] Tree rendering complete")


func update_view(scroll: Vector2, scale: float, center: Vector2) -> void:
	"""Update view parameters (called when transform changes)."""
	var old_scale = _current_scale
	var old_scroll = _scroll_offset
	_scroll_offset = scroll
	_current_scale = scale
	_viewport_center = center
	_viewport_size = get_viewport_rect().size

	if tree_data:
		var view_changed = (scale != old_scale) or (scroll != old_scroll)
		_update_visible_nodes()
		_update_multimesh()
		# Re-render edges when view changes (scroll or scale)
		# Edge visibility depends on view rect intersection, so must update when panning
		if view_changed:
			_render_radial_edges()
		_render_taxonomy_labels()


func clear() -> void:
	"""Clear all rendered content."""
	render_nodes.clear()
	visible_nodes.clear()
	nodes_by_position.clear()
	tree_data = null

	if nodes_multimesh and nodes_multimesh.multimesh:
		nodes_multimesh.multimesh.instance_count = 0

	if edges_container:
		for child in edges_container.get_children():
			child.queue_free()

	for label in taxonomy_labels.values():
		label.queue_free()
	taxonomy_labels.clear()

	print("[TreeRenderer] Cleared all render data")


# =============================================================================
# Frustum Culling
# =============================================================================

func _update_visible_nodes() -> void:
	"""Update which nodes are visible based on current view."""
	visible_nodes.clear()

	# Get view bounds in world space
	var view_rect = _get_view_rect()

	for render_data in render_nodes:
		if view_rect.has_point(render_data.position):
			render_data.is_visible = true
			visible_nodes.append(render_data)
		else:
			render_data.is_visible = false

		if visible_nodes.size() >= MAX_VISIBLE_NODES:
			break


func _get_view_rect() -> Rect2:
	"""Get current view rectangle in world coordinates.
	Culling margin is defined in screen-space and converted to world-space
	so it remains consistent regardless of zoom level.

	Note: scroll_offset represents the world position at viewport center
	(matches transform convention in tree_controller.gd)."""
	var margin_world = CULL_MARGIN_SCREEN / _current_scale
	var half_size = (_viewport_size / 2.0) / _current_scale + Vector2(margin_world, margin_world)
	# scroll_offset IS the world center (not divided by scale)
	var center = _scroll_offset

	return Rect2(center - half_size, half_size * 2)


func _update_multimesh() -> void:
	"""Update MultiMesh with visible nodes."""
	if not nodes_multimesh or not nodes_multimesh.multimesh:
		return

	var multimesh = nodes_multimesh.multimesh
	multimesh.instance_count = visible_nodes.size()

	for i in range(visible_nodes.size()):
		var render_data = visible_nodes[i]
		render_data.instance_index = i

		var transform = Transform2D()
		transform = transform.scaled(Vector2(render_data.scale, render_data.scale))
		transform.origin = render_data.position
		multimesh.set_instance_transform_2d(i, transform)

		var color = render_data.color

		if render_data.node == selected_node:
			color = COLOR_SELECTED
		elif render_data.node == hovered_node:
			if render_data.node.is_taxonomic():
				color = COLOR_TAXONOMY_HOVER
			else:
				color = color.lightened(0.2)

		multimesh.set_instance_color(i, color)


# =============================================================================
# Radial Edge Rendering
# =============================================================================

func _render_radial_edges() -> void:
	"""Render edges as curved lines for radial layout.
	Edges are rendered if they intersect the view rect, not just if both endpoints are visible.
	This prevents edges from disappearing when zoomed in on child nodes."""
	if not edges_container:
		return

	# Clear existing
	for child in edges_container.get_children():
		child.queue_free()

	if not tree_data:
		return

	var view_rect = _get_view_rect()
	var rendered = 0
	var max_edges = 10000

	for edge in tree_data.edges:
		var source_node = tree_data.get_node_by_id(edge.source)
		var target_node = tree_data.get_node_by_id(edge.target)

		if not source_node or not target_node:
			continue

		# Check if edge's bounding box intersects the view rect
		# This catches edges where one or both endpoints are outside but the edge crosses through
		var edge_rect = Rect2(source_node.position, Vector2.ZERO).expand(target_node.position)
		if view_rect.intersects(edge_rect):
			_draw_radial_edge(edge)
			rendered += 1
			if rendered >= max_edges:
				break


func _draw_radial_edge(edge: TreeDataModels.TreeEdge) -> void:
	"""Draw a radial edge (curved for aesthetic)."""
	var source_node = tree_data.get_node_by_id(edge.source)
	var target_node = tree_data.get_node_by_id(edge.target)

	if not source_node or not target_node:
		return

	var line = Line2D.new()

	var source_radius = source_node.position.length()

	if source_radius < 1.0:
		# Source is root (center) - straight line
		line.add_point(source_node.position)
		line.add_point(target_node.position)
	else:
		# Curved edge using quadratic bezier approximation
		var points = _calculate_curved_edge(source_node.position, target_node.position)
		for p in points:
			line.add_point(p)

	line.antialiased = true
	line.width = _get_edge_width(source_node, target_node)
	line.default_color = _get_edge_color(source_node, target_node)

	edges_container.add_child(line)


func _calculate_curved_edge(from: Vector2, to: Vector2) -> Array[Vector2]:
	"""Calculate curved edge points for radial layout."""
	var points: Array[Vector2] = []

	var from_radius = from.length()
	var to_radius = to.length()

	# Control point: at parent's radius, midpoint angle
	var from_angle = from.angle()
	var to_angle = to.angle()

	# Handle angle wrapping
	var angle_diff = to_angle - from_angle
	if angle_diff > PI:
		angle_diff -= TAU
	elif angle_diff < -PI:
		angle_diff += TAU

	var mid_angle = from_angle + angle_diff * 0.5
	var control_radius = from_radius
	var control = Vector2(cos(mid_angle), sin(mid_angle)) * control_radius

	# Quadratic bezier curve
	for i in range(BEZIER_SEGMENTS + 1):
		var t = float(i) / float(BEZIER_SEGMENTS)
		var p = _quadratic_bezier(from, control, to, t)
		points.append(p)

	return points


func _quadratic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	"""Calculate point on quadratic bezier curve."""
	var u = 1.0 - t
	return u * u * p0 + 2.0 * u * t * p1 + t * t * p2


func _get_edge_width(source: TreeDataModels.TaxonomicNode, target: TreeDataModels.TaxonomicNode) -> float:
	"""Get edge width based on node types. Scaled inversely with zoom for consistent screen width."""
	var base_width: float
	if source.is_taxonomic() and target.is_taxonomic():
		base_width = 6.0
	elif source.is_taxonomic() and target.is_animal():
		base_width = 5.0
	else:
		base_width = 4.0
	# Scale inversely so lines maintain consistent screen-space thickness
	# Clamp to minimum width so lines don't disappear at high zoom
	var scaled_width = base_width / _current_scale
	return maxf(scaled_width, 0.5)


func _get_edge_color(source: TreeDataModels.TaxonomicNode, target: TreeDataModels.TaxonomicNode) -> Color:
	"""Get edge color based on node types."""
	if source.is_taxonomic() and target.is_taxonomic():
		return Color(0.15, 0.15, 0.15, 0.85)
	return Color(0.2, 0.2, 0.2, 0.8)


# =============================================================================
# Label Rendering
# =============================================================================

func _render_taxonomy_labels() -> void:
	"""Render labels for taxonomy nodes and dex animal nodes (zoom-dependent).
	Labels are counter-scaled to maintain crisp screen-space rendering.
	Uses priority-based culling and overlap detection to ensure readability."""
	for label in taxonomy_labels.values():
		label.queue_free()
	taxonomy_labels.clear()

	if not labels_container:
		return

	# Only show labels when zoomed in enough
	if _current_scale < MIN_ZOOM_FOR_LABELS:
		return

	# Collect label candidates with their priority
	var candidates: Array = []
	for render_data in visible_nodes:
		var label_text = ""
		var should_show_label = false

		if render_data.node.is_taxonomic():
			# Only show taxonomy labels for higher ranks at lower zoom levels
			if _should_show_taxonomy_label_at_zoom(render_data.node):
				label_text = render_data.node.name
				should_show_label = true
		elif render_data.node.is_animal():
			if render_data.node.captured_by_user or render_data.node.captured_by_friends.size() > 0:
				label_text = render_data.node.common_name if render_data.node.common_name else render_data.node.scientific_name
				should_show_label = true

		if should_show_label and not label_text.is_empty():
			candidates.append({
				"render_data": render_data,
				"label_text": label_text,
				"priority": _get_label_priority(render_data)
			})

	# Sort by priority (higher priority first)
	candidates.sort_custom(func(a, b): return a.priority > b.priority)

	# Place labels with overlap detection
	var placed_positions: Array[Vector2] = []  # Screen-space positions of placed labels
	var labels_created = 0
	var inverse_scale = 1.0 / _current_scale

	for candidate in candidates:
		if labels_created >= MAX_LABELS:
			break

		var render_data = candidate.render_data

		# Calculate screen position of label center
		var node_size = NODE_SIZE_BASE * render_data.scale
		var label_screen_pos = _world_to_screen(render_data.position + Vector2(0, node_size + 10))

		# Check for overlap with already placed labels
		var overlaps = false
		for placed_pos in placed_positions:
			if label_screen_pos.distance_to(placed_pos) < MIN_LABEL_SPACING_SCREEN:
				overlaps = true
				break

		if overlaps:
			continue

		# Create the label
		var label = Label.new()
		label.text = candidate.label_text
		label.theme = _theme
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		# Counter-scale to render at screen resolution (prevents pixelation)
		label.scale = Vector2(inverse_scale, inverse_scale)

		labels_container.add_child(label)

		# Position label below and centered on node
		var label_size = label.get_minimum_size()
		var offset = Vector2(-label_size.x * inverse_scale / 2.0, node_size + 5 * inverse_scale)
		label.position = render_data.position + offset

		taxonomy_labels[render_data.node.id] = label
		placed_positions.append(label_screen_pos)
		labels_created += 1


func _should_show_taxonomy_label_at_zoom(node: TreeDataModels.TaxonomicNode) -> bool:
	"""Determine if a taxonomy node's label should be shown at current zoom level.
	Higher ranks are shown at all zoom levels; lower ranks require more zoom."""
	match node.rank:
		TreeDataModels.TaxonomicRank.ROOT, TreeDataModels.TaxonomicRank.KINGDOM:
			return _current_scale >= 0.1
		TreeDataModels.TaxonomicRank.PHYLUM, TreeDataModels.TaxonomicRank.CLASS:
			return _current_scale >= 0.3
		TreeDataModels.TaxonomicRank.ORDER, TreeDataModels.TaxonomicRank.FAMILY:
			return _current_scale >= 0.5
		TreeDataModels.TaxonomicRank.SUBFAMILY, TreeDataModels.TaxonomicRank.GENUS:
			return _current_scale >= 1.0
		_:
			return _current_scale >= 1.5


func _get_label_priority(render_data: NodeRenderData) -> float:
	"""Calculate priority for a label. Higher values = more important.
	Priority is based on: taxonomic rank (higher = more important), capture status, discoverer status."""
	var priority: float = 0.0

	if render_data.node.is_taxonomic():
		# Taxonomic nodes get base priority from rank (root=100, kingdom=90, etc)
		priority = 100.0 - float(render_data.node.rank) * 10.0
	else:
		# Animal nodes: base priority is lower than most taxonomy
		priority = 20.0

		# Boost for user captures
		if render_data.node.captured_by_user:
			priority += 15.0
		elif render_data.node.captured_by_friends.size() > 0:
			priority += 10.0

		# Boost for discoverer status
		if render_data.node.discoverer.get("is_self", false):
			priority += 10.0
		elif render_data.node.discoverer.get("is_friend", false):
			priority += 5.0

	return priority


func _world_to_screen(world_pos: Vector2) -> Vector2:
	"""Convert world position to screen coordinates.
	Matches transform: screen = (world - scroll_offset) * scale + viewport_center"""
	return (world_pos - _scroll_offset) * _current_scale + _viewport_center


# =============================================================================
# Node Appearance
# =============================================================================

func _get_node_color(node: TreeDataModels.TaxonomicNode) -> Color:
	"""Get color for a node based on type and capture status."""
	if node.is_taxonomic():
		return COLOR_TAXONOMY

	if node.captured_by_user and node.captured_by_friends.size() > 0:
		return COLOR_BOTH_CAPTURED
	elif node.captured_by_user:
		return COLOR_USER_CAPTURED
	elif node.captured_by_friends.size() > 0:
		return COLOR_FRIEND_CAPTURED
	else:
		return COLOR_UNCAPTURED


func _get_node_scale(node: TreeDataModels.TaxonomicNode) -> float:
	"""Get scale for a node based on type, rank, capture status and importance."""
	if node.is_taxonomic():
		var base = TAXONOMY_NODE_SIZE
		var multiplier = RANK_SIZE_MULTIPLIERS.get(node.rank, 1.0)
		return (base * multiplier) / NODE_SIZE_BASE

	var base_size = NODE_SIZE_BASE

	if node.captured_by_user:
		base_size = NODE_SIZE_USER
	elif node.captured_by_friends.size() > 0:
		base_size = NODE_SIZE_FRIEND

	if node.discoverer.get("is_self", false) or node.discoverer.get("is_friend", false):
		base_size += NODE_SIZE_DISCOVERER_BONUS

	return base_size / NODE_SIZE_BASE


# =============================================================================
# Click Detection (World Space)
# =============================================================================

func _input(event: InputEvent) -> void:
	"""Handle input events for node interaction."""
	if Engine.is_editor_hint():
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_click(event.position)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_handle_click(event.position)


func _handle_click(screen_pos: Vector2) -> void:
	"""Handle click/tap for node selection."""
	var world_pos = _screen_to_world(screen_pos)
	var node = get_node_at_position(world_pos)

	if node:
		select_node(node)
	else:
		clear_selection()


func _handle_mouse_motion(screen_pos: Vector2) -> void:
	"""Handle mouse motion for hover effects."""
	var world_pos = _screen_to_world(screen_pos)
	var node = get_node_at_position(world_pos, 10.0)
	set_hovered_node(node)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	"""Convert screen position to world coordinates.
	Inverse of transform: screen = (world - scroll_offset) * scale + viewport_center"""
	return (screen_pos - _viewport_center) / _current_scale + _scroll_offset


func _get_grid_key(pos: Vector2) -> Vector2i:
	"""Get grid key for spatial indexing."""
	var grid_size = 100.0
	return Vector2i(int(pos.x / grid_size), int(pos.y / grid_size))


func get_node_at_position(world_pos: Vector2, radius: float = 20.0) -> TreeDataModels.TaxonomicNode:
	"""Get node at world position (for click detection)."""
	var grid_key = _get_grid_key(world_pos)

	# Search radius scales with zoom
	var search_radius = radius / _current_scale

	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var check_key = Vector2i(grid_key.x + dx, grid_key.y + dy)
			if nodes_by_position.has(check_key):
				for render_data in nodes_by_position[check_key]:
					if not render_data.is_visible:
						continue

					var dist = render_data.position.distance_to(world_pos)
					var node_radius = NODE_SIZE_BASE * render_data.scale

					if dist <= node_radius + search_radius:
						return render_data.node

	return null


func select_node(node: TreeDataModels.TaxonomicNode) -> void:
	"""Select a node."""
	if selected_node == node:
		return

	selected_node = node
	_update_multimesh()

	if node:
		node_selected.emit(node)
		print("[TreeRenderer] Selected node: %s" % (node.scientific_name if node.scientific_name else node.name))


func clear_selection() -> void:
	"""Clear node selection."""
	if not selected_node:
		return

	selected_node = null
	_update_multimesh()


func set_hovered_node(node: TreeDataModels.TaxonomicNode) -> void:
	"""Set hovered node for visual feedback."""
	if hovered_node == node:
		return

	hovered_node = node
	_update_multimesh()

	if node:
		if node.is_animal():
			node_hovered.emit(node)
	else:
		node_unhovered.emit()


# =============================================================================
# Debug
# =============================================================================

func get_stats() -> Dictionary:
	"""Get rendering statistics."""
	return {
		"total_nodes": render_nodes.size(),
		"visible_nodes": visible_nodes.size(),
		"total_edges": tree_data.edges.size() if tree_data else 0,
		"rendered_edges": edges_container.get_child_count() if edges_container else 0
	}
