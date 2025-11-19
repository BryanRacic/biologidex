extends BaseService
class_name TaxonomyService

## TaxonomyService - Taxonomy database operations

signal search_completed(results: Array)
signal search_failed(error: APITypes.APIError)
signal taxonomy_received(taxonomy: Dictionary)
signal taxonomy_failed(error: APITypes.APIError)

## Search taxonomy database
func search(
	query: String = "",
	genus: String = "",
	species: String = "",
	common_name: String = "",
	rank: String = "",
	kingdom: String = "",
	limit: int = 20,
	callback: Callable = Callable()
) -> void:
	_log("Searching taxonomy database")

	# Build search query - combine all search fields into 'q' parameter
	var search_terms = []
	if not genus.is_empty():
		search_terms.append(genus)
	if not species.is_empty():
		search_terms.append(species)
	if not common_name.is_empty():
		search_terms.append(common_name)
	if not query.is_empty():
		search_terms.append(query)

	var search_query = " ".join(search_terms).strip_edges()

	if search_query.is_empty():
		_log("ERROR: Search query is empty")
		var error = APITypes.APIError.new()
		error.code = 400
		error.message = "Search query cannot be empty"
		search_failed.emit(error)
		if callback and callback.is_valid():
			callback.call({"error": error.message}, 400)
		return

	var params = {"q": search_query, "limit": str(limit)}

	if not rank.is_empty():
		params["rank"] = rank
	if not kingdom.is_empty():
		params["kingdom"] = kingdom

	var url = _build_url_with_params(config.ENDPOINTS_TAXONOMY["search"], params)
	var req_config = _create_request_config(false)  # Public endpoint
	var context = {"callback": callback}

	api_client.request_get(
		url,
		_on_search_success.bind(context),
		_on_search_error.bind(context),
		req_config
	)

func _on_search_success(response: Dictionary, context: Dictionary) -> void:
	var results = response.get("results", [])
	var count = response.get("count", 0)
	_log("Search completed: %d results" % count)
	search_completed.emit(results)
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_search_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "search")
	search_failed.emit(error)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Validate scientific name against taxonomy database
func validate(
	scientific_name: String,
	common_name: String = "",
	confidence: float = 0.0,
	callback: Callable = Callable()
) -> void:
	_log("Validating taxonomy: %s" % scientific_name)

	var data = {
		"scientific_name": scientific_name
	}

	if not common_name.is_empty():
		data["common_name"] = common_name

	if confidence > 0.0:
		data["confidence"] = confidence

	var req_config = _create_request_config(false)  # Public endpoint
	var context = {"callback": callback}

	api_client.post(
		config.ENDPOINTS_TAXONOMY["validate"],
		data,
		_on_validate_success.bind(context),
		_on_validate_error.bind(context),
		req_config
	)

func _on_validate_success(response: Dictionary, context: Dictionary) -> void:
	var is_valid = response.get("valid", false)
	_log("Validation result: %s" % ("valid" if is_valid else "invalid"))
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_validate_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "validate")
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Get single taxonomy record by ID
func get_taxonomy(taxonomy_id: String, callback: Callable = Callable()) -> void:
	_log("Getting taxonomy: %s" % taxonomy_id)

	var endpoint = _format_endpoint(config.ENDPOINTS_TAXONOMY["detail"], [taxonomy_id])
	var req_config = _create_request_config(false)  # Public endpoint
	var context = {"taxonomy_id": taxonomy_id, "callback": callback}

	api_client.request_get(
		endpoint,
		_on_get_taxonomy_success.bind(context),
		_on_get_taxonomy_error.bind(context),
		req_config
	)

func _on_get_taxonomy_success(response: Dictionary, context: Dictionary) -> void:
	_log("Retrieved taxonomy: %s" % context.taxonomy_id)
	taxonomy_received.emit(response)
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_get_taxonomy_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_taxonomy")
	taxonomy_failed.emit(error)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Get taxonomic lineage for a taxon
func get_lineage(taxonomy_id: String, callback: Callable = Callable()) -> void:
	_log("Getting lineage for taxonomy: %s" % taxonomy_id)

	var endpoint = _format_endpoint(config.ENDPOINTS_TAXONOMY["lineage"], [taxonomy_id])
	var req_config = _create_request_config(false)  # Public endpoint
	var context = {"callback": callback}

	api_client.request_get(
		endpoint,
		_on_get_lineage_success.bind(context),
		_on_get_lineage_error.bind(context),
		req_config
	)

func _on_get_lineage_success(response: Dictionary, context: Dictionary) -> void:
	var lineage = response if typeof(response) == TYPE_ARRAY else response.get("results", [])
	_log("Retrieved lineage: %d levels" % lineage.size())
	if context.callback and context.callback.is_valid():
		context.callback.call({"results": lineage}, 200)

func _on_get_lineage_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_lineage")
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)
