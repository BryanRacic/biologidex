extends Node2D
class_name TreeVisualization

## TreeVisualization - Reusable component for taxonomic tree rendering.
##
## Encapsulates tree data loading, friend sync, and rendering logic.
## Can be added to any scene that has a PaperCameraScene.
##
## Usage:
##   var tree_vis = TreeVisualization.new()
##   paper_camera.content_container.add_child(tree_vis)
##   tree_vis.setup(paper_camera)
##   # Tree will auto-load if auto_load_on_ready is true

const APITypes = preload("res://features/server_interface/api/core/api_types.gd")
const TreeRenderer = preload("res://features/tree/tree_renderer.gd")

# =============================================================================
# Signals
# =============================================================================

signal tree_loaded(tree_data: TreeDataModels.TreeData)
signal tree_load_failed(error: APITypes.APIError)
signal node_selected(node: TreeDataModels.TaxonomicNode)
signal node_hovered(node: TreeDataModels.TaxonomicNode)
signal node_unhovered()
signal loading_started()
signal loading_finished()

# =============================================================================
# Export Variables
# =============================================================================

@export_group("Tree Loading")
## Automatically load tree when setup() completes
@export var auto_load_on_ready: bool = true
## Initial tree mode (0=Personal, 1=Friends, 2=Selected, 3=Global)
@export var initial_mode: int = APITypes.TreeMode.FRIENDS
## Use server cache for tree data
@export var use_cache: bool = true

@export_group("Visual Settings")
## Overall scale of the tree (larger = more zoomed in appearance)
@export var tree_scale: float = 1.0:
	set(value):
		tree_scale = value
		if tree_graph:
			tree_graph.scale = Vector2(tree_scale, tree_scale)
		if tree_renderer:
			tree_renderer.set_tree_scale(tree_scale)
## Size of dex images in world units
@export var dex_image_size: float = 1000.0
## Enable branch extension to reduce image overlap
@export var branch_extension_enabled: bool = true
## Minimum zoom level to show labels
@export var min_zoom_for_labels: float = 0.3

@export_group("Node Appearance")
## Base size of nodes in world units
@export var node_size: float = 20.0
## Opacity of taxonomy/uncaptured nodes (0.0 - 1.0)
@export_range(0.0, 1.0, 0.05) var node_opacity: float = 1.0
## Hide the root node (Kingdom) circle
@export var hide_root_node: bool = false
## Hide the root node (Kingdom) label
@export var hide_root_label: bool = false

@export_group("Edge Appearance")
## Width of edges in world units
@export var edge_width: float = 5.0
## Opacity of edges (0.0 - 1.0)
@export_range(0.0, 1.0, 0.05) var edge_opacity: float = 0.85

@export_group("Label Appearance")
## Font size for labels in world units
@export var label_font_size: int = 90
## Opacity of labels (0.0 - 1.0)
@export_range(0.0, 1.0, 0.05) var label_opacity: float = 1.0

@export_group("Diff Circle")
## Enable a circular boundary that clips tree edges (for home scene menu)
@export var diff_circle_enabled: bool = false:
	set(value):
		diff_circle_enabled = value
		if tree_renderer:
			tree_renderer.diff_circle_enabled = value
## Radius of the diff circle in world units (tree-local space)
@export var diff_circle_radius: float = 330.0:
	set(value):
		diff_circle_radius = value
		if tree_renderer:
			tree_renderer.diff_circle_radius = value
## Center position of the diff circle in tree-local coordinates
@export var diff_circle_center: Vector2 = Vector2.ZERO:
	set(value):
		diff_circle_center = value
		if tree_renderer:
			tree_renderer.diff_circle_center = value

# =============================================================================
# Internal State
# =============================================================================

# Node references (created dynamically for web export compatibility)
var tree_graph: Node2D = null
var _edges_layer: Node2D = null
var _nodes_layer: Node2D = null
var _labels_layer: Node2D = null
var _dex_images_layer: Node2D = null
var tree_renderer: TreeRenderer = null

# Paper camera reference
var _paper_camera: PaperCameraScene = null

# Tree data
var _tree_data: TreeDataModels.TreeData = null
var _current_mode: int = APITypes.TreeMode.FRIENDS
var _selected_friend_ids: Array = []

# Loading state
var _is_loading: bool = false
var _friends_synced: bool = false
var _tree_loaded: bool = false
var _pending_tree_data: TreeDataModels.TreeData = null

# View state (for TreeRenderer culling)
var _scroll_offset: Vector2 = Vector2.ZERO
var _current_scale: float = 1.0
var _viewport_center: Vector2 = Vector2.ZERO

# =============================================================================
# Read-only Properties
# =============================================================================

## Whether the tree is currently loading
var is_loading: bool:
	get: return _is_loading

## Current tree mode
var current_mode: int:
	get: return _current_mode

## Current tree data
var tree_data: TreeDataModels.TreeData:
	get: return _tree_data

# =============================================================================
# Public API
# =============================================================================

## Setup the tree visualization with a paper camera.
## This MUST be called after adding to the scene tree.
func setup(paper_camera: PaperCameraScene) -> void:
	_paper_camera = paper_camera
	_current_mode = initial_mode

	# Create renderer and layers
	_setup_renderer()

	# Connect camera view changes
	_setup_camera_connection()

	# Connect API signals
	_connect_api_signals()

	# Connect friend sync signals
	_connect_friend_sync_signals()

	print("[TreeVisualization] Setup complete")

	# Auto-load if configured
	if auto_load_on_ready:
		_start_parallel_load()


## Load tree data from server.
## mode: Tree mode to use (-1 to use current mode)
## use_cache_param: Whether to use server cache
func load_tree(mode: int = -1, use_cache_param: bool = true) -> void:
	if mode >= 0:
		_current_mode = mode

	if _is_loading:
		return

	_is_loading = true
	loading_started.emit()

	# Request radial layout from server
	APIManager.tree.fetch_tree(_current_mode, _selected_friend_ids, use_cache_param, "radial")


## Reload tree from server (bypass cache)
func reload_tree() -> void:
	load_tree(-1, false)


## Set the tree mode and optionally reload
func set_mode(mode: int, reload: bool = false) -> void:
	_current_mode = mode
	if reload:
		load_tree()


## Set selected friend IDs for SELECTED mode
func set_selected_friends(friend_ids: Array) -> void:
	_selected_friend_ids = friend_ids


## Get the root position (center of radial layout).
## For radial layouts, the root is always at world origin by design.
func get_root_position() -> Vector2:
	# Radial layout algorithm centers the tree at origin
	return Vector2.ZERO


## Get current tree data
func get_tree_data() -> TreeDataModels.TreeData:
	return _tree_data


## Get tree statistics
func get_stats() -> TreeDataModels.TreeStats:
	if _tree_data:
		return _tree_data.stats
	return null


## Clear tree and renderer
func clear() -> void:
	if tree_renderer:
		tree_renderer.clear()
	_tree_data = null
	_pending_tree_data = null
	_tree_loaded = false

# =============================================================================
# Internal Methods - Setup
# =============================================================================

func _setup_renderer() -> void:
	"""Setup TreeRenderer for visualization.
	Creates TreeGraph and layers programmatically to avoid web export bug (GitHub #101975)."""
	# Create TreeGraph and layers dynamically
	tree_graph = Node2D.new()
	tree_graph.name = "TreeGraph"
	tree_graph.scale = Vector2(tree_scale, tree_scale)
	add_child(tree_graph)

	_edges_layer = Node2D.new()
	_edges_layer.name = "EdgesLayer"
	_edges_layer.z_index = -1
	tree_graph.add_child(_edges_layer)

	_nodes_layer = Node2D.new()
	_nodes_layer.name = "NodesLayer"
	tree_graph.add_child(_nodes_layer)

	_dex_images_layer = Node2D.new()
	_dex_images_layer.name = "DexImagesLayer"
	_dex_images_layer.z_index = 1
	tree_graph.add_child(_dex_images_layer)

	_labels_layer = Node2D.new()
	_labels_layer.name = "LabelsLayer"
	_labels_layer.z_index = 2
	tree_graph.add_child(_labels_layer)

	# Create and setup TreeRenderer
	tree_renderer = TreeRenderer.new()
	tree_renderer.name = "TreeRenderer"
	tree_graph.add_child(tree_renderer)

	# Pass node containers to renderer
	tree_renderer.setup_containers(_edges_layer, _nodes_layer, _labels_layer, _dex_images_layer)

	# Set tree scale so renderer can do correct coordinate conversions
	tree_renderer.set_tree_scale(tree_scale)

	# Connect renderer signals
	tree_renderer.node_selected.connect(_on_node_selected)
	tree_renderer.node_hovered.connect(_on_node_hovered)
	tree_renderer.node_unhovered.connect(_on_node_unhovered)

	# Apply visual configuration to renderer
	_configure_renderer()

	print("[TreeVisualization] TreeRenderer initialized")


func _configure_renderer() -> void:
	"""Apply visual configuration to the TreeRenderer."""
	if not tree_renderer:
		return

	# Node appearance
	tree_renderer.node_size_base = node_size
	tree_renderer.node_opacity = node_opacity
	tree_renderer.hide_root_node = hide_root_node
	tree_renderer.hide_root_label = hide_root_label

	# Edge appearance
	tree_renderer.edge_width_base = edge_width
	tree_renderer.edge_opacity = edge_opacity

	# Label appearance
	tree_renderer.label_font_size = label_font_size
	tree_renderer.label_opacity = label_opacity

	# Dex image settings
	tree_renderer.dex_image_size = dex_image_size
	tree_renderer.branch_extension_enabled = branch_extension_enabled
	tree_renderer.min_zoom_for_labels = min_zoom_for_labels

	# Diff circle settings
	tree_renderer.diff_circle_enabled = diff_circle_enabled
	tree_renderer.diff_circle_radius = diff_circle_radius
	tree_renderer.diff_circle_center = diff_circle_center


func _setup_camera_connection() -> void:
	"""Connect to PaperCameraScene signals."""
	if not _paper_camera:
		push_error("[TreeVisualization] No paper camera provided")
		return

	# Connect to view_changed signal
	_paper_camera.view_changed.connect(_on_view_changed)

	# Get initial state for culling calculations
	_scroll_offset = _paper_camera.get_camera_position()
	_current_scale = _paper_camera.get_current_zoom()
	if is_inside_tree():
		_viewport_center = get_viewport_rect().size / 2.0
	else:
		_viewport_center = Vector2(640, 360)  # Default fallback


func _connect_api_signals() -> void:
	"""Connect to tree service signals."""
	APIManager.tree.tree_loaded.connect(_on_tree_data_loaded)
	APIManager.tree.tree_load_failed.connect(_on_tree_data_load_failed)


func _connect_friend_sync_signals() -> void:
	"""Connect to friend dex sync service signals."""
	var sync_service = get_node_or_null("/root/FriendDexSyncService")
	if sync_service:
		sync_service.sync_completed.connect(_on_friends_sync_completed)
		sync_service.sync_failed.connect(_on_friends_sync_failed)

# =============================================================================
# Internal Methods - Tree Loading
# =============================================================================

func _start_parallel_load() -> void:
	"""Start friend sync and tree load in parallel."""
	_friends_synced = false
	_tree_loaded = false
	_pending_tree_data = null

	loading_started.emit()

	# Start friend sync (will use cached data if already synced)
	var sync_service = get_node_or_null("/root/FriendDexSyncService")
	if sync_service:
		sync_service.sync_friends()
	else:
		_friends_synced = true  # No sync service, continue anyway

	# Load tree
	load_tree()


func _on_tree_data_loaded(data: TreeDataModels.TreeData) -> void:
	"""Handle successful tree load."""
	_tree_loaded = true
	_pending_tree_data = data
	_is_loading = false

	_try_render_tree()


func _on_friends_sync_completed(_friends_data: Dictionary) -> void:
	"""Handle friend sync completion."""
	_friends_synced = true
	_try_render_tree()


func _on_friends_sync_failed(_error: String) -> void:
	"""Handle friend sync failure - still allow rendering with cached data."""
	_friends_synced = true  # Continue anyway with cached data
	_try_render_tree()


func _try_render_tree() -> void:
	"""Render tree when tree data is ready.
	Friend sync runs in background but doesn't block tree rendering."""
	if not _tree_loaded:
		return

	if not _pending_tree_data:
		return

	_tree_data = _pending_tree_data
	_pending_tree_data = null

	loading_finished.emit()
	_render_tree()

	# Emit loaded signal
	tree_loaded.emit(_tree_data)


func _on_tree_data_load_failed(error: APITypes.APIError) -> void:
	"""Handle tree load failure."""
	push_error("[TreeVisualization] Failed to load tree: ", error.message)
	_is_loading = false
	loading_finished.emit()
	tree_load_failed.emit(error)

# =============================================================================
# Internal Methods - Rendering
# =============================================================================

func _render_tree() -> void:
	"""Render the tree visualization."""
	if not _tree_data:
		push_error("[TreeVisualization] No tree data to render")
		return

	if not tree_renderer:
		push_error("[TreeVisualization] TreeRenderer not initialized")
		return

	print("[TreeVisualization] Rendering tree...")
	tree_renderer.render_tree(_tree_data)

	# Initialize renderer with current view state
	if is_inside_tree():
		_viewport_center = get_viewport_rect().size / 2.0
	_scroll_offset = _paper_camera.get_camera_position()
	_current_scale = _paper_camera.get_current_zoom()
	tree_renderer.update_view(_scroll_offset, _current_scale, _viewport_center)

	print("[TreeVisualization] Rendering complete")


func _on_view_changed(cam_position: Vector2, zoom: float) -> void:
	"""Handle view changes from PaperCameraScene."""
	_scroll_offset = cam_position
	_current_scale = zoom
	if is_inside_tree():
		_viewport_center = get_viewport_rect().size / 2.0

	# Update renderer for culling/labels
	if tree_renderer:
		tree_renderer.update_view(_scroll_offset, _current_scale, _viewport_center)


func _process(_delta: float) -> void:
	"""Update viewport center on resize."""
	if not _paper_camera:
		return

	if not is_inside_tree():
		return

	var new_center = get_viewport_rect().size / 2.0
	if new_center != _viewport_center:
		_viewport_center = new_center
		# Trigger renderer update with current view state
		if tree_renderer:
			tree_renderer.update_view(_scroll_offset, _current_scale, _viewport_center)

# =============================================================================
# Internal Methods - Node Interaction
# =============================================================================

func _on_node_selected(node: TreeDataModels.TaxonomicNode) -> void:
	"""Handle node selection from renderer."""
	node_selected.emit(node)


func _on_node_hovered(node: TreeDataModels.TaxonomicNode) -> void:
	"""Handle node hover from renderer."""
	node_hovered.emit(node)


func _on_node_unhovered() -> void:
	"""Handle node unhover from renderer."""
	node_unhovered.emit()

# =============================================================================
# Cleanup
# =============================================================================

func _exit_tree() -> void:
	"""Cleanup when exiting tree."""
	print("[TreeVisualization] Cleaning up")

	if tree_renderer:
		tree_renderer.clear()
		tree_renderer.queue_free()
		tree_renderer = null

	# Disconnect API signals
	if APIManager.tree.tree_loaded.is_connected(_on_tree_data_loaded):
		APIManager.tree.tree_loaded.disconnect(_on_tree_data_loaded)
	if APIManager.tree.tree_load_failed.is_connected(_on_tree_data_load_failed):
		APIManager.tree.tree_load_failed.disconnect(_on_tree_data_load_failed)

	# Disconnect friend sync signals
	var sync_service = get_node_or_null("/root/FriendDexSyncService")
	if sync_service:
		if sync_service.sync_completed.is_connected(_on_friends_sync_completed):
			sync_service.sync_completed.disconnect(_on_friends_sync_completed)
		if sync_service.sync_failed.is_connected(_on_friends_sync_failed):
			sync_service.sync_failed.disconnect(_on_friends_sync_failed)

	# Disconnect camera signals
	if _paper_camera and _paper_camera.view_changed.is_connected(_on_view_changed):
		_paper_camera.view_changed.disconnect(_on_view_changed)
