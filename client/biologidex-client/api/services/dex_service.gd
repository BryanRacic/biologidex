extends BaseService
class_name DexService

## DexService - Dex entry management

signal dex_entry_created(entry_data: Dictionary)
signal dex_entry_creation_failed(error: APITypes.APIError)
signal my_entries_received(entries: Array)
signal my_entries_failed(error: APITypes.APIError)
signal favorites_received(entries: Array)
signal favorites_failed(error: APITypes.APIError)
signal favorite_toggled(entry_data: Dictionary)
signal favorite_toggle_failed(error: APITypes.APIError)
signal sync_completed(entries: Array)
signal sync_failed(error: APITypes.APIError)

## Create a new dex entry
func create_entry(
	animal_id: int,
	vision_job_id: String = "",
	notes: String = "",
	visibility: String = "friends",
	callback: Callable = Callable()
) -> void:
	_log("Creating dex entry for animal: %d" % animal_id)

	var data = {
		"animal": animal_id,
		"visibility": visibility
	}

	if not vision_job_id.is_empty():
		data["source_vision_job"] = vision_job_id

	if not notes.is_empty():
		data["notes"] = notes

	var req_config = _create_request_config()

	var context = {"callback": callback}

	api_client.post(
		config.ENDPOINTS_DEX["entries"],
		data,
		_on_create_entry_success.bind(context),
		_on_create_entry_error.bind(context),
		req_config
	)

func _on_create_entry_success(response: Dictionary, context: Dictionary) -> void:
	_log("Dex entry created successfully: %s" % response.get("id", ""))
	dex_entry_created.emit(response)
	if context.callback:
		context.callback.call(response, 200)

func _on_create_entry_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "create_entry")
	dex_entry_creation_failed.emit(error)
	if context.callback:
		context.callback.call({"error": error.message}, error.code)

## Get user's dex entries
func get_my_entries(callback: Callable = Callable()) -> void:
	_log("Getting my dex entries")

	var req_config = _create_request_config()

	var context = {"callback": callback}

	api_client.request_get(
		config.ENDPOINTS_DEX["my_entries"],
		_on_get_my_entries_success.bind(context),
		_on_get_my_entries_error.bind(context),
		req_config
	)

func _on_get_my_entries_success(response: Dictionary, context: Dictionary) -> void:
	var entries = response.get("results", [])
	_log("Received %d dex entries" % entries.size())
	my_entries_received.emit(entries)
	if context.callback:
		context.callback.call(response, 200)

func _on_get_my_entries_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_my_entries")
	my_entries_failed.emit(error)
	if context.callback:
		context.callback.call({"error": error.message}, error.code)

## Get favorite dex entries
func get_favorites(callback: Callable = Callable()) -> void:
	_log("Getting favorite dex entries")

	var req_config = _create_request_config()

	var context = {"callback": callback}

	api_client.request_get(
		config.ENDPOINTS_DEX["favorites"],
		_on_get_favorites_success.bind(context),
		_on_get_favorites_error.bind(context),
		req_config
	)

func _on_get_favorites_success(response: Dictionary, context: Dictionary) -> void:
	var entries = response.get("results", [])
	_log("Received %d favorite entries" % entries.size())
	favorites_received.emit(entries)
	if context.callback:
		context.callback.call(response, 200)

func _on_get_favorites_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_favorites")
	favorites_failed.emit(error)
	if context.callback:
		context.callback.call({"error": error.message}, error.code)

## Toggle favorite status of a dex entry
func toggle_favorite(entry_id: int, callback: Callable = Callable()) -> void:
	_log("Toggling favorite for entry: %d" % entry_id)

	var endpoint = _format_endpoint(config.ENDPOINTS_DEX["toggle_favorite"], [str(entry_id)])

	var req_config = _create_request_config()

	var context = {"entry_id": entry_id, "callback": callback}

	api_client.post(
		endpoint,
		{},
		_on_toggle_favorite_success.bind(context),
		_on_toggle_favorite_error.bind(context),
		req_config
	)

func _on_toggle_favorite_success(response: Dictionary, context: Dictionary) -> void:
	var is_favorite = response.get("is_favorite", false)
	_log("Entry %d favorite status: %s" % [context.entry_id, "favorited" if is_favorite else "unfavorited"])
	favorite_toggled.emit(response)
	if context.callback:
		context.callback.call(response, 200)

func _on_toggle_favorite_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "toggle_favorite")
	favorite_toggle_failed.emit(error)
	if context.callback:
		context.callback.call({"error": error.message}, error.code)

## Sync dex entries with server (get updates since last sync)
func sync_entries(last_sync: String = "", callback: Callable = Callable()) -> void:
	_log("Syncing dex entries (last_sync: %s)" % last_sync)

	var params = {}
	if not last_sync.is_empty():
		params["last_sync"] = last_sync

	var url = _build_url_with_params(config.ENDPOINTS_DEX["sync"], params)

	var req_config = _create_request_config()

	var context = {"callback": callback}

	api_client.request_get(
		url,
		_on_sync_entries_success.bind(context),
		_on_sync_entries_error.bind(context),
		req_config
	)

func _on_sync_entries_success(response: Dictionary, context: Dictionary) -> void:
	var entries = response.get("results", [])
	_log("Sync completed: %d entries" % entries.size())
	sync_completed.emit(entries)
	if context.callback:
		context.callback.call(response, 200)

func _on_sync_entries_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "sync_entries")
	sync_failed.emit(error)
	if context.callback:
		context.callback.call({"error": error.message}, error.code)