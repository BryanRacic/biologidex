# Scenes

This directory contains all scene-specific code organized by screen/feature.

## Scene Structure

Each scene should follow this structure:

```
scenes/my_scene/
├── my_scene.gd           # Scene script (UI logic)
├── my_scene.tscn         # Scene file
├── my_scene_controller.gd # Business logic (optional, for complex scenes)
└── components/           # Scene-specific components (optional)
    ├── custom_component.gd
    └── custom_component.tscn
```

## Current Scenes

### camera/
Camera and computer vision integration.
- Takes photos
- Uploads to server
- Displays analysis results
- Creates dex entries

### dex/
Dex viewing and management.
- Displays user's dex entries
- Switches between users (friends)
- Shows entry details

### home/
Main home screen after login.
- Navigation hub
- Quick stats

### login/
User login screen.
- Username/password authentication
- JWT token handling

### create_account/
New account creation.
- User registration
- Friend code generation

### social/
Friends and social features.
- Friend list
- Pending requests
- Add friends by code

### tree/
Taxonomic tree visualization.
- Interactive tree display
- Zoom and pan
- Entry markers

## Scene Development Guidelines

### 1. Separation of Concerns

**Scene Script** (`my_scene.gd`):
- Handle UI events (button clicks, input)
- Update UI elements
- Delegate business logic to controller

**Controller** (`my_scene_controller.gd`, optional):
- Business logic and orchestration
- API calls
- Data transformation
- State management

**Example**:
```gdscript
# my_scene.gd (View)
extends Control

var _controller: MySceneController

func _ready():
    _controller = MySceneController.new()
    _controller.data_loaded.connect(_on_data_loaded)
    _controller.load_data()

func _on_button_pressed():
    _controller.handle_action()

func _on_data_loaded(data: Dictionary):
    _update_ui(data)

# my_scene_controller.gd (Controller)
class_name MySceneController extends RefCounted

signal data_loaded(data: Dictionary)

var _api_manager: Variant

func _init():
    _api_manager = ServiceLocator.get_instance().api_manager()

func load_data():
    _api_manager.my_service.get_data(_on_api_response)

func _on_api_response(response: Dictionary, code: int):
    if code == 200:
        data_loaded.emit(response)
```

### 2. Using Services

Access services via ServiceLocator:

```gdscript
# Get API Manager
var api_manager = ServiceLocator.get_instance().api_manager()

# Get App State
var app_state = ServiceLocator.get_instance().get_service("AppState")

# Get Image Cache
var image_cache = ServiceLocator.get_instance().image_cache()
```

### 3. State Management

Use AppState for cross-scene state:

```gdscript
func _ready():
    # Subscribe to state changes
    var app_state = ServiceLocator.get_instance().get_service("AppState")
    app_state.subscribe("auth.user", _on_user_changed)

    # Get current state
    var user = app_state.get_state("auth.user")

func _on_user_changed(user_data: Dictionary):
    # React to state change
    _update_user_ui(user_data)
```

### 4. Navigation

Use NavigationManager for scene transitions:

```gdscript
func _on_continue_pressed():
    NavigationManager.navigate_to("home")
```

### 5. Error Handling

Use ErrorDisplay component for consistent error messaging:

```gdscript
@onready var _error_display: ErrorDisplay = $ErrorDisplay

func _on_api_error(error_msg: String):
    _error_display.show_error(error_msg, true)

func _ready():
    _error_display.retry_requested.connect(_on_retry)
```

### 6. Loading States

Use LoadingSpinner for async operations:

```gdscript
@onready var _loading_spinner: LoadingSpinner = $LoadingSpinner

func _load_data():
    _loading_spinner.show_loading("Loading data...")
    api_manager.get_data(_on_data_loaded)

func _on_data_loaded(data: Dictionary, code: int):
    _loading_spinner.hide_loading()
    # Process data
```

### 7. Resource Cleanup

Always clean up resources in `_exit_tree()`:

```gdscript
func _exit_tree():
    # Disconnect signals
    if _controller != null:
        if _controller.data_loaded.is_connected(_on_data_loaded):
            _controller.data_loaded.disconnect(_on_data_loaded)

    # Cancel pending operations
    if _http_request != null:
        _http_request.cancel_request()
```

## Best Practices

### DO:
- ✅ Keep scene scripts focused on UI
- ✅ Use controllers for complex business logic
- ✅ Reuse components from `features/ui/components/`
- ✅ Use ServiceLocator for dependency access
- ✅ Handle errors gracefully
- ✅ Show loading states for async operations
- ✅ Clean up resources on exit

### DON'T:
- ❌ Put business logic in scene scripts
- ❌ Access global nodes directly
- ❌ Create tight coupling between scenes
- ❌ Ignore error cases
- ❌ Block UI during long operations
- ❌ Forget to disconnect signals

## Creating New Scenes

1. **Create scene directory**:
   ```bash
   mkdir -p scenes/my_scene
   ```

2. **Create scene files**:
   - `my_scene.tscn` (in Godot Editor)
   - `my_scene.gd` (scene script)
   - `my_scene_controller.gd` (if complex)

3. **Implement scene logic**:
   ```gdscript
   extends Control

   func _ready():
       # Initialize scene
       pass

   func _exit_tree():
       # Clean up
       pass
   ```

4. **Add navigation**:
   ```gdscript
   # In NavigationManager or calling scene
   NavigationManager.navigate_to("my_scene")
   ```

5. **Test thoroughly**:
   - Test UI interactions
   - Test error cases
   - Test navigation in/out
   - Test resource cleanup

## Scene Lifecycle

1. **Initialization** (`_ready`):
   - Set up UI
   - Connect signals
   - Load initial data
   - Subscribe to state changes

2. **Active** (user interaction):
   - Handle user input
   - Update UI
   - Make API calls
   - Update state

3. **Cleanup** (`_exit_tree`):
   - Disconnect signals
   - Cancel pending operations
   - Free resources
   - Unsubscribe from state

## Performance Tips

- **Lazy load data**: Only load what's needed when it's needed
- **Cache responses**: Use HTTPCache for API responses
- **Pool resources**: Use HTTPRequestPool for HTTP requests
- **Optimize images**: Use ImageCache for image caching
- **Batch updates**: Update UI in batches, not per-item

## Common Patterns

### Loading Data on Enter
```gdscript
func _ready():
    _load_data()

func _load_data():
    _loading_spinner.show_loading()
    api_manager.my_service.get_data(_on_data_loaded)

func _on_data_loaded(data: Dictionary, code: int):
    _loading_spinner.hide_loading()
    if code == 200:
        _display_data(data)
    else:
        _error_display.show_error("Failed to load data")
```

### Form Submission
```gdscript
func _on_submit_pressed():
    var form_data = _collect_form_data()
    if not _validate_form(form_data):
        return

    _loading_spinner.show_loading("Submitting...")
    api_manager.my_service.submit(form_data, _on_submit_complete)

func _on_submit_complete(response: Dictionary, code: int):
    _loading_spinner.hide_loading()
    if code == 200:
        NavigationManager.navigate_to("success")
    else:
        _error_display.show_error("Submission failed")
```

### Retry on Error
```gdscript
func _ready():
    _error_display.retry_requested.connect(_on_retry)

func _on_retry():
    _load_data()

func _on_api_error(error_msg: String):
    _error_display.show_error(error_msg, true)  # Enable retry
```

## Testing Scenes

- Test in isolation: Run individual scenes
- Test navigation: Ensure proper flow between scenes
- Test error cases: Simulate API failures
- Test edge cases: Empty data, large datasets
- Test performance: Profile with many items

## Migration Notes

When migrating existing scenes:
1. Extract business logic to controller
2. Update to use ServiceLocator
3. Add error handling
4. Add loading states
5. Use reusable components
6. Test thoroughly
