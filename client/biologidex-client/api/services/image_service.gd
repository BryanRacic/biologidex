extends BaseService
class_name ImageService

## ImageService - Image conversion and management
## Handles the new two-step upload process:
## 1. Convert image to dex-compatible format
## 2. Download converted image for display

signal image_converted(response: Dictionary)
signal image_conversion_failed(error: APITypes.APIError)
signal image_downloaded(image_data: PackedByteArray)
signal image_download_failed(error: APITypes.APIError)

## Convert an uploaded image to dex-compatible format
## Requires: Authorization Bearer token
## Returns: { conversion_id, download_url, metadata }
func convert_image(
	image_data: PackedByteArray,
	file_name: String,
	file_type: String,
	callback: Callable = Callable(),
	transformations: Dictionary = {}
) -> void:
	_log("Converting image: %s (%d bytes)" % [file_name, image_data.size()])

	# Build multipart form data fields
	var fields = [
		{
			"name": "image",
			"filename": file_name,
			"type": file_type,
			"data": image_data
		}
	]

	# Add transformations if provided
	if transformations.size() > 0:
		_log("Including transformations: %s" % JSON.stringify(transformations))
		fields.append({
			"name": "transformations",
			"data": JSON.stringify(transformations)
		})

	var req_config = _create_request_config(
		true,
		config.UPLOAD_TIMEOUT
	)

	var context = {"callback": callback}

	api_client.post_multipart(
		config.ENDPOINTS_IMAGES["convert"],
		fields,
		_on_convert_image_success.bind(context),
		_on_convert_image_error.bind(context),
		req_config
	)

func _on_convert_image_success(response: Dictionary, context: Dictionary) -> void:
	_log("Image converted successfully: %s" % response.get("id", ""))
	image_converted.emit(response)
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 201)

func _on_convert_image_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "convert_image")
	image_conversion_failed.emit(error)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Download a converted image by conversion ID
## Requires: Authorization Bearer token
## Returns: Image data as PackedByteArray
func download_converted_image(
	conversion_id: String,
	callback: Callable = Callable()
) -> void:
	_log("Downloading converted image: %s" % conversion_id)

	var endpoint = _format_endpoint(config.ENDPOINTS_IMAGES["download"], [conversion_id])
	var req_config = _create_request_config()
	req_config.expect_binary = true  # CRITICAL: Tell HTTP layer to expect binary PNG data

	var context = {"conversion_id": conversion_id, "callback": callback}

	api_client.request_get(
		_build_url(endpoint),
		_on_download_image_success.bind(context),
		_on_download_image_error.bind(context),
		req_config
	)

func _on_download_image_success(response: Dictionary, context: Dictionary) -> void:
	# Response should contain raw image data
	var image_data = response.get("data", PackedByteArray())

	if image_data.size() > 0:
		_log("Downloaded converted image: %d bytes" % image_data.size())
		image_downloaded.emit(image_data)
		if context.callback and context.callback.is_valid():
			context.callback.call({"data": image_data}, 200)
	else:
		var error_msg = "Downloaded image data is empty"
		push_error("[ImageService] %s" % error_msg)
		var error = APITypes.APIError.new()
		error.code = 500
		error.message = error_msg
		image_download_failed.emit(error)
		if context.callback and context.callback.is_valid():
			context.callback.call({"error": error_msg}, 500)

func _on_download_image_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "download_converted_image")
	image_download_failed.emit(error)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Get metadata about a conversion
## Requires: Authorization Bearer token
## Returns: Conversion metadata
func get_conversion_metadata(
	conversion_id: String,
	callback: Callable = Callable()
) -> void:
	_log("Getting conversion metadata: %s" % conversion_id)

	var endpoint = _format_endpoint(config.ENDPOINTS_IMAGES["conversion_detail"], [conversion_id])
	var req_config = _create_request_config()

	var context = {"conversion_id": conversion_id, "callback": callback}

	api_client.request_get(
		_build_url(endpoint),
		_on_get_metadata_success.bind(context),
		_on_get_metadata_error.bind(context),
		req_config
	)

func _on_get_metadata_success(response: Dictionary, context: Dictionary) -> void:
	_log("Retrieved conversion metadata: %s" % response.get("id", ""))
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_get_metadata_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_conversion_metadata")
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)
