extends Node
## Version Manager - Handles client version checking and update prompts
## Autoloaded singleton that manages version compatibility between client and server

signal version_check_completed(is_current: bool)
signal update_required(current_version: String, expected_version: String)

const VERSION_CHECK_ENDPOINT = "/api/v1/version/"
const VERSION_FILE_PATH = "res://version.txt"
const CHECK_INTERVAL = 300.0  # Check every 5 minutes
const MIN_CHECK_INTERVAL = 60.0  # Minimum 1 minute between checks
const MAX_RETRY_ATTEMPTS = 3
const RETRY_DELAY = 5.0

var current_version: String = "unknown"
var expected_version: String = "unknown"
var last_check_time: float = 0
var check_timer: Timer
var is_checking: bool = false
var retry_count: int = 0
var update_dismissed: bool = false

# Feature flags from server
var server_features: Dictionary = {}

# Services (accessed via autoload)
var api_manager
var token_manager
var navigation_manager

func _ready() -> void:
	# Skip version checking entirely when running in editor
	if OS.has_feature("editor"):
		print("[VersionManager] Running in editor - version checking disabled")
		return

	# Only perform version checking in exported builds
	if not _is_exported_build():
		print("[VersionManager] Not an exported build - version checking disabled")
		return

	print("[VersionManager] Initializing for exported build...")

	# Load current version from embedded file
	_load_current_version()

	# Get service references
	_initialize_services()

	# Setup periodic check timer
	_setup_timer()

	print("[VersionManager] Ready. Current version: ", current_version)


func _is_exported_build() -> bool:
	"""
	Check if this is an exported build (not running in editor)
	Currently only supports web exports for version checking
	"""
	# Check for editor feature (running in Godot editor)
	if OS.has_feature("editor"):
		return false

	# Check for debug feature (typically means running from editor)
	if OS.has_feature("debug") and not OS.has_feature("web"):
		return false

	# Currently only support version checking for web exports
	if not OS.has_feature("web"):
		print("[VersionManager] Version checking only supported for web exports")
		return false

	# Check if the version file exists (should be present in exports)
	if not FileAccess.file_exists(VERSION_FILE_PATH):
		# In web builds, might still have version in meta tags
		if OS.has_feature("web"):
			# Try to detect if we're in an exported web build
			var js_check = JavaScriptBridge.eval("""
				(() => {
					// Check if we have Godot's expected structure
					return typeof Module !== 'undefined' &&
					       typeof Module.canvas !== 'undefined';
				})()
			""")
			return js_check == true
		return false

	return true


func _initialize_services() -> void:
	"""Initialize service references from autoloads"""
	api_manager = get_node_or_null("/root/APIManager")
	token_manager = get_node_or_null("/root/TokenManager")
	navigation_manager = get_node_or_null("/root/NavigationManager")

	if not api_manager:
		push_error("[VersionManager] APIManager not found - version checking disabled")


func _setup_timer() -> void:
	"""Setup the periodic version check timer"""
	check_timer = Timer.new()
	check_timer.wait_time = CHECK_INTERVAL
	check_timer.timeout.connect(_on_check_timer_timeout)
	check_timer.autostart = false
	check_timer.one_shot = false
	add_child(check_timer)


func _load_current_version() -> void:
	"""Load the current client version from embedded file or web metadata"""
	# Try to load from embedded version file
	if FileAccess.file_exists(VERSION_FILE_PATH):
		var file = FileAccess.open(VERSION_FILE_PATH, FileAccess.READ)
		if file:
			current_version = file.get_line().strip_edges()
			file.close()
			print("[VersionManager] Loaded version from file: ", current_version)
			return

	# Fallback for web builds: try to get from HTML metadata
	if OS.has_feature("web"):
		_load_version_from_web_metadata()


func _load_version_from_web_metadata() -> void:
	"""Load version from HTML meta tags (web builds only)"""
	if not OS.has_feature("web"):
		return

	var js_code = """
		(() => {
			const meta = document.querySelector('meta[name="client-version"]');
			return meta ? meta.content : 'unknown';
		})()
	"""

	var version_meta = JavaScriptBridge.eval(js_code)
	if version_meta and version_meta != "unknown":
		current_version = version_meta
		print("[VersionManager] Loaded version from web metadata: ", current_version)


func check_version(force: bool = false, silent: bool = false) -> void:
	"""
	Check if client version matches server expectation

	Args:
		force: Skip cooldown check
		silent: Don't show update dialog even if update is required
	"""
	if is_checking:
		print("[VersionManager] Version check already in progress")
		return

	if not api_manager:
		print("[VersionManager] Cannot check version - APIManager not available")
		version_check_completed.emit(true)
		return

	# Check cooldown (unless forced)
	var current_time = Time.get_ticks_msec() / 1000.0
	if not force and current_time - last_check_time < MIN_CHECK_INTERVAL:
		print("[VersionManager] Version check on cooldown")
		return

	is_checking = true
	last_check_time = current_time
	update_dismissed = silent  # Remember if this is a silent check

	print("[VersionManager] Checking version (current: %s)..." % current_version)

	# Prepare headers
	var headers = {
		"X-Client-Version": current_version,
		"X-Client-Build": str(Time.get_unix_time())
	}

	# Make version check request using APIManager's raw request method
	_make_version_request(headers)


func _make_version_request(headers: Dictionary) -> void:
	"""Make the actual version check request"""
	# Since version endpoint doesn't require auth, we can use a direct HTTP request
	# or use APIManager if it supports unauthenticated requests

	var http_request = HTTPRequest.new()
	add_child(http_request)

	# Build full URL
	var base_url = ""
	if api_manager and api_manager.has_method("get_base_url"):
		base_url = api_manager.get_base_url()
	else:
		base_url = "https://biologidex.com"  # Fallback

	var full_url = base_url.rstrip("/") + VERSION_CHECK_ENDPOINT

	# Convert headers dict to PackedStringArray
	var header_array: PackedStringArray = []
	for key in headers:
		header_array.append("%s: %s" % [key, headers[key]])

	# Connect response signal
	http_request.request_completed.connect(_on_version_request_completed.bind(http_request))

	# Make request
	var error = http_request.request(full_url, header_array, HTTPClient.METHOD_GET)
	if error != OK:
		push_error("[VersionManager] Failed to make version request: ", error)
		http_request.queue_free()
		_handle_version_error()


func _on_version_request_completed(_result: int, response_code: int, _headers: PackedStringArray,
								   body: PackedByteArray, http_request: HTTPRequest) -> void:
	"""Handle the version check response"""
	http_request.queue_free()

	if response_code != 200:
		print("[VersionManager] Version check failed with code: ", response_code)
		_handle_version_error()
		return

	# Parse JSON response
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())

	if parse_result != OK:
		push_error("[VersionManager] Failed to parse version response")
		_handle_version_error()
		return

	_handle_version_response(json.data, response_code)


func _handle_version_response(response: Dictionary, _code: int) -> void:
	"""Process the version check response"""
	is_checking = false
	retry_count = 0  # Reset retry count on success

	# Check if version checking is enabled on server
	if not response.get("version_check_enabled", true):
		print("[VersionManager] Version checking disabled on server")
		version_check_completed.emit(true)
		start_periodic_checks()
		return

	# Extract version information
	expected_version = response.get("git_commit", response.get("expected_version", "unknown"))
	var update_is_required = response.get("update_required", false)
	var update_message = response.get("update_message", "")
	server_features = response.get("features", {})

	print("[VersionManager] Version check complete:")
	print("  Current: ", current_version)
	print("  Expected: ", expected_version)
	print("  Update Required: ", update_is_required)

	# Check for version mismatch
	var versions_match = (current_version == expected_version) or \
						(current_version == "unknown") or \
						(expected_version == "unknown")

	if update_is_required or not versions_match:
		# Version mismatch detected
		print("[VersionManager] Version mismatch detected!")
		version_check_completed.emit(false)
		update_required.emit(current_version, expected_version)

		# Show update dialog unless this is a silent check or user dismissed it
		if not update_dismissed:
			_show_update_dialog(update_message)

		# Stop periodic checks during update requirement
		stop_periodic_checks()
	else:
		# Version is current
		print("[VersionManager] Version is current")
		version_check_completed.emit(true)

		# Start periodic checks
		start_periodic_checks()


func _handle_version_error() -> void:
	"""Handle version check request failure"""
	is_checking = false

	retry_count += 1
	if retry_count < MAX_RETRY_ATTEMPTS:
		print("[VersionManager] Version check failed, retrying in %s seconds..." % RETRY_DELAY)
		await get_tree().create_timer(RETRY_DELAY).timeout
		check_version(true, true)  # Retry silently
	else:
		print("[VersionManager] Version check failed after %s attempts" % MAX_RETRY_ATTEMPTS)
		# Assume version is OK on persistent failure
		version_check_completed.emit(true)
		# Still start periodic checks, but with longer interval
		check_timer.wait_time = CHECK_INTERVAL * 2
		start_periodic_checks()


func _show_update_dialog(message: String = "") -> void:
	"""Show update required dialog to user"""
	var dialog_message = message
	if dialog_message.is_empty():
		dialog_message = """Your client is out of date and may not work as expected!

Please refresh the page to load the latest version.

If the issue persists:
• Clear your browser cache (Ctrl+Shift+R or Cmd+Shift+R)
• For installed PWAs: Uninstall and reinstall the app
• For mobile: Clear app data in settings

Current version: %s
Expected version: %s""" % [current_version, expected_version]

	print("[VersionManager] Showing update dialog")

	# Try to use the error dialog system if available
	var error_handler = get_node_or_null("/root/ErrorHandler")
	if error_handler and error_handler.has_method("show_error"):
		error_handler.show_error(
			"Update Required",
			dialog_message,
			{
				"type": "warning",
				"actions": ["Refresh Now", "Continue Anyway"],
				"callbacks": [
					func(): force_refresh(),
					func(): _on_update_dismissed()
				]
			}
		)
	else:
		# Fallback: Create a simple confirmation dialog
		_show_fallback_update_dialog(dialog_message)


func _show_fallback_update_dialog(message: String) -> void:
	"""Show a fallback update dialog using AcceptDialog"""
	var dialog = ConfirmationDialog.new()
	dialog.title = "Update Required"
	dialog.dialog_text = message
	dialog.ok_button_text = "Refresh Now"
	dialog.cancel_button_text = "Continue Anyway"

	# Connect signals
	dialog.confirmed.connect(func(): force_refresh())
	dialog.canceled.connect(func(): _on_update_dismissed())

	# Add to scene
	get_viewport().add_child(dialog)
	dialog.popup_centered(Vector2(600, 400))
	dialog.show()

	# Clean up when closed
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)


func _on_update_dismissed() -> void:
	"""Handle user dismissing the update dialog"""
	print("[VersionManager] User dismissed update dialog")
	update_dismissed = true
	# Still allow periodic checks, but don't show dialog again
	start_periodic_checks()


func _on_check_timer_timeout() -> void:
	"""Periodic version check callback"""
	check_version(false, update_dismissed)  # Silent if user already dismissed


func start_periodic_checks() -> void:
	"""Start periodic version checking"""
	if check_timer and check_timer.is_stopped():
		print("[VersionManager] Starting periodic version checks")
		check_timer.start()


func stop_periodic_checks() -> void:
	"""Stop periodic version checking"""
	if check_timer and not check_timer.is_stopped():
		print("[VersionManager] Stopping periodic version checks")
		check_timer.stop()


func force_refresh() -> void:
	"""Force a hard refresh of the application"""
	print("[VersionManager] Forcing application refresh")

	if OS.has_feature("web"):
		# Web build - use JavaScript to reload
		JavaScriptBridge.eval("window.location.reload(true);")
	else:
		# Native build - restart application
		OS.set_restart_on_exit(true)
		get_tree().quit()


func clear_cache_and_refresh() -> void:
	"""Attempt to clear cache and refresh (web only)"""
	if not OS.has_feature("web"):
		print("[VersionManager] Cache clearing only available on web builds")
		force_refresh()
		return

	print("[VersionManager] Clearing cache and refreshing...")

	var js_code = """
		(async () => {
			try {
				// Clear all caches
				if ('caches' in window) {
					const names = await caches.keys();
					await Promise.all(names.map(name => caches.delete(name)));
					console.log('Cleared all caches');
				}

				// Unregister service workers
				if ('serviceWorker' in navigator) {
					const registrations = await navigator.serviceWorker.getRegistrations();
					for(let registration of registrations) {
						await registration.unregister();
						console.log('Unregistered service worker');
					}
				}

				// Clear local storage
				if (window.localStorage) {
					localStorage.clear();
					console.log('Cleared localStorage');
				}

				// Clear session storage
				if (window.sessionStorage) {
					sessionStorage.clear();
					console.log('Cleared sessionStorage');
				}

				// Force reload with cache bypass
				window.location.reload(true);
			} catch (error) {
				console.error('Error clearing cache:', error);
				// Fallback to simple reload
				window.location.reload(true);
			}
		})();
	"""

	JavaScriptBridge.eval(js_code)


func get_current_version() -> String:
	"""Get the current client version"""
	return current_version


func get_expected_version() -> String:
	"""Get the expected version from server"""
	return expected_version


func is_version_current() -> bool:
	"""Check if the current version matches expected"""
	if current_version == "unknown" or expected_version == "unknown":
		return true  # Assume OK if version unknown

	return current_version == expected_version


func has_feature(feature_name: String) -> bool:
	"""Check if a specific feature is available based on server response"""
	return server_features.get(feature_name, false)