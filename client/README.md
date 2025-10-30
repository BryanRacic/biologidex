# BiologiDex Client

# Usage

## Note: *File Upload Limitations*
- File upload is only available in the HTML5 build 
- Browsers enforce CORS (Cross-Origin Resource Sharing) policies that prevent file:// URLs from loading resources
    - Godot HTML5 exports require:
        - .wasm (WebAssembly binary)
        - .pck (game data package)
    - These files must be served via HTTP/HTTPS to work properly.
        - See the web server under the File Upload Compatible instructions

## No File Upload
Open html export in web browser
```
client/biologidex-client/export/web/biologidex-client.html
```

## File Upload Compatible
```
client/biologidex-client/export/web/serve.sh
# Runs on: http://localhost:8080
```
Then access: http://localhost:8080/biologidex-client.html

# Godot 4.5 Implementation Guide

## Table of Contents
1. [Project Structure](#project-structure)
2. [Current Implementation Analysis](#current-implementation-analysis)
3. [Authentication Implementation](#authentication-implementation--completed)
4. [Responsive Design Best Practices](#responsive-design-best-practices)
5. [Recommended Improvements](#recommended-improvements)
6. [Implementation Guidelines](#implementation-guidelines)
7. [Testing Strategy](#testing-strategy)
8. [Platform-Specific Considerations](#platform-specific-considerations)
9. [Development Roadmap](#development-roadmap)
10. [Quick Reference: Using Authenticated Endpoints](#quick-reference-using-authenticated-endpoints)

## Project Structure

```
client/
├── biologidex-client/
│   ├── .godot/               # Engine cache (git-ignored)
│   ├── icon.svg              # Application icon
│   ├── main.tscn             # Main scene file
│   ├── login.tscn            # Login scene
│   ├── login.gd              # Login logic with token refresh
│   ├── create_acct.tscn      # Registration scene
│   ├── create_account.gd     # Registration logic with auto-login
│   ├── home.tscn             # Main app scene (post-auth)
│   ├── camera.tscn           # Photo upload scene
│   ├── camera.gd             # Photo upload with CV integration
│   ├── record_image.tscn     # Animal record card component
│   ├── api_manager.gd        # HTTP API singleton (autoload)
│   ├── token_manager.gd      # JWT token persistence (autoload)
│   ├── navigation_manager.gd # Navigation singleton (autoload)
│   ├── responsive.gd         # Responsive behavior base script
│   ├── responsive_container.gd # Auto-margin container class
│   ├── theme.tres            # Base theme resource
│   └── project.godot         # Project configuration
└── README.md                 # This file
```

## Current Implementation Analysis

### Issues Found

1. **Incorrect Base Resolution**: Currently using 1320×2868 (unusual portrait aspect ratio)
   - This resolution is non-standard and may cause scaling issues
   - Extremely tall aspect ratio not suitable for most devices

2. **Basic Scene Structure**: The main.tscn uses basic containers but lacks proper responsive setup
   - Missing AspectRatioContainer for maintaining UI proportions
   - No proper anchor presets applied to main containers
   - VBoxContainer not properly stretched to full viewport

3. **Missing Scripts**: No GDScript attached for dynamic responsive behavior

4. **Incomplete UI Implementation**: Only skeleton UI without actual functionality

## Authentication Implementation (✅ COMPLETED)

### Login Flow
- **Scene**: `login.tscn` / `login.gd`
- **Features**:
  - Username/password authentication via `/api/v1/auth/login/`
  - Automatic token refresh on app launch
  - JWT token persistence via `TokenManager`
  - Form validation with user feedback
  - Loading states with disabled inputs
  - Navigation to create account screen
- **Security**: Passwords cleared on failed login, redacted in logs

### Registration Flow
- **Scene**: `create_acct.tscn` / `create_account.gd`
- **Features**:
  - Account creation via `/api/v1/users/` endpoint
  - Required fields: username, email, password, password_confirm
  - Client-side validation:
    - Email format validation
    - Username minimum length (3 chars)
    - Password minimum length (8 chars)
    - Password confirmation matching
  - Server-side error handling with field-specific messages
  - Automatic login after successful registration
  - Navigation to home screen after auth
- **Security**: Password fields cleared on errors, passwords redacted in logs

### API Integration
- **Singleton**: `APIManager` (autoload)
- **Endpoints**:
  - `login()` - POST /auth/login/
  - `register()` - POST /users/
  - `refresh_token()` - POST /auth/refresh/
- **Pattern**: Callback-based async requests with response code handling
- **Base URL**: https://biologidex.io/api/v1

### Token Management
- **Singleton**: `TokenManager` (autoload)
- **Storage**: Browser localStorage (web), encrypted file (native)
- **Features**:
  - JWT access/refresh token persistence
  - Automatic token refresh
  - User data caching
  - Session validation

## Responsive Design Best Practices

### 1. Base Resolution Configuration

**Recommended Settings:**
```gdscript
# Desktop/Landscape Mobile (16:9)
viewport_width = 1280
viewport_height = 720

# Portrait Mobile (9:16)
viewport_width = 720
viewport_height = 1280

# Tablet Support (4:3 or 16:10)
viewport_width = 1280
viewport_height = 800
```

### 2. Project Settings Configuration

Update `project.godot` with:

```ini
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/handheld/orientation=6  # sensor_landscape for mobile

[gui]
theme/default_font_multichannel_signed_distance_field=true
theme/default_theme_scale=1.0  # Increase to 1.5-2.0 for mobile
```

### 3. Scene Structure Best Practices

```
Main (Control - Full Rect Anchor)
├── Panel (Full Rect with margins for overscan)
│   ├── AspectRatioContainer (for constrained layouts)
│   │   └── VBoxContainer
│   │       ├── Header (HBoxContainer)
│   │       │   ├── Logo
│   │       │   ├── Title
│   │       │   └── MenuButton
│   │       ├── Content (ScrollContainer)
│   │       │   └── MarginContainer
│   │       │       └── [Page-specific content]
│   │       └── Footer (HBoxContainer)
│   │           └── NavigationButtons
│   └── NotificationLayer (for popups/dialogs)
```

### 4. Anchor and Margin System

**Key Concepts:**
- Use anchor presets (Full Rect, Center, etc.) for quick setup
- Apply margins for padding: `margin_left/top/right/bottom`
- Use containers for automatic arrangement
- Combine anchors with containers for flexible layouts

**Example Control Setup:**
```gdscript
extends Control

func _ready():
    # Set full rect anchor
    set_anchors_preset(Control.PRESET_FULL_RECT)
    # Add margins for safe area
    add_theme_constant_override("margin_left", 20)
    add_theme_constant_override("margin_right", 20)
    add_theme_constant_override("margin_top", 20)
    add_theme_constant_override("margin_bottom", 20)
```

## Recommended Improvements

### Immediate Fixes

1. **Update project.godot:**
```ini
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
```

2. **Restructure main.tscn:**
   - Add proper anchor presets to all controls
   - Implement AspectRatioContainer for UI consistency
   - Add MarginContainer for safe area handling

3. **Create responsive.gd script:**
```gdscript
extends Control

var base_size := Vector2(1280, 720)
var gui_aspect_ratio := 16.0 / 9.0
var gui_margin := 20.0

@onready var main_panel: Panel = $Panel
@onready var aspect_container: AspectRatioContainer = $Panel/AspectRatioContainer

func _ready():
    get_viewport().size_changed.connect(_on_viewport_size_changed)
    _update_responsive_layout()

func _on_viewport_size_changed():
    _update_responsive_layout()

func _update_responsive_layout():
    var viewport_size = get_viewport().size
    var scale_factor = min(viewport_size.x / base_size.x, viewport_size.y / base_size.y)

    # Update GUI scale for different screen densities
    if viewport_size.x < 800:  # Mobile
        theme.default_font_size = int(14 * scale_factor * 1.5)
    else:  # Desktop/Tablet
        theme.default_font_size = int(14 * scale_factor)

    # Update aspect ratio container
    if aspect_container:
        aspect_container.ratio = min(viewport_size.aspect(), gui_aspect_ratio)
```

### Page Implementation Structure

For each page listed in requirements:

#### 1. Create Account Page (✅ IMPLEMENTED)
```
create_acct.tscn
├── Panel
│   └── MarginContainer
│       └── VBoxContainer
│           ├── Header (Title + Subtitle)
│           ├── HSeparator
│           └── Content (ScrollContainer)
│               └── CreateAcctForm
│                   ├── EmailField
│                   ├── UsernameField
│                   ├── PasswordField
│                   ├── ConfirmPasswordField
│                   ├── StatusLabel
│                   ├── LoadingSpinner
│                   └── CreateAcctButton
```

#### 2. Login Page (✅ IMPLEMENTED)
```
login.tscn
├── Panel
│   └── MarginContainer
│       └── VBoxContainer
│           ├── Header (Title + Subtitle)
│           ├── HSeparator
│           └── Content (ScrollContainer)
│               └── LoginForm
│                   ├── CreateAcctButton
│                   ├── UsernameField
│                   ├── PasswordField
│                   ├── StatusLabel
│                   ├── LoadingSpinner
│                   └── LoginButton
```

#### 3. Home/Main Navigation
```
home.tscn
├── VBoxContainer
│   ├── Header
│   ├── TabContainer
│   │   ├── DexTab
│   │   ├── CameraTab
│   │   ├── TreeTab
│   │   └── SocialTab
│   └── BottomNavigation
```

## Implementation Guidelines

### 1. Navigation System

Create a `NavigationManager` singleton:

```gdscript
# navigation_manager.gd (AutoLoad)
extends Node

var current_scene: PackedScene
var scene_stack: Array = []

func navigate_to(scene_path: String):
    scene_stack.push_back(get_tree().current_scene.scene_file_path)
    get_tree().change_scene_to_file(scene_path)

func go_back():
    if scene_stack.size() > 0:
        var previous_scene = scene_stack.pop_back()
        get_tree().change_scene_to_file(previous_scene)
```

### 2. Responsive Container System

Create reusable responsive containers:

```gdscript
# responsive_container.gd
class_name ResponsiveContainer
extends MarginContainer

@export var mobile_margins: int = 16
@export var tablet_margins: int = 32
@export var desktop_margins: int = 48

func _ready():
    _update_margins()
    get_viewport().size_changed.connect(_update_margins)

func _update_margins():
    var width = get_viewport().size.x
    var margin_value: int

    if width < 600:  # Mobile
        margin_value = mobile_margins
    elif width < 1024:  # Tablet
        margin_value = tablet_margins
    else:  # Desktop
        margin_value = desktop_margins

    add_theme_constant_override("margin_left", margin_value)
    add_theme_constant_override("margin_right", margin_value)
    add_theme_constant_override("margin_top", margin_value)
    add_theme_constant_override("margin_bottom", margin_value)
```

### 3. Theme Management

Create a unified theme resource:

```gdscript
# Create theme.tres resource with:
# - Font sizes that scale with DPI
# - Consistent color palette
# - Button/input field minimum sizes
# - Proper touch target sizes (min 44x44 dp for mobile)
```

### 4. Camera/CV Integration Pattern

**Editor Testing Mode:**
```gdscript
# Detect editor vs export
if OS.has_feature("editor"):
    # Load test image from resources
    var image := Image.new()
    image.load("res://resources/test_img.jpeg")
    # Process normally
```

**Two-Stage Image Display:**
```gdscript
# Stage 1: Simple preview during upload
simple_image.texture = texture
simple_image.visible = true
bordered_container.visible = false

# Stage 2: After CV identification
bordered_image.texture = simple_image.texture
bordered_container.ratio = img_width / img_height
simple_image.visible = false
bordered_container.visible = true

# Update parent container size
await get_tree().process_frame
var required_height := available_width / aspect_ratio
parent_control.custom_minimum_size.y = required_height
```

**Animal API Response Format:**
```json
{
  "scientific_name": "Hydrochoerus hydrochaeris",
  "common_name": "capybara",
  "kingdom": "Animalia",
  "phylum": "Chordata",
  "class_name": "Mammalia"
}
```
Display pattern: "Scientific name - common name"

### 5. Authentication Pattern

Best practices from implemented login/registration:

```gdscript
# Form validation pattern
func _on_submit_button_pressed() -> void:
    if is_loading:
        return

    # 1. Get and strip input values
    var field_value := input_field.text.strip_edges()

    # 2. Validate client-side
    if field_value.length() == 0:
        _show_error("Field is required")
        input_field.grab_focus()
        return

    # 3. Set loading state (disable inputs)
    _set_loading(true, "Processing...")

    # 4. Make API call with callback
    APIManager.some_endpoint(field_value, func(response: Dictionary, code: int):
        if code == 200:
            # Success path
            _handle_success(response)
        else:
            # Error handling with field-specific messages
            var error_message := _parse_error_response(response, code)
            _show_error(error_message)
            _set_loading(false)
    )

# Error parsing pattern
func _parse_error_response(response: Dictionary, code: int) -> String:
    # Check for field-specific errors (arrays)
    if response.has("field_name"):
        var errors = response["field_name"]
        if typeof(errors) == TYPE_ARRAY and errors.size() > 0:
            return "Field: " + str(errors[0])
    # Fallback to general errors
    elif response.has("detail"):
        return str(response["detail"])
    elif code == 0:
        return "Cannot connect to server"
    return "Request failed"

# Loading state pattern
func _set_loading(loading: bool, message: String = "") -> void:
    is_loading = loading
    loading_spinner.visible = loading
    submit_button.disabled = loading
    # Disable all input fields
    for field in input_fields:
        field.editable = not loading
```

## Testing Strategy

### Resolution Testing Matrix

Test on these common resolutions:

| Device Type | Resolution | Aspect Ratio | Notes |
|-------------|------------|--------------|-------|
| iPhone SE | 750×1334 | 9:16 | Smallest iOS |
| iPhone 14 Pro | 1179×2556 | 9:19.5 | Modern iOS |
| Android Phone | 1080×1920 | 9:16 | Common Android |
| iPad | 1024×768 | 4:3 | Tablet portrait |
| Steam Deck | 1280×800 | 16:10 | Gaming handheld |
| Desktop HD | 1920×1080 | 16:9 | Standard monitor |
| Ultrawide | 2560×1080 | 21:9 | Wide monitor |

### Testing Checklist

- [ ] All UI elements visible at minimum resolution (750×1334)
- [ ] No overlapping elements at any resolution
- [ ] Touch targets minimum 44×44 dp on mobile
- [ ] Text remains readable at all scales
- [ ] ScrollContainers work properly when content overflows
- [ ] Keyboard doesn't obscure input fields on mobile
- [ ] Landscape/portrait rotation handled gracefully

## Platform-Specific Considerations

### Mobile (iOS/Android)
```gdscript
# Handle safe areas for notches/system UI
func _ready():
    if OS.has_feature("mobile"):
        var safe_area = DisplayServer.get_display_safe_area()
        # Adjust margins based on safe_area
```

### Web Export
```gdscript
# Handle browser window resizing
func _ready():
    if OS.has_feature("web"):
        # Enable fullscreen button
        # Handle browser back button
        # Adjust for mobile browsers
```

### Desktop
```gdscript
# Handle window resizing and multiple monitors
func _ready():
    if OS.has_feature("pc"):
        # Set minimum window size
        DisplayServer.window_set_min_size(Vector2i(800, 600))
        # Remember window position/size
```

## Development Roadmap

### Phase 1: Foundation (COMPLETED ✅)
- [x] Basic project structure
- [x] Fix resolution settings
- [x] Implement responsive base scene
- [x] Create navigation system
- [x] Setup theme resource

### Phase 2: Core Pages (IN PROGRESS)
- [x] Login/Registration flow
  - [x] Login scene with JWT token management
  - [x] Registration scene with auto-login
  - [x] API integration (login, register, refresh)
  - [x] Token persistence and auto-refresh
- [x] Camera/Photo upload scene (✅ COMPLETED)
  - [x] FileAccessWeb integration for HTML5 file selection
  - [x] Editor testing mode with test image loading
  - [x] Two-stage image display (simple → bordered after identification)
  - [x] RecordImage component with dynamic aspect ratio
  - [x] Vision API integration with async job polling
  - [x] Animal information display (scientific name - common name)
- [ ] Home screen with navigation
- [ ] Basic profile view
- [ ] Dex entry creation flow (post-CV identification)

### Phase 3: Features
- [ ] Animal dex listing
- [ ] Taxonomic tree visualization
- [ ] Friends system UI
- [ ] Settings page

### Phase 4: Polish
- [ ] Animations and transitions
- [ ] Loading states
- [ ] Error handling
- [ ] Offline mode UI

### Phase 5: Platform Optimization
- [ ] iOS specific adjustments
- [ ] Android specific adjustments
- [ ] Web export optimization
- [ ] Desktop window management

## Additional Resources

### Godot Documentation
- [Multiple Resolutions Guide](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html)
- [UI System Overview](https://docs.godotengine.org/en/stable/tutorials/ui/index.html)
- [Container Tutorial](https://docs.godotengine.org/en/stable/tutorials/ui/gui_containers.html)

### Best Practices References
- Official Godot Demo: `godot-demo-projects/gui/multiple_resolutions/`
- [Godot UI Anchors Guide](https://docs.godotengine.org/en/stable/tutorials/ui/size_and_anchors.html)
- [Responsive Design Patterns](https://material.io/design/layout/responsive-layout-grid.html)

### Testing Tools
- Godot's Project Settings > Window > Override for testing different resolutions
- Device simulators for mobile testing
- Browser developer tools for web export testing

## Quick Start Guide

1. **Fix Project Settings:**
   ```bash
   cd client/biologidex-client
   # Update project.godot with recommended display settings
   ```

2. **Create Base Scene Structure:**
   ```bash
   # Open Godot editor
   # Create new scene following recommended structure
   # Save as main_responsive.tscn
   ```

3. **Implement Navigation:**
   ```bash
   # Add navigation_manager.gd to autoload
   # Create page scenes for each requirement
   ```

4. **Test Responsive Behavior:**
   ```bash
   # Run project and resize window
   # Test with different aspect ratios
   # Verify on mobile preview
   ```

## Quick Reference: Using Authenticated Endpoints

Now that authentication is implemented, here's how to use it in new pages:

### Making Authenticated API Calls

```gdscript
# Example: Fetching user's dex entries
func fetch_my_dex_entries() -> void:
    # Get access token from TokenManager
    var token := TokenManager.get_access_token()

    if token.length() == 0:
        # User not logged in, redirect to login
        NavigationManager.navigate_to("res://login.tscn")
        return

    # Make API call with token
    var url := APIManager.BASE_URL + "/dex/entries/my_entries/"
    var headers := ["Authorization: Bearer %s" % token]

    http_request.request(url, headers, HTTPClient.METHOD_GET)

# Example: Creating a new dex entry
func create_dex_entry(animal_id: String, image_data: PackedByteArray) -> void:
    var token := TokenManager.get_access_token()

    if token.length() == 0:
        _handle_unauthorized()
        return

    # Use APIManager pattern with token
    # (Add method to APIManager for consistency)
```

### Handling Token Expiration

```gdscript
# In your scene's API callback:
func _on_api_response(response: Dictionary, code: int) -> void:
    if code == 401:
        # Token expired, try refresh
        TokenManager.refresh_access_token(func(success: bool, error: String):
            if success:
                # Retry original request
                _retry_request()
            else:
                # Refresh failed, redirect to login
                NavigationManager.navigate_to("res://login.tscn", true)
        )
    else:
        # Handle normal response
        _process_response(response)
```

### Navigation with Auth Check

```gdscript
# Create helper function in NavigationManager:
func navigate_to_protected(scene_path: String) -> void:
    if not TokenManager.has_access_token():
        # Save intended destination
        set_meta("redirect_after_login", scene_path)
        navigate_to("res://login.tscn")
    else:
        navigate_to(scene_path)

# After successful login in login.gd:
if NavigationManager.has_meta("redirect_after_login"):
    var redirect := NavigationManager.get_meta("redirect_after_login")
    NavigationManager.remove_meta("redirect_after_login")
    NavigationManager.navigate_to(redirect)
else:
    NavigationManager.navigate_to("res://home.tscn")
```

## Conclusion

The BiologiDex client now has a solid foundation with:

✅ **Authentication System**: Complete login/registration flow with JWT token management
✅ **API Integration**: RESTful API communication with the Django backend
✅ **Responsive Design**: Foundation for multi-platform support
✅ **Navigation System**: Scene management with history stack

### Current Status
Phase 1 (Foundation) and Phase 2 (Core Pages) are mostly complete. Implemented features:
- ✅ Authentication system with JWT token management
- ✅ Camera/photo upload with CV integration
- ✅ Image preview with dynamic aspect ratio handling

Next priorities:
- Home screen implementation with tab navigation
- Dex entry creation workflow (post-CV identification)
- Profile and social features

### Development Priorities
1. ✅ Authentication and API integration (COMPLETED)
2. ✅ Camera integration and image upload (COMPLETED)
3. Home screen with tab navigation (NEXT)
4. Dex entry creation flow
5. Testing across target resolutions and platforms

The authentication patterns established (form validation, error handling, loading states, token management) should be followed for all future API-connected features to maintain consistency and reliability.