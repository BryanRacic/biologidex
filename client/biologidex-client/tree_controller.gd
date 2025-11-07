"""
TreeController - Main orchestrator for taxonomic tree visualization.
Coordinates data loading, rendering, and user interaction.
"""
extends Control

const APITypes = preload("res://api/core/api_types.gd")

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
var selected_friend_ids: Array[int] = []

# State
var is_loading: bool = false
var is_initialized: bool = false


func _ready() -> void:
	print("[TreeController] Initializing tree view")

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

	# Setup mode dropdown
	_setup_mode_dropdown()

	# Setup viewport
	_setup_viewport()

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


func _on_tree_load_failed(error: String) -> void:
	"""Handle tree load failure."""
	push_error("[TreeController] Failed to load tree: ", error)
	is_loading = false
	_show_loading(false)

	# Show error message
	stats_label.text = "Error: " + error
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

	print("[TreeController] Rendering tree...")

	# For now, just log the data
	# Full rendering implementation will be added with TreeRenderer

	var bounds = current_tree_data.layout.world_bounds
	print("[TreeController] World bounds: ", bounds)
	print("[TreeController] Chunk size: ", current_tree_data.layout.chunk_size)

	# Position camera at center of tree
	if tree_camera:
		var center = bounds.get_center()
		tree_camera.position = center
		print("[TreeController] Camera positioned at: ", center)

	# TODO: Implement actual rendering with MultiMeshInstance2D
	# This will be done in tree_renderer.gd
	print("[TreeController] Rendering complete (placeholder)")


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


func _on_search_failed(error: String) -> void:
	"""Handle search failure."""
	push_error("[TreeController] Search failed: ", error)
	stats_label.text = "Search error: " + error
	stats_label.add_theme_color_override("font_color", Color.RED)


func _on_zoom_in() -> void:
	"""Handle zoom in button."""
	if tree_camera:
		var current_zoom = tree_camera.zoom.x
		tree_camera.zoom = Vector2(current_zoom * 1.2, current_zoom * 1.2)
		print("[TreeController] Zoomed in to: ", tree_camera.zoom.x)


func _on_zoom_out() -> void:
	"""Handle zoom out button."""
	if tree_camera:
		var current_zoom = tree_camera.zoom.x
		tree_camera.zoom = Vector2(current_zoom / 1.2, current_zoom / 1.2)
		print("[TreeController] Zoomed out to: ", tree_camera.zoom.x)


func _on_zoom_reset() -> void:
	"""Handle zoom reset button."""
	if tree_camera:
		tree_camera.zoom = Vector2(1, 1)
		if current_tree_data:
			var center = current_tree_data.layout.world_bounds.get_center()
			tree_camera.position = center
		print("[TreeController] Zoom reset")


func _on_back_button_pressed() -> void:
	"""Handle back button press."""
	print("[TreeController] Back button pressed")
	NavigationManager.go_back()


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

	# Disconnect signals
	if APIManager.tree.tree_loaded.is_connected(_on_tree_loaded):
		APIManager.tree.tree_loaded.disconnect(_on_tree_loaded)
	if APIManager.tree.tree_load_failed.is_connected(_on_tree_load_failed):
		APIManager.tree.tree_load_failed.disconnect(_on_tree_load_failed)
