extends BaseService
class_name VisionService

## VisionService - Computer vision job management

signal job_created(job_data: Dictionary)
signal job_creation_failed(error: APITypes.APIError)
signal job_status_received(job_data: Dictionary)
signal job_status_failed(error: APITypes.APIError)
signal job_completed(job_data: Dictionary)

## Upload image for CV analysis
## Requires: Authorization Bearer token
## Returns: AnalysisJob object
func create_vision_job(
	image_data: PackedByteArray,
	file_name: String,
	file_type: String,
	callback: Callable = Callable(),
	transformations: Dictionary = {}
) -> void:
	_log("Creating vision job for image: %s (%d bytes)" % [file_name, image_data.size()])

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
		config.ENDPOINTS_VISION["jobs"],
		fields,
		_on_create_vision_job_success.bind(context),
		_on_create_vision_job_error.bind(context),
		req_config
	)

func _on_create_vision_job_success(response: Dictionary, context: Dictionary) -> void:
	_log("Vision job created successfully: %s" % response.get("id", ""))
	job_created.emit(response)
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_create_vision_job_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "create_vision_job")
	job_creation_failed.emit(error)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Check status of vision analysis job
## Requires: Authorization Bearer token
## Returns: AnalysisJob object
func get_vision_job(job_id: String, callback: Callable = Callable()) -> void:
	_log("Getting vision job status: %s" % job_id)

	var endpoint = _format_endpoint(config.ENDPOINTS_VISION["job_detail"], [job_id])
	var req_config = _create_request_config()

	var context = {"job_id": job_id, "callback": callback}

	api_client.request_get(
		endpoint,
		_on_get_vision_job_success.bind(context),
		_on_get_vision_job_error.bind(context),
		req_config
	)

func _on_get_vision_job_success(response: Dictionary, context: Dictionary) -> void:
	var status = response.get("status", "unknown")
	_log("Vision job %s status: %s" % [context.job_id, status])

	job_status_received.emit(response)

	# Emit completed signal if job is done
	if status == "completed":
		job_completed.emit(response)

	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_get_vision_job_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_vision_job")
	job_status_failed.emit(error)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Retry a failed vision job
## Requires: Authorization Bearer token
## Returns: AnalysisJob object
func retry_vision_job(
	job_id: String,
	callback: Callable = Callable(),
	transformations: Dictionary = {}
) -> void:
	_log("Retrying vision job: %s" % job_id)

	var endpoint = _format_endpoint(config.ENDPOINTS_VISION["retry"], [job_id])
	var data = {}

	if transformations.size() > 0:
		data["transformations"] = transformations

	var req_config = _create_request_config()

	var context = {"job_id": job_id, "callback": callback}

	api_client.post(
		endpoint,
		data,
		_on_retry_vision_job_success.bind(context),
		_on_retry_vision_job_error.bind(context),
		req_config
	)

func _on_retry_vision_job_success(response: Dictionary, context: Dictionary) -> void:
	_log("Vision job retry initiated: %s" % context.job_id)
	job_created.emit(response)
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_retry_vision_job_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "retry_vision_job")
	job_creation_failed.emit(error)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Get completed vision jobs
## Requires: Authorization Bearer token
## Returns: Array of completed AnalysisJob objects
func get_completed_jobs(callback: Callable = Callable()) -> void:
	_log("Getting completed vision jobs")

	var req_config = _create_request_config()

	var context = {"callback": callback}

	api_client.request_get(
		config.ENDPOINTS_VISION["completed"],
		_on_get_completed_jobs_success.bind(context),
		_on_get_completed_jobs_error.bind(context),
		req_config
	)

func _on_get_completed_jobs_success(response: Dictionary, context: Dictionary) -> void:
	var results = response.get("results", [])
	_log("Received %d completed jobs" % results.size())
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_get_completed_jobs_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_completed_jobs")
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)