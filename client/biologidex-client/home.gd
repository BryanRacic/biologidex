extends Control

# Home scene - Main screen after login
# Provides navigation to main app features

@onready var welcome_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/ContentContainer/WelcomeLabel
@onready var camera_button: Button = $Panel/MarginContainer/VBoxContainer/Footer/CameraButton
@onready var dex_button: Button = $Panel/MarginContainer/VBoxContainer/Footer/DexButton
@onready var tree_button: Button = $Panel/MarginContainer/VBoxContainer/Footer/TreeButton
@onready var social_button: Button = $Panel/MarginContainer/VBoxContainer/Footer/SocialButton
@onready var menu_button: Button = $Panel/MarginContainer/VBoxContainer/Header/MenuButton


func _ready() -> void:
	print("[Home] Scene loaded")

	# Update welcome message with username
	if TokenManager.is_logged_in():
		var username := TokenManager.get_username()
		welcome_label.text = "Welcome back, %s!" % username
		print("[Home] User logged in: ", username)
	else:
		print("[Home] WARNING: User not logged in, redirecting to login")
		NavigationManager.navigate_to("res://login.tscn", true)
		return

	# Connect navigation buttons
	camera_button.pressed.connect(_on_camera_pressed)
	dex_button.pressed.connect(_on_dex_pressed)
	tree_button.pressed.connect(_on_tree_pressed)
	social_button.pressed.connect(_on_social_pressed)
	menu_button.pressed.connect(_on_menu_pressed)


func _on_camera_pressed() -> void:
	"""Navigate to camera/upload scene"""
	print("[Home] Camera button pressed")
	NavigationManager.navigate_to("res://camera.tscn")


func _on_dex_pressed() -> void:
	"""Navigate to dex collection"""
	print("[Home] Dex button pressed")
	NavigationManager.navigate_to("res://dex.tscn")


func _on_tree_pressed() -> void:
	"""Navigate to evolutionary tree"""
	print("[Home] Tree button pressed")
	# TODO: Implement tree scene
	print("[Home] TODO: Tree scene not yet implemented")


func _on_social_pressed() -> void:
	"""Navigate to social/friends"""
	print("[Home] Social button pressed")
	# TODO: Implement social scene
	print("[Home] TODO: Social scene not yet implemented")


func _on_menu_pressed() -> void:
	"""Show menu with logout option"""
	print("[Home] Menu button pressed")
	# For now, just logout directly
	# TODO: Show proper menu popup
	_logout()


func _logout() -> void:
	"""Logout and return to login screen"""
	print("[Home] Logging out...")
	TokenManager.logout()
	NavigationManager.navigate_to("res://login.tscn", true)