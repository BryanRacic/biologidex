class_name AnalysisJobModel extends Resource

# Data model for CV Analysis Job entities
# Represents a computer vision analysis job for animal identification

# Core identifiers
@export var id: String = ""
@export var owner_id: String = ""

# Status tracking
@export var status: String = "pending"  # pending, processing, completed, failed
@export var progress: float = 0.0  # 0.0 to 1.0

# Image references
@export var conversion_id: String = ""  # UUID from image conversion
@export var image_url: String = ""  # Deprecated direct upload
@export var dex_compatible_image_url: String = ""  # Processed PNG

# Post-conversion transformations (rotation, etc.)
var post_conversion_transformations: Dictionary = {}

# Multiple animal detection
var detected_animals: Array[AnimalModel] = []
@export var detected_animals_raw: Array = []  # For serialization
@export var selected_animal_index: int = -1

# Legacy single animal reference (for backward compatibility)
var identified_animal: AnimalModel = null
@export var identified_animal_id: String = ""

# Analysis results
@export var confidence_score: float = 0.0
@export var error_message: String = ""
@export var retry_count: int = 0

# Timestamps
@export var created_at: String = ""
@export var updated_at: String = ""
@export var completed_at: String = ""


# ============================================================================
# Factory Methods
# ============================================================================

static func from_dict(data: Dictionary) -> AnalysisJobModel:
	"""Create AnalysisJobModel from API response dictionary"""
	var model = AnalysisJobModel.new()

	# Core identifiers (handle null values from API)
	model.id = data.get("id", "") if data.get("id") != null else ""
	# API uses "user" field, not "owner"
	var owner = data.get("user", data.get("owner", ""))
	model.owner_id = owner if owner != null else ""

	# Status
	model.status = data.get("status", "pending")
	model.progress = data.get("progress", 0.0)

	# Images (handle null values from API)
	model.conversion_id = data.get("source_conversion", "") if data.get("source_conversion") != null else ""
	model.image_url = data.get("image", "") if data.get("image") != null else ""
	# API returns "dex_compatible_url" for the image URL
	var dex_url = data.get("dex_compatible_url", data.get("dex_compatible_image", ""))
	model.dex_compatible_image_url = dex_url if dex_url != null else ""

	# Post-conversion transformations
	if data.has("post_conversion_transformations"):
		model.post_conversion_transformations = data["post_conversion_transformations"]

	# Multiple animal detection
	if data.has("detected_animals") and data["detected_animals"] is Array:
		for animal_data in data["detected_animals"]:
			if animal_data is Dictionary:
				var animal = AnimalModel.from_dict(animal_data)
				model.detected_animals.append(animal)

	# Selected animal index (handle null from API)
	var selected_idx = data.get("selected_animal_index", -1)
	model.selected_animal_index = int(selected_idx) if selected_idx != null else -1

	# Parse animal_details (full animal data with creation_index)
	if data.has("animal_details") and data["animal_details"] is Dictionary:
		model.identified_animal = AnimalModel.from_dict(data["animal_details"])
		model.identified_animal_id = model.identified_animal.id

		# Merge animal_details into corresponding detected_animals entry
		# This ensures detected_animals has complete data including creation_index
		for i in range(model.detected_animals.size()):
			if model.detected_animals[i].id == model.identified_animal.id:
				# Merge complete data from animal_details
				model.detected_animals[i] = model.identified_animal.duplicate_model()
				break

	# Legacy identified animal (fallback if no animal_details)
	elif data.has("identified_animal"):
		var animal_data = data["identified_animal"]
		if animal_data is Dictionary:
			model.identified_animal = AnimalModel.from_dict(animal_data)
			model.identified_animal_id = model.identified_animal.id
		elif animal_data is String:
			model.identified_animal_id = animal_data

	# Results (handle null values from API)
	model.confidence_score = data.get("confidence_score", 0.0) if data.get("confidence_score") != null else 0.0
	model.error_message = data.get("error_message", "") if data.get("error_message") != null else ""
	model.retry_count = int(data.get("retry_count", 0)) if data.get("retry_count") != null else 0

	# Timestamps (handle null values from API)
	model.created_at = data.get("created_at", "") if data.get("created_at") != null else ""
	model.updated_at = data.get("updated_at", "") if data.get("updated_at") != null else ""
	model.completed_at = data.get("completed_at", "") if data.get("completed_at") != null else ""

	return model


func to_dict() -> Dictionary:
	"""Convert model to dictionary for API submission"""
	var data = {
		"id": id,
		"user": owner_id,  # Server uses "user" not "owner"
		"status": status,
		"progress": progress,
		"source_conversion": conversion_id,
		"image": image_url,
		"dex_compatible_url": dex_compatible_image_url,  # Server uses "dex_compatible_url"
		"post_conversion_transformations": post_conversion_transformations,
		"selected_animal_index": selected_animal_index,
		"confidence_score": confidence_score,
		"error_message": error_message,
		"retry_count": retry_count,
		"created_at": created_at,
		"updated_at": updated_at,
		"completed_at": completed_at
	}

	# Add detected animals
	var animals_array: Array = []
	for animal in detected_animals:
		animals_array.append(animal.to_dict())
	data["detected_animals"] = animals_array

	# Add identified animal (legacy)
	if identified_animal:
		data["identified_animal"] = identified_animal.to_dict()
	elif not identified_animal_id.is_empty():
		data["identified_animal"] = identified_animal_id

	return data


# ============================================================================
# Status Checking
# ============================================================================

func is_pending() -> bool:
	"""Check if job is pending"""
	return status == "pending"


func is_processing() -> bool:
	"""Check if job is processing"""
	return status == "processing"


func is_completed() -> bool:
	"""Check if job completed successfully"""
	return status == "completed"


func is_failed() -> bool:
	"""Check if job failed"""
	return status == "failed"


func is_done() -> bool:
	"""Check if job is in a terminal state (completed or failed)"""
	return is_completed() or is_failed()


func is_in_progress() -> bool:
	"""Check if job is actively running"""
	return is_pending() or is_processing()


# ============================================================================
# Animal Detection
# ============================================================================

func has_detected_animals() -> bool:
	"""Check if any animals were detected"""
	return detected_animals.size() > 0


func get_detected_animal_count() -> int:
	"""Get number of detected animals"""
	return detected_animals.size()


func has_multiple_animals() -> bool:
	"""Check if multiple animals were detected"""
	return detected_animals.size() > 1


func get_selected_animal() -> AnimalModel:
	"""Get the selected animal (or first one if not set)"""
	if selected_animal_index >= 0 and selected_animal_index < detected_animals.size():
		return detected_animals[selected_animal_index]
	elif detected_animals.size() > 0:
		return detected_animals[0]
	elif identified_animal:
		return identified_animal
	return null


func select_animal(index: int) -> bool:
	"""Select an animal from detected animals by index"""
	if index >= 0 and index < detected_animals.size():
		selected_animal_index = index
		# Also set as identified_animal for backward compatibility
		identified_animal = detected_animals[index]
		identified_animal_id = identified_animal.id
		return true
	return false


func get_all_detected_animals() -> Array[AnimalModel]:
	"""Get all detected animals"""
	return detected_animals


# ============================================================================
# Transformations
# ============================================================================

func set_transformation(key: String, value: Variant) -> void:
	"""Set a post-conversion transformation"""
	post_conversion_transformations[key] = value


func get_transformation(key: String, default_value: Variant = null) -> Variant:
	"""Get a transformation value"""
	return post_conversion_transformations.get(key, default_value)


func has_transformations() -> bool:
	"""Check if any transformations were applied"""
	return not post_conversion_transformations.is_empty()


func get_rotation() -> int:
	"""Get rotation transformation (0, 90, 180, 270)"""
	return post_conversion_transformations.get("rotation", 0)


func set_rotation(degrees: int) -> void:
	"""Set rotation transformation"""
	post_conversion_transformations["rotation"] = degrees % 360


# ============================================================================
# Display Methods
# ============================================================================

func get_status_display() -> String:
	"""Get formatted status for display"""
	match status:
		"pending":
			return "Waiting..."
		"processing":
			return "Analyzing... %.0f%%" % (progress * 100.0)
		"completed":
			return "Complete"
		"failed":
			return "Failed"
		_:
			return status.capitalize()


func get_error_display() -> String:
	"""Get formatted error message"""
	if error_message.is_empty():
		return "Unknown error"
	return error_message


func get_progress_percentage() -> int:
	"""Get progress as percentage (0-100)"""
	return int(progress * 100.0)


# ============================================================================
# Validation
# ============================================================================

func is_valid() -> bool:
	"""Check if model has minimum required data"""
	return not id.is_empty()


func can_retry() -> bool:
	"""Check if job can be retried"""
	return is_failed() and retry_count < 3


# ============================================================================
# Utility
# ============================================================================

func duplicate_model() -> AnalysisJobModel:
	"""Create a deep copy of this model"""
	return AnalysisJobModel.from_dict(to_dict())


func _to_string() -> String:
	"""String representation for debugging"""
	return "AnalysisJobModel(%s - %s)" % [id, status]
