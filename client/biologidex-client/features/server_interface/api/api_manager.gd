extends Node

## APIManager - Central orchestrator for all API services
## Provides singleton access to service layer

# Signals
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
var images: ImageService

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
	images = ImageService.new(api_client, config)

	print("[APIManager] Services initialized: auth, vision, tree, social, dex, animals, taxonomy, images")

## Connect signals
func _connect_signals() -> void:
	http_client.request_started.connect(func(url, method): request_started.emit(url, method))
	http_client.request_completed.connect(func(url, code, body): request_completed.emit(url, code, body))
	http_client.request_failed.connect(func(url, error): request_failed.emit(url, error))

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
