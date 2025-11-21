class_name AnimalModel extends Resource

# Data model for Animal entities
# Represents taxonomic information about an animal species

# Core identifiers
@export var id: String = ""
@export var creation_index: int = -1

# Taxonomic hierarchy
@export var scientific_name: String = ""
@export var common_name: String = ""
@export var genus: String = ""
@export var species: String = ""
@export var subspecies: String = ""
@export var family: String = ""
@export var order: String = ""
@export var animal_class: String = ""  # 'class' is reserved
@export var phylum: String = ""
@export var kingdom: String = ""

# Additional metadata
@export var verified: bool = false
@export var source_taxon_id: String = ""
@export var description: String = ""
@export var habitat: String = ""
@export var conservation_status: String = ""

# Timestamps
@export var created_at: String = ""
@export var updated_at: String = ""


# ============================================================================
# Factory Methods
# ============================================================================

static func from_dict(data: Dictionary) -> AnimalModel:
	"""Create AnimalModel from API response dictionary"""
	var model = AnimalModel.new()

	# Core identifiers
	model.id = data.get("id", "")
	model.creation_index = data.get("creation_index", -1)

	# Taxonomic hierarchy
	model.scientific_name = data.get("scientific_name", "")
	model.common_name = data.get("common_name", "")
	model.genus = data.get("genus", "")
	model.species = data.get("species", "")
	model.subspecies = data.get("subspecies", "")
	model.family = data.get("family", "")
	model.order = data.get("order", "")
	model.animal_class = data.get("class", "")
	model.phylum = data.get("phylum", "")
	model.kingdom = data.get("kingdom", "")

	# Metadata
	model.verified = data.get("verified", false)
	model.source_taxon_id = data.get("source_taxon_id", "")
	model.description = data.get("description", "")
	model.habitat = data.get("habitat", "")
	model.conservation_status = data.get("conservation_status", "")

	# Timestamps
	model.created_at = data.get("created_at", "")
	model.updated_at = data.get("updated_at", "")

	return model


func to_dict() -> Dictionary:
	"""Convert model to dictionary for API submission"""
	return {
		"id": id,
		"creation_index": creation_index,
		"scientific_name": scientific_name,
		"common_name": common_name,
		"genus": genus,
		"species": species,
		"subspecies": subspecies,
		"family": family,
		"order": order,
		"class": animal_class,
		"phylum": phylum,
		"kingdom": kingdom,
		"verified": verified,
		"source_taxon_id": source_taxon_id,
		"description": description,
		"habitat": habitat,
		"conservation_status": conservation_status,
		"created_at": created_at,
		"updated_at": updated_at
	}


# ============================================================================
# Display Methods
# ============================================================================

func get_display_name() -> String:
	"""Get formatted display name (common name or scientific name)"""
	if not common_name.is_empty():
		return common_name
	if not scientific_name.is_empty():
		return scientific_name
	return "Unknown Species"


func get_full_scientific_name() -> String:
	"""Get full scientific name with genus, species, subspecies"""
	var parts: Array[String] = []

	if not genus.is_empty():
		parts.append(genus)
	if not species.is_empty():
		parts.append(species)
	if not subspecies.is_empty():
		parts.append(subspecies)

	if parts.is_empty():
		return scientific_name

	return " ".join(parts)


func get_taxonomic_rank() -> String:
	"""Get the most specific taxonomic rank available"""
	if not subspecies.is_empty():
		return "Subspecies"
	if not species.is_empty():
		return "Species"
	if not genus.is_empty():
		return "Genus"
	if not family.is_empty():
		return "Family"
	if not order.is_empty():
		return "Order"
	if not animal_class.is_empty():
		return "Class"
	if not phylum.is_empty():
		return "Phylum"
	if not kingdom.is_empty():
		return "Kingdom"
	return "Unknown"


func get_hierarchical_display() -> String:
	"""Get hierarchical taxonomic display"""
	var parts: Array[String] = []

	if not kingdom.is_empty():
		parts.append("Kingdom: %s" % kingdom)
	if not phylum.is_empty():
		parts.append("Phylum: %s" % phylum)
	if not animal_class.is_empty():
		parts.append("Class: %s" % animal_class)
	if not order.is_empty():
		parts.append("Order: %s" % order)
	if not family.is_empty():
		parts.append("Family: %s" % family)

	return "\n".join(parts)


# ============================================================================
# Validation
# ============================================================================

func is_valid() -> bool:
	"""Check if model has minimum required data"""
	return not id.is_empty() and (not scientific_name.is_empty() or not common_name.is_empty())


func is_identified_to_species() -> bool:
	"""Check if animal is identified to species level"""
	return not genus.is_empty() and not species.is_empty()


# ============================================================================
# Comparison
# ============================================================================

func equals(other: AnimalModel) -> bool:
	"""Check if two animal models are the same species"""
	if not other:
		return false

	# Compare by ID if available
	if not id.is_empty() and not other.id.is_empty():
		return id == other.id

	# Compare by scientific name
	if not scientific_name.is_empty() and not other.scientific_name.is_empty():
		return scientific_name == other.scientific_name

	# Compare by taxonomic components
	return (genus == other.genus and
			species == other.species and
			subspecies == other.subspecies)


# ============================================================================
# Utility
# ============================================================================

func duplicate_model() -> AnimalModel:
	"""Create a deep copy of this model"""
	return AnimalModel.from_dict(to_dict())


func _to_string() -> String:
	"""String representation for debugging"""
	return "AnimalModel(%s - %s)" % [creation_index, get_display_name()]