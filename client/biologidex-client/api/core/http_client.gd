extends Node
class_name HTTPClientCore

## HTTPClientCore - Low-level HTTP request handling
## Manages raw HTTP operations, response parsing, and platform-specific configurations

const APITypes = preload("res://api/core/api_types.gd")

signal request_started(url: String, method: String)
signal request_completed(url: String, response_code: int, body: Dictionary)
signal request_failed(url: String, error: String)

var http_request: HTTPRequest

func _ready() -> void:
	# Create HTTPRequest node
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

	# Disable gzip decompression in web builds to avoid double decompression
	# (browsers already decompress gzip responses automatically)
	if OS.get_name() == "Web":
		http_request.accept_gzip = false
		print("[HTTPClient] Web build detected - disabled gzip decompression")

	print("[HTTPClient] Initialized")

## Convert HTTPClient.Method enum to string
func _method_to_string(method: HTTPClient.Method) -> String:
	match method:
		HTTPClient.METHOD_GET:
			return "GET"
		HTTPClient.METHOD_POST:
			return "POST"
		HTTPClient.METHOD_PUT:
			return "PUT"
		HTTPClient.METHOD_DELETE:
			return "DELETE"
		HTTPClient.METHOD_HEAD:
			return "HEAD"
		HTTPClient.METHOD_PATCH:
			return "PATCH"
		_:
			return "UNKNOWN"

## Make a JSON request
func make_json_request(
	method: HTTPClient.Method,
	url: String,
	data: Dictionary,
	success_callback: Callable,
	error_callback: Callable,
	custom_headers: Array = []
) -> int:
	var headers = PackedStringArray(["Content-Type: application/json"])
	for header in custom_headers:
		headers.append(header)

	var body = JSON.stringify(data)

	var method_str = _method_to_string(method)
	_log_request(method_str, url, data)
	request_started.emit(url, method_str)

	var error = http_request.request(url, headers, method, body)

	if error != OK:
		var error_msg = "Failed to make request: %s" % error
		_log_error(url, error_msg)
		request_failed.emit(url, error_msg)
		if error_callback:
			error_callback.call(APITypes.APIError.new(0, error_msg, error_msg))
		return error

	# Store callbacks for response handling
	http_request.set_meta("success_callback", success_callback)
	http_request.set_meta("error_callback", error_callback)
	http_request.set_meta("request_url", url)

	return OK

## Make a raw request (for multipart/form-data, etc.)
func make_raw_request(
	method: HTTPClient.Method,
	url: String,
	headers: PackedStringArray,
	body: PackedByteArray,
	success_callback: Callable,
	error_callback: Callable,
	log_data: Dictionary = {}
) -> int:
	var method_str = _method_to_string(method)
	_log_request(method_str, url, log_data)
	request_started.emit(url, method_str)

	var error = http_request.request_raw(url, headers, method, body)

	if error != OK:
		var error_msg = "Failed to make request: %s" % error
		_log_error(url, error_msg)
		request_failed.emit(url, error_msg)
		if error_callback:
			error_callback.call(APITypes.APIError.new(0, error_msg, error_msg))
		return error

	# Store callbacks for response handling
	http_request.set_meta("success_callback", success_callback)
	http_request.set_meta("error_callback", error_callback)
	http_request.set_meta("request_url", url)

	return OK

## Make a simple GET request
func http_get(
	url: String,
	success_callback: Callable,
	error_callback: Callable,
	custom_headers: Array = []
) -> int:
	var headers = PackedStringArray()
	for header in custom_headers:
		headers.append(header)

	_log_request("GET", url, {})
	request_started.emit(url, "GET")

	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)

	if error != OK:
		var error_msg = "Failed to make request: %s" % error
		_log_error(url, error_msg)
		request_failed.emit(url, error_msg)
		if error_callback:
			error_callback.call(APITypes.APIError.new(0, error_msg, error_msg))
		return error

	# Store callbacks for response handling
	http_request.set_meta("success_callback", success_callback)
	http_request.set_meta("error_callback", error_callback)
	http_request.set_meta("request_url", url)

	return OK

## Build multipart/form-data request body for a single file
func build_multipart_body(
	boundary: String,
	field_name: String,
	file_name: String,
	file_type: String,
	file_data: PackedByteArray
) -> PackedByteArray:
	var packet := PackedByteArray()
	var boundary_start := ("\r\n--%s" % boundary).to_utf8_buffer()
	var disposition := ("\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"" % [field_name, file_name]).to_utf8_buffer()
	var content_type := ("\r\nContent-Type: %s\r\n\r\n" % file_type).to_utf8_buffer()
	var boundary_end := ("\r\n--%s--\r\n" % boundary).to_utf8_buffer()

	packet.append_array(boundary_start)
	packet.append_array(disposition)
	packet.append_array(content_type)
	packet.append_array(file_data)
	packet.append_array(boundary_end)

	return packet

## Build multipart/form-data request body with multiple fields
func build_multipart_body_with_fields(boundary: String, fields: Array) -> PackedByteArray:
	var packet := PackedByteArray()

	for field in fields:
		var field_name: String = field.get("name", "")
		var field_data = field.get("data")
		var filename: String = field.get("filename", "")
		var content_type: String = field.get("type", "")

		# Start boundary
		packet.append_array(("\r\n--%s\r\n" % boundary).to_utf8_buffer())

		# Content-Disposition header
		if filename:
			# File field
			packet.append_array(
				("Content-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\n" % [field_name, filename]).to_utf8_buffer()
			)
			if content_type:
				packet.append_array(("Content-Type: %s\r\n\r\n" % content_type).to_utf8_buffer())
			else:
				packet.append_array("\r\n".to_utf8_buffer())
		else:
			# Text field
			packet.append_array(
				("Content-Disposition: form-data; name=\"%s\"\r\n\r\n" % field_name).to_utf8_buffer()
			)

		# Field data
		if field_data is PackedByteArray:
			packet.append_array(field_data)
		elif field_data is String:
			packet.append_array(field_data.to_utf8_buffer())
		else:
			# Convert to string if needed
			packet.append_array(str(field_data).to_utf8_buffer())

	# End boundary
	packet.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())

	return packet

## Handle HTTP request completion
func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var url: String = http_request.get_meta("request_url", "unknown")
	var success_callback: Callable = http_request.get_meta("success_callback")
	var error_callback: Callable = http_request.get_meta("error_callback")

	# Parse response body
	var response_text := body.get_string_from_utf8()
	var response_data := {}

	if response_text.length() > 0:
		var json := JSON.new()
		var parse_result := json.parse(response_text)
		if parse_result == OK:
			response_data = json.data
		else:
			response_data = {"raw": response_text}

	# Log response
	_log_response(url, response_code, response_data)

	# Handle response
	if response_code >= 200 and response_code < 300:
		request_completed.emit(url, response_code, response_data)
		if success_callback:
			success_callback.call(response_data)
	else:
		var detail_value = response_data.get("detail")
		var detail: String = "Unknown error" if detail_value == null else str(detail_value)
		var error_msg := "HTTP %d: %s" % [response_code, detail]
		request_failed.emit(url, error_msg)

		# Create error object
		var api_error = APITypes.APIError.new(response_code, detail, error_msg)

		# Extract field errors
		for key in response_data:
			if typeof(response_data[key]) == TYPE_ARRAY:
				var errors_array: Array = response_data[key]
				if errors_array.size() > 0:
					api_error.field_errors[key] = errors_array

		if error_callback:
			error_callback.call(api_error)

## Logging functions
func _log_request(method: String, url: String, data: Dictionary) -> void:
	print("[HTTPClient] === REQUEST ===")
	print("[HTTPClient] %s %s" % [method, url])
	if data.size() > 0:
		print("[HTTPClient] Data: ", JSON.stringify(data, "\t"))

func _log_response(url: String, code: int, data: Dictionary) -> void:
	print("[HTTPClient] === RESPONSE ===")
	print("[HTTPClient] URL: ", url)
	print("[HTTPClient] Status: ", code)
	if data.size() > 0:
		print("[HTTPClient] Body: ", JSON.stringify(data, "\t"))

func _log_error(url: String, error: String) -> void:
	print("[HTTPClient] === ERROR ===")
	print("[HTTPClient] URL: ", url)
	print("[HTTPClient] Error: ", error)
