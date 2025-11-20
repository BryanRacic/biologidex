# BiologiDex Client Refactoring Plan

## Executive Summary
This document outlines a comprehensive refactoring plan for the BiologiDex Godot client application. The audit has identified significant architectural issues including poor separation of concerns, code duplication, tight coupling, inconsistent patterns, and memory management concerns. The proposed refactor will transform the codebase into a maintainable, scalable, and efficient architecture following industry best practices.

## Critical Issues Identified

### 1. Architectural Issues
- **Flat File Structure**: All scenes and scripts are in the root directory, making navigation difficult
- **Mixed Responsibilities**: Scene scripts contain business logic, API calls, UI updates, and state management
- **Tight Coupling**: Direct dependencies between scenes, no clear interfaces or abstractions
- **Singleton Overuse**: 6 autoloaded singletons creating global state dependencies
- **No Clear Layers**: Missing separation between presentation, business logic, and data layers

### 2. Code Quality Issues
- **Massive Files**: `camera.gd` has 1400+ lines, `dex.gd` has 600+ lines
- **Duplicate Code**: Image display logic repeated across camera.gd, dex.gd
- **Hardcoded Values**: Magic numbers, hardcoded paths, inline configuration
- **Inconsistent Patterns**: Mixed async patterns (callbacks vs await), inconsistent error handling
- **Poor Naming**: Generic names like "record_image", unclear variable names

### 3. API Layer Problems
- **Incomplete Abstraction**: API layer exists but scenes still contain direct HTTP logic
- **Callback Hell**: Nested callbacks without proper error boundaries
- **No Request Cancellation**: No way to cancel in-flight requests when navigating away
- **Missing Retry Logic**: Inconsistent retry implementation across services
- **No Response Caching**: Each scene manages its own caching logic

### 4. State Management Issues
- **Global Mutable State**: Singletons with public mutable properties
- **Inconsistent State Updates**: No clear data flow, bidirectional dependencies
- **No State Validation**: Missing guards against invalid state transitions
- **Memory Leaks Risk**: Circular references between singletons and scenes

### 5. Performance Concerns
- **No Resource Pooling**: HTTPRequest nodes created/destroyed repeatedly
- **Inefficient Image Handling**: Full resolution images kept in memory
- **Missing Lazy Loading**: All data loaded upfront rather than on-demand
- **No Background Loading**: UI blocks during data fetching

## Proposed Architecture

### Directory Structure
```
client/biologidex-client/
├── features/                     # Reusable feature modules
│   ├── server_interface/         # All server communication
│   │   ├── api/                  # API layer
│   │   │   ├── core/            # HTTP client, config, types
│   │   │   ├── services/        # Service implementations
│   │   │   └── api_manager.gd   # API orchestrator
│   │   └── auth/                # Authentication management
│   │       └── token_manager.gd
│   ├── cache/                   # Caching layer
│   │   ├── base_cache.gd        # Abstract cache implementation
│   │   ├── memory_cache.gd      # In-memory caching
│   │   ├── disk_cache.gd        # Persistent caching
│   │   └── image_cache.gd       # Specialized image caching
│   ├── database/                # Local data storage
│   │   ├── dex_database.gd      # Dex storage abstraction
│   │   └── sync_manager.gd      # Data synchronization
│   ├── navigation/              # Navigation system
│   │   ├── navigation_manager.gd
│   │   └── route_config.gd      # Route definitions
│   ├── ui/                      # Reusable UI components
│   │   ├── components/          # Generic components
│   │   │   ├── loading_spinner.gd
│   │   │   ├── error_display.gd
│   │   │   └── image_viewer/
│   │   │       ├── image_viewer.gd
│   │   │       └── image_viewer.tscn
│   │   └── dialogs/            # Dialog components
│   │       ├── confirmation_dialog.gd
│   │       └── selection_dialog.gd
│   ├── image_processing/       # Image handling utilities
│   │   ├── image_processor.gd   # Rotation, resizing
│   │   └── image_loader.gd      # Async loading
│   └── tree/                    # Tree visualization (generic)
│       ├── tree_algorithm.gd    # Walker-Buchheim implementation
│       ├── tree_renderer.gd     # Generic rendering
│       └── tree_models.gd       # Data structures
│
├── scenes/                      # Scene-specific code
│   ├── login/
│   │   ├── login.gd
│   │   ├── login.tscn
│   │   └── login_controller.gd  # Business logic
│   ├── create_account/
│   │   ├── create_account.gd
│   │   ├── create_account.tscn
│   │   └── create_account_controller.gd
│   ├── home/
│   │   ├── home.gd
│   │   ├── home.tscn
│   │   └── home_controller.gd
│   ├── camera/
│   │   ├── camera.gd            # UI only
│   │   ├── camera.tscn
│   │   ├── camera_controller.gd # Business logic
│   │   ├── camera_state.gd      # State machine
│   │   └── components/
│   │       ├── photo_selector.gd
│   │       └── analysis_display.gd
│   ├── dex/
│   │   ├── dex.gd
│   │   ├── dex.tscn
│   │   ├── dex_controller.gd
│   │   └── components/
│   │       ├── dex_entry_card.gd
│   │       └── user_selector.gd
│   ├── social/
│   │   ├── social.gd
│   │   ├── social.tscn
│   │   ├── social_controller.gd
│   │   └── components/
│   │       ├── friend_list_item.gd
│   │       └── pending_request_item.gd
│   └── tree/
│       ├── tree.gd              # Scene-specific UI
│       ├── tree.tscn
│       └── tree_controller.gd   # Uses generic tree features
│
├── resources/                   # Resources and configurations
│   ├── themes/
│   ├── fonts/
│   └── test_images/
│
└── project.godot
```

## Implementation Plan

### Phase 1: Foundation (Week 1)
1. **Create directory structure**
   - Set up all directories as outlined above
   - Create README.md files documenting each module's purpose

2. **Extract core features**
   - Move API layer to `features/server_interface/api/`
   - Extract TokenManager to `features/server_interface/auth/`
   - Create base cache classes in `features/cache/`

3. **Implement dependency injection**
   - Create ServiceLocator pattern for managing dependencies
   - Replace direct singleton access with injected dependencies
   - Add interfaces for all major components

### Phase 2: API Layer Refactor (Week 1-2)
1. **Enhance API client**
   ```gdscript
   # features/server_interface/api/core/request_manager.gd
   class_name RequestManager

   var _active_requests: Dictionary = {}
   var _request_pool: Array[HTTPRequest] = []

   func execute_request(config: RequestConfig) -> RequestResult:
       var request = _get_or_create_request()
       var id = _generate_request_id()
       _active_requests[id] = request
       # Implementation with proper cancellation support

   func cancel_request(id: String) -> void:
       if id in _active_requests:
           _active_requests[id].cancel_request()
   ```

2. **Implement response caching**
   ```gdscript
   # features/cache/http_cache.gd
   class_name HTTPCache extends BaseCache

   func get_cached_response(url: String, max_age: int) -> Variant:
       var key = _hash_url(url)
       return get_cached(key, max_age)
   ```

3. **Add retry middleware**
   - Exponential backoff
   - Circuit breaker pattern
   - Request deduplication

### Phase 3: Scene Refactoring (Week 2-3)
1. **Separate concerns in camera scene**
   ```gdscript
   # scenes/camera/camera_controller.gd
   class_name CameraController

   signal state_changed(new_state: CameraState)
   signal analysis_complete(result: Dictionary)

   var _state_machine: CameraStateMachine
   var _image_service: ImageService
   var _vision_service: VisionService

   func _init(image_svc: ImageService, vision_svc: VisionService):
       _image_service = image_svc
       _vision_service = vision_svc
       _state_machine = CameraStateMachine.new()
   ```

2. **Extract reusable components**
   - Create ImageViewer component used by camera, dex, and tree
   - Extract LoadingOverlay component
   - Create ErrorBoundary component for consistent error handling

3. **Implement proper MVC/MVP pattern**
   - View: Scene files handle only UI updates
   - Controller: Business logic and orchestration
   - Model: Data models and state management

### Phase 4: State Management (Week 3)
1. **Implement state store pattern**
   ```gdscript
   # features/state/app_state.gd
   class_name AppState

   signal state_changed(path: String, value: Variant)

   var _state: Dictionary = {}
   var _subscribers: Dictionary = {}

   func set_state(path: String, value: Variant) -> void:
       _state[path] = value
       _notify_subscribers(path, value)

   func subscribe(path: String, callback: Callable) -> void:
       if not path in _subscribers:
           _subscribers[path] = []
       _subscribers[path].append(callback)
   ```

2. **Replace singleton state access**
   - Convert singletons to services
   - Inject dependencies through constructors
   - Use signals for state updates

### Phase 5: Memory & Performance (Week 4)
1. **Implement resource pooling**
   ```gdscript
   # features/pools/http_request_pool.gd
   class_name HTTPRequestPool

   var _pool: Array[HTTPRequest] = []
   var _max_size: int = 10

   func acquire() -> HTTPRequest:
       if _pool.is_empty():
           return _create_new()
       return _pool.pop_back()

   func release(request: HTTPRequest) -> void:
       if _pool.size() < _max_size:
           _reset_request(request)
           _pool.append(request)
       else:
           request.queue_free()
   ```

2. **Add image optimization**
   - Implement thumbnail generation
   - Add progressive loading
   - Cache processed images

3. **Implement lazy loading**
   - Virtual scrolling for lists
   - On-demand data fetching
   - Background preloading

### Phase 6: Testing & Documentation (Week 4-5)
1. **Add unit tests**
   - Test controllers independently
   - Mock API responses
   - Test state transitions

2. **Create integration tests**
   - Test complete user flows
   - Verify memory cleanup
   - Test error scenarios

3. **Document architecture**
   - Create architecture diagrams
   - Document coding standards
   - Create contribution guidelines

## Migration Strategy

### Incremental Migration Path
1. **Start with new features**: Implement new features using the new architecture
2. **Refactor on touch**: When modifying existing code, migrate it to new structure
3. **High-priority scenes first**: Start with camera and dex scenes (most complex)
4. **Maintain backward compatibility**: Keep old APIs working during transition

### Risk Mitigation
1. **Feature flags**: Use feature flags to toggle between old/new implementations
2. **Parallel development**: Keep old code working while building new
3. **Incremental releases**: Deploy refactored components gradually
4. **Rollback plan**: Maintain ability to revert to old implementation

## Code Style Guidelines

### Naming Conventions
- **Classes**: PascalCase (e.g., `CameraController`)
- **Files**: snake_case matching class name (e.g., `camera_controller.gd`)
- **Methods**: snake_case (e.g., `handle_image_upload`)
- **Signals**: snake_case past tense (e.g., `image_uploaded`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `MAX_IMAGE_SIZE`)

### Code Organization
```gdscript
class_name ExampleClass extends Node

## Brief description of the class
## Longer description if needed

# Signals
signal example_happened(data: Dictionary)

# Enums
enum State { IDLE, LOADING, ERROR }

# Constants
const MAX_RETRIES := 3

# Export variables
@export var public_property: int = 0

# Public variables
var current_state: State = State.IDLE

# Private variables
var _internal_data: Dictionary = {}

# Onready variables
@onready var _button: Button = $Button

# Lifecycle methods
func _ready() -> void:
    pass

func _process(delta: float) -> void:
    pass

# Public methods
func public_method() -> void:
    pass

# Private methods
func _private_method() -> void:
    pass

# Signal handlers
func _on_button_pressed() -> void:
    pass
```

### Best Practices
1. **Single Responsibility**: Each class should have one clear purpose
2. **Dependency Injection**: Pass dependencies through constructors
3. **Immutable Data**: Prefer returning new objects over modifying existing
4. **Error Handling**: Always handle errors explicitly
5. **Resource Cleanup**: Always free resources in _exit_tree()
6. **Type Safety**: Use static typing everywhere possible
7. **Documentation**: Document all public APIs

## Success Metrics

### Code Quality Metrics
- **File Size**: No file exceeds 300 lines
- **Cyclomatic Complexity**: No method exceeds complexity of 10
- **Coupling**: No class depends on more than 5 other classes

### Performance Metrics
- **Memory Usage**: 50% reduction in baseline memory usage
- **Load Time**: 30% faster scene transitions
- **Frame Rate**: Maintain 60 FPS during all operations
- **Network Efficiency**: 40% reduction in API calls through caching

### Developer Experience
- **Build Time**: No increase in build time
- **Onboarding**: New developers productive within 1 day
- **Bug Resolution**: 50% reduction in time to fix bugs
- **Feature Velocity**: 30% increase in feature delivery speed

## Timeline & Resources

### Timeline (5 weeks)
- **Week 1**: Foundation and core extraction
- **Week 2**: API layer refactoring
- **Week 3**: Scene refactoring (camera, dex)
- **Week 4**: State management and performance
- **Week 5**: Testing, documentation, and migration

## Conclusion

This refactoring plan addresses all critical issues identified in the audit while providing a clear path forward for the BiologiDex client application. The new architecture will significantly improve maintainability, testability, and performance while reducing technical debt and enabling faster feature development.

The incremental migration strategy ensures that development can continue during the refactor, minimizing disruption to the project timeline. By following this plan, the BiologiDex client will transform from a monolithic, tightly-coupled application to a modular, scalable, and maintainable codebase that can evolve with the project's needs.