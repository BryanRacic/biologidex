@tool
extends Node2D

## Home scene - Main screen after login with tree background.
##
## Features:
## - TreeVisualization as the background (pan/zoom enabled)
## - World-space UI buttons that move with the tree
## - RecenterButton to return to home position
## - Navigation to main app features

# =============================================================================
# Export Variables (editable in inspector)
# =============================================================================

@export_group("Tree Settings")
## Scale of the tree visualization (larger = tree appears bigger/more zoomed in)
@export_range(0.5, 10.0, 0.1) var tree_scale: float = 1.0:
	set(value):
		tree_scale = value
		if _tree_visualization:
			_tree_visualization.tree_scale = value

@export_group("Radial Menu")
## Scale factor for the radial menu (affects all button sizes and spacing)
@export_range(0.5, 3.0, 0.1) var menu_scale: float = 1.0:
	set(value):
		menu_scale = value
		if _radial_menu:
			_apply_menu_scale()

## If enabled, adds an invisible placeholder at the top position,
## offsetting visible buttons to form a triangle below the center button.
@export var menu_placeholder_button: bool = false:
	set(value):
		menu_placeholder_button = value
		if _radial_menu:
			_radial_menu.placeholder_button = value

@export_group("Tree Background Appearance")
## Hide the root node (Kingdom) circle
@export var hide_root_node: bool = false
## Hide the root node (Kingdom) label
@export var hide_root_label: bool = false
## Base size of tree nodes in world units (larger = bigger nodes)
@export_range(5.0, 100.0, 1.0) var tree_node_size: float = 15.0
## Opacity of tree nodes (lower = more subtle)
@export_range(0.0, 1.0, 0.05) var tree_node_opacity: float = 0.6
## Width of tree edges/branches
@export_range(1.0, 20.0, 0.5) var tree_edge_width: float = 3.0
## Opacity of tree edges (lower = more subtle)
@export_range(0.0, 1.0, 0.05) var tree_edge_opacity: float = 0.4
## Size of dex images on tree (smaller = less prominent)
@export_range(200.0, 2000.0, 50.0) var tree_dex_image_size: float = 800.0
## Font size of tree labels in world units (larger = bigger text)
@export_range(20, 200, 5) var tree_label_font_size: int = 90
## Opacity of tree labels
@export_range(0.0, 1.0, 0.05) var tree_label_opacity: float = 0.7

# =============================================================================
# Services
# =============================================================================

var token_manager
var navigation_manager

# =============================================================================
# Components (created dynamically for web export compatibility)
# =============================================================================

var _paper_camera: PaperCameraScene = null
var _tree_visualization: TreeVisualization = null
var _home_ui: WorldSpaceUI = null
var _recenter_button: RecenterButton = null

# =============================================================================
# UI References (world-space)
# =============================================================================

var _radial_menu: RadialMenuCircles = null

func _ready() -> void:
	# Skip runtime logic in editor (tool script only for export var visibility)
	if Engine.is_editor_hint():
		return

	print("[Home] Scene loaded")

	# Get services from ServiceLocator
	_initialize_services()

	if not token_manager.is_logged_in():
		print("[Home] WARNING: User not logged in, redirecting to login")
		navigation_manager.navigate_to("res://scenes/login/login.tscn", true)
		return

	var username: String = token_manager.get_username()
	print("[Home] User logged in: ", username)

	# Setup components
	_setup_components()


func _initialize_services() -> void:
	"""Initialize service references from autoloads"""
	token_manager = get_node_or_null("/root/TokenManager")
	navigation_manager = get_node_or_null("/root/NavigationManager")

	if not token_manager or not navigation_manager:
		push_error("[Home] Failed to initialize required services")
		return


func _setup_components() -> void:
	"""Setup all scene components."""
	# Get PaperCameraScene reference
	_paper_camera = $PaperCameraScene

	# Configure PaperCameraScene for tree interaction
	_paper_camera.min_zoom = 0.5
	_paper_camera.max_zoom = 4.0
	_paper_camera.initial_zoom = 1.5
	_paper_camera.zoom_enabled = true
	_paper_camera.pan_enabled = true
	_paper_camera.inertia_enabled = true

	# Create TreeVisualization in world-space
	_setup_tree_visualization()

	# Create world-space UI (buttons that pan with tree)
	_setup_world_space_ui()

	# Setup recenter button (screen-space overlay)
	_setup_recenter_button()


func _setup_tree_visualization() -> void:
	"""Create and setup TreeVisualization component with home-specific styling."""
	_tree_visualization = TreeVisualization.new()
	_tree_visualization.name = "TreeVisualization"
	_tree_visualization.auto_load_on_ready = true
	_tree_visualization.initial_mode = 1  # FRIENDS mode
	_tree_visualization.use_cache = true

	# Apply tree scale
	_tree_visualization.tree_scale = tree_scale

	# Apply home-specific visual settings (subtler background appearance)
	_tree_visualization.node_size = tree_node_size
	_tree_visualization.node_opacity = tree_node_opacity
	_tree_visualization.hide_root_node = hide_root_node
	_tree_visualization.hide_root_label = hide_root_label
	_tree_visualization.edge_width = tree_edge_width
	_tree_visualization.edge_opacity = tree_edge_opacity
	_tree_visualization.dex_image_size = tree_dex_image_size
	_tree_visualization.label_font_size = tree_label_font_size
	_tree_visualization.label_opacity = tree_label_opacity

	_paper_camera.content_container.add_child(_tree_visualization)
	_tree_visualization.setup(_paper_camera)

	# Connect to tree_loaded to re-center menu when tree data arrives
	_tree_visualization.tree_loaded.connect(_on_tree_loaded)

	print("[Home] TreeVisualization initialized with background styling")


func _setup_world_space_ui() -> void:
	"""Create world-space UI container with radial menu."""
	_home_ui = WorldSpaceUI.new()
	_home_ui.name = "HomeUI"
	_home_ui.anchor_position = Vector2.ZERO  # Centered at origin
	_paper_camera.content_container.add_child(_home_ui)

	# Build radial menu UI
	_build_radial_menu()

	print("[Home] World-space UI created with radial menu")


# Base values for menu dimensions (before scaling)
const MENU_BASE_CENTER_RADIUS := 120.0
const MENU_BASE_RING_DISTANCE := 220.0
const MENU_BASE_RING_BUTTON_RADIUS := 70.0
const MENU_BASE_CENTER_ICON_SIZE := 200.0
const MENU_BASE_RING_ICON_SIZE := 120.0


func _build_radial_menu() -> void:
	"""Build the radial menu for home navigation."""

	# Create RadialMenuCircles programmatically (web export compatible)
	_radial_menu = RadialMenuCircles.new()
	_radial_menu.name = "RadialMenu"

	# Make buttons transparent (icon-only style)
	_radial_menu.center_normal_color = Color.TRANSPARENT
	_radial_menu.center_hover_color = Color(0, 0, 0, 0.1)
	_radial_menu.center_pressed_color = Color(0, 0, 0, 0.2)
	_radial_menu.center_border_width = 0.0
	_radial_menu.ring_normal_color = Color.TRANSPARENT
	_radial_menu.ring_hover_color = Color(0, 0, 0, 0.1)
	_radial_menu.ring_pressed_color = Color(0, 0, 0, 0.2)
	_radial_menu.ring_border_width = 0.0

	# Configure icon colors
	_radial_menu.center_icon_color = Color.BLACK
	_radial_menu.ring_icon_color = Color.BLACK

	# Load icons
	var icon_camera: Texture2D = load("res://resources/icons/kenny_board-game-icons/card_add.svg")
	var icon_friends: Texture2D = load("res://resources/icons/kenny_board-game-icons/pawns.svg")
	var icon_dex: Texture2D = load("res://resources/icons/kenny_board-game-icons/book_closed.svg")

	# Apply scaled dimensions BEFORE adding to tree (so _ready() uses correct values)
	_radial_menu.center_radius = MENU_BASE_CENTER_RADIUS * menu_scale
	_radial_menu.ring_distance = MENU_BASE_RING_DISTANCE * menu_scale
	_radial_menu.ring_button_radius = MENU_BASE_RING_BUTTON_RADIUS * menu_scale
	_radial_menu.placeholder_button = menu_placeholder_button
	# Position ring buttons at top (-PI/2) so placeholder is at top, visible buttons below
	_radial_menu.start_angle = -PI / 2
	var center_icon := MENU_BASE_CENTER_ICON_SIZE * menu_scale
	var ring_icon := MENU_BASE_RING_ICON_SIZE * menu_scale
	_radial_menu.center_icon_size = Vector2(center_icon, center_icon)
	_radial_menu.ring_icon_size = Vector2(ring_icon, ring_icon)

	# Add to world-space UI (triggers _ready() which sets up sizing with our values)
	_home_ui.add_child(_radial_menu)

	# Center at origin immediately (size is now correct from _ready())
	_radial_menu.center_at_position(Vector2.ZERO)

	# Configure center button with icon (primary action)
	_radial_menu.set_center_button("camera", "", icon_camera)

	# Configure ring buttons with icons (navigation - evenly distributed around center)
	# NOTE: Feed and Settings temporarily disabled for troubleshooting
	#_radial_menu.add_ring_button("feed", "Feed")
	_radial_menu.add_ring_button("dex", "", icon_dex)
	_radial_menu.add_ring_button("social", "", icon_friends)
	#_radial_menu.add_ring_button("settings", "Settings")

	# Connect signals
	_radial_menu.center_pressed.connect(_on_camera_pressed)
	_radial_menu.button_pressed.connect(_on_radial_button_pressed)

	print("[Home] RadialMenuCircles created at world origin with scale: ", menu_scale)


func _apply_menu_scale() -> void:
	"""Apply menu_scale to all radial menu dimensions (called when scale changes at runtime)."""
	if not _radial_menu:
		return

	# Apply scaled layout dimensions
	_radial_menu.center_radius = MENU_BASE_CENTER_RADIUS * menu_scale
	_radial_menu.ring_distance = MENU_BASE_RING_DISTANCE * menu_scale
	_radial_menu.ring_button_radius = MENU_BASE_RING_BUTTON_RADIUS * menu_scale

	# Apply scaled icon sizes
	var center_icon := MENU_BASE_CENTER_ICON_SIZE * menu_scale
	var ring_icon := MENU_BASE_RING_ICON_SIZE * menu_scale
	_radial_menu.center_icon_size = Vector2(center_icon, center_icon)
	_radial_menu.ring_icon_size = Vector2(ring_icon, ring_icon)

	# Wait for layout update then center - layout updates happen in _process(),
	# so we need to wait for a full frame to pass
	_center_menu_after_layout()


func _center_menu_after_layout() -> void:
	"""Wait for layout update to complete, then center the menu."""
	if not _radial_menu or not is_inside_tree():
		return
	# Wait for next frame (after _process runs and updates layout)
	await get_tree().process_frame
	if _radial_menu:
		_radial_menu.center_at_position(Vector2.ZERO)


func _on_radial_button_pressed(button_id: String) -> void:
	"""Handle radial menu ring button press."""
	match button_id:
		"feed":
			_on_feed_pressed()
		"dex":
			_on_dex_pressed()
		"social":
			_on_social_pressed()
		"settings":
			_on_menu_pressed()


func _setup_recenter_button() -> void:
	"""Setup the recenter button in screen-space overlay."""
	# Get reference to overlay layer and recenter button
	_recenter_button = $HomeOverlayLayer/Control/TopRightContainer/RecenterButton

	if _recenter_button:
		_recenter_button.connect_to_camera(_paper_camera)
		_recenter_button.center_position = Vector2.ZERO
		_recenter_button.center_threshold = 100.0
		_recenter_button.recenter_requested.connect(_on_recenter_requested)
		print("[Home] RecenterButton connected")
	else:
		push_warning("[Home] RecenterButton not found in overlay layer")


func _on_recenter_requested() -> void:
	"""Handle recenter button press - return to world origin where menu and tree root are."""
	print("[Home] Recentering view to origin")
	_paper_camera.scroll_to(Vector2.ZERO, true)


func _on_tree_loaded(tree_data) -> void:
	"""Handle tree data loaded - verify root is at origin for debugging."""
	# Find root node (should be Kingdom rank at depth 0 after server fix)
	var root_node = null
	for node in tree_data.nodes:
		if node.rank == TreeDataModels.TaxonomicRank.KINGDOM:
			root_node = node
			break

	if root_node:
		var world_pos: Vector2 = root_node.position * tree_scale
		print("[Home] Tree loaded - Root '", root_node.name, "' at world: ", world_pos)

		if world_pos.length() > 10:
			push_warning("[Home] Tree root not at origin! Clear server cache and reload.")
	else:
		print("[Home] Tree loaded - ", tree_data.nodes.size(), " nodes")


# =============================================================================
# Navigation Handlers
# =============================================================================

func _on_camera_pressed() -> void:
	"""Navigate to camera/upload scene"""
	print("[Home] Camera button pressed")
	navigation_manager.navigate_to("res://scenes/camera/camera.tscn")


func _on_dex_pressed() -> void:
	"""Navigate to dex collection"""
	print("[Home] Dex button pressed")
	navigation_manager.navigate_to("res://scenes/dex/dex.tscn")


func _on_feed_pressed() -> void:
	"""Navigate to friends' feed"""
	print("[Home] Feed button pressed")
	navigation_manager.navigate_to("res://scenes/dex_feed/dex_feed.tscn")


func _on_social_pressed() -> void:
	"""Navigate to social/friends"""
	print("[Home] Social button pressed")
	navigation_manager.navigate_to("res://scenes/social/social.tscn")


func _on_menu_pressed() -> void:
	"""Show menu with logout option"""
	print("[Home] Menu button pressed")
	# For now, just logout directly
	# TODO: Show proper menu popup
	_logout()


func _logout() -> void:
	"""Logout and return to login screen"""
	print("[Home] Logging out...")
	token_manager.logout()
	navigation_manager.navigate_to("res://scenes/login/login.tscn", true)
