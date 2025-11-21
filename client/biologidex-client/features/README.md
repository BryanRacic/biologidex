# Features

This directory contains reusable, self-contained feature modules that can be used across different scenes.

## Module Overview

### cache/
Caching layer with multiple implementations:
- `BaseCache`: Abstract base class for all caches
- `MemoryCache`: LRU in-memory cache with size limits
- `DiskCache`: Persistent disk-based cache
- `ImageCache`: Specialized image caching with thumbnails
- `HTTPCache`: HTTP response caching

**Use cases**: Caching API responses, images, user data

### database/
Local data storage:
- `DexDatabase`: User-partitioned dex storage
- `SyncManager`: Data synchronization with server

**Use cases**: Storing dex entries, sync state

### image_processing/
Image manipulation utilities:
- `ImageProcessor`: Rotation, resizing, format conversion
- `ImageLoader`: Asynchronous image loading

**Use cases**: Preparing images for upload, generating thumbnails, rotating images

### navigation/
Navigation system:
- `NavigationManager`: Scene navigation and routing

**Use cases**: Navigating between scenes

### pools/
Resource pooling for performance:
- `HTTPRequestPool`: Pool of HTTPRequest nodes

**Use cases**: Avoiding repeated allocation of HTTP request nodes

### server_interface/
All server communication:
- `api/`: API layer with services
  - `core/`: HTTP client, request manager, types
  - `services/`: Service implementations (auth, dex, vision, etc.)
  - `api_manager.gd`: API orchestrator
- `auth/`: Authentication
  - `TokenManager`: JWT token management

**Use cases**: Making API calls, authentication

### state/
State management:
- `AppState`: Centralized reactive state store

**Use cases**: Managing application state, reactive updates

### tree/
Tree visualization:
- `tree_cache.gd`: Tree data caching
- `tree_data_models.gd`: Tree data structures
- `tree_renderer.gd`: Tree rendering logic

**Use cases**: Displaying taxonomic tree

### ui/
Reusable UI components:
- `components/`: Generic components
  - `LoadingSpinner`: Animated loading indicator
  - `ErrorDisplay`: Error message display
  - `ImageViewer`: Image viewer with rotation
- `dialogs/`: Dialog components

**Use cases**: Consistent UI elements across scenes

## Creating New Features

When creating a new feature module:

1. **Create directory structure**:
   ```
   features/my_feature/
   ├── my_feature.gd         # Main feature class
   ├── my_feature_types.gd   # Type definitions (if needed)
   └── README.md             # Feature documentation
   ```

2. **Follow patterns**:
   - Use dependency injection
   - Emit signals for events
   - Document public APIs
   - Provide examples in README

3. **Register in Bootstrap** (if it's a service):
   ```gdscript
   # In bootstrap.gd
   var my_feature = MyFeature.new()
   add_child(my_feature)
   service_locator.register_service("MyFeature", my_feature)
   ```

4. **Use in scenes**:
   ```gdscript
   var my_feature = ServiceLocator.get_instance().get_service("MyFeature")
   ```

## Design Principles

### 1. Single Responsibility
Each feature should have one clear purpose.

### 2. Dependency Injection
Pass dependencies through constructors, not global access.

```gdscript
# Good
func _init(http_pool: HTTPRequestPool):
    _http_pool = http_pool

# Bad
func _init():
    _http_pool = get_node("/root/HTTPRequestPool")
```

### 3. Loose Coupling
Features should not directly depend on other features when possible.

### 4. High Cohesion
Related functionality should be grouped together.

### 5. Reusability
Features should be generic enough to use in multiple contexts.

## Testing Features

Features should be testable in isolation:

```gdscript
# Example test
func test_memory_cache():
    var cache = MemoryCache.new(10, 1.0)
    cache.set_cached("key", "value")
    assert(cache.get_cached("key") == "value")
    cache.clear()
```

## Performance Considerations

- **Memory**: Use resource pooling for frequently created objects
- **CPU**: Avoid operations in `_process()` when possible
- **I/O**: Cache results to minimize disk/network access

## Documentation

Each feature module should have:
- Clear class/method documentation
- Usage examples
- Performance characteristics
- Known limitations

## Migration from Legacy Code

When migrating existing functionality:
1. Extract into feature module
2. Maintain backward compatibility initially
3. Update callers incrementally
4. Remove old code when fully migrated
