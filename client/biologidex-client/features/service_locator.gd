class_name ServiceLocator extends Node

## Service Locator pattern for dependency injection
## Provides centralized access to services without tight coupling

signal service_registered(service_name: String)
signal service_unregistered(service_name: String)

# Singleton instance
static var _instance: ServiceLocator = null

# Services registry
var _services: Dictionary = {}
var _service_factories: Dictionary = {}
var _singletons: Dictionary = {}

static func get_instance() -> ServiceLocator:
	if _instance == null:
		_instance = ServiceLocator.new()
	return _instance

## Register a service instance
func register_service(service_name: String, service_instance: Variant) -> void:
	if service_name in _services:
		push_warning("ServiceLocator: Overwriting existing service: %s" % service_name)

	_services[service_name] = service_instance
	service_registered.emit(service_name)

## Register a service factory (lazy instantiation)
func register_factory(service_name: String, factory: Callable) -> void:
	if service_name in _service_factories:
		push_warning("ServiceLocator: Overwriting existing factory: %s" % service_name)

	_service_factories[service_name] = factory
	service_registered.emit(service_name)

## Register a singleton (created once, cached)
func register_singleton(service_name: String, factory: Callable) -> void:
	if service_name in _service_factories:
		push_warning("ServiceLocator: Overwriting existing singleton: %s" % service_name)

	_service_factories[service_name] = factory
	_singletons[service_name] = true
	service_registered.emit(service_name)

## Get a service by name
func get_service(service_name: String) -> Variant:
	# Check direct services first
	if service_name in _services:
		return _services[service_name]

	# Check factories
	if service_name in _service_factories:
		var factory: Callable = _service_factories[service_name]

		# Handle singletons
		if service_name in _singletons:
			if not service_name in _services:
				# Create singleton instance
				var instance: Variant = factory.call()
				_services[service_name] = instance
				return instance
			else:
				return _services[service_name]
		else:
			# Create new instance each time
			return factory.call()

	push_error("ServiceLocator: Service not found: %s" % service_name)
	return null

## Check if service is registered
func has_service(service_name: String) -> bool:
	return service_name in _services or service_name in _service_factories

## Unregister a service
func unregister_service(service_name: String) -> void:
	_services.erase(service_name)
	_service_factories.erase(service_name)
	_singletons.erase(service_name)
	service_unregistered.emit(service_name)

## Clear all services
func clear() -> void:
	var service_names: Array = _services.keys() + _service_factories.keys()
	_services.clear()
	_service_factories.clear()
	_singletons.clear()

	for service_name in service_names:
		service_unregistered.emit(service_name)

## Get all registered service names
func get_service_names() -> Array:
	var names: Array = []
	for name in _services.keys():
		if not name in names:
			names.append(name)
	for name in _service_factories.keys():
		if not name in names:
			names.append(name)
	return names

## Get statistics about registered services
func get_stats() -> Dictionary:
	return {
		"total_services": get_service_names().size(),
		"instantiated_services": _services.size(),
		"factories": _service_factories.size(),
		"singletons": _singletons.size()
	}

# Convenience methods for common services

## Get API Manager service
func api_manager() -> Variant:
	return get_service("APIManager")

## Get Token Manager service
func token_manager() -> Variant:
	return get_service("TokenManager")

## Get Navigation Manager service
func navigation_manager() -> Variant:
	return get_service("NavigationManager")

## Get Dex Database service
func dex_database() -> Variant:
	return get_service("DexDatabase")

## Get Sync Manager service
func sync_manager() -> Variant:
	return get_service("SyncManager")

## Get Image Cache service
func image_cache() -> Variant:
	return get_service("ImageCache")

## Get HTTP Request Pool service
func http_pool() -> Variant:
	return get_service("HTTPRequestPool")
