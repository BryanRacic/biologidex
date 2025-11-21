extends Control

# Create Account scene - Handles user registration
# Shows registration form and creates new account via API

@onready var email_input: LineEdit = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/CreateAcctForm/EmailField/EmailInput
@onready var username_input: LineEdit = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/CreateAcctForm/UsernameField/UsernameInput
@onready var password_input: LineEdit = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/CreateAcctForm/PasswordField/PasswordInput
@onready var confirm_password_input: LineEdit = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/CreateAcctForm/ConfirmPasswordField2/ConfirmPasswordInput
@onready var create_acct_button: Button = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/CreateAcctForm/CreateAcctButton
@onready var status_label: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/CreateAcctForm/StatusLabel
@onready var loading_spinner: Label = $Panel/MarginContainer/VBoxContainer/Content/ContentMargin/CreateAcctForm/LoadingSpinner

var is_loading: bool = false


func _ready() -> void:
	print("[CreateAccount] Scene loaded")

	# Hide loading spinner initially
	loading_spinner.visible = false
	status_label.text = ""

	# Connect button
	create_acct_button.pressed.connect(_on_create_acct_button_pressed)

	# Connect Enter key in confirm password field
	confirm_password_input.text_submitted.connect(func(_text: String): _on_create_acct_button_pressed())

	# Focus on first field
	email_input.grab_focus()


func _on_create_acct_button_pressed() -> void:
	"""Handle create account button press"""
	if is_loading:
		return

	var email := email_input.text.strip_edges()
	var username := username_input.text.strip_edges()
	var password := password_input.text
	var confirm_password := confirm_password_input.text

	# Validate input
	if email.length() == 0:
		_show_error("Please enter your email address")
		email_input.grab_focus()
		return

	# Basic email validation
	if not _is_valid_email(email):
		_show_error("Please enter a valid email address")
		email_input.grab_focus()
		return

	if username.length() == 0:
		_show_error("Please enter a username")
		username_input.grab_focus()
		return

	if username.length() < 3:
		_show_error("Username must be at least 3 characters")
		username_input.grab_focus()
		return

	if password.length() == 0:
		_show_error("Please enter a password")
		password_input.grab_focus()
		return

	if password.length() < 8:
		_show_error("Password must be at least 8 characters")
		password_input.grab_focus()
		return

	if confirm_password.length() == 0:
		_show_error("Please confirm your password")
		confirm_password_input.grab_focus()
		return

	if password != confirm_password:
		_show_error("Passwords do not match")
		confirm_password_input.grab_focus()
		return

	# Attempt registration
	_perform_registration(username, email, password, confirm_password)


func _perform_registration(username: String, email: String, password: String, password_confirm: String) -> void:
	"""Perform registration API request"""
	print("[CreateAccount] Attempting registration for user: ", username)
	_set_loading(true, "Creating account...")

	APIManager.register(username, email, password, password_confirm, func(response: Dictionary, code: int):
		if code == 200 or code == 201:
			# Successful registration (service layer normalizes 201 to 200)
			print("[CreateAccount] Registration successful!")

			# Show success message
			_show_success("Account created successfully! Logging in...")

			# Now log the user in automatically
			await get_tree().create_timer(1.0).timeout
			_perform_auto_login(username, password)
		else:
			# Registration failed
			var error_message := "Registration failed"

			# Handle field-specific errors
			if response.has("username"):
				var username_errors = response["username"]
				if typeof(username_errors) == TYPE_ARRAY and username_errors.size() > 0:
					error_message = "Username: " + str(username_errors[0])
				else:
					error_message = "Username: " + str(username_errors)
			elif response.has("email"):
				var email_errors = response["email"]
				if typeof(email_errors) == TYPE_ARRAY and email_errors.size() > 0:
					error_message = "Email: " + str(email_errors[0])
				else:
					error_message = "Email: " + str(email_errors)
			elif response.has("password"):
				var password_errors = response["password"]
				if typeof(password_errors) == TYPE_ARRAY and password_errors.size() > 0:
					error_message = "Password: " + str(password_errors[0])
				else:
					error_message = "Password: " + str(password_errors)
			elif response.has("detail"):
				error_message = str(response["detail"])
			elif response.has("error"):
				error_message = str(response["error"])
			elif code == 400:
				error_message = "Invalid registration data"
			elif code == 0:
				error_message = "Cannot connect to server"

			print("[CreateAccount] Registration failed: ", error_message)
			_show_error(error_message)
			_set_loading(false)

			# Clear password fields on failed registration
			password_input.text = ""
			confirm_password_input.text = ""
	)


func _perform_auto_login(username: String, password: String) -> void:
	"""Automatically log in after successful registration"""
	print("[CreateAccount] Auto-login after registration")
	_set_loading(true, "Logging in...")

	APIManager.login(username, password, func(response: Dictionary, code: int):
		if code == 200:
			# Successful login
			print("[CreateAccount] Auto-login successful!")

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

				# Clear all input fields for security
				email_input.text = ""
				username_input.text = ""
				password_input.text = ""
				confirm_password_input.text = ""

				# Navigate to home
				_navigate_to_home()
			else:
				_show_error("Login failed after registration. Please login manually.")
				_set_loading(false)
				await get_tree().create_timer(2.0).timeout
				_navigate_to_login()
		else:
			# Auto-login failed, redirect to login page
			print("[CreateAccount] Auto-login failed, redirecting to login")
			_show_error("Account created! Please login.")
			_set_loading(false)
			await get_tree().create_timer(2.0).timeout
			_navigate_to_login()
	)


func _navigate_to_home() -> void:
	"""Navigate to home scene after successful registration and login"""
	print("[CreateAccount] Navigating to home scene")
	# Clear navigation history since this is a fresh login
	NavigationManager.navigate_to("res://home.tscn", true)


func _navigate_to_login() -> void:
	"""Navigate back to login scene"""
	print("[CreateAccount] Navigating to login scene")
	NavigationManager.navigate_to("res://login.tscn", true)


func _set_loading(loading: bool, message: String = "") -> void:
	"""Set loading state and update UI"""
	is_loading = loading
	loading_spinner.visible = loading
	create_acct_button.disabled = loading
	email_input.editable = not loading
	username_input.editable = not loading
	password_input.editable = not loading
	confirm_password_input.editable = not loading

	if loading and message.length() > 0:
		status_label.text = message
		status_label.add_theme_color_override("font_color", Color.WHITE)


func _show_error(message: String) -> void:
	"""Display error message"""
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color.RED)


func _show_success(message: String) -> void:
	"""Display success message"""
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color.GREEN)


func _is_valid_email(email: String) -> bool:
	"""Basic email validation"""
	# Check for @ symbol and domain
	var at_pos := email.find("@")
	if at_pos <= 0:
		return false

	var domain := email.substr(at_pos + 1)
	if domain.length() < 3 or domain.find(".") <= 0:
		return false

	return true
