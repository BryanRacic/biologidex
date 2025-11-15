"""
TreeRenderer - High-performance rendering engine for taxonomic tree visualization.
Handles batch rendering of nodes, edges, and interactions using MultiMeshInstance2D.
"""
extends Node2D
class_name TreeRenderer

const TreeDataModels = preload("res://tree_data_models.gd")

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
const NODE_SIZE_BASE: float = 10.0
const NODE_SIZE_USER: float = 16.0
const NODE_SIZE_FRIEND: float = 14.0
const NODE_SIZE_DISCOVERER_BONUS: float = 2.0

# Visual settings - Taxonomy nodes
const TAXONOMY_NODE_SIZE: float = 6.0
const COLOR_TAXONOMY: Color = Color(0.6, 0.6, 0.6, 0.8)  # Gray with transparency
const COLOR_TAXONOMY_HOVER: Color = Color(0.7, 0.7, 0.7, 0.9)

# Rank-specific size multipliers (hierarchy visual emphasis)
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
const COLOR_USER_CAPTURED: Color = Color(0.13, 0.59, 0.95, 1.0)  # #2196F3
const COLOR_FRIEND_CAPTURED: Color = Color(0.30, 0.69, 0.31, 1.0)  # #4CAF50
const COLOR_BOTH_CAPTURED: Color = Color(0.48, 0.12, 0.64, 1.0)  # #7B1FA2
const COLOR_UNCAPTURED: Color = Color(0.46, 0.46, 0.46, 1.0)  # #757575
const COLOR_SELECTED: Color = Color(1.0, 0.92, 0.23, 1.0)  # Yellow
const COLOR_EDGE: Color = Color(0.26, 0.26, 0.26, 0.3)  # #424242 with alpha

# Performance settings
const MAX_VISIBLE_NODES: int = 50000
const CULL_MARGIN: float = 100.0  # Extra margin for frustum culling

# =============================================================================
# Node References
# =============================================================================

var camera: Camera2D = null
var tree_data: TreeDataModels.TreeData = null

# Rendering nodes
var nodes_multimesh: MultiMeshInstance2D = null
var edges_container: Node2D = null

# =============================================================================
# State
# =============================================================================

# Render data
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

var render_nodes: Array[NodeRenderData] = []
var visible_nodes: Array[NodeRenderData] = []
var selected_node: TreeDataModels.TaxonomicNode = null
var hovered_node: TreeDataModels.TaxonomicNode = null

# Spatial indexing for click detection
var nodes_by_position: Dictionary = {}  # Simplified for now, quadtree later

# =============================================================================
# Initialization
# =============================================================================

func _ready() -> void:
	print("[TreeRenderer] Initializing renderer")

	# Create rendering nodes
	_setup_multimesh()
	_setup_edges_container()

	print("[TreeRenderer] Renderer ready")


func _setup_multimesh() -> void:
	"""Setup MultiMeshInstance2D for batch rendering nodes."""
	nodes_multimesh = MultiMeshInstance2D.new()
	add_child(nodes_multimesh)

	# Create MultiMesh
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = false

	# Create a simple circle mesh for nodes
	var mesh = _create_circle_mesh(NODE_SIZE_BASE)
	multimesh.mesh = mesh

	nodes_multimesh.multimesh = multimesh
	nodes_multimesh.z_index = 1  # Nodes above edges

	print("[TreeRenderer] MultiMesh setup complete")


func _create_circle_mesh(radius: float) -> ArrayMesh:
	"""Create a circle mesh for node rendering."""
	var segments = 16
	var vertices = PackedVector2Array()
	var colors = PackedColorArray()
	var indices = PackedInt32Array()

	# Center vertex
	vertices.append(Vector2.ZERO)
	colors.append(Color.WHITE)

	# Circle vertices
	for i in range(segments + 1):
		var angle = (float(i) / segments) * TAU
		var x = cos(angle) * radius
		var y = sin(angle) * radius
		vertices.append(Vector2(x, y))
		colors.append(Color.WHITE)

	# Triangle fan indices
	for i in range(segments):
		indices.append(0)
		indices.append(i + 1)
		indices.append(i + 2)

	# Create mesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return array_mesh


func _setup_edges_container() -> void:
	"""Setup container for edge rendering."""
	edges_container = Node2D.new()
	edges_container.name = "EdgesContainer"
	add_child(edges_container)
	edges_container.z_index = 0  # Edges below nodes

	print("[TreeRenderer] Edges container setup complete")


# =============================================================================
# Public API
# =============================================================================

func set_camera(cam: Camera2D) -> void:
	"""Set the camera for frustum culling."""
	camera = cam
	print("[TreeRenderer] Camera set")


func render_tree(data: TreeDataModels.TreeData) -> void:
	"""Render the complete tree data."""
	if not data:
		push_error("[TreeRenderer] No tree data provided")
		return

	print("[TreeRenderer] Rendering tree with %d nodes" % data.nodes.size())
	tree_data = data

	# Clear previous render data
	render_nodes.clear()
	visible_nodes.clear()
	nodes_by_position.clear()

	# Build render data for all nodes
	for node in data.nodes:
		var render_data = NodeRenderData.new(node)
		render_data.color = _get_node_color(node)
		render_data.scale = _get_node_scale(node)
		render_nodes.append(render_data)

		# Add to spatial index (simplified - just grid cells)
		var grid_key = _get_grid_key(node.position)
		if not nodes_by_position.has(grid_key):
			nodes_by_position[grid_key] = []
		nodes_by_position[grid_key].append(render_data)

	print("[TreeRenderer] Built render data for %d nodes" % render_nodes.size())

	# Update visible nodes and render
	_update_visible_nodes()
	_update_multimesh()
	_render_edges()

	print("[TreeRenderer] Tree rendering complete")


func update_view() -> void:
	"""Update the view based on camera position (call this when camera moves)."""
	if not tree_data:
		return

	_update_visible_nodes()
	_update_multimesh()


func clear() -> void:
	"""Clear all rendered content."""
	render_nodes.clear()
	visible_nodes.clear()
	nodes_by_position.clear()
	tree_data = null

	if nodes_multimesh and nodes_multimesh.multimesh:
		nodes_multimesh.multimesh.instance_count = 0

	# Clear edges
	for child in edges_container.get_children():
		child.queue_free()

	print("[TreeRenderer] Cleared all render data")


# =============================================================================
# Rendering Implementation
# =============================================================================

func _update_visible_nodes() -> void:
	"""Update which nodes are visible based on camera frustum."""
	visible_nodes.clear()

	if not camera:
		# No camera, show all nodes (up to limit)
		for i in range(mini(render_nodes.size(), MAX_VISIBLE_NODES)):
			visible_nodes.append(render_nodes[i])
		return

	# Get camera frustum in world coordinates
	var viewport_size = get_viewport_rect().size
	var camera_zoom = camera.zoom.x
	var camera_pos = camera.global_position

	# Calculate frustum bounds with margin
	var half_width = (viewport_size.x / (2.0 * camera_zoom)) + CULL_MARGIN
	var half_height = (viewport_size.y / (2.0 * camera_zoom)) + CULL_MARGIN

	var frustum = Rect2(
		camera_pos.x - half_width,
		camera_pos.y - half_height,
		half_width * 2,
		half_height * 2
	)

	# Cull nodes outside frustum
	for render_data in render_nodes:
		if frustum.has_point(render_data.position):
			render_data.is_visible = true
			visible_nodes.append(render_data)
		else:
			render_data.is_visible = false

		# Stop if we hit the limit
		if visible_nodes.size() >= MAX_VISIBLE_NODES:
			break

	# print("[TreeRenderer] Visible nodes: %d / %d" % [visible_nodes.size(), render_nodes.size()])


func _update_multimesh() -> void:
	"""Update MultiMesh with visible nodes."""
	if not nodes_multimesh or not nodes_multimesh.multimesh:
		return

	var multimesh = nodes_multimesh.multimesh
	multimesh.instance_count = visible_nodes.size()

	# Update each instance
	for i in range(visible_nodes.size()):
		var render_data = visible_nodes[i]
		render_data.instance_index = i

		# Set transform (position and scale)
		var transform = Transform2D()
		transform = transform.scaled(Vector2(render_data.scale, render_data.scale))
		transform.origin = render_data.position
		multimesh.set_instance_transform_2d(i, transform)

		# Set color
		var color = render_data.color

		# Apply selection/hover overlay
		if render_data.node == selected_node:
			color = COLOR_SELECTED
		elif render_data.node == hovered_node:
			# Different hover effect for taxonomy vs animal nodes
			if render_data.node.is_taxonomic():
				color = COLOR_TAXONOMY_HOVER
			else:
				color = color.lightened(0.2)

		multimesh.set_instance_color(i, color)


func _render_edges() -> void:
	"""Render edges between nodes."""
	# Clear existing edges
	for child in edges_container.get_children():
		child.queue_free()

	if not tree_data:
		return

	# For now, only render edges for visible nodes (performance optimization)
	var visible_node_ids = {}
	for render_data in visible_nodes:
		visible_node_ids[render_data.node.id] = true

	var edges_rendered = 0
	var max_edges = 10000  # Limit edges for performance

	for edge in tree_data.edges:
		# Only render if both nodes are visible
		if visible_node_ids.has(edge.source) and visible_node_ids.has(edge.target):
			_draw_edge(edge)
			edges_rendered += 1

			if edges_rendered >= max_edges:
				break

	# print("[TreeRenderer] Rendered %d edges" % edges_rendered)


func _draw_edge(edge: TreeDataModels.TreeEdge) -> void:
	"""Draw a single edge with style based on node types."""
	var source_node = tree_data.get_node_by_id(edge.source)
	var target_node = tree_data.get_node_by_id(edge.target)

	if not source_node or not target_node:
		return

	var line = Line2D.new()
	line.add_point(source_node.position)
	line.add_point(target_node.position)
	line.antialiased = false  # Performance

	# Vary edge appearance based on node types
	if source_node.is_taxonomic() and target_node.is_taxonomic():
		# Taxonomy to taxonomy: thicker, more visible (hierarchical structure)
		line.width = 2.0
		line.default_color = Color(0.4, 0.4, 0.4, 0.5)
	elif source_node.is_taxonomic() and target_node.is_animal():
		# Taxonomy to animal: thinner, less opaque (leaf connections)
		line.width = 1.0
		line.default_color = Color(0.3, 0.3, 0.3, 0.3)
	else:
		# Default (shouldn't happen with proper hierarchy, but fallback)
		line.width = 1.0
		line.default_color = COLOR_EDGE

	edges_container.add_child(line)


# =============================================================================
# Node Appearance
# =============================================================================

func _get_node_color(node: TreeDataModels.TaxonomicNode) -> Color:
	"""Get color for a node based on type and capture status."""
	# Taxonomy nodes are gray
	if node.is_taxonomic():
		return COLOR_TAXONOMY

	# Animal nodes: color by capture status
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
	# Taxonomy nodes: size based on rank
	if node.is_taxonomic():
		var base = TAXONOMY_NODE_SIZE
		var multiplier = RANK_SIZE_MULTIPLIERS.get(node.rank, 1.0)
		return (base * multiplier) / NODE_SIZE_BASE

	# Animal nodes: size based on capture status
	var base_size = NODE_SIZE_BASE

	if node.captured_by_user:
		base_size = NODE_SIZE_USER
	elif node.captured_by_friends.size() > 0:
		base_size = NODE_SIZE_FRIEND

	# Bonus for discoverer
	if node.discoverer.get("is_self", false) or node.discoverer.get("is_friend", false):
		base_size += NODE_SIZE_DISCOVERER_BONUS

	# Return scale relative to base size
	return base_size / NODE_SIZE_BASE


# =============================================================================
# Interaction Helpers
# =============================================================================

func _get_grid_key(pos: Vector2) -> Vector2i:
	"""Get grid key for spatial indexing."""
	var grid_size = 100.0  # 100 units per cell
	return Vector2i(int(pos.x / grid_size), int(pos.y / grid_size))


func get_node_at_position(world_pos: Vector2, radius: float = 20.0) -> TreeDataModels.TaxonomicNode:
	"""Get node at world position (for click detection)."""
	var grid_key = _get_grid_key(world_pos)

	# Check the cell and adjacent cells
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var check_key = Vector2i(grid_key.x + dx, grid_key.y + dy)
			if nodes_by_position.has(check_key):
				var nodes_in_cell = nodes_by_position[check_key]
				for render_data in nodes_in_cell:
					if not render_data.is_visible:
						continue

					var distance = render_data.position.distance_to(world_pos)
					var node_radius = NODE_SIZE_BASE * render_data.scale

					if distance <= node_radius + radius:
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
		print("[TreeRenderer] Selected node: %s" % node.scientific_name)


func clear_selection() -> void:
	"""Clear node selection."""
	if not selected_node:
		return

	selected_node = null
	_update_multimesh()
	print("[TreeRenderer] Selection cleared")


func set_hovered_node(node: TreeDataModels.TaxonomicNode) -> void:
	"""Set hovered node for visual feedback."""
	if hovered_node == node:
		return

	hovered_node = node
	_update_multimesh()

	if node:
		# Only emit hover signal for animal nodes
		if node.is_animal():
			node_hovered.emit(node)
		# Taxonomy nodes get visual feedback but no signal
	else:
		node_unhovered.emit()


# =============================================================================
# Input Handling
# =============================================================================

func _input(event: InputEvent) -> void:
	"""Handle input events for node interaction."""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_click(event.position)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event.position)


func _handle_click(screen_pos: Vector2) -> void:
	"""Handle mouse click."""
	if not camera:
		return

	# Convert screen to world coordinates
	var world_pos = camera.get_global_mouse_position()

	# Find node at position
	var node = get_node_at_position(world_pos)

	if node:
		# Only select animal nodes, not taxonomy nodes
		if node.is_animal():
			select_node(node)
		else:
			# Taxonomy node clicked - could show info in future
			print("[TreeRenderer] Clicked taxonomy node: %s (rank: %d)" % [node.name, node.rank])
	else:
		clear_selection()


func _handle_mouse_motion(screen_pos: Vector2) -> void:
	"""Handle mouse motion for hover effects."""
	if not camera:
		return

	# Convert screen to world coordinates
	var world_pos = camera.get_global_mouse_position()

	# Find node at position
	var node = get_node_at_position(world_pos, 10.0)  # Smaller radius for hover

	set_hovered_node(node)


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
