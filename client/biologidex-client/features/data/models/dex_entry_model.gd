class_name DexEntryModel extends Resource

# Data model for Dex Entry entities
# Represents a user's observation/collection of an animal

# Core identifiers
@export var id: String = ""
@export var owner_id: String = ""
@export var owner_username: String = ""

# Animal reference
var animal: AnimalModel = null
@export var animal_id: String = ""

# Images
@export var image_url: String = ""
@export var image_path: String = ""  # Local cache path
@export var image_checksum: String = ""
@export var thumbnail_url: String = ""
@export var original_image_url: String = ""
@export var processed_image_url: String = ""

# Metadata
@export var notes: String = ""
@export var visibility: String = "private"  # private, friends, public
@export var is_favorite: bool = false
@export var location: String = ""  # Server uses "location_name"
@export var location_lat: float = 0.0  # GPS latitude
@export var location_lon: float = 0.0  # GPS longitude
@export var captured_at: String = ""  # Server uses "catch_date"

# Customizations (stored as JSON in API)
var customizations: Dictionary = {}

# Source
@export var source_vision_job_id: String = ""
@export var confidence_score: float = 0.0

# Timestamps
@export var created_at: String = ""
@export var updated_at: String = ""

# Local-only fields
@export var is_local_only: bool = false
@export var sync_status: String = "synced"  # synced, pending, failed


# ============================================================================
# Factory Methods
# ============================================================================

static func from_dict(data: Dictionary) -> DexEntryModel:
	"""Create DexEntryModel from API response dictionary"""
	var model = DexEntryModel.new()

	# Core identifiers
	model.id = data.get("id", "")
	model.owner_id = data.get("owner", "")
	model.owner_username = data.get("owner_username", "")

	# Animal data
	if data.has("animal") and data["animal"] is Dictionary:
		model.animal = AnimalModel.from_dict(data["animal"])
		model.animal_id = model.animal.id
	else:
		model.animal_id = data.get("animal", "")

	# Images
	model.image_url = data.get("image", "")
	model.image_checksum = data.get("image_checksum", "")
	model.thumbnail_url = data.get("thumbnail", "")
	model.original_image_url = data.get("original_image", "")
	model.processed_image_url = data.get("processed_image", "")

	# Metadata (handle null values and server field name differences)
	model.notes = data.get("notes", "") if data.get("notes") != null else ""
	model.visibility = data.get("visibility", "private") if data.get("visibility") != null else "private"
	model.is_favorite = data.get("is_favorite", false) if data.get("is_favorite") != null else false
	# Server uses "location_name" for string location
	model.location = data.get("location_name", data.get("location", ""))
	model.location = model.location if model.location != null else ""
	# Server uses "catch_date" for captured timestamp
	model.captured_at = data.get("catch_date", data.get("captured_at", ""))
	model.captured_at = model.captured_at if model.captured_at != null else ""
	# GPS coordinates
	var lat = data.get("location_lat", 0.0)
	model.location_lat = float(lat) if lat != null else 0.0
	var lon = data.get("location_lon", 0.0)
	model.location_lon = float(lon) if lon != null else 0.0

	# Customizations
	if data.has("customizations"):
		model.customizations = data["customizations"]

	# Source
	model.source_vision_job_id = data.get("source_vision_job", "")
	model.confidence_score = data.get("confidence_score", 0.0)

	# Timestamps
	model.created_at = data.get("created_at", "")
	model.updated_at = data.get("updated_at", "")

	return model


func to_dict() -> Dictionary:
	"""Convert model to dictionary for API submission"""
	var data = {
		"id": id,
		"owner": owner_id,
		"animal": animal_id,
		"original_image": image_url,  # Server uses "original_image" not "image"
		"image_checksum": image_checksum,
		"notes": notes,
		"visibility": visibility,
		"is_favorite": is_favorite,
		"location_name": location,  # Server uses "location_name"
		"location_lat": location_lat,
		"location_lon": location_lon,
		"catch_date": captured_at,  # Server uses "catch_date"
		"customizations": customizations,
		"source_vision_job": source_vision_job_id,
		"confidence_score": confidence_score,
		"created_at": created_at,
		"updated_at": updated_at
	}

	# Include animal data if available
	if animal:
		data["animal"] = animal.to_dict()

	return data


static func from_local_dict(data: Dictionary) -> DexEntryModel:
	"""Create DexEntryModel from local storage dictionary"""
	var model = from_dict(data)

	# Add local-only fields
	model.image_path = data.get("image_path", "")
	model.is_local_only = data.get("is_local_only", false)
	model.sync_status = data.get("sync_status", "synced")

	return model


func to_local_dict() -> Dictionary:
	"""Convert model to dictionary for local storage"""
	var data = to_dict()

	# Add local-only fields
	data["image_path"] = image_path
	data["is_local_only"] = is_local_only
	data["sync_status"] = sync_status

	return data


# ============================================================================
# Display Methods
# ============================================================================

func get_display_name() -> String:
	"""Get display name for the entry"""
	if animal:
		return animal.get_display_name()
	return "Unknown Species"


func get_label_text() -> String:
	"""Get text for card label"""
	if animal:
		var name = animal.common_name if not animal.common_name.is_empty() else animal.scientific_name
		if animal.creation_index >= 0:
			return "No. %d - %s" % [animal.creation_index, name]
		return name
	return "Unknown"


func get_metadata_summary() -> String:
	"""Get summary metadata for display"""
	var parts: Array[String] = []

	if animal and animal.creation_index >= 0:
		parts.append("No. %d" % animal.creation_index)

	if not location.is_empty():
		parts.append(location)

	if not captured_at.is_empty():
		# Format date nicely
		var date_parts = captured_at.split("T")
		if date_parts.size() > 0:
			parts.append(date_parts[0])

	return " • ".join(parts)


func get_confidence_display() -> String:
	"""Get formatted confidence score"""
	if confidence_score > 0.0:
		return "%.1f%% confidence" % (confidence_score * 100.0)
	return ""


# ============================================================================
# Validation
# ============================================================================

func is_valid() -> bool:
	"""Check if model has minimum required data"""
	return (not id.is_empty() and
			not owner_id.is_empty() and
			(animal != null or not animal_id.is_empty()))


func has_image() -> bool:
	"""Check if entry has an image"""
	return not image_url.is_empty() or not image_path.is_empty()


func has_local_image() -> bool:
	"""Check if entry has a locally cached image"""
	return not image_path.is_empty()


func needs_sync() -> bool:
	"""Check if entry needs to be synced"""
	return sync_status == "pending" or is_local_only


# ============================================================================
# Image Management
# ============================================================================

func get_image_url_or_path() -> String:
	"""Get image URL or local path (prefer local)"""
	if not image_path.is_empty():
		return image_path
	return image_url


func get_best_image_url() -> String:
	"""Get best quality image URL"""
	if not image_url.is_empty():
		return image_url
	if not processed_image_url.is_empty():
		return processed_image_url
	if not original_image_url.is_empty():
		return original_image_url
	return ""


# ============================================================================
# Visibility
# ============================================================================

func is_visible_to_friends() -> bool:
	"""Check if entry is visible to friends"""
	return visibility == "friends" or visibility == "public"


func is_visible_to_public() -> bool:
	"""Check if entry is visible to public"""
	return visibility == "public"


func set_visibility(new_visibility: String) -> bool:
	"""Set visibility level with validation"""
	if new_visibility in ["private", "friends", "public"]:
		visibility = new_visibility
		return true
	return false


# ============================================================================
# Customizations
# ============================================================================

func set_customization(key: String, value: Variant) -> void:
	"""Set a customization value"""
	customizations[key] = value


func get_customization(key: String, default_value: Variant = null) -> Variant:
	"""Get a customization value"""
	return customizations.get(key, default_value)


func has_customization(key: String) -> bool:
	"""Check if customization exists"""
	return customizations.has(key)


# ============================================================================
# Utility
# ============================================================================

func duplicate_model() -> DexEntryModel:
	"""Create a deep copy of this model"""
	return DexEntryModel.from_local_dict(to_local_dict())


func _to_string() -> String:
	"""String representation for debugging"""
	return "DexEntryModel(%s - %s)" % [id, get_display_name()]
