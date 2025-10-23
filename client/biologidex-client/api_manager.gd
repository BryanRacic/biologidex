extends Node

# APIManager - Global singleton for HTTP API requests
# Handles all communication with Django backend with logging

signal request_started(url: String, method: String)
signal request_completed(url: String, response_code: int, body: Dictionary)
signal request_failed(url: String, error: String)

const BASE_URL = "http://localhost:8000/api/v1"

# API Endpoints
const ENDPOINTS = {
	"login": "/auth/login/",
	"refresh": "/auth/refresh/",
	"vision_jobs": "/vision/jobs/",
	"vision_job_detail": "/vision/jobs/%s/",  # Format with job ID
}

var http_request: HTTPRequest


func _ready() -> void:
	# Create HTTPRequest node
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

	print("[APIManager] Initialized with base URL: ", BASE_URL)


func login(username: String, password: String, callback: Callable) -> void:
	"""
	Login with username and password
	Returns: {access, refresh, user}
	"""
	var url := BASE_URL + ENDPOINTS["login"]
	var data := {
		"username": username,
		"password": password
	}

	_log_request("POST", url, data)
	request_started.emit(url, "POST")

	_make_json_request(url, HTTPClient.METHOD_POST, data, callback)


func refresh_token(refresh: String, callback: Callable) -> void:
	"""
	Refresh access token using refresh token
	Returns: {access}
	"""
	var url := BASE_URL + ENDPOINTS["refresh"]
	var data := {
		"refresh": refresh
	}

	_log_request("POST", url, {"refresh": "[REDACTED]"})
	request_started.emit(url, "POST")

	_make_json_request(url, HTTPClient.METHOD_POST, data, callback)


func create_vision_job(image_data: PackedByteArray, file_name: String, file_type: String,
	access_token: String, callback: Callable) -> void:
	"""
	Upload image for CV analysis
	Requires: Authorization Bearer token
	Returns: AnalysisJob object
	"""
	var url := BASE_URL + ENDPOINTS["vision_jobs"]

	_log_request("POST", url, {"image": file_name, "size": image_data.size()})
	request_started.emit(url, "POST")

	# Build multipart/form-data request
	const boundary := "GodotBiologiDexBoundary"
	var headers := [
		"Content-Type: multipart/form-data; boundary=%s" % boundary,
		"Authorization: Bearer %s" % access_token
	]

	var body := _build_multipart_body(boundary, "image", file_name, file_type, image_data)

	# Make request
	var error := http_request.request_raw(url, headers, HTTPClient.METHOD_POST, body)

	if error != OK:
		var error_msg := "Failed to make request: %s" % error
		_log_error(url, error_msg)
		request_failed.emit(url, error_msg)
		callback.call({"error": error_msg}, 0)
	else:
		# Store callback for response handling
		http_request.set_meta("callback", callback)
		http_request.set_meta("request_url", url)


func get_vision_job(job_id: String, access_token: String, callback: Callable) -> void:
	"""
	Check status of vision analysis job
	Requires: Authorization Bearer token
	Returns: AnalysisJob object
	"""
	var url := BASE_URL + (ENDPOINTS["vision_job_detail"] % job_id)

	_log_request("GET", url, {})
	request_started.emit(url, "GET")

	var headers := [
		"Authorization: Bearer %s" % access_token
	]

	var error := http_request.request(url, headers, HTTPClient.METHOD_GET)

	if error != OK:
		var error_msg := "Failed to make request: %s" % error
		_log_error(url, error_msg)
		request_failed.emit(url, error_msg)
		callback.call({"error": error_msg}, 0)
	else:
		http_request.set_meta("callback", callback)
		http_request.set_meta("request_url", url)


func _make_json_request(url: String, method: HTTPClient.Method, data: Dictionary, callback: Callable) -> void:
	"""Make a JSON request"""
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify(data)

	var error := http_request.request(url, headers, method, body)

	if error != OK:
		var error_msg := "Failed to make request: %s" % error
		_log_error(url, error_msg)
		request_failed.emit(url, error_msg)
		callback.call({"error": error_msg}, 0)
	else:
		# Store callback for response handling
		http_request.set_meta("callback", callback)
		http_request.set_meta("request_url", url)


func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Handle HTTP request completion"""
	var url: String = http_request.get_meta("request_url", "unknown")
	var callback: Callable = http_request.get_meta("callback")

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

	# Emit signal
	if response_code >= 200 and response_code < 300:
		request_completed.emit(url, response_code, response_data)
	else:
		var detail_value = response_data.get("detail")
		var detail: String = "Unknown error" if detail_value == null else str(detail_value)
		var error_msg := "HTTP %d: %s" % [response_code, detail]
		request_failed.emit(url, error_msg)

	# Call callback
	if callback:
		callback.call(response_data, response_code)


func _build_multipart_body(boundary: String, field_name: String, file_name: String,
	file_type: String, file_data: PackedByteArray) -> PackedByteArray:
	"""Build multipart/form-data request body"""
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


func _log_request(method: String, url: String, data: Dictionary) -> void:
	"""Log outgoing request"""
	print("\n[APIManager] === REQUEST ===")
	print("[APIManager] %s %s" % [method, url])
	print("[APIManager] Data: ", JSON.stringify(data, "\t"))


func _log_response(url: String, code: int, data: Dictionary) -> void:
	"""Log incoming response"""
	print("\n[APIManager] === RESPONSE ===")
	print("[APIManager] URL: ", url)
	print("[APIManager] Status: ", code)
	print("[APIManager] Body: ", JSON.stringify(data, "\t"))


func _log_error(url: String, error: String) -> void:
	"""Log request error"""
	print("\n[APIManager] === ERROR ===")
	print("[APIManager] URL: ", url)
	print("[APIManager] Error: ", error)
