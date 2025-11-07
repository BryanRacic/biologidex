extends RefCounted
class_name APITypes

## APITypes - Shared type definitions and error classes

## API Error class for standardized error handling
class APIError extends RefCounted:
	var code: int = 0  # HTTP status code
	var message: String = ""  # User-friendly message
	var detail: String = ""  # Technical details
	var field_errors: Dictionary = {}  # Field-specific errors
	var retry_after: float = 0.0  # Seconds before retry (if applicable)

	func _init(error_code: int = 0, error_message: String = "", error_detail: String = "") -> void:
		code = error_code
		message = error_message
		detail = error_detail

	func is_network_error() -> bool:
		return code == 0 or code == -1

	func is_auth_error() -> bool:
		return code == 401 or code == 403

	func is_validation_error() -> bool:
		return code == 400

	func is_server_error() -> bool:
		return code >= 500 and code < 600

	func is_rate_limit_error() -> bool:
		return code == 429

	func format() -> String:
		if is_network_error():
			return "Network Error: %s" % message
		return "HTTP %d: %s" % [code, message]

## API Response wrapper
class APIResponse extends RefCounted:
	var success: bool = false
	var data: Dictionary = {}
	var error: APIError = null
	var status_code: int = 0

	func _init(is_success: bool = false, response_data: Dictionary = {}, response_code: int = 0) -> void:
		success = is_success
		data = response_data
		status_code = response_code

		if not success:
			# Create error from response
			var error_message: String
			var detail_value = data.get("detail")
			if detail_value != null:
				error_message = str(detail_value)
			else:
				error_message = "Unknown error"

			error = APIError.new(status_code, error_message, error_message)

			# Extract field errors if present
			for key in data:
				if typeof(data[key]) == TYPE_ARRAY:
					var errors_array: Array = data[key]
					if errors_array.size() > 0:
						error.field_errors[key] = errors_array

## Request configuration
class RequestConfig extends RefCounted:
	var timeout: float = 30.0
	var max_retries: int = 3
	var retry_on_failure: bool = true
	var requires_auth: bool = true
	var priority: int = 0  # Higher priority = processed first

	func _init() -> void:
		pass

## Request queue item
class QueuedRequest extends RefCounted:
	var method: HTTPClient.Method
	var url: String
	var headers: PackedStringArray
	var body: Variant  # String or PackedByteArray
	var config: RequestConfig
	var success_callback: Callable
	var error_callback: Callable
	var attempt: int = 0

	func _init(
		req_method: HTTPClient.Method,
		req_url: String,
		req_headers: PackedStringArray,
		req_body: Variant,
		req_config: RequestConfig,
		success_cb: Callable,
		error_cb: Callable
	) -> void:
		method = req_method
		url = req_url
		headers = req_headers
		body = req_body
		config = req_config
		success_callback = success_cb
		error_callback = error_cb

## Tree mode enum (moved from tree_api_service)
enum TreeMode {
	PERSONAL,   # User's dex only
	FRIENDS,    # User + all friends (default)
	SELECTED,   # User + specific friends
	GLOBAL      # All users (admin only)
}

## Mode string mapping
const TREE_MODE_STRINGS = {
	TreeMode.PERSONAL: "personal",
	TreeMode.FRIENDS: "friends",
	TreeMode.SELECTED: "selected",
	TreeMode.GLOBAL: "global",
}

## Get tree mode string
static func get_tree_mode_string(mode: TreeMode) -> String:
	return TREE_MODE_STRINGS[mode]