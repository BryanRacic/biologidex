extends BaseService
class_name AnimalsService

## AnimalsService - Animal database operations

signal animals_list_received(animals: Array)
signal animals_list_failed(error: APITypes.APIError)
signal animal_received(animal: Dictionary)
signal animal_failed(error: APITypes.APIError)
signal animal_created(animal: Dictionary, was_new: bool)
signal animal_creation_failed(error: APITypes.APIError)

## Get list of animals with optional filtering
func list(
	search: String = "",
	conservation_status: String = "",
	verified_only: bool = false,
	callback: Callable = Callable()
) -> void:
	_log("Getting animals list")

	var params = {}
	if not search.is_empty():
		params["search"] = search
	if not conservation_status.is_empty():
		params["conservation_status"] = conservation_status
	if verified_only:
		params["verified"] = "true"

	var url = config.ENDPOINTS_ANIMALS["list"]
	if params.size() > 0:
		url = _build_url_with_params(url, params)

	var req_config = _create_request_config(false)  # Public endpoint
	var context = {"callback": callback}

	api_client.request_get(
		url,
		_on_list_success.bind(context),
		_on_list_error.bind(context),
		req_config
	)

func _on_list_success(response: Dictionary, context: Dictionary) -> void:
	var animals = response.get("results", [])
	_log("Received %d animals" % animals.size())
	animals_list_received.emit(animals)
	if context.callback:
		context.callback.call(response, 200)

func _on_list_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "list")
	animals_list_failed.emit(error)
	if context.callback:
		context.callback.call({"error": error.message}, error.code)

## Get single animal by ID
func get_animal(animal_id: String, callback: Callable = Callable()) -> void:
	_log("Getting animal: %s" % animal_id)

	var endpoint = config.ENDPOINTS_ANIMALS["list"] + animal_id + "/"
	var req_config = _create_request_config(false)  # Public endpoint
	var context = {"animal_id": animal_id, "callback": callback}

	api_client.request_get(
		endpoint,
		_on_get_animal_success.bind(context),
		_on_get_animal_error.bind(context),
		req_config
	)

func _on_get_animal_success(response: Dictionary, context: Dictionary) -> void:
	_log("Retrieved animal: %s" % context.animal_id)
	animal_received.emit(response)
	if context.callback:
		context.callback.call(response, 200)

func _on_get_animal_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_animal")
	animal_failed.emit(error)
	if context.callback:
		context.callback.call({"error": error.message}, error.code)

## Look up animal by scientific name, or create if doesn't exist
## Used by CV identification pipeline
## Requires: Authorization Bearer token
func lookup_or_create(
	scientific_name: String,
	common_name: String = "",
	additional_data: Dictionary = {},
	callback: Callable = Callable()
) -> void:
	_log("Looking up or creating animal: %s (%s)" % [scientific_name, common_name])

	var data = {
		"scientific_name": scientific_name
	}

	if not common_name.is_empty():
		data["common_name"] = common_name

	# Merge additional data (taxonomy, conservation status, etc.)
	for key in additional_data:
		data[key] = additional_data[key]

	var req_config = _create_request_config()
	var context = {"callback": callback}

	api_client.post(
		config.ENDPOINTS_ANIMALS["lookup_or_create"],
		data,
		_on_lookup_or_create_success.bind(context),
		_on_lookup_or_create_error.bind(context),
		req_config
	)

func _on_lookup_or_create_success(response: Dictionary, context: Dictionary) -> void:
	var was_created = response.get("created", false)
	var animal = response.get("animal", {})
	_log("Animal %s: %s" % ["created" if was_created else "found", animal.get("scientific_name", "")])
	animal_created.emit(animal, was_created)
	if context.callback:
		context.callback.call(response, 200)

func _on_lookup_or_create_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "lookup_or_create")
	animal_creation_failed.emit(error)
	if context.callback:
		context.callback.call({"error": error.message}, error.code)

## Get recently discovered animals
func get_recent(callback: Callable = Callable()) -> void:
	_log("Getting recently discovered animals")

	var endpoint = config.ENDPOINTS_ANIMALS["list"] + "recent/"
	var req_config = _create_request_config(false)  # Public endpoint
	var context = {"callback": callback}

	api_client.request_get(
		endpoint,
		_on_get_recent_success.bind(context),
		_on_get_recent_error.bind(context),
		req_config
	)

func _on_get_recent_success(response: Dictionary, context: Dictionary) -> void:
	var animals = response if typeof(response) == TYPE_ARRAY else response.get("results", [])
	_log("Received %d recent animals" % animals.size())
	if context.callback:
		context.callback.call({"results": animals}, 200)

func _on_get_recent_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_recent")
	if context.callback:
		context.callback.call({"error": error.message}, error.code)

## Get most captured/popular animals
func get_popular(callback: Callable = Callable()) -> void:
	_log("Getting popular animals")

	var endpoint = config.ENDPOINTS_ANIMALS["list"] + "popular/"
	var req_config = _create_request_config(false)  # Public endpoint
	var context = {"callback": callback}

	api_client.request_get(
		endpoint,
		_on_get_popular_success.bind(context),
		_on_get_popular_error.bind(context),
		req_config
	)

func _on_get_popular_success(response: Dictionary, context: Dictionary) -> void:
	var animals = response if typeof(response) == TYPE_ARRAY else response.get("results", [])
	_log("Received %d popular animals" % animals.size())
	if context.callback:
		context.callback.call({"results": animals}, 200)

func _on_get_popular_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_popular")
	if context.callback:
		context.callback.call({"error": error.message}, error.code)

## Get taxonomic tree for an animal
func get_taxonomy(animal_id: String, callback: Callable = Callable()) -> void:
	_log("Getting taxonomy for animal: %s" % animal_id)

	var endpoint = config.ENDPOINTS_ANIMALS["list"] + animal_id + "/taxonomy/"
	var req_config = _create_request_config(false)  # Public endpoint
	var context = {"animal_id": animal_id, "callback": callback}

	api_client.request_get(
		endpoint,
		_on_get_taxonomy_success.bind(context),
		_on_get_taxonomy_error.bind(context),
		req_config
	)

func _on_get_taxonomy_success(response: Dictionary, context: Dictionary) -> void:
	_log("Retrieved taxonomy for animal: %s" % context.animal_id)
	if context.callback:
		context.callback.call(response, 200)

func _on_get_taxonomy_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_taxonomy")
	if context.callback:
		context.callback.call({"error": error.message}, error.code)
