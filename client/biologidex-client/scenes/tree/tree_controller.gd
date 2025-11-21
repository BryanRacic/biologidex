"""
TreeController - Main orchestrator for taxonomic tree visualization.
Coordinates data loading, rendering, and user interaction.
"""
extends Control

const APITypes = preload("res://features/server_interface/api/core/api_types.gd")
const TreeRenderer = preload("res://features/tree/tree_renderer.gd")

# Services
var APIManager
var NavigationManager

# Node references (assigned in _ready)
@onready var back_button: Button = $VBoxContainer/Toolbar/BackButton
@onready var search_bar: LineEdit = $VBoxContainer/Toolbar/SearchBar
@onready var mode_dropdown: OptionButton = $VBoxContainer/Toolbar/ModeDropdown
@onready var zoom_in_button: Button = $VBoxContainer/Toolbar/ZoomControls/ZoomInButton
@onready var zoom_out_button: Button = $VBoxContainer/Toolbar/ZoomControls/ZoomOutButton
@onready var zoom_reset_button: Button = $VBoxContainer/Toolbar/ZoomControls/ZoomResetButton
@onready var loading_label: Label = $VBoxContainer/LoadingLabel
@onready var stats_label: Label = $VBoxContainer/StatsLabel
@onready var viewport_container: SubViewportContainer = $VBoxContainer/ViewportContainer
@onready var sub_viewport: SubViewport = $VBoxContainer/ViewportContainer/SubViewport
@onready var tree_world: Node2D = $VBoxContainer/ViewportContainer/SubViewport/TreeWorld
@onready var tree_camera: Camera2D = $VBoxContainer/ViewportContainer/SubViewport/TreeWorld/Camera2D

# Tree data
var current_tree_data: TreeDataModels.TreeData = null
var current_mode: APITypes.TreeMode = APITypes.TreeMode.FRIENDS
var selected_friend_ids: Array = []  # Array of UUID strings

# Renderer
var tree_renderer: TreeRenderer = null

# State
var is_loading: bool = false
var is_initialized: bool = false

# Camera control state
var is_panning: bool = false
var last_mouse_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	print("[TreeController] Initializing tree view")

	# Initialize services (with fallback to autoloads)
	_initialize_services()

	# Connect UI signals
	search_bar.text_submitted.connect(_on_search_submitted)
	mode_dropdown.item_selected.connect(_on_mode_selected)
	zoom_in_button.pressed.connect(_on_zoom_in)
	zoom_out_button.pressed.connect(_on_zoom_out)
	zoom_reset_button.pressed.connect(_on_zoom_reset)

	# Connect API signals
	APIManager.tree.tree_loaded.connect(_on_tree_loaded)
	APIManager.tree.tree_load_failed.connect(_on_tree_load_failed)
	APIManager.tree.search_results_received.connect(_on_search_results)
	APIManager.tree.search_failed.connect(_on_search_failed)

	# Check for friend context from navigation (viewing friend's tree)
	if NavigationManager.has_context():
		var context: Dictionary = NavigationManager.get_context()
		if context.has("user_id"):
			var friend_id: String = context.get("user_id")
			print("[TreeController] Loading friend's tree: ", friend_id)
			# Set mode to selected friend and add their ID
			current_mode = APITypes.TreeMode.SELECTED
			selected_friend_ids = [friend_id]
			# Clear context
			NavigationManager.clear_context()


func _initialize_services() -> void:
	"""Initialize service references from autoloads"""
	APIManager = get_node("/root/APIManager")
	NavigationManager = get_node("/root/NavigationManager")

	# Setup mode dropdown
	_setup_mode_dropdown()

	# Setup viewport
	_setup_viewport()

	# Setup renderer
	_setup_renderer()

	# Initial load
	await get_tree().process_frame
	load_tree()


func _setup_mode_dropdown() -> void:
	"""Setup mode selection dropdown."""
	mode_dropdown.clear()
	mode_dropdown.add_item("Personal", APITypes.TreeMode.PERSONAL)
	mode_dropdown.add_item("Friends", APITypes.TreeMode.FRIENDS)
	mode_dropdown.add_item("Selected", APITypes.TreeMode.SELECTED)
	# Don't add Global mode for non-admin users
	mode_dropdown.select(APITypes.TreeMode.FRIENDS)


func _setup_viewport() -> void:
	"""Setup SubViewport for rendering."""
	sub_viewport.size = Vector2i(1280, 720)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _setup_renderer() -> void:
	"""Setup TreeRenderer for visualization."""
	tree_renderer = TreeRenderer.new()
	tree_renderer.name = "TreeRenderer"
	tree_world.add_child(tree_renderer)

	# Set camera reference
	tree_renderer.set_camera(tree_camera)

	# Connect renderer signals
	tree_renderer.node_selected.connect(_on_node_selected)
	tree_renderer.node_hovered.connect(_on_node_hovered)
	tree_renderer.node_unhovered.connect(_on_node_unhovered)

	print("[TreeController] TreeRenderer initialized")


# =============================================================================
# Tree Loading
# =============================================================================

func load_tree(use_cache: bool = true) -> void:
	"""Load tree data from API."""
	if is_loading:
		print("[TreeController] Already loading, skipping")
		return

	is_loading = true
	_show_loading(true)

	print("[TreeController] Loading tree (mode: ", APITypes.get_tree_mode_string(current_mode), ")")

	# Fetch from API
	APIManager.tree.fetch_tree(current_mode, selected_friend_ids, use_cache)


func _on_tree_loaded(tree_data: TreeDataModels.TreeData) -> void:
	"""Handle successful tree load."""
	print("[TreeController] Tree loaded successfully")
	print("[TreeController] Nodes: ", tree_data.nodes.size())
	print("[TreeController] Edges: ", tree_data.edges.size())

	current_tree_data = tree_data
	is_loading = false
	is_initialized = true

	_show_loading(false)
	_update_stats_display()
	_render_tree()


func _on_tree_load_failed(error: APITypes.APIError) -> void:
	"""Handle tree load failure."""
	push_error("[TreeController] Failed to load tree: ", error.message)
	is_loading = false
	_show_loading(false)

	# Show error message
	stats_label.text = "Error: " + error.message
	stats_label.add_theme_color_override("font_color", Color.RED)


func reload_tree() -> void:
	"""Reload tree from server (bypass cache)."""
	print("[TreeController] Reloading tree (no cache)")
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

	var bounds = current_tree_data.layout.world_bounds
	print("[TreeController] World bounds: ", bounds)
	print("[TreeController] Chunk size: ", current_tree_data.layout.chunk_size)

	# Position camera at center of tree
	if tree_camera:
		var center = bounds.get_center()
		tree_camera.position = center
		print("[TreeController] Camera positioned at: ", center)

	# Render tree with TreeRenderer
	tree_renderer.render_tree(current_tree_data)

	# Log rendering stats
	var stats = tree_renderer.get_stats()
	print("[TreeController] Rendered %d/%d nodes, %d/%d edges" % [
		stats.visible_nodes,
		stats.total_nodes,
		stats.rendered_edges,
		stats.total_edges
	])

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

	# If selected mode, show friend selection UI
	if current_mode == APITypes.TreeMode.SELECTED:
		_show_friend_selection()
	else:
		# Reload tree with new mode
		load_tree()


func _show_friend_selection() -> void:
	"""Show friend selection UI for SELECTED mode."""
	# TODO: Implement friend selection UI
	# For now, just use all friends
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

	# TODO: Implement search results UI
	# For now, just focus camera on first result
	if results.size() > 0:
		var first_result = results[0] as Dictionary
		var position_array = first_result.get("position", [0, 0])
		if position_array is Array and position_array.size() >= 2:
			var position = Vector2(position_array[0], position_array[1])
			if tree_camera:
				tree_camera.position = position
				print("[TreeController] Focused on: ", first_result.get("scientific_name", ""))


func _on_search_failed(error: APITypes.APIError) -> void:
	"""Handle search failure."""
	push_error("[TreeController] Search failed: ", error.message)
	stats_label.text = "Search error: " + error.message
	stats_label.add_theme_color_override("font_color", Color.RED)


func _on_zoom_in() -> void:
	"""Handle zoom in button."""
	if tree_camera:
		var current_zoom = tree_camera.zoom.x
		tree_camera.zoom = Vector2(current_zoom * 1.2, current_zoom * 1.2)
		print("[TreeController] Zoomed in to: ", tree_camera.zoom.x)

		# Update renderer view
		if tree_renderer:
			tree_renderer.update_view()


func _on_zoom_out() -> void:
	"""Handle zoom out button."""
	if tree_camera:
		var current_zoom = tree_camera.zoom.x
		tree_camera.zoom = Vector2(current_zoom / 1.2, current_zoom / 1.2)
		print("[TreeController] Zoomed out to: ", tree_camera.zoom.x)

		# Update renderer view
		if tree_renderer:
			tree_renderer.update_view()


func _on_zoom_reset() -> void:
	"""Handle zoom reset button."""
	if tree_camera:
		tree_camera.zoom = Vector2(1, 1)
		if current_tree_data:
			var center = current_tree_data.layout.world_bounds.get_center()
			tree_camera.position = center
		print("[TreeController] Zoom reset")

		# Update renderer view
		if tree_renderer:
			tree_renderer.update_view()


func _on_back_button_pressed() -> void:
	"""Handle back button press."""
	print("[TreeController] Back button pressed")
	NavigationManager.go_back()


func _input(event: InputEvent) -> void:
	"""Handle input events for camera control."""
	if not tree_camera or not is_initialized:
		return

	# Middle mouse button or right mouse button for panning
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton

		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE or mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			if mouse_event.pressed:
				is_panning = true
				last_mouse_position = mouse_event.position
			else:
				is_panning = false

		# Scroll wheel for zoom
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_on_zoom_in()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_on_zoom_out()

	# Mouse motion for panning
	elif event is InputEventMouseMotion and is_panning:
		var motion_event = event as InputEventMouseMotion
		var delta = motion_event.position - last_mouse_position
		last_mouse_position = motion_event.position

		# Move camera (invert delta and scale by zoom)
		var zoom_factor = 1.0 / tree_camera.zoom.x
		tree_camera.position -= delta * zoom_factor

		# Update renderer view
		if tree_renderer:
			tree_renderer.update_view()


func _on_node_selected(node: TreeDataModels.TaxonomicNode) -> void:
	"""Handle node selection from renderer."""
	if node.is_taxonomic():
		# Taxonomy node selected - show taxonomic information
		print("[TreeController] Taxonomy node selected: %s (rank: %s)" % [node.name, _get_rank_name(node.rank)])

		var info = "%s (Rank: %s)" % [node.name, _get_rank_name(node.rank)]
		if node.children_count > 0:
			info += " - %d children" % node.children_count

		stats_label.text = info
		stats_label.remove_theme_color_override("font_color")
	else:
		# Animal node selected - show dex information
		print("[TreeController] Node selected: %s" % node.scientific_name)

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


func _on_node_hovered(node: TreeDataModels.TaxonomicNode) -> void:
	"""Handle node hover from renderer."""
	# Could show tooltip here in the future
	pass


func _on_node_unhovered() -> void:
	"""Handle node unhover from renderer."""
	# Could hide tooltip here in the future
	pass


# =============================================================================
# UI Updates
# =============================================================================

func _show_loading(show: bool) -> void:
	"""Show/hide loading indicator."""
	if loading_label:
		loading_label.visible = show
		if show:
			loading_label.text = "Loading tree..."


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
	print("[TreeController] Stats updated: ", stats_text)


# =============================================================================
# Cleanup
# =============================================================================

func _exit_tree() -> void:
	"""Cleanup when exiting tree view."""
	print("[TreeController] Cleaning up")

	# Clean up renderer
	if tree_renderer:
		tree_renderer.clear()
		tree_renderer.queue_free()
		tree_renderer = null

	# Disconnect signals
	if APIManager.tree.tree_loaded.is_connected(_on_tree_loaded):
		APIManager.tree.tree_loaded.disconnect(_on_tree_loaded)
	if APIManager.tree.tree_load_failed.is_connected(_on_tree_load_failed):
		APIManager.tree.tree_load_failed.disconnect(_on_tree_load_failed)
