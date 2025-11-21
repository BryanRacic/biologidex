extends Control

# Home scene - Main screen after login
# Provides navigation to main app features

# UI Elements
@onready var welcome_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/WelcomeLabel
@onready var camera_button: Button = $Panel/MarginContainer/VBoxContainer/Footer/CameraButton
@onready var dex_button: Button = $Panel/MarginContainer/VBoxContainer/Footer/DexButton
@onready var tree_button: Button = $Panel/MarginContainer/VBoxContainer/Footer/TreeButton
@onready var social_button: Button = $Panel/MarginContainer/VBoxContainer/Footer/SocialButton
@onready var menu_button: Button = $Panel/MarginContainer/VBoxContainer/Header/MenuButton

# Services (accessed via ServiceLocator)
var token_manager
var navigation_manager


func _ready() -> void:
	print("[Home] Scene loaded")

	# Get services from ServiceLocator
	_initialize_services()

	# Update welcome message with username
	if token_manager.is_logged_in():
		var username: String = token_manager.get_username()
		welcome_label.text = "Welcome back, %s!" % username
		print("[Home] User logged in: ", username)
	else:
		print("[Home] WARNING: User not logged in, redirecting to login")
		navigation_manager.navigate_to("res://scenes/login/login.tscn", true)
		return

	# Connect navigation buttons
	camera_button.pressed.connect(_on_camera_pressed)
	dex_button.pressed.connect(_on_dex_pressed)
	tree_button.pressed.connect(_on_tree_pressed)
	social_button.pressed.connect(_on_social_pressed)
	menu_button.pressed.connect(_on_menu_pressed)


func _initialize_services() -> void:
	"""Initialize service references from autoloads"""
	token_manager = get_node_or_null("/root/TokenManager")
	navigation_manager = get_node_or_null("/root/NavigationManager")

	if not token_manager or not navigation_manager:
		push_error("[Home] Failed to initialize required services")
		return


func _on_camera_pressed() -> void:
	"""Navigate to camera/upload scene"""
	print("[Home] Camera button pressed")
	navigation_manager.navigate_to("res://scenes/camera/camera.tscn")


func _on_dex_pressed() -> void:
	"""Navigate to dex collection"""
	print("[Home] Dex button pressed")
	navigation_manager.navigate_to("res://scenes/dex/dex.tscn")


func _on_tree_pressed() -> void:
	"""Navigate to taxonomic tree"""
	print("[Home] Tree button pressed")
	navigation_manager.navigate_to("res://scenes/tree/tree.tscn")


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