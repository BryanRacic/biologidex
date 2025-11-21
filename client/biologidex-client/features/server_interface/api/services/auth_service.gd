extends BaseService
class_name AuthService

## AuthService - Authentication operations (login, register, token refresh)

signal login_succeeded(user_data: Dictionary)
signal login_failed(error: APITypes.APIError)
signal registration_succeeded(user_data: Dictionary)
signal registration_failed(error: APITypes.APIError)
signal token_refreshed(new_access_token: String)
signal token_refresh_failed(error: APITypes.APIError)

## Login with username and password
## Returns: {access, refresh, user}
func login(username: String, password: String, callback: Callable = Callable()) -> void:
	_log("Logging in user: %s" % username)

	var data = {
		"username": username,
		"password": password
	}

	var req_config = _create_request_config(false)
	var context = {"username": username, "callback": callback}

	api_client.post(
		config.ENDPOINTS_AUTH["login"],
		data,
		_on_login_success.bind(context),
		_on_login_error.bind(context),
		req_config
	)

func _on_login_success(response: Dictionary, context: Dictionary) -> void:
	_log("Login successful for user: %s" % context.username)
	login_succeeded.emit(response)
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_login_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "login")
	login_failed.emit(error)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Register a new user account
## Returns: User object with id, username, email, friend_code, etc.
func register(
	username: String,
	email: String,
	password: String,
	password_confirm: String,
	callback: Callable = Callable()
) -> void:
	_log("Registering new user: %s" % username)

	var data = {
		"username": username,
		"email": email,
		"password": password,
		"password_confirm": password_confirm
	}

	var req_config = _create_request_config(false)
	var context = {"username": username, "callback": callback}

	api_client.post(
		config.ENDPOINTS_USER["register"],
		data,
		_on_register_success.bind(context),
		_on_register_error.bind(context),
		req_config
	)

func _on_register_success(response: Dictionary, context: Dictionary) -> void:
	_log("Registration successful for user: %s" % context.username)
	registration_succeeded.emit(response)
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_register_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "register")
	registration_failed.emit(error)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message, "field_errors": error.field_errors}, error.code)

## Refresh access token using refresh token
## Returns: {access}
func refresh_token(refresh: String, callback: Callable = Callable()) -> void:
	_log("Refreshing access token")

	var data = {
		"refresh": refresh
	}

	var req_config = _create_request_config(false)
	var context = {"callback": callback}

	api_client.post(
		config.ENDPOINTS_AUTH["refresh"],
		data,
		_on_refresh_success.bind(context),
		_on_refresh_error.bind(context),
		req_config
	)

func _on_refresh_success(response: Dictionary, context: Dictionary) -> void:
	_log("Token refresh successful")
	token_refreshed.emit(response.get("access", ""))
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_refresh_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "refresh_token")
	token_refresh_failed.emit(error)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Get current user's friend code
## Returns: {friend_code, username}
func get_friend_code(callback: Callable = Callable()) -> void:
	_log("Getting user's friend code")

	var req_config = _create_request_config(true)
	var context = {"callback": callback}

	api_client.request_get(
		config.ENDPOINTS_USER["friend_code"],
		_on_friend_code_success.bind(context),
		_on_friend_code_error.bind(context),
		req_config
	)

func _on_friend_code_success(response: Dictionary, context: Dictionary) -> void:
	_log("Friend code retrieved successfully")
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_friend_code_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_friend_code")
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)