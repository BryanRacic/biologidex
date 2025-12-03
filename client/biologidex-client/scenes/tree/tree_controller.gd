@tool
"""
TreeController - Orchestrates radial taxonomic tree visualization.
Uses InteractiveBackground for pan/zoom gestures.
Refactored to remove SubViewport and use direct Node2D transforms.
"""
extends BaseSceneNode

const APITypes = preload("res://features/server_interface/api/core/api_types.gd")
const TreeRenderer = preload("res://features/tree/tree_renderer.gd")
const BackgroundTouchController = preload("res://features/ui/components/interactive_background/background_touch_controller.gd")

# Editor preview: Load tree from cached JSON file for UI development
const EDITOR_PREVIEW_PATH: String = "res://resources/tree.json"
@export var editor_preview: bool = false:
	set(value):
		editor_preview = value
		if Engine.is_editor_hint() and value:
			_load_editor_preview()

# Node references
@onready var tree_graph: Node2D = %TreeGraph
@onready var interactive_bg: Control = %InteractiveBackground
@onready var search_bar: LineEdit = %SearchBar
@onready var mode_dropdown: OptionButton = %ModeDropdown
@onready var zoom_in_button: Button = %ZoomInButton
@onready var zoom_out_button: Button = %ZoomOutButton
@onready var zoom_reset_button: Button = %ZoomResetButton
@onready var center_button: Button = %CenterButton
@onready var loading_label: Label = %LoadingLabel
@onready var stats_label: Label = %StatsLabel

# Touch controller reference (from InteractiveBackground)
var touch_controller: BackgroundTouchController = null

# Tree data
var current_tree_data: TreeDataModels.TreeData = null
var current_mode: APITypes.TreeMode = APITypes.TreeMode.FRIENDS
var selected_friend_ids: Array = []

# Renderer
var tree_renderer: TreeRenderer = null

# State
var is_initialized: bool = false

# Transform state (synced with touch controller)
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

	if not tree_renderer and tree_graph:
		_setup_renderer_for_editor()

	_render_tree()


func _setup_renderer_for_editor() -> void:
	"""Setup renderer in editor mode."""
	tree_renderer = TreeRenderer.new()
	tree_renderer.name = "EditorTreeRenderer"
	tree_graph.add_child(tree_renderer)
	tree_renderer.setup_containers(%EdgesLayer, %NodesLayer, %LabelsLayer)
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

	# Get viewport center for transform calculations
	await get_tree().process_frame
	_viewport_center = get_viewport_rect().size / 2.0

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

	# Setup touch controller integration
	_setup_touch_controller()

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

	# Initial load
	load_tree()


func _setup_touch_controller() -> void:
	"""Connect to InteractiveBackground's touch controller."""
	if not interactive_bg:
		push_error("[TreeController] InteractiveBackground not found")
		return

	# Get the TouchController child
	touch_controller = interactive_bg.get_node_or_null("TouchController")
	if not touch_controller:
		push_error("[TreeController] TouchController not found in InteractiveBackground")
		return

	# Connect to scroll/scale signals
	touch_controller.scroll_changed.connect(_on_scroll_changed)
	touch_controller.scale_changed.connect(_on_scale_changed)

	# Initialize with current values
	_scroll_offset = touch_controller.scroll_offset
	_current_scale = touch_controller.current_scale

	print("[TreeController] Touch controller connected")


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
	tree_renderer.setup_containers(%EdgesLayer, %NodesLayer, %LabelsLayer)

	# Connect renderer signals
	tree_renderer.node_selected.connect(_on_node_selected)
	tree_renderer.node_hovered.connect(_on_node_hovered)
	tree_renderer.node_unhovered.connect(_on_node_unhovered)

	print("[TreeController] TreeRenderer initialized")


# =============================================================================
# Transform Handling
# =============================================================================

func _on_scroll_changed(offset: Vector2) -> void:
	"""Handle scroll offset changes from touch controller."""
	_scroll_offset = offset
	_update_tree_transform()


func _on_scale_changed(new_scale: float) -> void:
	"""Handle scale changes from touch controller."""
	_current_scale = new_scale
	_update_tree_transform()


func _update_tree_transform() -> void:
	"""Apply current scroll/scale to tree graph."""
	if not tree_graph:
		return

	# Transform: scale, then translate
	# Tree origin (0,0) should appear at viewport center minus scroll offset
	var transform = Transform2D()
	transform = transform.scaled(Vector2(_current_scale, _current_scale))
	transform.origin = _viewport_center - _scroll_offset * _current_scale

	tree_graph.transform = transform

	# Update renderer for culling/labels
	if tree_renderer:
		tree_renderer.update_view(_scroll_offset, _current_scale, _viewport_center)


func _process(_delta: float) -> void:
	"""Update viewport center on resize."""
	if Engine.is_editor_hint():
		return

	var new_center = get_viewport_rect().size / 2.0
	if new_center != _viewport_center:
		_viewport_center = new_center
		_update_tree_transform()


# =============================================================================
# Zoom Controls
# =============================================================================

func _on_zoom_in() -> void:
	"""Zoom in via button."""
	if touch_controller:
		var new_scale = clampf(_current_scale * 1.2, touch_controller.min_scale, touch_controller.max_scale)
		touch_controller.current_scale = new_scale
		touch_controller.scale_changed.emit(new_scale)


func _on_zoom_out() -> void:
	"""Zoom out via button."""
	if touch_controller:
		var new_scale = clampf(_current_scale / 1.2, touch_controller.min_scale, touch_controller.max_scale)
		touch_controller.current_scale = new_scale
		touch_controller.scale_changed.emit(new_scale)


func _on_zoom_reset() -> void:
	"""Reset zoom and position."""
	if touch_controller:
		touch_controller.reset()


func _on_center_on_root() -> void:
	"""Center view on tree root (center of radial layout)."""
	if touch_controller:
		# Reset scroll to center (root is at 0,0 in radial layout)
		touch_controller.scroll_offset = Vector2.ZERO
		touch_controller.scroll_changed.emit(Vector2.ZERO)


# =============================================================================
# Tree Loading
# =============================================================================

func load_tree(use_cache: bool = true) -> void:
	"""Load tree data from API."""
	if is_loading:
		return

	is_loading = true
	_show_loading(true)

	print("[TreeController] Loading tree (mode: %s, layout: radial)" % APITypes.get_tree_mode_string(current_mode))

	# Request radial layout from server
	APIManager.tree.fetch_tree(current_mode, selected_friend_ids, use_cache, "radial")


func _on_tree_loaded(tree_data: TreeDataModels.TreeData) -> void:
	"""Handle successful tree load."""
	print("[TreeController] Tree loaded: %d nodes, %d edges" % [tree_data.nodes.size(), tree_data.edges.size()])

	current_tree_data = tree_data
	is_loading = false
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
	_update_tree_transform()
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
			# Set scroll offset to center on this position
			if touch_controller:
				touch_controller.scroll_offset = pos * _current_scale
				touch_controller.scroll_changed.emit(touch_controller.scroll_offset)
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

func _show_loading(show: bool) -> void:
	"""Show/hide loading indicator."""
	if loading_label:
		loading_label.visible = show


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
