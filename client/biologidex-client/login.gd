extends Control

# Login scene - Handles user authentication
# Shows login form if no valid refresh token exists

@onready var username_input: LineEdit = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/LoginForm/UsernameField/UsernameInput
@onready var password_input: LineEdit = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/LoginForm/PasswordField/PasswordInput
@onready var login_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/LoginForm/LoginButton
@onready var create_acct_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/LoginForm/CreateAcctButton
@onready var status_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/LoginForm/StatusLabel
@onready var loading_spinner: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/LoginForm/LoadingSpinner

var is_loading: bool = false


func _ready() -> void:
	print("[Login] Scene loaded")

	# Hide loading spinner initially
	loading_spinner.visible = false
	status_label.text = ""

	# Connect buttons
	login_button.pressed.connect(_on_login_button_pressed)
	create_acct_button.pressed.connect(_on_create_acct_button_pressed)

	# Connect Enter key in password field
	password_input.text_submitted.connect(func(_text: String): _on_login_button_pressed())

	# Check if we have a saved refresh token
	if TokenManager.has_refresh_token():
		print("[Login] Found saved refresh token, attempting automatic login...")
		_attempt_token_refresh()
	else:
		print("[Login] No saved token, showing login form")
		# Prepopulate username if available
		if TokenManager.get_username().length() > 0:
			username_input.text = TokenManager.get_username()
			password_input.grab_focus()
		else:
			username_input.grab_focus()


func _attempt_token_refresh() -> void:
	"""Try to use saved refresh token to get new access token"""
	_set_loading(true, "Checking saved credentials...")

	TokenManager.refresh_access_token(func(success: bool, error: String):
		if success:
			print("[Login] Token refresh successful, navigating to home")
			_navigate_to_home()
		else:
			print("[Login] Token refresh failed: ", error)
			_set_loading(false)
			status_label.text = "Session expired. Please login again."
			status_label.add_theme_color_override("font_color", Color.ORANGE)
	)


func _on_login_button_pressed() -> void:
	"""Handle login button press"""
	if is_loading:
		return

	var username := username_input.text.strip_edges()
	var password := password_input.text

	# Validate input
	if username.length() == 0:
		_show_error("Please enter your username")
		username_input.grab_focus()
		return

	if password.length() == 0:
		_show_error("Please enter your password")
		password_input.grab_focus()
		return

	# Attempt login
	_perform_login(username, password)


func _perform_login(username: String, password: String) -> void:
	"""Perform login API request"""
	print("[Login] Attempting login for user: ", username)
	_set_loading(true, "Logging in...")

	APIManager.login(username, password, func(response: Dictionary, code: int):
		if code == 200:
			# Successful login
			print("[Login] Login successful!")

			# Handle potential null values in response
			var access_value = response.get("access")
			var refresh_value = response.get("refresh")
			var user_value = response.get("user")

			var access: String = "" if access_value == null else str(access_value)
			var refresh: String = "" if refresh_value == null else str(refresh_value)
			var user: Dictionary = {} if user_value == null or typeof(user_value) != TYPE_DICTIONARY else user_value

			if access.length() > 0 and refresh.length() > 0:
				# Save tokens
				TokenManager.save_login(access, refresh, user)

				# Clear password field for security
				password_input.text = ""

				# Navigate to home
				_navigate_to_home()
			else:
				_show_error("Invalid response from server")
				_set_loading(false)
		else:
			# Login failed
			var error_message := "Login failed"

			if response.has("detail"):
				error_message = str(response["detail"])
			elif response.has("error"):
				error_message = str(response["error"])
			elif code == 401:
				error_message = "Invalid username or password"
			elif code == 0:
				error_message = "Cannot connect to server"

			print("[Login] Login failed: ", error_message)
			_show_error(error_message)
			_set_loading(false)

			# Clear password on failed login
			password_input.text = ""
			password_input.grab_focus()
	)


func _navigate_to_home() -> void:
	"""Navigate to home scene after successful login"""
	print("[Login] Navigating to home scene")
	# Clear navigation history since this is a fresh login
	NavigationManager.navigate_to("res://home.tscn", true)


func _set_loading(loading: bool, message: String = "") -> void:
	"""Set loading state and update UI"""
	is_loading = loading
	loading_spinner.visible = loading
	login_button.disabled = loading
	username_input.editable = not loading
	password_input.editable = not loading

	if loading and message.length() > 0:
		status_label.text = message
		status_label.add_theme_color_override("font_color", Color.WHITE)


func _show_error(message: String) -> void:
	"""Display error message"""
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color.RED)


func _on_create_acct_button_pressed() -> void:
	"""Handle create account button press"""
	if is_loading:
		return

	print("[Login] Navigating to create account scene")
	NavigationManager.navigate_to("res://create_acct.tscn")