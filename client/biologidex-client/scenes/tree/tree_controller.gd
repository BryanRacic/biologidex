@tool
"""
TreeController - Orchestrates radial taxonomic tree visualization.
Uses PaperCameraScene for pan/zoom gestures and TreeVisualization component for rendering.
Refactored to use composition pattern for tree rendering.
"""
extends BaseSceneNode

const APITypes = preload("res://features/server_interface/api/core/api_types.gd")

# Editor preview: Load tree from cached JSON file for UI development
const EDITOR_PREVIEW_PATH: String = "res://resources/tree.json"
@export var editor_preview: bool = false:
	set(value):
		editor_preview = value
		if Engine.is_editor_hint() and value:
			_load_editor_preview()

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

# TreeVisualization component (replaces inline tree logic)
var _tree_visualization: TreeVisualization = null

# Mode state
var current_mode: APITypes.TreeMode = APITypes.TreeMode.FRIENDS
var selected_friend_ids: Array = []

# State
var is_initialized: bool = false


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

	# For editor preview, create a minimal TreeVisualization
	if not _tree_visualization:
		_setup_tree_visualization_for_editor()

	var tree_data = TreeDataModels.TreeData.new(response)
	if _tree_visualization and _tree_visualization.tree_renderer:
		_tree_visualization.tree_renderer.render_tree(tree_data)


func _setup_tree_visualization_for_editor() -> void:
	"""Setup TreeVisualization in editor mode."""
	if not _paper_camera:
		_paper_camera = get_node_or_null("PaperCameraScene")
	if not _paper_camera or not _paper_camera.content_container:
		push_warning("[TreeController] Cannot setup editor preview: PaperCameraScene not ready")
		return

	_tree_visualization = TreeVisualization.new()
	_tree_visualization.name = "EditorTreeVisualization"
	_tree_visualization.auto_load_on_ready = false  # Don't auto-load in editor
	_paper_camera.content_container.add_child(_tree_visualization)
	_tree_visualization.setup(_paper_camera)


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

	# Check for friend context from navigation
	if NavigationManager.has_context():
		var context: Dictionary = NavigationManager.get_context()
		if context.has("user_id"):
			current_mode = APITypes.TreeMode.SELECTED
			selected_friend_ids = [context.get("user_id")]
			NavigationManager.clear_context()

	# Setup mode dropdown
	_setup_mode_dropdown()

	# Setup TreeVisualization component
	_setup_tree_visualization()

	# Connect search signals
	APIManager.tree.search_results_received.connect(_on_search_results)
	APIManager.tree.search_failed.connect(_on_search_failed)


func _setup_mode_dropdown() -> void:
	"""Setup mode selection dropdown."""
	mode_dropdown.clear()
	mode_dropdown.add_item("Personal", APITypes.TreeMode.PERSONAL)
	mode_dropdown.add_item("Friends", APITypes.TreeMode.FRIENDS)
	mode_dropdown.add_item("Selected", APITypes.TreeMode.SELECTED)
	mode_dropdown.select(APITypes.TreeMode.FRIENDS)


func _setup_tree_visualization() -> void:
	"""Setup TreeVisualization component (composition pattern)."""
	# Create TreeVisualization dynamically (web export compatibility)
	_tree_visualization = TreeVisualization.new()
	_tree_visualization.name = "TreeVisualization"
	_tree_visualization.initial_mode = current_mode
	_tree_visualization.auto_load_on_ready = true
	_paper_camera.content_container.add_child(_tree_visualization)

	# Set selected friends if in SELECTED mode
	if selected_friend_ids.size() > 0:
		_tree_visualization.set_selected_friends(selected_friend_ids)

	# Setup with paper camera
	_tree_visualization.setup(_paper_camera)

	# Connect TreeVisualization signals
	_tree_visualization.tree_loaded.connect(_on_tree_loaded)
	_tree_visualization.tree_load_failed.connect(_on_tree_load_failed)
	_tree_visualization.node_selected.connect(_on_node_selected)
	_tree_visualization.node_hovered.connect(_on_node_hovered)
	_tree_visualization.node_unhovered.connect(_on_node_unhovered)
	_tree_visualization.loading_started.connect(func(): _show_loading(true))
	_tree_visualization.loading_finished.connect(func(): _show_loading(false))

	print("[TreeController] TreeVisualization initialized")


# =============================================================================
# Tree Events
# =============================================================================

func _on_tree_loaded(tree_data: TreeDataModels.TreeData) -> void:
	"""Handle successful tree load."""
	is_initialized = true
	_update_stats_display(tree_data)

	# Center on root after loading
	_on_center_on_root()


func _on_tree_load_failed(error: APITypes.APIError) -> void:
	"""Handle tree load failure."""
	push_error("[TreeController] Failed to load tree: ", error.message)
	stats_label.text = "Error: " + error.message
	stats_label.add_theme_color_override("font_color", Color.RED)


# =============================================================================
# Zoom Controls
# =============================================================================

func _on_zoom_in() -> void:
	"""Zoom in via button."""
	if _paper_camera:
		var current_zoom = _paper_camera.get_current_zoom()
		var new_zoom = clampf(current_zoom * 1.2, _paper_camera.min_zoom, _paper_camera.max_zoom)
		_paper_camera.set_zoom(new_zoom)


func _on_zoom_out() -> void:
	"""Zoom out via button."""
	if _paper_camera:
		var current_zoom = _paper_camera.get_current_zoom()
		var new_zoom = clampf(current_zoom / 1.2, _paper_camera.min_zoom, _paper_camera.max_zoom)
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
		_tree_visualization.set_mode(current_mode, false)
		_tree_visualization.load_tree()


func _show_friend_selection() -> void:
	"""Show friend selection UI for SELECTED mode."""
	print("[TreeController] Friend selection UI not yet implemented, using all friends")
	_tree_visualization.set_mode(current_mode, false)
	_tree_visualization.load_tree()


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
	"""Handle node selection from TreeVisualization."""
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
	"""Handle node hover from TreeVisualization."""
	pass


func _on_node_unhovered() -> void:
	"""Handle node unhover from TreeVisualization."""
	pass


# =============================================================================
# UI Updates
# =============================================================================

func _show_loading(should_show: bool) -> void:
	"""Show/hide loading indicator."""
	if loading_label:
		loading_label.visible = should_show


func _update_stats_display(tree_data: TreeDataModels.TreeData) -> void:
	"""Update stats label with current tree info."""
	if not tree_data or not stats_label:
		return

	var stats = tree_data.stats
	var metadata = tree_data.metadata

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
		if _tree_visualization:
			_tree_visualization.queue_free()
			_tree_visualization = null
		return

	print("[TreeController] Cleaning up")

	# TreeVisualization handles its own cleanup in _exit_tree()

	if APIManager.tree.search_results_received.is_connected(_on_search_results):
		APIManager.tree.search_results_received.disconnect(_on_search_results)
	if APIManager.tree.search_failed.is_connected(_on_search_failed):
		APIManager.tree.search_failed.disconnect(_on_search_failed)
