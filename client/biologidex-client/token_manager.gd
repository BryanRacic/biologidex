extends Node

# TokenManager - Manages JWT tokens and user session
# Handles storage, refresh, and validation of authentication tokens

signal token_refreshed(new_access_token: String)
signal token_refresh_failed(error: String)
signal logged_in(user_data: Dictionary)
signal logged_out()

const SAVE_FILE_PATH = "user://biologidex_auth.dat"

var access_token: String = ""
var refresh_token: String = ""
var username: String = ""
var user_data: Dictionary = {}
var is_authenticated: bool = false


func _ready() -> void:
	print("[TokenManager] Initialized")
	load_from_disk()


func save_login(access: String, refresh: String, user: Dictionary) -> void:
	"""
	Save login credentials after successful authentication
	"""
	access_token = access
	refresh_token = refresh
	username = user.get("username", "")
	user_data = user
	is_authenticated = true

	print("[TokenManager] Login saved for user: ", username)

	# Save to disk
	save_to_disk()

	# Emit signal
	logged_in.emit(user_data)


func logout() -> void:
	"""
	Clear all authentication data
	"""
	print("[TokenManager] Logging out user: ", username)

	access_token = ""
	refresh_token = ""
	username = ""
	user_data = {}
	is_authenticated = false

	# Clear saved data
	if FileAccess.file_exists(SAVE_FILE_PATH):
		DirAccess.remove_absolute(SAVE_FILE_PATH)

	logged_out.emit()


func has_refresh_token() -> bool:
	"""
	Check if we have a saved refresh token
	"""
	return refresh_token.length() > 0


func get_access_token() -> String:
	"""
	Get current access token
	"""
	return access_token


func get_username() -> String:
	"""
	Get current username
	"""
	return username


func get_user_data() -> Dictionary:
	"""
	Get current user data
	"""
	return user_data


func get_user_id() -> String:
	"""
	Get current user ID from user_data
	"""
	var id_value = user_data.get("id", "")
	return str(id_value) if id_value else ""


func update_access_token(new_access: String) -> void:
	"""
	Update access token after refresh
	"""
	access_token = new_access
	save_to_disk()
	token_refreshed.emit(new_access)
	print("[TokenManager] Access token refreshed")


func refresh_access_token(callback: Callable) -> void:
	"""
	Refresh the access token using the refresh token
	"""
	if not has_refresh_token():
		var error_msg := "No refresh token available"
		print("[TokenManager] ERROR: ", error_msg)
		token_refresh_failed.emit(error_msg)
		callback.call(false, error_msg)
		return

	print("[TokenManager] Refreshing access token...")

	# Use APIManager to refresh
	APIManager.refresh_token(refresh_token, func(response: Dictionary, code: int):
		if code == 200 and response.has("access"):
			update_access_token(response["access"])
			callback.call(true, "")
		else:
			var error_value = response.get("detail")
			var error_msg: String = "Failed to refresh token" if error_value == null else str(error_value)
			print("[TokenManager] ERROR: Failed to refresh - ", error_msg)
			token_refresh_failed.emit(error_msg)
			# Clear invalid tokens
			logout()
			callback.call(false, error_msg)
	)


func save_to_disk() -> void:
	"""
	Save authentication data to disk
	Note: In production, this should be encrypted
	"""
	var save_data := {
		"access_token": access_token,
		"refresh_token": refresh_token,
		"username": username,
		"user_data": user_data,
		"saved_at": Time.get_unix_time_from_system()
	}

	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file:
		var json_string := JSON.stringify(save_data)
		file.store_string(json_string)
		file.close()
		print("[TokenManager] Auth data saved to disk")
	else:
		print("[TokenManager] ERROR: Failed to save auth data - ", FileAccess.get_open_error())


func load_from_disk() -> void:
	"""
	Load authentication data from disk
	"""
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		print("[TokenManager] No saved auth data found")
		return

	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file:
		var json_string := file.get_as_text()
		file.close()

		var json := JSON.new()
		var parse_result := json.parse(json_string)

		if parse_result == OK:
			var data: Dictionary = json.data

			# Handle potential null values from saved data
			var access_value = data.get("access_token")
			var refresh_value = data.get("refresh_token")
			var username_value = data.get("username")
			var user_data_value = data.get("user_data")

			access_token = "" if access_value == null else str(access_value)
			refresh_token = "" if refresh_value == null else str(refresh_value)
			username = "" if username_value == null else str(username_value)
			user_data = {} if user_data_value == null or typeof(user_data_value) != TYPE_DICTIONARY else user_data_value

			if has_refresh_token():
				is_authenticated = true
				print("[TokenManager] Loaded saved auth for user: ", username)
			else:
				print("[TokenManager] Loaded auth data but no refresh token")
		else:
			print("[TokenManager] ERROR: Failed to parse saved auth data")
	else:
		print("[TokenManager] ERROR: Failed to load auth data - ", FileAccess.get_open_error())


func is_logged_in() -> bool:
	"""
	Check if user is currently logged in
	"""
	return is_authenticated and has_refresh_token()
