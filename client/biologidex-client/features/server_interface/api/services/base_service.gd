extends RefCounted
class_name BaseService

## BaseService - Abstract base class for all API services
## Provides common functionality: URL building, error handling, logging

const APIClient = preload("res://features/server_interface/api/core/api_client.gd")
const APIConfig = preload("res://features/server_interface/api/core/api_config.gd")
const APITypes = preload("res://features/server_interface/api/core/api_types.gd")

var api_client
var config

func _init(client: APIClient, cfg: APIConfig) -> void:
	api_client = client
	config = cfg

## Build full URL from endpoint
func _build_url(endpoint: String) -> String:
	return config.build_url(endpoint)

## Build URL with query parameters
func _build_url_with_params(endpoint: String, params: Dictionary) -> String:
	return config.build_url_with_params(endpoint, params)

## Format endpoint with parameters (e.g., "/jobs/%s/" with job_id)
func _format_endpoint(endpoint: String, args: Array) -> String:
	var formatted = endpoint
	for arg in args:
		# Replace only the first occurrence manually (GDScript replace() doesn't have count param)
		var pos = formatted.find("%s")
		if pos != -1:
			formatted = formatted.substr(0, pos) + str(arg) + formatted.substr(pos + 2)
	return formatted

## Standardized error handling
func _handle_error(error: APITypes.APIError, context: String) -> void:
	if error.is_network_error():
		push_error("[%s] Network error in %s: %s" % [get_script().get_global_name(), context, error.message])
	elif error.is_auth_error():
		push_error("[%s] Authentication error in %s: %s" % [get_script().get_global_name(), context, error.message])
	elif error.is_server_error():
		push_error("[%s] Server error in %s: %s" % [get_script().get_global_name(), context, error.message])
	else:
		push_error("[%s] Error in %s: %s" % [get_script().get_global_name(), context, error.format()])

	# Log field errors if present
	if error.field_errors.size() > 0:
		for field in error.field_errors:
			push_error("[%s]   %s: %s" % [get_script().get_global_name(), field, error.field_errors[field]])

## Log service operation
func _log(message: String) -> void:
	print("[%s] %s" % [get_script().get_global_name(), message])

## Create request config with custom settings
func _create_request_config(
	requires_auth: bool = true,
	timeout: float = -1.0,
	max_retries: int = -1,
	retry_on_failure: bool = true,
	priority: int = 0
) -> APITypes.RequestConfig:
	var req_config = APITypes.RequestConfig.new()
	req_config.requires_auth = requires_auth

	if timeout > 0:
		req_config.timeout = timeout
	else:
		req_config.timeout = config.DEFAULT_TIMEOUT

	if max_retries >= 0:
		req_config.max_retries = max_retries
	else:
		req_config.max_retries = config.MAX_RETRIES

	req_config.retry_on_failure = retry_on_failure
	req_config.priority = priority

	return req_config