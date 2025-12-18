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

@export_group("Tree Background Appearance")
## Base size of tree nodes (smaller = subtler background)
@export_range(5.0, 50.0, 1.0) var tree_node_size: float = 15.0
## Opacity of tree nodes (lower = more subtle)
@export_range(0.0, 1.0, 0.05) var tree_node_opacity: float = 0.6
## Width of tree edges/branches
@export_range(1.0, 20.0, 0.5) var tree_edge_width: float = 3.0
## Opacity of tree edges (lower = more subtle)
@export_range(0.0, 1.0, 0.05) var tree_edge_opacity: float = 0.4
## Size of dex images on tree (smaller = less prominent)
@export_range(200.0, 2000.0, 50.0) var tree_dex_image_size: float = 800.0
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
# UI References (world-space buttons)
# =============================================================================

var camera_button: Button = null
var dex_button: Button = null
var feed_button: Button = null
var social_button: Button = null
var menu_button: Button = null
var title_label: Label = null


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
	_tree_visualization.edge_width = tree_edge_width
	_tree_visualization.edge_opacity = tree_edge_opacity
	_tree_visualization.dex_image_size = tree_dex_image_size
	_tree_visualization.label_opacity = tree_label_opacity

	_paper_camera.content_container.add_child(_tree_visualization)
	_tree_visualization.setup(_paper_camera)

	print("[Home] TreeVisualization initialized with background styling")


func _setup_world_space_ui() -> void:
	"""Create world-space UI container with buttons."""
	_home_ui = WorldSpaceUI.new()
	_home_ui.name = "HomeUI"
	_home_ui.anchor_position = Vector2.ZERO  # Centered at origin
	_paper_camera.content_container.add_child(_home_ui)

	# Build UI structure
	_build_home_buttons()

	print("[Home] World-space UI created")


func _build_home_buttons() -> void:
	"""Build the home screen buttons in world-space."""
	# Create a CenterContainer to center the VBox at world origin
	var center_container = CenterContainer.new()
	center_container.name = "CenterContainer"
	# Size large enough to contain the menu (1600x1200 to fit 1400px separator + padding)
	center_container.custom_minimum_size = Vector2(1600, 1200)
	center_container.size = Vector2(1600, 1200)
	center_container.position = Vector2(-800, -600)  # Center the container at origin
	center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home_ui.add_child(center_container)

	# Create VBoxContainer for buttons (will be auto-centered by CenterContainer)
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.add_theme_constant_override("separation", 30)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_container.add_child(vbox)

	# Create title label with proper font styling (matching original)
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "BiologiDex"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Load the Fraunces font and create LabelSettings (matching original home.tscn)
	var font = load("res://resources/fonts/Fraunces/Fraunces-VariableFont_SOFT,WONK,opsz,wght.ttf") as Font
	var label_settings = LabelSettings.new()
	label_settings.font = font
	label_settings.font_size = 246
	label_settings.font_color = Color.BLACK
	title_label.label_settings = label_settings

	vbox.add_child(title_label)

	# Separator (matching original 1400px width, 3px height)
	var separator = ColorRect.new()
	separator.name = "Separator"
	separator.custom_minimum_size = Vector2(1400, 3)
	separator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	separator.color = Color(0, 0, 0, 0.6)
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(separator)

	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 30)
	spacer1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer1)

	# Second spacer (matching original)
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 30)
	spacer2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer2)

	# Load theme for buttons
	var theme = load("res://theme.tres") as Theme

	# Create navigation buttons
	camera_button = _create_nav_button("Upload Image", theme)
	camera_button.pressed.connect(_on_camera_pressed)
	vbox.add_child(camera_button)

	feed_button = _create_nav_button("Dex Feed", theme)
	feed_button.pressed.connect(_on_feed_pressed)
	vbox.add_child(feed_button)

	dex_button = _create_nav_button("View Dex", theme)
	dex_button.pressed.connect(_on_dex_pressed)
	vbox.add_child(dex_button)

	social_button = _create_nav_button("Friends", theme)
	social_button.pressed.connect(_on_social_pressed)
	vbox.add_child(social_button)

	# Menu button (hidden for now)
	menu_button = _create_nav_button("Menu", theme)
	menu_button.visible = false
	menu_button.pressed.connect(_on_menu_pressed)
	vbox.add_child(menu_button)


func _create_nav_button(text: String, theme: Theme) -> Button:
	"""Create a styled navigation button."""
	var button = Button.new()
	button.text = text
	button.theme = theme
	button.custom_minimum_size = Vector2(80, 44)
	button.add_theme_font_size_override("font_size", 124)
	return button


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
	"""Handle recenter button press."""
	print("[Home] Recentering view")
	_paper_camera.scroll_to(Vector2.ZERO, true)


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
