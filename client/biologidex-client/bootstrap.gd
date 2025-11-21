extends Node

## Bootstrap script that initializes all services and dependencies
## This should be the first autoload in the project

# Service references
var service_locator: ServiceLocator
var app_state: AppState
var http_pool: HTTPRequestPool
var image_cache: ImageCache
var http_cache: HTTPCache
var request_manager: RequestManager

# Legacy singletons (will be migrated)
var token_manager: Node
var api_manager: Node
var navigation_manager: Node
var dex_database: Node
var sync_manager: Node
var tree_cache: Node

func _ready() -> void:
	print("BiologiDex: Initializing application...")

	# Initialize service locator first
	_initialize_service_locator()

	# Initialize core features
	_initialize_caching_layer()
	_initialize_http_layer()
	_initialize_state_management()

	# Initialize legacy singletons (backward compatibility)
	_initialize_legacy_services()

	# Register all services
	_register_services()

	print("BiologiDex: Initialization complete")

## Initialize service locator
func _initialize_service_locator() -> void:
	service_locator = ServiceLocator.new()
	service_locator.name = "ServiceLocator"
	add_child(service_locator)
	print("  ✓ ServiceLocator initialized")

## Initialize caching layer
func _initialize_caching_layer() -> void:
	# Image cache
	image_cache = ImageCache.new()
	image_cache.name = "ImageCache"
	add_child(image_cache)
	print("  ✓ ImageCache initialized")

	# HTTP response cache
	http_cache = HTTPCache.new()
	http_cache.name = "HTTPCache"
	add_child(http_cache)
	print("  ✓ HTTPCache initialized")

## Initialize HTTP layer
func _initialize_http_layer() -> void:
	# HTTP request pool
	http_pool = HTTPRequestPool.new(10, 20)
	http_pool.name = "HTTPRequestPool"
	add_child(http_pool)
	print("  ✓ HTTPRequestPool initialized")

	# Request manager
	request_manager = RequestManager.new(http_pool, http_cache)
	request_manager.name = "RequestManager"
	add_child(request_manager)
	print("  ✓ RequestManager initialized")

## Initialize state management
func _initialize_state_management() -> void:
	app_state = AppState.new()
	app_state.name = "AppState"
	add_child(app_state)
	print("  ✓ AppState initialized")

## Initialize legacy services for backward compatibility
func _initialize_legacy_services() -> void:
	# These will be loaded as autoloads but we'll store references
	# and eventually migrate them to the new architecture
	print("  ✓ Legacy services will be loaded via autoload")

## Register all services in the service locator
func _register_services() -> void:
	# Register new services
	service_locator.register_service("ServiceLocator", service_locator)
	service_locator.register_service("AppState", app_state)
	service_locator.register_service("HTTPRequestPool", http_pool)
	service_locator.register_service("ImageCache", image_cache)
	service_locator.register_service("HTTPCache", http_cache)
	service_locator.register_service("RequestManager", request_manager)

	# Register legacy services (these are autoloaded)
	# We'll register them when they become available
	call_deferred("_register_legacy_services")

	print("  ✓ Services registered in ServiceLocator")

## Register legacy autoloaded services (deferred)
func _register_legacy_services() -> void:
	# Wait one frame for autoloads to be ready
	await get_tree().process_frame

	# Get references to legacy autoloads
	if has_node("/root/TokenManager"):
		token_manager = get_node("/root/TokenManager")
		service_locator.register_service("TokenManager", token_manager)

	if has_node("/root/APIManager"):
		api_manager = get_node("/root/APIManager")
		service_locator.register_service("APIManager", api_manager)

	if has_node("/root/NavigationManager"):
		navigation_manager = get_node("/root/NavigationManager")
		service_locator.register_service("NavigationManager", navigation_manager)

	if has_node("/root/DexDatabase"):
		dex_database = get_node("/root/DexDatabase")
		service_locator.register_service("DexDatabase", dex_database)

	if has_node("/root/SyncManager"):
		sync_manager = get_node("/root/SyncManager")
		service_locator.register_service("SyncManager", sync_manager)

	if has_node("/root/TreeCache"):
		tree_cache = get_node("/root/TreeCache")
		service_locator.register_service("TreeCache", tree_cache)

	print("  ✓ Legacy services registered")

## Convenience method to get service locator
static func get_service_locator() -> ServiceLocator:
	if Engine.has_singleton("Bootstrap"):
		var bootstrap: Node = Engine.get_singleton("Bootstrap")
		return bootstrap.service_locator
	elif has_node("/root/Bootstrap"):
		var bootstrap: Node = get_node("/root/Bootstrap")
		return bootstrap.service_locator
	return null
