class_name CVAnalysisWorkflow extends Node

# CV Analysis Workflow Manager
# Handles the complete two-step CV analysis process:
# 1. Upload → Convert to PNG
# 2. Download converted image → Submit for analysis → Poll for results
# Includes comprehensive error handling and retry logic

signal analysis_started
signal analysis_progress(stage: String, message: String, progress: float)
signal conversion_complete(conversion_id: String)
signal image_downloaded(image_data: PackedByteArray)
signal analysis_submitted(job_id: String)
signal analysis_complete(job_model: AnalysisJobModel)
signal analysis_failed(error_type: String, message: String, code: int)
signal retry_available

enum AnalysisStage {
	IDLE,
	CONVERTING,      # Uploading and converting image
	DOWNLOADING,     # Downloading converted PNG
	ANALYZING,       # Submitting analysis job
	POLLING,         # Polling for results
	COMPLETE,        # Successfully completed
	FAILED           # Failed with error
}

# Dependencies (injected or autoloaded)
var APIManager
var DexDatabase

# Configuration
@export var enable_auto_retry: bool = true
@export var max_retries: int = 3
@export var poll_interval: float = 2.0  # seconds
@export var poll_timeout: float = 120.0  # seconds

# State
var current_stage: AnalysisStage = AnalysisStage.IDLE
var state_machine: StateMachine

# Data
var source_image_path: String = ""
var source_image_data: PackedByteArray = PackedByteArray()
var conversion_id: String = ""
var converted_image_data: PackedByteArray = PackedByteArray()
var job_id: String = ""
var job_model: AnalysisJobModel = null
var transformations: Dictionary = {}  # Post-conversion transformations

# Error tracking
var last_error: Dictionary = {}
var retry_count: int = 0

# Polling
var poll_timer: Timer = null
var poll_elapsed: float = 0.0


func _ready() -> void:
	_initialize_dependencies()
	_setup_state_machine()
	_setup_polling()


# ============================================================================
# Initialization
# ============================================================================

func _initialize_dependencies() -> void:
	"""Initialize service dependencies"""
	if not APIManager:
		APIManager = get_node("/root/APIManager")
	if not DexDatabase:
		DexDatabase = get_node("/root/DexDatabase")


func _setup_state_machine() -> void:
	"""Setup state machine for workflow tracking"""
	state_machine = StateMachine.new()
	state_machine.initial_state = AnalysisStage.IDLE
	state_machine.enable_logging = true
	state_machine.set_state_names({
		AnalysisStage.IDLE: "IDLE",
		AnalysisStage.CONVERTING: "CONVERTING",
		AnalysisStage.DOWNLOADING: "DOWNLOADING",
		AnalysisStage.ANALYZING: "ANALYZING",
		AnalysisStage.POLLING: "POLLING",
		AnalysisStage.COMPLETE: "COMPLETE",
		AnalysisStage.FAILED: "FAILED"
	})
	add_child(state_machine)
	state_machine.state_changed.connect(_on_state_changed)


func _setup_polling() -> void:
	"""Setup polling timer"""
	poll_timer = Timer.new()
	poll_timer.wait_time = poll_interval
	poll_timer.timeout.connect(_on_poll_timer_timeout)
	add_child(poll_timer)


# ============================================================================
# Public API - Start Analysis
# ============================================================================

func start_analysis_from_path(image_path: String, post_transformations: Dictionary = {}) -> void:
	"""Start CV analysis from an image file path"""
	# Load image data
	var file = FileAccess.open(image_path, FileAccess.READ)
	if not file:
		_handle_error(AnalysisStage.IDLE, 0, "Failed to open image file: %s" % image_path)
		return

	var data = file.get_buffer(file.get_length())
	file.close()

	start_analysis_from_data(data, post_transformations)
	source_image_path = image_path


func start_analysis_from_data(image_data: PackedByteArray, post_transformations: Dictionary = {}) -> void:
	"""Start CV analysis from image byte data"""
	# Reset state
	_reset_state()

	# Store data
	source_image_data = image_data
	transformations = post_transformations
	retry_count = 0

	# Start workflow
	_transition_to(AnalysisStage.CONVERTING)
	analysis_started.emit()
	_emit_progress("Converting", "Uploading and converting image...", 0.1)

	# Step 1: Convert image
	_upload_and_convert()


# ============================================================================
# Public API - Control
# ============================================================================

func retry_analysis() -> void:
	"""Retry the analysis from the last successful stage"""
	if last_error.is_empty():
		push_warning("[CVAnalysisWorkflow] No error to retry")
		return

	if retry_count >= max_retries:
		push_error("[CVAnalysisWorkflow] Max retries exceeded")
		return

	retry_count += 1
	print("[CVAnalysisWorkflow] Retrying analysis (attempt %d/%d)" % [retry_count, max_retries])

	# Determine what stage to retry from
	var retry_stage = last_error.get("stage", AnalysisStage.IDLE)

	match retry_stage:
		AnalysisStage.CONVERTING:
			# Retry entire upload + conversion
			_transition_to(AnalysisStage.CONVERTING)
			_emit_progress("Retrying", "Retrying image conversion...", 0.1)
			_upload_and_convert()

		AnalysisStage.DOWNLOADING:
			# Retry download only
			_transition_to(AnalysisStage.DOWNLOADING)
			_emit_progress("Retrying", "Retrying image download...", 0.3)
			_download_converted_image()

		AnalysisStage.ANALYZING:
			# Retry analysis submission
			_transition_to(AnalysisStage.ANALYZING)
			_emit_progress("Retrying", "Retrying analysis submission...", 0.5)
			_submit_analysis()

		AnalysisStage.POLLING:
			# Resume polling
			_transition_to(AnalysisStage.POLLING)
			_emit_progress("Retrying", "Resuming status check...", 0.7)
			_start_polling()


func cancel_analysis() -> void:
	"""Cancel ongoing analysis"""
	print("[CVAnalysisWorkflow] Analysis cancelled")
	_stop_polling()
	_reset_state()
	_transition_to(AnalysisStage.IDLE)


# ============================================================================
# Public API - Getters
# ============================================================================

func get_current_stage() -> AnalysisStage:
	"""Get current workflow stage"""
	return current_stage


func get_job_model() -> AnalysisJobModel:
	"""Get current analysis job model"""
	return job_model


func get_last_error() -> Dictionary:
	"""Get last error information"""
	return last_error


func is_in_progress() -> bool:
	"""Check if analysis is currently in progress"""
	return current_stage in [
		AnalysisStage.CONVERTING,
		AnalysisStage.DOWNLOADING,
		AnalysisStage.ANALYZING,
		AnalysisStage.POLLING
	]


# ============================================================================
# Workflow Steps
# ============================================================================

func _upload_and_convert() -> void:
	"""Step 1: Upload image and convert to PNG"""
	if source_image_data.is_empty():
		_handle_error(AnalysisStage.CONVERTING, 0, "No image data to upload")
		return

	# Determine filename and type
	var file_name = "image.jpg"
	if not source_image_path.is_empty():
		file_name = source_image_path.get_file()

	var file_type = "image/jpeg"
	if file_name.ends_with(".png"):
		file_type = "image/png"
	elif file_name.ends_with(".jpg") or file_name.ends_with(".jpeg"):
		file_type = "image/jpeg"

	# Call image conversion API (single callback handles both success/error)
	APIManager.images.convert_image(
		source_image_data,
		file_name,
		file_type,
		_on_conversion_response,
		transformations
	)


func _on_conversion_response(response: Dictionary, code: int) -> void:
	"""Unified callback for conversion (routes to success or error handler)"""
	if code == 200 or code == 201:
		_on_conversion_complete(response, code)
	else:
		_on_conversion_failed(response, code)


func _on_conversion_complete(response: Dictionary, code: int) -> void:
	"""Handle successful image conversion"""
	if code != 200 and code != 201:
		_handle_error(AnalysisStage.CONVERTING, code, response.get("message", "Conversion failed"))
		return

	conversion_id = response.get("id", "")
	if conversion_id.is_empty():
		_handle_error(AnalysisStage.CONVERTING, 0, "No conversion ID in response")
		return

	print("[CVAnalysisWorkflow] Conversion complete: %s" % conversion_id)
	conversion_complete.emit(conversion_id)

	# Step 2: Download converted image
	_transition_to(AnalysisStage.DOWNLOADING)
	_emit_progress("Downloading", "Downloading converted image...", 0.3)
	_download_converted_image()


func _on_conversion_failed(response: Dictionary, code: int) -> void:
	"""Handle image conversion failure"""
	var message = response.get("message", "Image conversion failed")
	_handle_error(AnalysisStage.CONVERTING, code, message)


func _download_converted_image() -> void:
	"""Step 2: Download the converted PNG image"""
	if conversion_id.is_empty():
		_handle_error(AnalysisStage.DOWNLOADING, 0, "No conversion ID to download")
		return

	# Call download API (single callback)
	APIManager.images.download_converted_image(
		conversion_id,
		_on_download_response
	)


func _on_download_response(response: Dictionary, code: int) -> void:
	"""Unified callback for download (routes to success or error handler)"""
	if code == 200:
		_on_download_complete(response, code)
	else:
		_on_download_failed(response, code)


func _on_download_complete(response: Dictionary, _code: int) -> void:
	"""Handle successful image download"""
	var image_data: PackedByteArray = response.get("data", PackedByteArray())

	if image_data.is_empty():
		_handle_error(AnalysisStage.DOWNLOADING, 0, "Downloaded image is empty")
		return

	converted_image_data = image_data
	print("[CVAnalysisWorkflow] Downloaded converted image (%d bytes)" % image_data.size())
	image_downloaded.emit(image_data)

	# Step 3: Submit for analysis
	_transition_to(AnalysisStage.ANALYZING)
	_emit_progress("Analyzing", "Submitting for CV analysis...", 0.5)
	_submit_analysis()


func _on_download_failed(response: Dictionary, code: int) -> void:
	"""Handle image download failure"""
	var message = response.get("message", "Image download failed")
	_handle_error(AnalysisStage.DOWNLOADING, code, message)


func _submit_analysis() -> void:
	"""Step 3: Submit analysis job with conversion ID and transformations"""
	if conversion_id.is_empty():
		_handle_error(AnalysisStage.ANALYZING, 0, "No conversion ID for analysis")
		return

	# Call vision API (single callback)
	APIManager.vision.create_vision_job_from_conversion(
		conversion_id,
		_on_analysis_response,
		transformations
	)


func _on_analysis_response(response: Dictionary, code: int) -> void:
	"""Unified callback for analysis submission (routes to success or error handler)"""
	if code == 200 or code == 201:
		_on_analysis_submitted(response, code)
	else:
		_on_analysis_submit_failed(response, code)


func _on_analysis_submitted(response: Dictionary, code: int) -> void:
	"""Handle successful analysis submission"""
	if code != 200 and code != 201:
		_handle_error(AnalysisStage.ANALYZING, code, response.get("message", "Analysis submission failed"))
		return

	job_id = response.get("id", "")
	if job_id.is_empty():
		_handle_error(AnalysisStage.ANALYZING, 0, "No job ID in response")
		return

	# Create job model
	job_model = AnalysisJobModel.from_dict(response)

	print("[CVAnalysisWorkflow] Analysis submitted: %s" % job_id)
	analysis_submitted.emit(job_id)

	# Step 4: Start polling for results
	_transition_to(AnalysisStage.POLLING)
	_emit_progress("Processing", "Waiting for analysis results...", 0.7)
	_start_polling()


func _on_analysis_submit_failed(response: Dictionary, code: int) -> void:
	"""Handle analysis submission failure"""
	var message = response.get("message", "Analysis submission failed")
	_handle_error(AnalysisStage.ANALYZING, code, message)


func _start_polling() -> void:
	"""Step 4: Start polling for job status"""
	poll_elapsed = 0.0
	if poll_timer:
		poll_timer.start()
	_check_job_status()


func _stop_polling() -> void:
	"""Stop polling for job status"""
	if poll_timer and not poll_timer.is_stopped():
		poll_timer.stop()


func _on_poll_timer_timeout() -> void:
	"""Handle poll timer timeout"""
	poll_elapsed += poll_interval

	# Check for overall timeout
	if poll_elapsed >= poll_timeout:
		_stop_polling()
		_handle_error(AnalysisStage.POLLING, 408, "Analysis timed out")
		return

	_check_job_status()


func _check_job_status() -> void:
	"""Check job status via API"""
	if job_id.is_empty():
		_handle_error(AnalysisStage.POLLING, 0, "No job ID to check status")
		return

	# Call vision API (single callback)
	APIManager.vision.get_vision_job(
		job_id,
		_on_job_status_response
	)


func _on_job_status_response(response: Dictionary, code: int) -> void:
	"""Unified callback for job status (routes to success or error handler)"""
	if code == 200:
		_on_job_status_received(response, code)
	else:
		_on_job_status_failed(response, code)


func _on_job_status_received(response: Dictionary, code: int) -> void:
	"""Handle job status response"""
	if code != 200:
		_handle_error(AnalysisStage.POLLING, code, response.get("message", "Status check failed"))
		return

	# Update job model
	job_model = AnalysisJobModel.from_dict(response)
	var status = job_model.status

	match status:
		"pending", "processing":
			# Continue polling
			var progress = 0.7 + (job_model.progress * 0.2)
			_emit_progress("Processing", "Analyzing image... %.0f%%" % (job_model.progress * 100.0), progress)

		"completed":
			# Analysis complete!
			_stop_polling()
			_on_analysis_complete()

		"failed":
			# Analysis failed
			_stop_polling()
			var error_msg = job_model.error_message
			if error_msg.is_empty():
				error_msg = "Analysis failed on server"
			_handle_error(AnalysisStage.POLLING, 500, error_msg)


func _on_job_status_failed(_response: Dictionary, code: int) -> void:
	"""Handle job status check failure"""
	# For polling errors, we can continue trying
	push_warning("[CVAnalysisWorkflow] Status check failed (code %d), will retry" % code)
	# Don't call _handle_error here, just continue polling


func _on_analysis_complete() -> void:
	"""Handle successful analysis completion"""
	_transition_to(AnalysisStage.COMPLETE)
	_emit_progress("Complete", "Analysis complete!", 1.0)

	print("[CVAnalysisWorkflow] Analysis complete: %d animals detected" % job_model.get_detected_animal_count())
	analysis_complete.emit(job_model)


# ============================================================================
# Error Handling
# ============================================================================

func _handle_error(stage: AnalysisStage, code: int, message: String) -> void:
	"""Handle workflow error"""
	_transition_to(AnalysisStage.FAILED)
	_stop_polling()

	# Classify error
	var context = ErrorHandler.create_error_context("CV Analysis", {
		"stage": state_machine.state_names.get(stage, str(stage)),
		"retry_count": retry_count
	})
	var error = ErrorHandler.classify_error(code, message, context)

	# Store error for retry
	last_error = error.duplicate()
	last_error["stage"] = stage

	# Log error
	ErrorHandler.log_error(error)

	# Determine error type for signal
	var error_type = "NETWORK_ERROR"
	if code >= 400 and code < 600:
		error_type = "API_ERROR"
	elif code == 0:
		error_type = "NETWORK_ERROR"

	# Emit failure signal
	analysis_failed.emit(error_type, message, code)

	# Offer retry if applicable
	if enable_auto_retry and ErrorHandler.should_retry(error, retry_count):
		retry_available.emit()


# ============================================================================
# State Management
# ============================================================================

func _transition_to(new_stage: AnalysisStage) -> void:
	"""Transition to a new workflow stage"""
	if state_machine:
		state_machine.transition_to(new_stage)
	current_stage = new_stage


func _on_state_changed(old_state: int, new_state: int) -> void:
	"""Handle state machine transitions"""
	print("[CVAnalysisWorkflow] State: %s -> %s" % [
		state_machine.state_names.get(old_state, str(old_state)),
		state_machine.state_names.get(new_state, str(new_state))
	])


func _reset_state() -> void:
	"""Reset workflow state"""
	conversion_id = ""
	converted_image_data = PackedByteArray()
	job_id = ""
	job_model = null
	transformations = {}
	last_error = {}
	poll_elapsed = 0.0


# ============================================================================
# Progress Reporting
# ============================================================================

func _emit_progress(stage: String, message: String, progress: float) -> void:
	"""Emit progress signal"""
	analysis_progress.emit(stage, message, progress)
