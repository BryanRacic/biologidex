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

## New multi-user sync signals
signal sync_started(user_id: String)
signal sync_progress(user_id: String, current: int, total: int)
signal sync_user_completed(user_id: String, entries_updated: int)
signal sync_user_failed(user_id: String, error_message: String)
signal friends_overview_received(friends: Array)
signal friends_overview_failed(error: APITypes.APIError)

## Entry update signals
signal entry_updated(entry_data: Dictionary)
signal entry_update_failed(error: APITypes.APIError)

## Create a new dex entry
func create_entry(
	animal_id: String,
	vision_job_id: String = "",
	notes: String = "",
	visibility: String = "friends",
	callback: Callable = Callable()
) -> void:
	_log("Creating dex entry for animal: %s" % animal_id)

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
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_create_entry_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "create_entry")
	dex_entry_creation_failed.emit(error)
	if context.callback and context.callback.is_valid():
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
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_get_my_entries_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_my_entries")
	my_entries_failed.emit(error)
	if context.callback and context.callback.is_valid():
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
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_get_favorites_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_favorites")
	favorites_failed.emit(error)
	if context.callback and context.callback.is_valid():
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
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_toggle_favorite_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "toggle_favorite")
	favorite_toggle_failed.emit(error)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Update a dex entry (e.g., change animal, notes, visibility)
func update_entry(
	entry_id: String,
	update_data: Dictionary,
	callback: Callable = Callable()
) -> void:
	_log("Updating dex entry: %s" % entry_id)

	var endpoint = config.ENDPOINTS_DEX["entries"] + entry_id + "/"
	var req_config = _create_request_config()
	var context = {"entry_id": entry_id, "callback": callback}

	api_client.put(
		endpoint,
		update_data,
		_on_update_entry_success.bind(context),
		_on_update_entry_error.bind(context),
		req_config
	)

func _on_update_entry_success(response: Dictionary, context: Dictionary) -> void:
	_log("Dex entry updated successfully: %s" % context.entry_id)
	entry_updated.emit(response)
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_update_entry_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "update_entry")
	entry_update_failed.emit(error)
	if context.callback and context.callback.is_valid():
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
	var entries = response.get("entries", [])
	_log("Sync completed: %d entries" % entries.size())
	sync_completed.emit(entries)
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_sync_entries_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "sync_entries")
	sync_failed.emit(error)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Sync a specific user's dex (self or friend)
func sync_user_dex(user_id: String = "self", callback: Callable = Callable()) -> void:
	_log("Syncing dex for user: %s" % user_id)
	sync_started.emit(user_id)

	# Get last sync timestamp from SyncManager
	var last_sync := SyncManager.get_last_sync(user_id)

	# Determine endpoint
	var endpoint := ""
	if user_id == "self":
		endpoint = config.ENDPOINTS_DEX["sync"]
	else:
		endpoint = "/dex/entries/user/" + user_id + "/entries/"

	# Build URL with query params
	var params := {}
	if not last_sync.is_empty():
		params["last_sync"] = last_sync

	var url := _build_url_with_params(endpoint, params)
	var req_config := _create_request_config()

	var context := {
		"user_id": user_id,
		"callback": callback
	}

	api_client.request_get(
		url,
		_on_sync_user_success.bind(context),
		_on_sync_user_error.bind(context),
		req_config
	)

func _on_sync_user_success(response: Dictionary, context: Dictionary) -> void:
	var user_id: String = context.user_id
	var entries: Array = response.get("entries", [])
	var server_time: String = response.get("server_time", "")

	_log("Sync completed for '%s': %d entries" % [user_id, entries.size()])

	if entries.is_empty():
		sync_user_completed.emit(user_id, 0)
		if not server_time.is_empty():
			SyncManager.update_last_sync(user_id, server_time)
		if context.callback and context.callback.is_valid():
			context.callback.call(response, 200)
		return

	# Process entries with progress tracking
	_process_sync_entries(entries, user_id, server_time, context.callback)

func _on_sync_user_error(error: APITypes.APIError, context: Dictionary) -> void:
	var user_id: String = context.user_id
	_handle_error(error, "sync_user_dex")
	sync_user_failed.emit(user_id, error.message)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

func _process_sync_entries(entries: Array, user_id: String, server_time: String, callback: Callable) -> void:
	"""Process synced entries and update local database with progress tracking"""
	var total := entries.size()
	var processed := 0

	for entry in entries:
		# Get existing record to preserve cached_image_path if not re-downloading
		var creation_index_val: int = entry.get("creation_index", -1)
		var existing_record := DexDatabase.get_record_for_user(creation_index_val, user_id)
		var existing_cached_path: String = existing_record.get("cached_image_path", "")

		# Update local database with expanded record format
		var record := {
			"creation_index": creation_index_val,
			"scientific_name": entry.get("scientific_name", ""),
			"common_name": entry.get("common_name", ""),
			"image_checksum": entry.get("image_checksum", ""),
			"dex_compatible_url": entry.get("dex_compatible_url", ""),
			"updated_at": entry.get("updated_at", ""),
			"cached_image_path": existing_cached_path,  # Preserve existing path
			"animal_id": entry.get("animal_id", ""),  # Store animal UUID for editing
			"dex_entry_id": entry.get("id", "")  # Store dex entry ID for editing
		}

		# Check if image needs downloading
		var needs_download := _needs_image_download(record, user_id)

		if needs_download and not record["dex_compatible_url"].is_empty():
			# Download image asynchronously
			await _download_and_cache_image(record, user_id)

		# Check if this dex_entry_id exists with a different creation_index (animal was changed)
		var dex_entry_id = record.get("dex_entry_id", "")
		var new_creation_index = record.get("creation_index", -1)
		if not dex_entry_id.is_empty() and new_creation_index >= 0:
			# Search all records to find if this dex_entry_id exists elsewhere
			var all_indices = DexDatabase.get_sorted_indices_for_user(user_id)
			for old_index in all_indices:
				var existing = DexDatabase.get_record_for_user(old_index, user_id)
				if existing.get("dex_entry_id", "") == dex_entry_id and old_index != new_creation_index:
					# Found old record with same dex_entry_id but different creation_index
					# Delete it since the animal was changed
					_log("Removing old record #%d (animal changed to #%d)" % [old_index, new_creation_index])
					DexDatabase.remove_record(old_index, user_id)
					break

		# Add to database (with updated cached_image_path)
		DexDatabase.add_record_from_dict(record, user_id)

		processed += 1
		sync_progress.emit(user_id, processed, total)

	# Update sync timestamp
	if not server_time.is_empty():
		SyncManager.update_last_sync(user_id, server_time)

	sync_user_completed.emit(user_id, total)

	if callback:
		callback.call({"entries": entries, "count": total}, 200)

func _needs_image_download(record: Dictionary, user_id: String) -> bool:
	"""Check if image needs to be downloaded"""
	var creation_index: int = record.get("creation_index", -1)
	if creation_index < 0:
		return false

	var existing_record := DexDatabase.get_record_for_user(creation_index, user_id)
	if existing_record.is_empty():
		return true

	# Check if checksum changed
	var old_checksum: String = existing_record.get("image_checksum", "")
	var new_checksum: String = record.get("image_checksum", "")

	return old_checksum != new_checksum

func _download_and_cache_image(record: Dictionary, user_id: String) -> void:
	"""Download and cache image, update record with local path"""
	var image_url: String = record.get("dex_compatible_url", "")
	if image_url.is_empty():
		return

	_log("Downloading image for user '%s': %s" % [user_id, image_url])

	# Use HTTPClient directly (doesn't require scene tree)
	var http := HTTPClient.new()

	# Parse URL
	var url_parts := image_url.replace("https://", "").replace("http://", "").split("/", false, 1)
	var host := url_parts[0]
	var path := "/" + (url_parts[1] if url_parts.size() > 1 else "")
	var use_tls := image_url.begins_with("https://")

	# Connect to host with TLS options (Godot 4.x)
	var tls_options = TLSOptions.client() if use_tls else null
	var connect_error := http.connect_to_host(host, 443 if use_tls else 80, tls_options)
	if connect_error != OK:
		push_error("[DexService] Failed to connect to host: ", connect_error)
		return

	# Wait for connection
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		await Engine.get_main_loop().process_frame

	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		push_error("[DexService] Failed to establish connection")
		return

	# Send request
	var request_error := http.request(HTTPClient.METHOD_GET, path, [])
	if request_error != OK:
		push_error("[DexService] Failed to send request: ", request_error)
		return

	# Wait for response
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		await Engine.get_main_loop().process_frame

	if http.get_status() != HTTPClient.STATUS_BODY and http.get_status() != HTTPClient.STATUS_CONNECTED:
		push_error("[DexService] Request failed with status: ", http.get_status())
		return

	# Check response code
	var response_code := http.get_response_code()
	if response_code != 200:
		push_error("[DexService] Image download failed with code: ", response_code)
		return

	# Read body
	var body := PackedByteArray()
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk := http.read_response_body_chunk()
		if chunk.size() > 0:
			body.append_array(chunk)
		else:
			await Engine.get_main_loop().process_frame

	# Cache image with deduplication
	var cached_path := DexDatabase.cache_image(image_url, body, user_id)
	record["cached_image_path"] = cached_path

	_log("Image cached for user '%s': %s" % [user_id, cached_path])

	# Update the database record with the cached image path
	var creation_index: int = record.get("creation_index", -1)
	if creation_index >= 0:
		DexDatabase.add_record_from_dict(record, user_id)

## Get friends overview
func get_friends_overview(callback: Callable = Callable()) -> void:
	_log("Getting friends overview")

	var req_config := _create_request_config()
	var context := {"callback": callback}

	api_client.request_get(
		"/dex/entries/friends_overview/",
		_on_friends_overview_success.bind(context),
		_on_friends_overview_error.bind(context),
		req_config
	)

func _on_friends_overview_success(response: Dictionary, context: Dictionary) -> void:
	var friends: Array = response.get("friends", [])
	_log("Received friends overview: %d friends" % friends.size())
	friends_overview_received.emit(friends)
	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_friends_overview_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "get_friends_overview")
	friends_overview_failed.emit(error)
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Sync all friends' dex in one operation
func sync_all_friends(callback: Callable = Callable()) -> void:
	"""Sync own dex and all friends' dex"""
	_log("Starting batch sync for all friends")

	# First get friends overview
	get_friends_overview(_on_friends_overview_for_batch_sync.bind(callback))

func _on_friends_overview_for_batch_sync(response: Dictionary, code: int, callback: Callable) -> void:
	if code != 200:
		_log("Failed to get friends overview for batch sync")
		if callback:
			callback.call(response, code)
		return

	var friends: Array = response.get("friends", [])

	# Build batch sync request
	var sync_requests := []

	# Add self
	sync_requests.append({
		"user_id": "self",
		"last_sync": SyncManager.get_last_sync("self")
	})

	# Add all friends
	for friend in friends:
		var friend_id: String = friend.get("user_id", "")
		if not friend_id.is_empty():
			sync_requests.append({
				"user_id": friend_id,
				"last_sync": SyncManager.get_last_sync(friend_id)
			})

	# Execute batch sync
	_execute_batch_sync(sync_requests, callback)

func _execute_batch_sync(sync_requests: Array, callback: Callable) -> void:
	"""Execute batch sync request"""
	_log("Executing batch sync for %d users" % sync_requests.size())

	var req_config := _create_request_config()
	var context := {"callback": callback}

	api_client.post(
		"/dex/entries/batch_sync/",
		{"sync_requests": sync_requests},
		_on_batch_sync_success.bind(context),
		_on_batch_sync_error.bind(context),
		req_config
	)

func _on_batch_sync_success(response: Dictionary, context: Dictionary) -> void:
	var results: Dictionary = response.get("results", {})
	var server_time: String = response.get("server_time", "")

	_log("Batch sync completed: %d users" % results.size())

	# Process each user's results
	for user_id in results.keys():
		var user_result = results[user_id]

		if user_result.has("error"):
			sync_user_failed.emit(user_id, user_result["error"])
			continue

		var entries: Array = user_result.get("entries", [])
		_process_sync_entries(entries, user_id, server_time, Callable())

	if context.callback and context.callback.is_valid():
		context.callback.call(response, 200)

func _on_batch_sync_error(error: APITypes.APIError, context: Dictionary) -> void:
	_handle_error(error, "batch_sync")
	if context.callback and context.callback.is_valid():
		context.callback.call({"error": error.message}, error.code)

## Retry logic with exponential backoff

func sync_user_dex_with_retry(user_id: String = "self", max_retries: int = 3, callback: Callable = Callable()) -> void:
	"""Sync a user's dex with automatic retry on failure"""
	_log("Starting sync with retry for user: %s (max retries: %d)" % [user_id, max_retries])
	_retry_sync(user_id, 0, max_retries, 1000, callback)

func _retry_sync(user_id: String, attempt: int, max_retries: int, backoff_ms: int, callback: Callable) -> void:
	"""Internal retry logic with exponential backoff"""
	# Attempt sync
	sync_user_dex(user_id, _on_retry_sync_complete.bind({
		"user_id": user_id,
		"attempt": attempt,
		"max_retries": max_retries,
		"backoff_ms": backoff_ms,
		"callback": callback
	}))

func _on_retry_sync_complete(response: Dictionary, code: int, context: Dictionary) -> void:
	"""Handle retry sync completion"""
	var user_id: String = context.user_id
	var attempt: int = context.attempt
	var max_retries: int = context.max_retries
	var backoff_ms: int = context.backoff_ms
	var callback: Callable = context.callback

	if code == 200:
		# Success!
		_log("Sync succeeded for user '%s' on attempt %d" % [user_id, attempt + 1])
		if callback:
			callback.call(response, code)
		return

	# Check if we should retry
	if attempt < max_retries:
		var next_attempt := attempt + 1
		_log("Sync failed for user '%s' (attempt %d/%d), retrying in %dms..." % [
			user_id, next_attempt, max_retries + 1, backoff_ms
		])

		# Wait with exponential backoff
		await Engine.get_main_loop().create_timer(backoff_ms / 1000.0).timeout

		# Retry with doubled backoff
		_retry_sync(user_id, next_attempt, max_retries, backoff_ms * 2, callback)
	else:
		# Max retries exceeded
		_log("Sync failed for user '%s' after %d attempts" % [user_id, max_retries + 1])
		sync_user_failed.emit(user_id, "Max retries exceeded")
		if callback:
			callback.call(response, code)