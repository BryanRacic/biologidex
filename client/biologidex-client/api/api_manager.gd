extends Node

## APIManager - Central orchestrator for all API services
## Provides singleton access to service layer and backward compatibility

# Signals (for backward compatibility)
signal request_started(url: String, method: String)
signal request_completed(url: String, response_code: int, body: Dictionary)
signal request_failed(url: String, error: String)

# Core components
var http_client: HTTPClientCore
var api_client: APIClient
var config: APIConfig

# Services
var auth: AuthService
var vision: VisionService
var tree: TreeService
var social: SocialService
var dex: DexService
var animals: AnimalsService
var taxonomy: TaxonomyService

func _ready() -> void:
	_initialize_core()
	_initialize_services()
	_connect_signals()
	print("[APIManager] Initialized with new service architecture")

## Initialize core components
func _initialize_core() -> void:
	# Create config
	config = APIConfig.new()

	# Create HTTP client
	http_client = HTTPClientCore.new()
	add_child(http_client)

	# Create API client
	api_client = APIClient.new(http_client, config)
	add_child(api_client)

## Initialize all services
func _initialize_services() -> void:
	auth = AuthService.new(api_client, config)
	vision = VisionService.new(api_client, config)
	tree = TreeService.new(api_client, config)
	social = SocialService.new(api_client, config)
	dex = DexService.new(api_client, config)
	animals = AnimalsService.new(api_client, config)
	taxonomy = TaxonomyService.new(api_client, config)

	print("[APIManager] Services initialized: auth, vision, tree, social, dex, animals, taxonomy")

## Connect signals for backward compatibility
func _connect_signals() -> void:
	http_client.request_started.connect(func(url, method): request_started.emit(url, method))
	http_client.request_completed.connect(func(url, code, body): request_completed.emit(url, code, body))
	http_client.request_failed.connect(func(url, error): request_failed.emit(url, error))

# =============================================================================
# Backward Compatibility Methods (Deprecated)
# These methods maintain compatibility with existing code but should be
# replaced with the new service-based API
# =============================================================================

## [DEPRECATED] Login with username and password
## Use: APIManager.auth.login(username, password, callback)
func login(username: String, password: String, callback: Callable) -> void:
	push_warning("[APIManager] login() is deprecated. Use APIManager.auth.login() instead")
	auth.login(username, password, callback)

## [DEPRECATED] Register a new user account
## Use: APIManager.auth.register(username, email, password, password_confirm, callback)
func register(username: String, email: String, password: String, password_confirm: String, callback: Callable) -> void:
	push_warning("[APIManager] register() is deprecated. Use APIManager.auth.register() instead")
	auth.register(username, email, password, password_confirm, callback)

## [DEPRECATED] Refresh access token using refresh token
## Use: APIManager.auth.refresh_token(refresh, callback)
func refresh_token(refresh: String, callback: Callable) -> void:
	push_warning("[APIManager] refresh_token() is deprecated. Use APIManager.auth.refresh_token() instead")
	auth.refresh_token(refresh, callback)

## [DEPRECATED] Upload image for CV analysis
## Use: APIManager.vision.create_vision_job(image_data, file_name, file_type, callback, transformations)
func create_vision_job(
	image_data: PackedByteArray,
	file_name: String,
	file_type: String,
	_access_token: String,  # Deprecated, kept for backward compatibility
	callback: Callable,
	transformations: Dictionary = {}
) -> void:
	push_warning("[APIManager] create_vision_job() is deprecated. Use APIManager.vision.create_vision_job() instead")
	# Note: access_token parameter is no longer needed as it's managed by TokenManager
	vision.create_vision_job(image_data, file_name, file_type, callback, transformations)

## [DEPRECATED] Check status of vision analysis job
## Use: APIManager.vision.get_vision_job(job_id, callback)
func get_vision_job(job_id: String, _access_token: String, callback: Callable) -> void:  # Deprecated parameter
	push_warning("[APIManager] get_vision_job() is deprecated. Use APIManager.vision.get_vision_job() instead")
	# Note: access_token parameter is no longer needed as it's managed by TokenManager
	vision.get_vision_job(job_id, callback)

# =============================================================================
# Utility Methods
# =============================================================================

## Get pending request count
func get_pending_requests() -> int:
	return api_client.get_pending_count()

## Get active request count
func get_active_requests() -> int:
	return api_client.get_active_count()

## Clear all pending requests
func clear_request_queue() -> void:
	api_client.clear_queue()
	print("[APIManager] Request queue cleared")
