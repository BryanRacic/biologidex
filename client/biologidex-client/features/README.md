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
Taxonomic tree rendering with radial layout:
- `tree_cache.gd`: Dual-layer caching (memory + disk)
- `tree_data_models.gd`: Data structures matching server API (TaxonomicNode, TreeEdge, TreeData)
- `tree_renderer.gd`: High-performance rendering with MultiMesh, frustum culling, label management

**Key features**:
- Frustum culling with screen-space margin (200px converted to world-space)
- Edge visibility via bounding box intersection (not just endpoint checks)
- Priority-based label overlap detection with 60px minimum spacing
- Zoom-based label filtering (higher ranks visible at all zoom levels)
- Coordinate convention: `scroll_offset` = world-space position at viewport center

**Use cases**: Low-level tree rendering (used by TreeVisualization component)

### tree_visualization/
Reusable tree visualization component (composition pattern):
- `tree_visualization.gd`: Self-contained component encapsulating tree logic
- `tree_visualization.tscn`: Instancable scene

**Key features**:
- Creates TreeGraph and layers programmatically (web export compatible)
- Handles tree data loading, friend sync, and rendering
- Configurable via export vars (auto_load, initial_mode, use_cache)
- Emits signals for tree events (loaded, failed, node_selected)

**Usage**:
```gdscript
var tree_vis = TreeVisualization.new()
paper_camera.content_container.add_child(tree_vis)
tree_vis.setup(paper_camera)  # Must call after adding to tree
tree_vis.tree_loaded.connect(_on_tree_loaded)
```

**Use cases**: Tree scene, home screen background

### ui/
Reusable UI components:
- `components/`: Generic components
  - `LoadingSpinner`: Animated loading indicator
  - `ErrorDisplay`: Error message display
  - `ImageViewer`: Image viewer with rotation
  - `dex_record_image/`: Unified image display component for dex entries
  - `recenter_button/`: Button that appears when camera is off-center (fade animation)
  - `world_space_ui/`: Container for UI elements that pan with the world
  - `clipboard/`: Cross-platform clipboard helper
- `dialogs/`: Dialog components

**RecenterButton usage**:
```gdscript
recenter_button.connect_to_camera(paper_camera)
recenter_button.center_position = Vector2.ZERO
recenter_button.center_threshold = 100.0
recenter_button.recenter_requested.connect(_on_recenter)
```

**WorldSpaceUI usage**:
```gdscript
var world_ui = WorldSpaceUI.new()
world_ui.anchor_position = Vector2.ZERO
paper_camera.content_container.add_child(world_ui)
# Add Controls as children - they will pan with the camera
```

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
