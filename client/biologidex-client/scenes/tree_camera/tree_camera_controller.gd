@tool
"""
TreeCameraController - Camera2D-based taxonomic tree visualization.
Uses Camera2D for view control instead of manual Transform2D.
This provides perfect background/foreground sync since the shader
gets camera transform automatically via CANVAS_MATRIX.
"""
extends BaseSceneNode

const APITypes = preload("res://features/server_interface/api/core/api_types.gd")
const TreeRenderer = preload("res://features/tree/tree_renderer.gd")
const TreeCameraControllerClass = preload("res://features/tree/camera_controller.gd")

# Editor preview: Load tree from cached JSON file for UI development
const EDITOR_PREVIEW_PATH: String = "res://resources/tree.json"
@export var editor_preview: bool = false:
	set(value):
		editor_preview = value
		if Engine.is_editor_hint() and value:
			_load_editor_preview()

# =============================================================================
# Paper Background Shader Settings (tweakable in editor)
# =============================================================================

@export_group("Paper Grid")
## Size of the grid cells in world units
@export_range(8.0, 64.0, 0.5) var grid_scale: float = 22.0:
	set(value):
		grid_scale = value
		_update_shader_param("grid_scale", value)
## Thickness of grid lines in pixels
@export_range(0.5, 3.0, 0.1) var grid_line_px: float = 0.5:
	set(value):
		grid_line_px = value
		_update_shader_param("line_px", value)
## Grid line color (RGB, alpha ignored)
@export var grid_line_color: Color = Color(0.55, 0.53, 0.5, 1.0):
	set(value):
		grid_line_color = value
		_update_shader_param("line_color", Vector4(value.r, value.g, value.b, 1.0))
## Grid line opacity (0 = invisible, 1 = fully opaque)
@export_range(0.0, 0.6, 0.01) var grid_line_alpha: float = 0.07:
	set(value):
		grid_line_alpha = value
		_update_shader_param("line_alpha", value)

@export_group("Paper Base")
## Base paper color
@export var paper_color: Color = Color(0.85, 0.82, 0.78, 1.0):
	set(value):
		paper_color = value
		_update_shader_param("paper_color", Vector4(value.r, value.g, value.b, 1.0))
## Amount of noise variation in paper color
@export_range(0.0, 0.15, 0.001) var paper_noise_amount: float = 0.05:
	set(value):
		paper_noise_amount = value
		_update_shader_param("paper_noise_amount", value)
## Scale of the paper noise pattern
@export_range(0.05, 1.5, 0.01) var paper_noise_scale: float = 0.35:
	set(value):
		paper_noise_scale = value
		_update_shader_param("paper_noise_scale", value)

@export_group("Paper Speckles")
## Amount of speckle darkness (0 = none, higher = darker spots)
@export_range(0.0, 0.30, 0.001) var speckle_amount: float = 0.064:
	set(value):
		speckle_amount = value
		_update_shader_param("speckle_amount", value)
## Density of speckles (higher = more frequent)
@export_range(0.25, 3.0, 0.01) var speckle_density: float = 1.68:
	set(value):
		speckle_density = value
		_update_shader_param("speckle_density", value)
## Scale of individual speckles
@export_range(0.5, 6.0, 0.01) var speckle_scale: float = 6.0:
	set(value):
		speckle_scale = value
		_update_shader_param("speckle_scale", value)

@export_group("Paper Fibers")
## Amount of fiber visibility
@export_range(0.0, 0.20, 0.001) var fiber_amount: float = 0.111:
	set(value):
		fiber_amount = value
		_update_shader_param("fiber_amount", value)
## Scale of fiber patterns
@export_range(0.2, 4.0, 0.01) var fiber_scale: float = 0.57:
	set(value):
		fiber_scale = value
		_update_shader_param("fiber_scale", value)

# Node references
@onready var camera: Camera2D = %Camera2D
@onready var camera_controller: TreeCameraControllerClass = %CameraController
@onready var world_content: Node2D = %WorldContent
@onready var tree_graph: Node2D = %TreeGraph
@onready var paper_background: Polygon2D = %PaperBackground
@onready var search_bar: LineEdit = %SearchBar
@onready var mode_dropdown: OptionButton = %ModeDropdown
@onready var zoom_in_button: Button = %ZoomInButton
@onready var zoom_out_button: Button = %ZoomOutButton
@onready var zoom_reset_button: Button = %ZoomResetButton
@onready var center_button: Button = %CenterButton
@onready var loading_label: Label = %LoadingLabel
@onready var stats_label: Label = %StatsLabel

# Tree data
var current_tree_data: TreeDataModels.TreeData = null
var current_mode: APITypes.TreeMode = APITypes.TreeMode.FRIENDS
var selected_friend_ids: Array = []

# Renderer
var tree_renderer: TreeRenderer = null

# State
var is_initialized: bool = false
var _friends_synced: bool = false
var _tree_loaded: bool = false
var _pending_tree_data: TreeDataModels.TreeData = null


# =============================================================================
# Shader Parameter Updates
# =============================================================================

func _update_shader_param(param_name: String, value: Variant) -> void:
	"""Update a shader parameter on the paper background material."""
	if not is_inside_tree():
		return
	if not paper_background:
		return
	var mat := paper_background.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter(param_name, value)


func _sync_all_shader_params() -> void:
	"""Sync all exported shader params to the material (call after _ready)."""
	if not paper_background:
		return
	var mat := paper_background.material as ShaderMaterial
	if not mat:
		return

	mat.set_shader_parameter("grid_scale", grid_scale)
	mat.set_shader_parameter("line_px", grid_line_px)
	mat.set_shader_parameter("line_color", Vector4(grid_line_color.r, grid_line_color.g, grid_line_color.b, 1.0))
	mat.set_shader_parameter("line_alpha", grid_line_alpha)
	mat.set_shader_parameter("paper_color", Vector4(paper_color.r, paper_color.g, paper_color.b, 1.0))
	mat.set_shader_parameter("paper_noise_amount", paper_noise_amount)
	mat.set_shader_parameter("paper_noise_scale", paper_noise_scale)
	mat.set_shader_parameter("speckle_amount", speckle_amount)
	mat.set_shader_parameter("speckle_density", speckle_density)
	mat.set_shader_parameter("speckle_scale", speckle_scale)
	mat.set_shader_parameter("fiber_amount", fiber_amount)
	mat.set_shader_parameter("fiber_scale", fiber_scale)


# =============================================================================
# Editor Preview
# =============================================================================

func _load_editor_preview() -> void:
	"""Load tree data from cached JSON for editor preview."""
	if not Engine.is_editor_hint():
		return

	print("[TreeCameraController] Loading editor preview from: ", EDITOR_PREVIEW_PATH)

	if not FileAccess.file_exists(EDITOR_PREVIEW_PATH):
		push_warning("[TreeCameraController] Editor preview file not found: %s" % EDITOR_PREVIEW_PATH)
		return

	var file = FileAccess.open(EDITOR_PREVIEW_PATH, FileAccess.READ)
	if not file:
		push_error("[TreeCameraController] Failed to open editor preview file")
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("[TreeCameraController] Failed to parse editor preview JSON: %s" % json.get_error_message())
		return

	var response = json.data as Dictionary
	if not response:
		push_error("[TreeCameraController] Editor preview JSON is not a valid dictionary")
		return

	print("[TreeCameraController] Loaded %d nodes, %d edges from cache" % [
		response.get("nodes", []).size(),
		response.get("edges", []).size()
	])

	current_tree_data = TreeDataModels.TreeData.new(response)

	if not tree_renderer and tree_graph:
		_setup_renderer_for_editor()

	_render_tree()


func _setup_renderer_for_editor() -> void:
	"""Setup renderer in editor mode."""
	tree_renderer = TreeRenderer.new()
	tree_renderer.name = "EditorTreeRenderer"
	tree_graph.add_child(tree_renderer)
	tree_renderer.setup_containers(%EdgesLayer, %NodesLayer, %LabelsLayer, %DexImagesLayer)
	print("[TreeCameraController] Editor TreeRenderer initialized")


# =============================================================================
# Initialization
# =============================================================================

func _on_scene_ready() -> void:
	"""Called by BaseSceneNode after managers are initialized."""
	if Engine.is_editor_hint():
		return

	scene_name = "TreeCameraController"
	print("[TreeCameraController] Scene ready (Camera2D-based)")

	# Wait for a frame to get viewport size
	await get_tree().process_frame

	# Wire up back button
	back_button = %BackButton
	if back_button and not back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.connect(_on_back_pressed)

	# Connect UI signals
	search_bar.text_submitted.connect(_on_search_submitted)
	mode_dropdown.item_selected.connect(_on_mode_selected)
	zoom_in_button.pressed.connect(_on_zoom_in)
	zoom_out_button.pressed.connect(_on_zoom_out)
	zoom_reset_button.pressed.connect(_on_zoom_reset)
	center_button.pressed.connect(_on_center_on_root)

	# Connect camera controller signals
	camera_controller.view_changed.connect(_on_view_changed)

	# Setup camera controller with our Camera2D
	camera_controller.camera = camera

	# Connect API signals
	APIManager.tree.tree_loaded.connect(_on_tree_loaded)
	APIManager.tree.tree_load_failed.connect(_on_tree_load_failed)
	APIManager.tree.search_results_received.connect(_on_search_results)
	APIManager.tree.search_failed.connect(_on_search_failed)

	# Check for friend context from navigation
	if NavigationManager.has_context():
		var context: Dictionary = NavigationManager.get_context()
		if context.has("user_id"):
			current_mode = APITypes.TreeMode.SELECTED
			selected_friend_ids = [context.get("user_id")]
			NavigationManager.clear_context()

	# Setup mode dropdown
	_setup_mode_dropdown()

	# Setup renderer
	_setup_renderer()

	# Sync shader params from exported vars to material
	_sync_all_shader_params()

	# Connect friend sync signals
	FriendDexSyncService.sync_completed.connect(_on_friends_sync_completed)
	FriendDexSyncService.sync_failed.connect(_on_friends_sync_failed)

	# Start friend sync and tree load in parallel
	_start_parallel_load()


func _setup_mode_dropdown() -> void:
	"""Setup mode selection dropdown."""
	mode_dropdown.clear()
	mode_dropdown.add_item("Personal", APITypes.TreeMode.PERSONAL)
	mode_dropdown.add_item("Friends", APITypes.TreeMode.FRIENDS)
	mode_dropdown.add_item("Selected", APITypes.TreeMode.SELECTED)
	mode_dropdown.select(APITypes.TreeMode.FRIENDS)


func _setup_renderer() -> void:
	"""Setup TreeRenderer for visualization."""
	tree_renderer = TreeRenderer.new()
	tree_renderer.name = "TreeRenderer"
	tree_graph.add_child(tree_renderer)

	# Pass node containers to renderer
	tree_renderer.setup_containers(%EdgesLayer, %NodesLayer, %LabelsLayer, %DexImagesLayer)

	# Connect renderer signals
	tree_renderer.node_selected.connect(_on_node_selected)
	tree_renderer.node_hovered.connect(_on_node_hovered)
	tree_renderer.node_unhovered.connect(_on_node_unhovered)

	print("[TreeCameraController] TreeRenderer initialized")


# =============================================================================
# Camera View Handling
# =============================================================================

func _on_view_changed(cam_position: Vector2, zoom: float) -> void:
	"""Called when camera position/zoom changes."""
	if tree_renderer:
		var viewport_size := get_viewport_rect().size
		var viewport_center := viewport_size / 2.0
		# With Camera2D, the camera position IS the world center (scroll_offset)
		tree_renderer.update_view(cam_position, zoom, viewport_center)


func _process(_delta: float) -> void:
	"""Handle window resize."""
	if Engine.is_editor_hint():
		return

	# TreeRenderer needs viewport size updates for culling calculations
	# The camera controller handles the actual view transform


# =============================================================================
# Zoom Controls
# =============================================================================

func _on_zoom_in() -> void:
	"""Zoom in via button."""
	if camera_controller:
		camera_controller.set_zoom(camera_controller.get_current_zoom() * 1.2)


func _on_zoom_out() -> void:
	"""Zoom out via button."""
	if camera_controller:
		camera_controller.set_zoom(camera_controller.get_current_zoom() / 1.2)


func _on_zoom_reset() -> void:
	"""Reset zoom and position."""
	if camera_controller:
		camera_controller.reset()


func _on_center_on_root() -> void:
	"""Center view on tree root (center of radial layout)."""
	if camera_controller:
		camera_controller.center_on(Vector2.ZERO)


# =============================================================================
# Tree Loading
# =============================================================================

func _start_parallel_load() -> void:
	"""Start friend sync and tree load in parallel."""
	_friends_synced = false
	_tree_loaded = false
	_pending_tree_data = null

	_show_loading(true)

	# Start friend sync (will use cached data if already synced)
	FriendDexSyncService.sync_friends()

	# Load tree
	load_tree()


func load_tree(use_cache: bool = true) -> void:
	"""Load tree data from API."""
	if is_loading:
		return

	is_loading = true
	_show_loading(true)

	# Request radial layout from server
	APIManager.tree.fetch_tree(current_mode, selected_friend_ids, use_cache, "radial")


func _on_tree_loaded(tree_data: TreeDataModels.TreeData) -> void:
	"""Handle successful tree load."""
	_tree_loaded = true
	_pending_tree_data = tree_data
	is_loading = false

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
	"""Render tree only when both tree and friends are ready."""
	if not _tree_loaded or not _friends_synced:
		return

	if not _pending_tree_data:
		return

	current_tree_data = _pending_tree_data
	_pending_tree_data = null
	is_initialized = true

	_show_loading(false)
	_update_stats_display()
	_render_tree()

	# Center on root after loading
	_on_center_on_root()


func _on_tree_load_failed(error: APITypes.APIError) -> void:
	"""Handle tree load failure."""
	push_error("[TreeCameraController] Failed to load tree: ", error.message)
	is_loading = false
	_show_loading(false)

	stats_label.text = "Error: " + error.message
	stats_label.add_theme_color_override("font_color", Color.RED)


func reload_tree() -> void:
	"""Reload tree from server (bypass cache)."""
	load_tree(false)


# =============================================================================
# Rendering
# =============================================================================

func _render_tree() -> void:
	"""Render the tree visualization."""
	if not current_tree_data:
		push_error("[TreeCameraController] No tree data to render")
		return

	if not tree_renderer:
		push_error("[TreeCameraController] TreeRenderer not initialized")
		return

	print("[TreeCameraController] Rendering tree...")
	tree_renderer.render_tree(current_tree_data)

	# Trigger initial view update
	if camera_controller:
		_on_view_changed(camera.position, camera.zoom.x)

	print("[TreeCameraController] Rendering complete")


# =============================================================================
# UI Interactions
# =============================================================================

func _on_mode_selected(index: int) -> void:
	"""Handle mode selection change."""
	var new_mode = mode_dropdown.get_item_id(index) as APITypes.TreeMode
	if new_mode == current_mode:
		return

	print("[TreeCameraController] Mode changed to: ", APITypes.get_tree_mode_string(new_mode))
	current_mode = new_mode

	if current_mode == APITypes.TreeMode.SELECTED:
		_show_friend_selection()
	else:
		load_tree()


func _show_friend_selection() -> void:
	"""Show friend selection UI for SELECTED mode."""
	print("[TreeCameraController] Friend selection UI not yet implemented, using all friends")
	load_tree()


func _on_search_submitted(query: String) -> void:
	"""Handle search query submission."""
	if query.strip_edges().is_empty():
		return

	print("[TreeCameraController] Searching for: ", query)
	APIManager.tree.search_tree(query, current_mode, selected_friend_ids, 50)


func _on_search_results(results: Array) -> void:
	"""Handle search results."""
	print("[TreeCameraController] Search results: ", results.size(), " found")

	if results.size() == 0:
		stats_label.text = "No results found"
		return

	# Navigate to first result
	if results.size() > 0:
		var first_result = results[0] as Dictionary
		var position_array = first_result.get("position", [0, 0])
		if position_array is Array and position_array.size() >= 2:
			var pos = Vector2(position_array[0], position_array[1])
			# Center camera on this position
			if camera_controller:
				camera_controller.center_on(pos)
				print("[TreeCameraController] Centered on: ", first_result.get("scientific_name", ""))


func _on_search_failed(error: APITypes.APIError) -> void:
	"""Handle search failure."""
	push_error("[TreeCameraController] Search failed: ", error.message)
	stats_label.text = "Search error: " + error.message
	stats_label.add_theme_color_override("font_color", Color.RED)


func _on_node_selected(node: TreeDataModels.TaxonomicNode) -> void:
	"""Handle node selection from renderer."""
	if node.is_taxonomic():
		print("[TreeCameraController] Taxonomy node selected: %s (rank: %s)" % [node.name, _get_rank_name(node.rank)])
		var info = "%s (Rank: %s)" % [node.name, _get_rank_name(node.rank)]
		if node.children_count > 0:
			info += " - %d children" % node.children_count
		stats_label.text = info
	else:
		print("[TreeCameraController] Animal node selected: %s" % node.scientific_name)
		var info = "%s (%s)" % [node.scientific_name, node.common_name]
		if node.captured_by_user:
			info += " - Captured by you"
		elif node.captured_by_friends.size() > 0:
			info += " - Captured by %d friend(s)" % node.captured_by_friends.size()
		else:
			info += " - Not yet captured"
		stats_label.text = info

	stats_label.remove_theme_color_override("font_color")


func _get_rank_name(rank: int) -> String:
	"""Convert rank enum to display name."""
	match rank:
		TreeDataModels.TaxonomicRank.ROOT: return "Root"
		TreeDataModels.TaxonomicRank.KINGDOM: return "Kingdom"
		TreeDataModels.TaxonomicRank.PHYLUM: return "Phylum"
		TreeDataModels.TaxonomicRank.CLASS: return "Class"
		TreeDataModels.TaxonomicRank.ORDER: return "Order"
		TreeDataModels.TaxonomicRank.FAMILY: return "Family"
		TreeDataModels.TaxonomicRank.SUBFAMILY: return "Subfamily"
		TreeDataModels.TaxonomicRank.GENUS: return "Genus"
		TreeDataModels.TaxonomicRank.SPECIES: return "Species"
		TreeDataModels.TaxonomicRank.SUBSPECIES: return "Subspecies"
		_: return "Unknown"


func _on_node_hovered(_node: TreeDataModels.TaxonomicNode) -> void:
	"""Handle node hover from renderer."""
	pass


func _on_node_unhovered() -> void:
	"""Handle node unhover from renderer."""
	pass


# =============================================================================
# UI Updates
# =============================================================================

func _show_loading(should_show: bool) -> void:
	"""Show/hide loading indicator."""
	if loading_label:
		loading_label.visible = should_show


func _update_stats_display() -> void:
	"""Update stats label with current tree info."""
	if not current_tree_data or not stats_label:
		return

	var stats = current_tree_data.stats
	var metadata = current_tree_data.metadata

	var stats_text = "Mode: %s | Animals: %d | Nodes: %d" % [
		metadata.mode.capitalize(),
		stats.total_animals,
		stats.total_nodes
	]

	if stats.user_captures > 0:
		stats_text += " | Your captures: %d" % stats.user_captures

	if stats.friend_captures > 0:
		stats_text += " | Friend captures: %d" % stats.friend_captures

	stats_label.text = stats_text
	stats_label.remove_theme_color_override("font_color")


# =============================================================================
# Cleanup
# =============================================================================

func _exit_tree() -> void:
	"""Cleanup when exiting tree view."""
	if Engine.is_editor_hint():
		if tree_renderer:
			tree_renderer.clear()
			tree_renderer.queue_free()
			tree_renderer = null
		return

	print("[TreeCameraController] Cleaning up")

	if tree_renderer:
		tree_renderer.clear()
		tree_renderer.queue_free()
		tree_renderer = null

	if APIManager.tree.tree_loaded.is_connected(_on_tree_loaded):
		APIManager.tree.tree_loaded.disconnect(_on_tree_loaded)
	if APIManager.tree.tree_load_failed.is_connected(_on_tree_load_failed):
		APIManager.tree.tree_load_failed.disconnect(_on_tree_load_failed)
	if FriendDexSyncService.sync_completed.is_connected(_on_friends_sync_completed):
		FriendDexSyncService.sync_completed.disconnect(_on_friends_sync_completed)
	if FriendDexSyncService.sync_failed.is_connected(_on_friends_sync_failed):
		FriendDexSyncService.sync_failed.disconnect(_on_friends_sync_failed)
