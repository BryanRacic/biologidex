@tool
"""
TreeController - Orchestrates radial taxonomic tree visualization.
Uses PaperCameraScene for pan/zoom gestures.
Refactored to remove SubViewport and use direct Node2D transforms.
"""
extends BaseSceneNode

const APITypes = preload("res://features/server_interface/api/core/api_types.gd")
const TreeRenderer = preload("res://features/tree/tree_renderer.gd")

# Editor preview: Load tree from cached JSON file for UI development
const EDITOR_PREVIEW_PATH: String = "res://resources/tree.json"
@export var editor_preview: bool = false:
	set(value):
		editor_preview = value
		if Engine.is_editor_hint() and value:
			_load_editor_preview()

# Node references (TreeGraph created dynamically to avoid web export bug GitHub #101975)
var tree_graph: Node2D = null
var _edges_layer: Node2D = null
var _nodes_layer: Node2D = null
var _labels_layer: Node2D = null
var _dex_images_layer: Node2D = null

# UI node references - using explicit paths to work around web export unique name issues
var _paper_camera: PaperCameraScene = null
var search_bar: LineEdit = null
var mode_dropdown: OptionButton = null
var zoom_in_button: Button = null
var zoom_out_button: Button = null
var zoom_reset_button: Button = null
var center_button: Button = null
var loading_label: Label = null
var stats_label: Label = null

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

# View state (for TreeRenderer culling - Camera2D handles actual transform)
var _scroll_offset: Vector2 = Vector2.ZERO
var _current_scale: float = 1.0
var _viewport_center: Vector2 = Vector2.ZERO


# =============================================================================
# Editor Preview
# =============================================================================

func _load_editor_preview() -> void:
	"""Load tree data from cached JSON for editor preview."""
	if not Engine.is_editor_hint():
		return

	print("[TreeController] Loading editor preview from: ", EDITOR_PREVIEW_PATH)

	if not FileAccess.file_exists(EDITOR_PREVIEW_PATH):
		push_warning("[TreeController] Editor preview file not found: %s" % EDITOR_PREVIEW_PATH)
		return

	var file = FileAccess.open(EDITOR_PREVIEW_PATH, FileAccess.READ)
	if not file:
		push_error("[TreeController] Failed to open editor preview file")
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("[TreeController] Failed to parse editor preview JSON: %s" % json.get_error_message())
		return

	var response = json.data as Dictionary
	if not response:
		push_error("[TreeController] Editor preview JSON is not a valid dictionary")
		return

	print("[TreeController] Loaded %d nodes, %d edges from cache" % [
		response.get("nodes", []).size(),
		response.get("edges", []).size()
	])

	current_tree_data = TreeDataModels.TreeData.new(response)

	if not tree_renderer:
		_setup_renderer_for_editor()

	_render_tree()


func _setup_renderer_for_editor() -> void:
	"""Setup renderer in editor mode (also creates TreeGraph dynamically)."""
	# Create TreeGraph and layers for editor preview
	if not _paper_camera:
		_paper_camera = get_node_or_null("PaperCameraScene")
	if not _paper_camera or not _paper_camera.content_container:
		push_warning("[TreeController] Cannot setup editor preview: PaperCameraScene not ready")
		return

	tree_graph = Node2D.new()
	tree_graph.name = "EditorTreeGraph"
	_paper_camera.content_container.add_child(tree_graph)

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

	tree_renderer = TreeRenderer.new()
	tree_renderer.name = "EditorTreeRenderer"
	tree_graph.add_child(tree_renderer)
	tree_renderer.setup_containers(_edges_layer, _nodes_layer, _labels_layer, _dex_images_layer)
	print("[TreeController] Editor TreeRenderer initialized")


# =============================================================================
# Initialization
# =============================================================================

func _on_scene_ready() -> void:
	"""Called by BaseSceneNode after managers are initialized."""
	if Engine.is_editor_hint():
		return

	scene_name = "TreeController"
	print("[TreeController] Scene ready (radial layout)")

	# Initialize node references using explicit paths (web export unique name workaround)
	_paper_camera = $PaperCameraScene
	back_button = $UILayer/Control/VBoxContainer/Header/BackButton
	search_bar = $UILayer/Control/VBoxContainer/Header/SearchBar
	mode_dropdown = $UILayer/Control/VBoxContainer/Header/ModeDropdown
	zoom_in_button = $UILayer/Control/VBoxContainer/Header/ZoomControls/ZoomInButton
	zoom_out_button = $UILayer/Control/VBoxContainer/Header/ZoomControls/ZoomOutButton
	zoom_reset_button = $UILayer/Control/VBoxContainer/Header/ZoomControls/ZoomResetButton
	center_button = $UILayer/Control/VBoxContainer/Header/ZoomControls/CenterButton
	loading_label = $UILayer/Control/VBoxContainer/LoadingLabel
	stats_label = $UILayer/Control/VBoxContainer/StatsLabel

	# Wire up back button
	if back_button and not back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.connect(_on_back_pressed)

	# Connect UI signals
	search_bar.text_submitted.connect(_on_search_submitted)
	mode_dropdown.item_selected.connect(_on_mode_selected)
	zoom_in_button.pressed.connect(_on_zoom_in)
	zoom_out_button.pressed.connect(_on_zoom_out)
	zoom_reset_button.pressed.connect(_on_zoom_reset)
	center_button.pressed.connect(_on_center_on_root)

	# Setup PaperCameraScene integration
	_setup_paper_camera()

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

	# Connect friend sync signals
	FriendDexSyncService.sync_completed.connect(_on_friends_sync_completed)
	FriendDexSyncService.sync_failed.connect(_on_friends_sync_failed)

	# Start friend sync and tree load in parallel
	_start_parallel_load()


func _setup_paper_camera() -> void:
	"""Connect to PaperCameraScene signals."""
	if not _paper_camera:
		push_error("[TreeController] PaperCameraScene not found")
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

	print("[TreeController] PaperCameraScene connected (initial scale: %.1f)" % _current_scale)


func _setup_mode_dropdown() -> void:
	"""Setup mode selection dropdown."""
	mode_dropdown.clear()
	mode_dropdown.add_item("Personal", APITypes.TreeMode.PERSONAL)
	mode_dropdown.add_item("Friends", APITypes.TreeMode.FRIENDS)
	mode_dropdown.add_item("Selected", APITypes.TreeMode.SELECTED)
	mode_dropdown.select(APITypes.TreeMode.FRIENDS)


func _setup_renderer() -> void:
	"""Setup TreeRenderer for visualization.
	Creates TreeGraph and layers programmatically to avoid web export bug (GitHub #101975)."""
	# Create TreeGraph and layers dynamically (can't be in .tscn as children of instanced scene)
	tree_graph = Node2D.new()
	tree_graph.name = "TreeGraph"
	_paper_camera.content_container.add_child(tree_graph)

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

	# Connect renderer signals
	tree_renderer.node_selected.connect(_on_node_selected)
	tree_renderer.node_hovered.connect(_on_node_hovered)
	tree_renderer.node_unhovered.connect(_on_node_unhovered)

	print("[TreeController] TreeRenderer initialized")


# =============================================================================
# View Change Handling (Camera2D handles transform, we just update culling state)
# =============================================================================
#
# COORDINATE SPACE CONVENTIONS:
# - Camera2D.position: The world-space position at viewport center
# - Camera2D.zoom: Scale factor (higher = zoomed in)
# - TreeGraph is a child of PaperCameraScene/WorldContent/ContentContainer
#   so it automatically transforms with the camera
# - TreeRenderer needs scroll_offset and scale for culling calculations
#
# =============================================================================

func _on_view_changed(cam_position: Vector2, zoom: float) -> void:
	"""Handle view changes from PaperCameraScene.
	Camera2D handles the actual transform - we just update renderer for culling."""
	_scroll_offset = cam_position
	_current_scale = zoom
	_viewport_center = get_viewport_rect().size / 2.0

	# Update renderer for culling/labels (no transform needed - Camera2D does it)
	if tree_renderer:
		tree_renderer.update_view(_scroll_offset, _current_scale, _viewport_center)


func _process(_delta: float) -> void:
	"""Update viewport center on resize."""
	if Engine.is_editor_hint():
		return

	var new_center = get_viewport_rect().size / 2.0
	if new_center != _viewport_center:
		_viewport_center = new_center
		# Trigger renderer update with current view state
		if tree_renderer:
			tree_renderer.update_view(_scroll_offset, _current_scale, _viewport_center)


# =============================================================================
# Zoom Controls
# =============================================================================

func _on_zoom_in() -> void:
	"""Zoom in via button."""
	if _paper_camera:
		var new_zoom = clampf(_current_scale * 1.2, _paper_camera.min_zoom, _paper_camera.max_zoom)
		_paper_camera.set_zoom(new_zoom)


func _on_zoom_out() -> void:
	"""Zoom out via button."""
	if _paper_camera:
		var new_zoom = clampf(_current_scale / 1.2, _paper_camera.min_zoom, _paper_camera.max_zoom)
		_paper_camera.set_zoom(new_zoom)


func _on_zoom_reset() -> void:
	"""Reset zoom and position."""
	if _paper_camera:
		_paper_camera.reset()


func _on_center_on_root() -> void:
	"""Center view on tree root (center of radial layout)."""
	if _paper_camera:
		# Reset scroll to center (root is at 0,0 in radial layout)
		_paper_camera.scroll_to(Vector2.ZERO, false)


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
	push_error("[TreeController] Failed to load tree: ", error.message)
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
		push_error("[TreeController] No tree data to render")
		return

	if not tree_renderer:
		push_error("[TreeController] TreeRenderer not initialized")
		return

	print("[TreeController] Rendering tree...")
	tree_renderer.render_tree(current_tree_data)

	# Initialize renderer with current view state (Camera2D handles transform)
	_viewport_center = get_viewport_rect().size / 2.0
	_scroll_offset = _paper_camera.get_camera_position()
	_current_scale = _paper_camera.get_current_zoom()
	tree_renderer.update_view(_scroll_offset, _current_scale, _viewport_center)

	print("[TreeController] Rendering complete")


# =============================================================================
# UI Interactions
# =============================================================================

func _on_mode_selected(index: int) -> void:
	"""Handle mode selection change."""
	var new_mode = mode_dropdown.get_item_id(index) as APITypes.TreeMode
	if new_mode == current_mode:
		return

	print("[TreeController] Mode changed to: ", APITypes.get_tree_mode_string(new_mode))
	current_mode = new_mode

	if current_mode == APITypes.TreeMode.SELECTED:
		_show_friend_selection()
	else:
		load_tree()


func _show_friend_selection() -> void:
	"""Show friend selection UI for SELECTED mode."""
	print("[TreeController] Friend selection UI not yet implemented, using all friends")
	load_tree()


func _on_search_submitted(query: String) -> void:
	"""Handle search query submission."""
	if query.strip_edges().is_empty():
		return

	print("[TreeController] Searching for: ", query)
	APIManager.tree.search_tree(query, current_mode, selected_friend_ids, 50)


func _on_search_results(results: Array) -> void:
	"""Handle search results."""
	print("[TreeController] Search results: ", results.size(), " found")

	if results.size() == 0:
		stats_label.text = "No results found"
		return

	# Navigate to first result
	if results.size() > 0:
		var first_result = results[0] as Dictionary
		var position_array = first_result.get("position", [0, 0])
		if position_array is Array and position_array.size() >= 2:
			var pos = Vector2(position_array[0], position_array[1])
			# Center on this position
			if _paper_camera:
				_paper_camera.scroll_to(pos, true)
				print("[TreeController] Centered on: ", first_result.get("scientific_name", ""))


func _on_search_failed(error: APITypes.APIError) -> void:
	"""Handle search failure."""
	push_error("[TreeController] Search failed: ", error.message)
	stats_label.text = "Search error: " + error.message
	stats_label.add_theme_color_override("font_color", Color.RED)


func _on_node_selected(node: TreeDataModels.TaxonomicNode) -> void:
	"""Handle node selection from renderer."""
	if node.is_taxonomic():
		print("[TreeController] Taxonomy node selected: %s (rank: %s)" % [node.name, _get_rank_name(node.rank)])
		var info = "%s (Rank: %s)" % [node.name, _get_rank_name(node.rank)]
		if node.children_count > 0:
			info += " - %d children" % node.children_count
		stats_label.text = info
	else:
		print("[TreeController] Animal node selected: %s" % node.scientific_name)
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

	print("[TreeController] Cleaning up")

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
