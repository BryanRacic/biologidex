@tool
"""
TreeRenderer - High-performance rendering engine for radial taxonomic tree visualization.
Handles batch rendering of nodes, straight edges, and interactions using MultiMeshInstance2D.
Updated to work with external transform control (no internal camera).
"""
extends Node2D
class_name TreeRenderer

# TreeDataModels and TreeDexImage are globally available via class_name

# Theme for labels
var _theme: Theme = preload("res://theme.tres")

# =============================================================================
# Signals
# =============================================================================

signal node_selected(node: TreeDataModels.TaxonomicNode)
signal node_hovered(node: TreeDataModels.TaxonomicNode)
signal node_unhovered()

# =============================================================================
# Configuration (Configurable - set via TreeVisualization)
# =============================================================================

# Visual settings - Node sizes (world units)
var node_size_base: float = 20.0  # Base size for nodes
var node_size_user: float = 20.0  # Size for user-captured nodes
var node_size_friend: float = 20.0  # Size for friend-captured nodes
var node_size_discoverer_bonus: float = 4.0  # Extra size for discoverer nodes
var taxonomy_node_size: float = 20.0  # Size for taxonomy nodes
var node_opacity: float = 1.0  # Opacity of nodes (0.0 - 1.0)
var hide_root_node: bool = false  # Hide the root node (Kingdom) circle
var hide_root_label: bool = false  # Hide the root node (Kingdom) label

# Visual settings - Edge appearance
var edge_width_base: float = 5.0  # Width of edges in world units
var edge_opacity: float = 0.85  # Opacity of edges (0.0 - 1.0)

# Visual settings - Labels
var label_font_size: int = 90  # Font size in world units
var label_opacity: float = 1.0  # Opacity of labels (0.0 - 1.0)
var min_zoom_for_labels: float = 0.3  # Minimum zoom to show labels

# Visual settings - Dex images
var dex_image_size: float = 1000.0  # Base size in world units
const DEX_IMAGE_POOL_SIZE: int = 100  # Maximum pooled image nodes (keep as const)

# Branch extension settings (reduces image overlap by extending branches beyond taxonomy nodes)
# All extension values are RATIOS of dex_image_size for consistent proportions at any scale
var branch_extension_enabled: bool = true
const BRANCH_EXTENSION_BASE_RATIO: float = 0.4  # Base extension (0.4 = 40% of image size)
const BRANCH_EXTENSION_ALT_RATIO: float = 0.25  # Additional extension for alternating siblings

# Rank-specific size multipliers (keep as const - structural, not visual tuning)
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

# Colors - Taxonomy nodes (keep as const for now, can be made configurable later)
const COLOR_TAXONOMY: Color = Color(0, 0, 0, 1)
const COLOR_TAXONOMY_HOVER: Color = Color(0.7, 0.7, 0.7, 0.9)

# Colors - Animal nodes (keep as const for now)
const COLOR_USER_CAPTURED: Color = Color(0.13, 0.59, 0.95, 1.0)
const COLOR_FRIEND_CAPTURED: Color = Color(0.30, 0.69, 0.31, 1.0)
const COLOR_BOTH_CAPTURED: Color = Color(0.48, 0.12, 0.64, 1.0)
const COLOR_UNCAPTURED: Color = Color(0, 0, 0, 1)
const COLOR_SELECTED: Color = Color(0, 0, 0, 1)
const COLOR_EDGE: Color = Color(0, 0, 0, 1)

# Diff circle settings (clips edges and draws circle around center)
var diff_circle_enabled: bool = false
var diff_circle_radius: float = 330.0  # Radius in tree-local units
var diff_circle_center: Vector2 = Vector2.ZERO  # Center in tree-local coordinates

# Performance settings (keep as const)
const MAX_VISIBLE_NODES: int = 50000
const CULL_MARGIN_SCREEN: float = 200.0  # Screen-space pixels outside viewport for culling buffer

# =============================================================================
# Rendering containers (injected from controller)
# =============================================================================

var edges_container: Node2D = null
var nodes_container: Node2D = null
var labels_container: Node2D = null
var dex_images_container: Node2D = null

# MultiMesh for batch rendering
var nodes_multimesh: MultiMeshInstance2D = null

# Dex image pool
var dex_image_pool: Array[TreeDexImage] = []
var active_dex_images: Dictionary = {}  # {image_key: TreeDexImage} - key is "user_id:creation_index"
var nodes_with_dex_images: Dictionary = {}  # {node_id: true} - tracks which nodes have images
var extended_positions: Dictionary = {}  # {node_id: Vector2} - extended positions for dex images

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
var _tree_scale: float = 1.0  # Parent TreeVisualization scale factor

# Visibility throttling
var _visibility_dirty: bool = false
var _last_view_rect: Rect2 = Rect2()
const VIEW_CHANGE_THRESHOLD: float = 50.0  # World units - minimum change to trigger update
const MIN_UPDATE_INTERVAL: float = 0.001    # 50ms minimum between updates (20 FPS cap on updates)
var _last_update_time: float = 0.0

# Image loading queue (lazy loading)
var _pending_loads: Array[String] = []  # Queue of image_keys waiting to load
var _loading_in_progress: Dictionary = {}  # {image_key: true} - currently loading
const IMAGES_PER_FRAME: int = 1  # Maximum images to start loading per frame
const MAX_CONCURRENT_LOADS: int = 4  # Maximum simultaneous HTTP requests

# Spatial indexing for click detection
var nodes_by_position: Dictionary = {}

# Label management
var taxonomy_labels: Dictionary = {}
const MAX_LABELS: int = 100  # Maximum labels to render at once (keep as const)
const MIN_LABEL_SPACING_SCREEN: float = 60.0  # Minimum screen pixels between label centers
const LABEL_OFFSET_WORLD: float = 1.0  # Offset from node in world units

# Label position alternation (reduces overlap on same branch)
var label_above_nodes: Dictionary = {}  # {node_id: bool} - true = label above, false = label below

# =============================================================================
# Initialization
# =============================================================================

func _ready() -> void:
	print("[TreeRenderer] Initializing radial renderer")


func setup_containers(edges: Node2D, nodes: Node2D, labels: Node2D, dex_images: Node2D = null) -> void:
	"""Setup rendering containers from controller."""
	edges_container = edges
	nodes_container = nodes
	labels_container = labels
	dex_images_container = dex_images

	# Create MultiMesh in nodes container
	_setup_multimesh()

	# Setup dex image pool
	if dex_images_container:
		_setup_dex_image_pool()

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
	# Use unit circle (radius 1.0) - actual size controlled by instance scale
	multimesh.mesh = _create_circle_mesh(1.0)

	nodes_multimesh.multimesh = multimesh
	nodes_multimesh.z_index = 1

	print("[TreeRenderer] MultiMesh setup complete with unit circle mesh")


func _setup_dex_image_pool() -> void:
	"""Pre-create pool of TreeDexImage nodes for efficient reuse."""
	if not dex_images_container:
		return

	for i in range(DEX_IMAGE_POOL_SIZE):
		var dex_image = TreeDexImage.new()
		dex_image.name = "DexImage_%d" % i
		dex_image.visible = false
		dex_images_container.add_child(dex_image)
		dex_image_pool.append(dex_image)

	print("[TreeRenderer] Dex image pool created with %d nodes" % DEX_IMAGE_POOL_SIZE)


func _get_available_dex_image() -> TreeDexImage:
	"""Get an inactive dex image from the pool."""
	for img in dex_image_pool:
		if not img.is_active():
			return img
	return null


func _deactivate_all_dex_images() -> void:
	"""Deactivate all dex images (return to pool)."""
	for img in dex_image_pool:
		if img.is_active():
			img.deactivate()
	active_dex_images.clear()
	nodes_with_dex_images.clear()


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

	# Clear previous state including loading queues
	render_nodes.clear()
	visible_nodes.clear()
	nodes_by_position.clear()
	_deactivate_all_dex_images()
	_pending_loads.clear()
	_loading_in_progress.clear()

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

	# Pre-calculate extended positions for dex images (reduces overlap with alternation)
	_calculate_extended_positions()

	# Pre-calculate label positions (alternating above/below for siblings)
	_calculate_label_positions()

	# Initial visibility update (will queue image loads)
	_last_view_rect = _get_view_rect()
	_update_visible_nodes()
	_update_dex_images()
	_update_multimesh()
	_render_radial_edges()
	_render_taxonomy_labels()

	print("[TreeRenderer] Tree rendering complete, %d images queued" % _pending_loads.size())


func set_tree_scale(new_scale: float) -> void:
	"""Set the parent tree scale factor (TreeVisualization.tree_scale).
	This affects coordinate conversions between tree-local and world space."""
	if abs(_tree_scale - new_scale) > 0.001:
		_tree_scale = new_scale
		_visibility_dirty = true


func update_view(scroll: Vector2, zoom: float, center: Vector2) -> void:
	"""Update view parameters (called when transform changes).
	Uses dirty flag to throttle visibility recalculation."""
	# Guard against being called before node is in scene tree (web export timing issue)
	if not is_inside_tree():
		return

	var old_scale = _current_scale
	_scroll_offset = scroll
	_current_scale = zoom
	_viewport_center = center
	_viewport_size = get_viewport_rect().size

	if not tree_data:
		return

	var new_rect := _get_view_rect()

	# Check if view changed enough to warrant update
	var scale_changed: bool = abs(zoom - old_scale) > 0.01
	var position_changed: bool = _rect_moved_significantly(new_rect, _last_view_rect)

	if scale_changed or position_changed:
		_visibility_dirty = true
		_last_view_rect = new_rect


func _rect_moved_significantly(new_rect: Rect2, old_rect: Rect2) -> bool:
	"""Check if the view rect moved enough to warrant a visibility update."""
	if old_rect.size == Vector2.ZERO:
		return true  # First update

	# Check if center moved more than threshold (in world units)
	var old_center := old_rect.position + old_rect.size / 2.0
	var new_center := new_rect.position + new_rect.size / 2.0

	return old_center.distance_to(new_center) > VIEW_CHANGE_THRESHOLD


func _process(_delta: float) -> void:
	"""Process deferred visibility updates and image loading queue."""
	if Engine.is_editor_hint():
		return

	if not tree_data:
		return

	# Throttle updates by time
	var current_time := Time.get_ticks_msec() / 1000.0
	if _visibility_dirty and (current_time - _last_update_time) >= MIN_UPDATE_INTERVAL:
		_visibility_dirty = false
		_last_update_time = current_time

		_update_visible_nodes()
		_update_dex_images()
		_update_multimesh()
		_render_radial_edges()
		_render_taxonomy_labels()

	# Process loading queue (Phase 3)
	_process_loading_queue()


func clear() -> void:
	"""Clear all rendered content."""
	render_nodes.clear()
	visible_nodes.clear()
	nodes_by_position.clear()
	extended_positions.clear()
	label_above_nodes.clear()
	tree_data = null

	# Clear loading queues and visibility state
	_pending_loads.clear()
	_loading_in_progress.clear()
	_visibility_dirty = false
	_last_view_rect = Rect2()

	if nodes_multimesh and nodes_multimesh.multimesh:
		nodes_multimesh.multimesh.instance_count = 0

	if edges_container:
		for child in edges_container.get_children():
			child.queue_free()

	for label in taxonomy_labels.values():
		label.queue_free()
	taxonomy_labels.clear()

	# Clear dex images
	_deactivate_all_dex_images()

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
		# Skip root node if hide_root_node is enabled
		if hide_root_node and _is_root_node(render_data.node):
			render_data.is_visible = false
			continue

		if view_rect.has_point(render_data.position):
			render_data.is_visible = true
			visible_nodes.append(render_data)
		else:
			render_data.is_visible = false

		if visible_nodes.size() >= MAX_VISIBLE_NODES:
			break


func _is_root_node(node: TreeDataModels.TaxonomicNode) -> bool:
	"""Check if a node is the root node (Kingdom rank at depth 0)."""
	return node.rank == TreeDataModels.TaxonomicRank.KINGDOM or node.rank == TreeDataModels.TaxonomicRank.ROOT


func _get_view_rect() -> Rect2:
	"""Get current view rectangle in TREE-LOCAL coordinates for culling.
	Culling margin is defined in screen-space and converted to tree-local space.

	Note: scroll_offset is in world-space (camera position).
	Positions in render_nodes are in tree-local space (before tree_graph.scale).
	We need to convert world-space view bounds to tree-local space for culling."""
	# Combined scale: camera zoom * tree scale
	var combined_scale = _current_scale * _tree_scale
	var margin_local = CULL_MARGIN_SCREEN / combined_scale
	var half_size = (_viewport_size / 2.0) / combined_scale + Vector2(margin_local, margin_local)
	# Convert scroll_offset from world space to tree-local space
	var center = _scroll_offset / _tree_scale

	return Rect2(center - half_size, half_size * 2)


func _get_dex_image_view_rect() -> Rect2:
	"""Get expanded view rectangle for dex image culling.
	Includes extra margin for:
	- Dex image size (images are large, ~1000 world units)
	- Branch extension (images render away from node center, up to ~650 units)

	This ensures images remain visible when centered on screen even though
	their node position may be outside the standard view rect."""
	# Combined scale: camera zoom * tree scale
	var combined_scale = _current_scale * _tree_scale

	# Standard screen margin converted to tree-local
	var margin_local = CULL_MARGIN_SCREEN / combined_scale

	# Extra margin for dex images: half image size + max branch extension
	var max_extension = dex_image_size * (BRANCH_EXTENSION_BASE_RATIO + BRANCH_EXTENSION_ALT_RATIO)
	var dex_margin = (dex_image_size / 2.0) + max_extension

	var total_margin = margin_local + dex_margin
	var half_size = (_viewport_size / 2.0) / combined_scale + Vector2(total_margin, total_margin)

	# Convert scroll_offset from world space to tree-local space
	var center = _scroll_offset / _tree_scale

	return Rect2(center - half_size, half_size * 2)


# =============================================================================
# Branch Extension (reduces dex image overlap)
# =============================================================================

func _calculate_extended_positions() -> void:
	"""Pre-calculate extended positions for all animal nodes that will show dex images.
	Uses alternating extension lengths based on sibling index to reduce overlap."""
	extended_positions.clear()

	if not branch_extension_enabled or not tree_data:
		return

	# Calculate extension distances based on dex_image_size
	var base_extension: float = dex_image_size * BRANCH_EXTENSION_BASE_RATIO
	var alt_extension: float = dex_image_size * BRANCH_EXTENSION_ALT_RATIO

	# Group animal nodes by their parent for sibling index calculation
	var siblings_by_parent: Dictionary = {}  # {parent_id: [node_ids]}

	for render_data in render_nodes:
		var node = render_data.node
		if not node.is_animal():
			continue
		# Only calculate for nodes that will show dex images
		if not (node.captured_by_user or node.captured_by_friends.size() > 0):
			continue

		var parent = tree_data.get_parent(node.id)
		if parent:
			if not siblings_by_parent.has(parent.id):
				siblings_by_parent[parent.id] = []
			siblings_by_parent[parent.id].append(node.id)

	# Now calculate extended positions with alternation
	for parent_id in siblings_by_parent:
		var sibling_ids: Array = siblings_by_parent[parent_id]
		var parent_node = tree_data.get_node_by_id(parent_id)
		if not parent_node:
			continue

		for i in range(sibling_ids.size()):
			var node_id: String = sibling_ids[i]
			var node = tree_data.get_node_by_id(node_id)
			if not node:
				continue

			# Calculate direction from parent to child (outward from tree center)
			var direction: Vector2
			if parent_node.position.distance_to(node.position) > 0.01:
				direction = (node.position - parent_node.position).normalized()
			else:
				# Fallback: radial direction from origin
				direction = node.position.normalized() if node.position.length() > 0.01 else Vector2.RIGHT

			# Calculate extension with alternation (odd siblings get extra extension)
			var extension_distance: float = base_extension
			if i % 2 == 1:
				extension_distance += alt_extension

			# Store extended position
			extended_positions[node_id] = node.position + direction * extension_distance


func _get_extended_position(node: TreeDataModels.TaxonomicNode) -> Vector2:
	"""Get the extended position for a node, or its original position if not extended."""
	if extended_positions.has(node.id):
		return extended_positions[node.id]
	return node.position


func _calculate_label_positions() -> void:
	"""Pre-calculate which nodes should have labels above vs below.
	Alternates based on parent's label position only (not sibling index),
	so each level of the tree alternates above/below."""
	label_above_nodes.clear()

	if not tree_data:
		return

	# Group all nodes by their parent
	var children_by_parent: Dictionary = {}  # {parent_id: [node_ids]}

	for render_data in render_nodes:
		var node = render_data.node
		var parent = tree_data.get_parent(node.id)
		if parent:
			if not children_by_parent.has(parent.id):
				children_by_parent[parent.id] = []
			children_by_parent[parent.id].append(node.id)

	# Process nodes in breadth-first order so parents are processed before children
	# Root nodes default to label below (false)
	var queue: Array[String] = []

	# Find root nodes (nodes without parents in our data)
	for render_data in render_nodes:
		var node = render_data.node
		var parent = tree_data.get_parent(node.id)
		if not parent:
			label_above_nodes[node.id] = false  # Root nodes: label below
			queue.append(node.id)

	# BFS to propagate label positions down the tree
	while queue.size() > 0:
		var current_id: String = queue.pop_front()
		var parent_above: bool = label_above_nodes.get(current_id, false)

		# Process children of this node - all children get opposite of parent
		if children_by_parent.has(current_id):
			var children: Array = children_by_parent[current_id]
			for child_id in children:
				# All children get the opposite position of their parent
				label_above_nodes[child_id] = not parent_above
				queue.append(child_id)


func _should_label_be_above(node: TreeDataModels.TaxonomicNode) -> bool:
	"""Check if a node's label should be positioned above it."""
	return label_above_nodes.get(node.id, false)


func _update_dex_images() -> void:
	"""Update dex images for visible animal nodes captured by user or friends.
	Queues image loads instead of loading immediately for better performance.

	Note: Uses extended positions for visibility checking, not just node positions,
	since images render at extended positions which can be far from the node center."""
	if not dex_images_container:
		return

	# Get view rect with extra margin for dex images (they're large and may be extended)
	var view_rect = _get_dex_image_view_rect()

	# Collect all visible captures (user and friends)
	# Each capture is keyed by "user_id:creation_index" to allow multiple captures per animal
	var visible_captures: Dictionary = {}  # {image_key: {render_data, user_id, creation_index, capture_info}}

	# Check ALL render nodes (not just visible_nodes) since dex images may be visible
	# even when their node center is outside the standard view rect
	for render_data in render_nodes:
		var node = render_data.node
		if not node.is_animal():
			continue

		# Check if this node has any captures
		var has_user_capture: bool = node.captured_by_user and node.creation_index > 0
		var has_friend_capture: bool = node.captured_by_friends.size() > 0 and not node.captured_by_user

		if not has_user_capture and not has_friend_capture:
			continue

		# Use extended position for visibility check (where image actually renders)
		var image_position: Vector2 = _get_extended_position(node)

		# Check if image position is within the expanded view rect
		if not view_rect.has_point(image_position):
			continue

		# User's own capture
		if has_user_capture:
			var image_key := "self:%d" % node.creation_index
			visible_captures[image_key] = {
				"render_data": render_data,
				"user_id": "self",
				"creation_index": node.creation_index,
				"capture_info": {}
			}

		# Friend captures - only show first friend's capture per animal to avoid overlap
		if has_friend_capture:
			var friend_capture: Dictionary = node.captured_by_friends[0]
			var friend_id: String = friend_capture.get("user_id", "")
			if not friend_id.is_empty():
				# Use node.id (animal UUID) as part of key since we don't have friend's creation_index
				var image_key := "%s:%s" % [friend_id, node.id]
				visible_captures[image_key] = {
					"render_data": render_data,
					"user_id": friend_id,
					"creation_index": -1,  # Will be looked up from synced data
					"capture_info": friend_capture
				}

	# Deactivate images that are no longer visible
	var to_deactivate: Array[String] = []
	for image_key in active_dex_images:
		if not visible_captures.has(image_key):
			to_deactivate.append(image_key)

	for key in to_deactivate:
		var img: TreeDexImage = active_dex_images[key]
		img.deactivate()
		active_dex_images.erase(key)
		# Remove from queues
		_pending_loads.erase(key)
		_loading_in_progress.erase(key)

	# Rebuild nodes_with_dex_images
	nodes_with_dex_images.clear()

	# Track newly visible captures to queue
	var newly_visible: Array[String] = []

	# Activate/update images for visible captures
	for image_key in visible_captures:
		var capture_data: Dictionary = visible_captures[image_key]
		var render_data = capture_data.render_data
		var user_id: String = capture_data.user_id
		var creation_index: int = capture_data.creation_index
		var node = render_data.node

		nodes_with_dex_images[node.id] = true

		# Use extended position if available (reduces overlap with alternating extensions)
		var image_position: Vector2 = _get_extended_position(node)

		if active_dex_images.has(image_key):
			# Already active, just update position
			var img: TreeDexImage = active_dex_images[image_key]
			img.position = image_position
		else:
			# NEW: Activate but don't load - add to queue
			var entry_data = _get_dex_entry_data(creation_index, user_id, node, capture_data.capture_info)

			var img = _get_available_dex_image()
			if not img:
				# Pool exhausted
				continue

			# Activate WITHOUT loading
			img.activate(image_position, creation_index, user_id, entry_data, dex_image_size)
			active_dex_images[image_key] = img

			# Queue for loading (if not already queued or loading)
			if not _pending_loads.has(image_key) and not _loading_in_progress.has(image_key):
				newly_visible.append(image_key)

	# Add newly visible to queue, prioritized by distance to viewport center
	_queue_images_by_priority(newly_visible, visible_captures)


func _get_dex_entry_data(creation_index: int, user_id: String, node: TreeDataModels.TaxonomicNode, capture_info: Dictionary = {}) -> Dictionary:
	"""Get entry data from DexDatabase or FriendDexSyncService, with fallback to tree node data."""
	var entry_data: Dictionary = {}

	if user_id == "self":
		# User's own entry - look up by creation_index
		var dex_db = get_node_or_null("/root/DexDatabase")
		if dex_db and dex_db.has_method("get_record_for_user"):
			entry_data = dex_db.get_record_for_user(creation_index, "self")
	else:
		# Friend's entry - look up by animal_id (since we may not have their creation_index)
		var sync_service = get_node_or_null("/root/FriendDexSyncService")
		if sync_service:
			# Try by animal_id first (node.id is the animal UUID)
			entry_data = sync_service.find_friend_entry_by_animal(user_id, node.id)
			# Fallback to scientific name if not found
			if entry_data.is_empty() and not node.scientific_name.is_empty():
				entry_data = sync_service.find_friend_entry_by_name(user_id, node.scientific_name)

	# Build fallback/supplement data
	var fallback := {
		"creation_index": creation_index if creation_index > 0 else entry_data.get("creation_index", -1),
		"scientific_name": node.scientific_name,
		"common_name": node.common_name,
		"owner_username": capture_info.get("username", ""),
		"catch_date": capture_info.get("captured_at", ""),
		"cached_image_path": "",
		"dex_compatible_url": ""
	}

	# Merge: DB record takes priority, but fill gaps from fallback
	if entry_data.is_empty():
		entry_data = fallback
	else:
		for key in fallback:
			if not entry_data.has(key) or (entry_data[key] is String and entry_data[key].is_empty()):
				entry_data[key] = fallback[key]

	return entry_data


func _queue_images_by_priority(image_keys: Array[String], capture_data: Dictionary) -> void:
	"""Add images to loading queue, prioritized by distance to viewport center."""
	if image_keys.is_empty():
		return

	# Calculate priority scores (lower = higher priority)
	var scored_keys: Array = []
	# Convert scroll_offset to tree-local space for distance comparison with render_data.position
	var viewport_center_local := _scroll_offset / _tree_scale

	for key in image_keys:
		if not capture_data.has(key):
			continue
		var data: Dictionary = capture_data[key]
		var render_data = data.render_data
		var distance: float = render_data.position.distance_to(viewport_center_local)
		scored_keys.append({"key": key, "distance": distance})

	# Sort by distance (closest first)
	scored_keys.sort_custom(func(a, b): return a.distance < b.distance)

	# Add to queue in priority order
	for item in scored_keys:
		_pending_loads.append(item.key)


func _process_loading_queue() -> void:
	"""Process the image loading queue with frame budget."""
	if _pending_loads.is_empty():
		return

	# Don't exceed concurrent load limit
	if _loading_in_progress.size() >= MAX_CONCURRENT_LOADS:
		return

	var loads_this_frame := 0
	var available_slots := MAX_CONCURRENT_LOADS - _loading_in_progress.size()
	var max_loads := mini(IMAGES_PER_FRAME, available_slots)

	while _pending_loads.size() > 0 and loads_this_frame < max_loads:
		var image_key: String = _pending_loads.pop_front()

		# Verify still active
		if not active_dex_images.has(image_key):
			continue

		var img: TreeDexImage = active_dex_images[image_key]

		# Skip if already loading or loaded
		if img.is_loading() or img.is_loaded():
			continue

		# Start load
		_loading_in_progress[image_key] = true
		img.load_state_changed.connect(_on_image_load_state_changed.bind(image_key))
		img.start_load()
		loads_this_frame += 1


func _on_image_load_state_changed(_new_state: int, image_key: String) -> void:
	"""Handle load state changes from TreeDexImage."""
	# Check if still loading by checking the image instance (more reliable than enum comparison)
	var still_loading := false
	if active_dex_images.has(image_key):
		var img: TreeDexImage = active_dex_images[image_key]
		still_loading = img.is_loading()

		# Disconnect signal to avoid memory leaks
		if img.load_state_changed.is_connected(_on_image_load_state_changed):
			img.load_state_changed.disconnect(_on_image_load_state_changed)

	# Remove from in-progress when no longer loading
	if not still_loading:
		_loading_in_progress.erase(image_key)


func _update_multimesh() -> void:
	"""Update MultiMesh with visible nodes.
	Skips animal nodes that have dex images (they're rendered separately)."""
	if not nodes_multimesh or not nodes_multimesh.multimesh:
		return

	var multimesh = nodes_multimesh.multimesh

	# Filter out nodes that have dex images
	var nodes_for_multimesh: Array[NodeRenderData] = []
	for render_data in visible_nodes:
		if not nodes_with_dex_images.has(render_data.node.id):
			nodes_for_multimesh.append(render_data)

	multimesh.instance_count = nodes_for_multimesh.size()

	for i in range(nodes_for_multimesh.size()):
		var render_data = nodes_for_multimesh[i]
		render_data.instance_index = i

		var node_transform := Transform2D()
		node_transform = node_transform.scaled(Vector2(render_data.scale, render_data.scale))
		node_transform.origin = render_data.position
		multimesh.set_instance_transform_2d(i, node_transform)

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

		# Determine target position - use extended position for visibility check too
		var target_position: Vector2 = target_node.position
		if extended_positions.has(target_node.id):
			target_position = extended_positions[target_node.id]

		# Check if edge's bounding box intersects the view rect
		# This catches edges where one or both endpoints are outside but the edge crosses through
		var edge_rect = Rect2(source_node.position, Vector2.ZERO).expand(target_position)
		if view_rect.intersects(edge_rect):
			_draw_radial_edge(edge)
			rendered += 1
			if rendered >= max_edges:
				break

	# Draw diff circle after edges so it appears on top
	_render_diff_circle()


func _draw_radial_edge(edge: TreeDataModels.TreeEdge) -> void:
	"""Draw a straight edge between nodes.
	For animal nodes with dex images, extends the edge to their extended position.
	Clips edges at diff circle boundary if enabled."""
	var source_node = tree_data.get_node_by_id(edge.source)
	var target_node = tree_data.get_node_by_id(edge.target)

	if not source_node or not target_node:
		return

	# Determine target position - use extended position if target has a dex image
	var source_position: Vector2 = source_node.position
	var target_position: Vector2 = target_node.position
	if extended_positions.has(target_node.id):
		target_position = extended_positions[target_node.id]

	# Get line segments to draw (handles diff circle clipping)
	var segments: Array
	if diff_circle_enabled:
		segments = _clip_line_to_circle(source_position, target_position, diff_circle_center, diff_circle_radius)
		if segments.is_empty():
			return  # Edge entirely inside circle, don't draw
	else:
		segments = [[source_position, target_position]]

	# Draw each segment
	var edge_width := _get_edge_width(source_node, target_node)
	var edge_color := _get_edge_color(source_node, target_node)

	for segment in segments:
		var line = Line2D.new()
		line.add_point(segment[0])
		line.add_point(segment[1])
		line.antialiased = true
		line.width = edge_width
		line.default_color = edge_color
		edges_container.add_child(line)


func _get_edge_width(_source: TreeDataModels.TaxonomicNode, _target: TreeDataModels.TaxonomicNode) -> float:
	"""Get edge width based on node types. Fixed world-space width scales naturally with zoom."""
	# Use configurable edge width (same for all edge types for now)
	return edge_width_base


func _get_edge_color(source: TreeDataModels.TaxonomicNode, target: TreeDataModels.TaxonomicNode) -> Color:
	"""Get edge color based on node types. Uses configurable edge_opacity."""
	var base_color: Color
	if source.is_taxonomic() and target.is_taxonomic():
		base_color = Color(0.15, 0.15, 0.15, 1.0)
	else:
		base_color = Color(0.2, 0.2, 0.2, 1.0)

	# Apply configurable opacity
	base_color.a = edge_opacity
	return base_color


# =============================================================================
# Diff Circle Rendering
# =============================================================================

func _render_diff_circle() -> void:
	"""Render the diff circle using edge settings (inherits edge color, width, opacity)."""
	if not diff_circle_enabled or not edges_container:
		return

	# Create a circle using Line2D with many segments
	var circle := Line2D.new()
	circle.name = "DiffCircle"

	const SEGMENTS := 64
	for i in range(SEGMENTS + 1):
		var angle := (float(i) / SEGMENTS) * TAU
		var point := diff_circle_center + Vector2(cos(angle), sin(angle)) * diff_circle_radius
		circle.add_point(point)

	# Use edge settings for consistent appearance
	circle.width = edge_width_base
	circle.default_color = Color(0.15, 0.15, 0.15, edge_opacity)
	circle.antialiased = true
	circle.closed = true

	edges_container.add_child(circle)


func _clip_line_to_circle(start: Vector2, end: Vector2, center: Vector2, radius: float) -> Array:
	"""Clip a line segment at circle boundary.
	Returns array of line segments to draw: [[start1, end1], [start2, end2], ...]
	Returns empty array if line should not be drawn.

	Cases:
	- Both inside: return [] (don't draw)
	- Start inside, end outside: return [[intersection, end]]
	- Start outside, end inside: return [[start, intersection]]
	- Both outside, passes through: return [[start, intersect1], [intersect2, end]]
	- Both outside, misses circle: return [[start, end]]"""

	var start_inside := start.distance_to(center) < radius
	var end_inside := end.distance_to(center) < radius

	# Both inside: don't draw at all
	if start_inside and end_inside:
		return []

	# Find intersection points using parametric line equation
	var d := end - start  # Direction vector
	var f := start - center  # Vector from circle center to line start

	# Quadratic equation: |start + t*d - center|^2 = radius^2
	# t^2(d·d) + 2t(f·d) + (f·f - r^2) = 0
	var a := d.dot(d)
	var b := 2.0 * f.dot(d)
	var c := f.dot(f) - radius * radius

	var discriminant := b * b - 4.0 * a * c

	# No intersection with circle - draw full line if both outside
	if discriminant < 0:
		if not start_inside and not end_inside:
			return [[start, end]]
		return []

	var sqrt_disc := sqrt(discriminant)
	var t1 := (-b - sqrt_disc) / (2.0 * a)
	var t2 := (-b + sqrt_disc) / (2.0 * a)

	# Ensure t1 < t2
	if t1 > t2:
		var temp := t1
		t1 = t2
		t2 = temp

	# Both outside: check if line passes through circle
	if not start_inside and not end_inside:
		# Line passes through if both t values are in [0, 1]
		if t1 >= 0.0 and t1 <= 1.0 and t2 >= 0.0 and t2 <= 1.0:
			# Split into two segments around the circle
			var intersect1 := start + d * t1
			var intersect2 := start + d * t2
			return [[start, intersect1], [intersect2, end]]
		else:
			# Line misses circle entirely
			return [[start, end]]

	# One inside, one outside
	if start_inside:
		# Find exit point (use t2, the farther intersection when starting inside)
		var t := t2 if t2 >= 0.0 and t2 <= 1.0 else t1
		if t >= 0.0 and t <= 1.0:
			var clipped_start := start + d * t
			return [[clipped_start, end]]
		return [[start, end]]  # Fallback
	else:
		# End is inside, find entry point (use t1, the closer intersection)
		var t := t1 if t1 >= 0.0 and t1 <= 1.0 else t2
		if t >= 0.0 and t <= 1.0:
			var clipped_end := start + d * t
			return [[start, clipped_end]]
		return [[start, end]]  # Fallback


# =============================================================================
# Label Rendering
# =============================================================================

func _render_taxonomy_labels() -> void:
	"""Render labels for taxonomy nodes and dex animal nodes (zoom-dependent).
	Labels use fixed world-space sizes and scale naturally with zoom like dex images.
	Uses priority-based culling and overlap detection to ensure readability."""
	for label in taxonomy_labels.values():
		label.queue_free()
	taxonomy_labels.clear()

	if not labels_container:
		return

	# Only show labels when zoomed in enough
	if _current_scale < min_zoom_for_labels:
		return

	# Collect label candidates with their priority
	var candidates: Array = []
	for render_data in visible_nodes:
		var label_text = ""
		var should_show_label = false

		if render_data.node.is_taxonomic():
			# Skip root label if hide_root_label is enabled
			if hide_root_label and _is_root_node(render_data.node):
				continue
			# Only show taxonomy labels for higher ranks at lower zoom levels
			if _should_show_taxonomy_label_at_zoom(render_data.node):
				label_text = render_data.node.name
				should_show_label = true
		elif render_data.node.is_animal():
			# Skip labels for animal nodes that have dex images (the image already shows the name)
			if nodes_with_dex_images.has(render_data.node.id):
				continue

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

	for candidate in candidates:
		if labels_created >= MAX_LABELS:
			break

		var render_data = candidate.render_data

		# Determine if label should be above or below the node (alternates for siblings)
		var label_above: bool = _should_label_be_above(render_data.node)

		# Calculate screen position of label center for overlap detection
		# With unit circle mesh, render_data.scale IS the world-unit radius
		var node_radius: float = render_data.scale
		var label_offset_y: float = node_radius + LABEL_OFFSET_WORLD if not label_above else -(node_radius + LABEL_OFFSET_WORLD)
		var label_screen_pos = _world_to_screen(render_data.position + Vector2(0, label_offset_y))

		# Check for overlap with already placed labels
		var overlaps = false
		for placed_pos in placed_positions:
			if label_screen_pos.distance_to(placed_pos) < MIN_LABEL_SPACING_SCREEN:
				overlaps = true
				break

		if overlaps:
			continue

		# Create the label with world-space font size (scales naturally with zoom)
		var label = Label.new()
		label.text = candidate.label_text
		label.theme = _theme
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", label_font_size)

		# Apply label opacity
		if label_opacity < 1.0:
			label.modulate.a = label_opacity

		labels_container.add_child(label)

		# Position label above or below the node, centered horizontally (all in world space)
		var label_size = label.get_minimum_size()
		var offset: Vector2
		if label_above:
			# Position above: negative Y offset, accounting for label height
			offset = Vector2(-label_size.x / 2.0, -(node_radius + LABEL_OFFSET_WORLD + label_size.y))
		else:
			# Position below: positive Y offset
			offset = Vector2(-label_size.x / 2.0, node_radius + LABEL_OFFSET_WORLD)
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


func _world_to_screen(local_pos: Vector2) -> Vector2:
	"""Convert tree-local position to screen coordinates.
	local_pos is in tree-local space (before tree_graph.scale).
	Transform: local -> world -> screen
	  world = local * tree_scale
	  screen = (world - scroll_offset) * camera_scale + viewport_center"""
	var world_pos = local_pos * _tree_scale
	return (world_pos - _scroll_offset) * _current_scale + _viewport_center


# =============================================================================
# Node Appearance
# =============================================================================

func _get_node_color(node: TreeDataModels.TaxonomicNode) -> Color:
	"""Get color for a node based on type and capture status. Applies node_opacity."""
	var base_color: Color

	if node.is_taxonomic():
		base_color = COLOR_TAXONOMY
	elif node.captured_by_user and node.captured_by_friends.size() > 0:
		base_color = COLOR_BOTH_CAPTURED
	elif node.captured_by_user:
		base_color = COLOR_USER_CAPTURED
	elif node.captured_by_friends.size() > 0:
		base_color = COLOR_FRIEND_CAPTURED
	else:
		base_color = COLOR_UNCAPTURED

	# Apply configurable opacity
	if node_opacity < 1.0:
		base_color.a = node_opacity

	return base_color


func _get_node_scale(node: TreeDataModels.TaxonomicNode) -> float:
	"""Get scale for a node based on type, rank, capture status and importance.
	With unit circle mesh, scale directly equals the desired world-unit size."""
	if node.is_taxonomic():
		var multiplier: float = RANK_SIZE_MULTIPLIERS.get(node.rank, 1.0)
		return node_size_base * multiplier

	# Animal nodes: start with base size
	var final_size: float = node_size_base

	# Discoverer bonus (additive, scales with node_size_base)
	if node.discoverer.get("is_self", false) or node.discoverer.get("is_friend", false):
		final_size += node_size_discoverer_bonus

	return final_size


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
	"""Convert screen position to tree-local coordinates.
	Transform: screen -> world -> tree-local
	  world = (screen - viewport_center) / camera_scale + scroll_offset
	  local = world / tree_scale"""
	var world_pos = (screen_pos - _viewport_center) / _current_scale + _scroll_offset
	return world_pos / _tree_scale


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
					# Use larger click area for nodes with dex images
					var node_radius: float
					if nodes_with_dex_images.has(render_data.node.id):
						node_radius = dex_image_size / 2.0  # Half the dex image size
					else:
						# With unit circle mesh, scale IS the world-unit radius
						node_radius = render_data.scale

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
		"rendered_edges": edges_container.get_child_count() if edges_container else 0,
		"active_dex_images": active_dex_images.size(),
		"dex_image_pool_size": dex_image_pool.size(),
		"pending_loads": _pending_loads.size(),
		"concurrent_loads": _loading_in_progress.size()
	}
