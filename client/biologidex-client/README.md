# BiologiDex Client

Godot 4.5 client application for the BiologiDex wildlife observation social network.

## Architecture Overview

The client follows a modular, feature-based architecture with clear separation of concerns:

```
client/biologidex-client/
├── bootstrap.gd              # Application bootstrap and service initialization
├── features/                 # Reusable feature modules
│   ├── cache/               # Caching layer (memory, disk, HTTP, images)
│   ├── database/            # Local storage (DexDatabase, SyncManager)
│   ├── image_processing/    # Image utilities (rotation, resizing, optimization)
│   ├── navigation/          # Navigation system
│   ├── pools/               # Resource pooling (HTTPRequestPool)
│   ├── server_interface/    # Server communication
│   │   ├── api/            # API layer (services, HTTP client)
│   │   └── auth/           # Authentication (TokenManager)
│   ├── state/              # State management (AppState)
│   ├── tree/               # Tree visualization
│   └── ui/                 # Reusable UI components
│       ├── components/     # Generic components (LoadingSpinner, ErrorDisplay)
│       └── dialogs/        # Dialog components
├── scenes/                  # Scene-specific code
│   ├── camera/             # Camera and CV integration
│   ├── dex/                # Dex viewing and management
│   ├── home/               # Home screen
│   ├── login/              # Login screen
│   ├── create_account/     # Account creation
│   ├── social/             # Friends and social features
│   └── tree/               # Tree visualization scene
└── resources/              # Assets (themes, fonts, images)
```

## Key Features

### 1. Service-Based Architecture
- **ServiceLocator**: Dependency injection container for managing services
- **Bootstrap**: Initializes all services at application startup
- Clean dependency management with minimal global state

### 2. Caching Layer
- **BaseCache**: Abstract base class for all caching implementations
- **MemoryCache**: LRU in-memory cache with size limits
- **DiskCache**: Persistent disk-based caching
- **ImageCache**: Specialized image caching with thumbnails
- **HTTPCache**: HTTP response caching

### 3. HTTP Layer
- **HTTPRequestPool**: Pooled HTTP request nodes for performance
- **RequestManager**: Request management with retry, deduplication, cancellation
- Automatic retry with exponential backoff
- Request deduplication to avoid duplicate API calls

### 4. State Management
- **AppState**: Centralized reactive state store
- Event-driven updates with signal-based subscriptions
- History tracking for undo/redo support

### 5. Image Processing
- **ImageProcessor**: Rotation, resizing, format conversion
- **ImageLoader**: Asynchronous image loading
- Automatic thumbnail generation
- Memory-efficient image handling

### 6. Reusable UI Components
- **ImageViewer**: Reusable image display with rotation
- **LoadingSpinner**: Animated loading indicator
- **ErrorDisplay**: Error messaging with retry

## Getting Started

### Prerequisites
- Godot 4.5 or later
- Backend server running (see server/ directory)

### Running the Client

1. Open project in Godot Editor:
   ```bash
   godot project.godot
   ```

2. Run the project (F5) or export for web/desktop

### Project Structure

#### Features
Reusable, self-contained feature modules that can be used across different scenes.

#### Scenes
Scene-specific code organized by screen/feature. Each scene should:
- Keep UI logic in the main scene script
- Delegate business logic to controllers
- Use features/ modules for shared functionality

#### Bootstrap
The `bootstrap.gd` file is the first autoload and initializes:
1. ServiceLocator for dependency injection
2. Core features (caching, HTTP, state)
3. Legacy services (backward compatibility)
4. Service registration

## Development Guidelines

### Code Organization
- **One responsibility per class**: Each class should have a single, well-defined purpose
- **Dependency injection**: Pass dependencies through constructors, avoid global access
- **Type safety**: Use static typing throughout (`var foo: String = ""`)
- **Documentation**: Document all public APIs with comments

### Naming Conventions
- **Classes**: PascalCase (e.g., `ImageProcessor`)
- **Files**: snake_case matching class name (e.g., `image_processor.gd`)
- **Methods**: snake_case (e.g., `process_image`)
- **Signals**: snake_case past tense (e.g., `image_processed`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `MAX_SIZE`)
- **Private members**: Prefix with underscore (e.g., `_internal_data`)

### Adding New Features
1. Create feature module in `features/` directory
2. Implement with clear interfaces
3. Register in Bootstrap if it's a service
4. Document in module README
5. Use in scenes via ServiceLocator

### Adding New Scenes
1. Create scene directory in `scenes/`
2. Create scene file (.tscn) and script (.gd)
3. Extract business logic to controller if complex
4. Reuse components from `features/ui/components/`
5. Use ServiceLocator to access services

## Architecture Patterns

### Service Locator Pattern
Services are registered at startup and retrieved via ServiceLocator:

```gdscript
# Get service
var api_manager = ServiceLocator.get_instance().api_manager()

# Or use convenience method
var state = ServiceLocator.get_instance().get_service("AppState")
```

### State Management
Centralized state with reactive updates:

```gdscript
# Get state value
var user = AppState.get_state("auth.user")

# Set state value
AppState.set_state("auth.is_authenticated", true)

# Subscribe to changes
AppState.subscribe("auth.user", func(user_data):
    print("User changed: ", user_data)
)
```

### Image Processing
Utilities for common image operations:

```gdscript
# Rotate image
var rotated = ImageProcessor.rotate_image(image, 90)

# Resize image
var resized = ImageProcessor.resize_image(image, 1024, 1024)

# Generate thumbnail
var thumb = ImageProcessor.generate_thumbnail(image)
```

## Testing

### Manual Testing
1. Run project in Godot Editor
2. Test each scene and workflow
3. Verify memory usage (Godot Profiler)
4. Test web export compatibility

### Web Export
```bash
# Export from Godot Editor or use script
./scripts/export-client.sh
```

## Performance Considerations

- **HTTP Request Pooling**: Reuses HTTPRequest nodes to avoid allocation overhead
- **Image Caching**: Two-layer caching (memory + disk) for images
- **Lazy Loading**: Load data on-demand rather than upfront
- **Resource Cleanup**: Always free resources in `_exit_tree()`

## Migration from Old Architecture

This refactored architecture maintains backward compatibility with the old structure:
- Legacy autoloads still work (NavigationManager, TokenManager, etc.)
- Gradual migration - old code continues to function
- New features should use the new architecture
- Refactor old code opportunistically

## Troubleshooting

### Service Not Found
If you get "Service not found" errors:
1. Check that service is registered in `bootstrap.gd`
2. Verify autoload order in `project.godot`
3. Ensure Bootstrap is first autoload

### Path Not Found
After refactor, if paths are broken:
1. Check that files were moved correctly
2. Update import paths in scripts
3. Verify scene references in .tscn files

### Memory Leaks
If you suspect memory leaks:
1. Check that `_exit_tree()` frees resources
2. Verify signal disconnections
3. Use Godot's memory profiler
4. Check for circular references

## Contributing

When contributing to the client:
1. Follow the coding standards
2. Keep features modular and reusable
3. Document public APIs
4. Test thoroughly before submitting
5. Update relevant READMEs

## License

See main project LICENSE file.
