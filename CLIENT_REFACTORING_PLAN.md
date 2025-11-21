# BiologiDex Client Refactoring Plan

## Executive Summary

This document outlines a comprehensive refactoring plan to break down the monolithic scene scripts in the BiologiDex Godot client application. The current architecture has scene scripts ranging from 190 to 1095 lines of code, with significant code duplication and tightly coupled responsibilities. This plan proposes a modular, component-based architecture that promotes code reuse, maintainability, and testability.

## Current State Analysis

### Problem Areas

1. **Monolithic Scene Scripts**
   - `camera.gd`: 1095 lines (largest)
   - `dex.gd`: 636 lines
   - `dex_feed.gd`: 484 lines
   - `tree_controller.gd`: 478 lines
   - `social.gd`: 443 lines
   - Total: 3,688 lines across 8 main scenes

2. **Code Duplication**
   - Manager initialization pattern repeated in every scene
   - Error handling logic duplicated
   - UI state management duplicated
   - Image loading/processing logic scattered

3. **Tight Coupling**
   - Business logic mixed with UI code
   - Direct scene dependencies
   - Hard-coded state machines
   - No clear separation of concerns

4. **Generic Functionality in Specific Scenes**
   - Image rotation logic in camera.gd (lines 158-206)
   - Image preview functionality in camera.gd
   - Manual entry popup handling in camera.gd
   - Status polling mechanisms duplicated

## Proposed Architecture

### Design Principles

1. **Single Responsibility Principle**: Each component handles one concern
2. **DRY (Don't Repeat Yourself)**: Extract common patterns into reusable components
3. **Composition over Inheritance**: Use component-based architecture
4. **Separation of Concerns**: Separate UI, business logic, and data management
5. **Dependency Injection**: Use service locator pattern (already partially implemented)
6. **Event-Driven Communication**: Use signals for loose coupling

### Component Categories

#### 1. UI Components (`features/ui/components/`)
Reusable visual elements and controls

#### 2. Feature Modules (`features/`)
Domain-specific logic and workflows (cv_analysis, dex, image_processing, etc.)

#### 3. Data Components (`features/data/`)
Data models and state management

#### 4. Utility Components (`utilities/`)
Pure utility functions without application-specific context

## Detailed Refactoring Plan

### Phase 1: Core Infrastructure (Week 1)

#### 1.1 Base Scene Controller
**File**: `features/base/base_scene_controller.gd`

```gdscript
class_name BaseSceneController extends Control

# Core managers automatically initialized
var TokenManager
var NavigationManager
var APIManager
var DexDatabase

# Common UI elements
@export var back_button: Button
@export var status_label: Label
@export var loading_spinner: Control

# Common state
var is_loading: bool = false
var scene_name: String = "Unknown"

func _ready() -> void:
    _initialize_managers()
    _setup_common_ui()
    _on_scene_ready()

func _initialize_managers() -> void:
    # Standard manager initialization

func _setup_common_ui() -> void:
    # Connect common UI elements

func _on_scene_ready() -> void:
    # Override in subclasses

func show_loading(message: String = "") -> void:
    # Standard loading display

func show_error(message: String, details: String = "", code: int = 0, actions: Array[String] = []) -> void:
    # Standard error display using ErrorDialog component
    if error_dialog:
        if code >= 400:
            error_dialog.show_api_error(code, message, details)
        else:
            error_dialog.show_network_error(message)

func show_success(message: String) -> void:
    # Standard success display

# Error dialog reference (auto-wired if present in scene)
var error_dialog: ErrorDialog
```

**Benefits**:
- Eliminates 50+ lines of boilerplate per scene
- Standardizes error handling
- Provides consistent UI feedback

#### 1.2 State Machine Component
**File**: `features/state/state_machine.gd`

```gdscript
class_name StateMachine extends Node

signal state_changed(old_state: int, new_state: int)

@export var initial_state: int = 0
var current_state: int
var state_history: Array[int] = []

func transition_to(new_state: int) -> void:
    # Handle state transitions with validation
```

**Usage**: Replace hardcoded state management in camera.gd, dex.gd, etc.

### Phase 2: UI Component Extraction (Week 1-2)

#### 2.1 Image Display Component
**File**: `features/ui/components/image_display/image_display.gd`

**Responsibilities**:
- Display images with different modes (simple, bordered, gallery)
- Handle aspect ratio management
- Provide rotation functionality
- Manage image caching

**Extracted From**:
- camera.gd: lines 158-206 (rotation logic)
- camera.gd: lines 434-459 (size management)
- dex.gd: similar image display code

#### 2.2 Record Card Component
**File**: `features/ui/components/record_card/record_card.gd`

**Responsibilities**:
- Display dex entry as a card
- Show image with border
- Display animal name/label
- Handle favorite toggling
- Emit interaction signals

**Replaces**:
- RecordImage controls in camera.gd and dex.gd
- Bordered container logic
- Label management

#### 2.3 Progress Indicator Component
**File**: `features/ui/components/progress_indicator/progress_indicator.gd`

**Features**:
- Multiple styles (spinner, bar, percentage)
- Message display
- Cancel support
- Auto-hide on completion

#### 2.4 User Selector Component
**File**: `features/ui/components/user_selector/user_selector.gd`

**Features**:
- Display available users (self, friends)
- Handle user switching
- Show sync status per user
- Emit selection signals

#### 2.5 Error Dialog Component
**File**: `features/ui/components/error_dialog/error_dialog.gd`

**Responsibilities**:
- Display API errors with code and message
- Show generic networking errors with user-friendly message
- Provide easy dismissal (X button, click outside, ESC key)
- Work consistently on web export and desktop
- Reusable from any scene via signal or direct call

**Features**:
- **Error Types**:
  - `NETWORK_ERROR`: Generic networking issues ("Connection failed. Please try again...")
  - `API_ERROR`: Specific API failures (show HTTP code + server message)
  - `VALIDATION_ERROR`: Client-side validation failures
  - `TIMEOUT_ERROR`: Request timeout with retry prompt
- **Display Modes**:
  - Simple modal popup (default)
  - Banner/toast notification (dismissible after timeout)
  - Inline error display (for form validation)
- **Customization**:
  - Title, message, and optional details
  - Optional action buttons ("Retry", "Cancel", "Dismiss")
  - Configurable auto-dismiss timeout
  - Theme-aware styling (matches app aesthetic)

**API**:
```gdscript
class_name ErrorDialog extends Control

signal dismissed
signal action_pressed(action_name: String)

enum ErrorType {
    NETWORK_ERROR,
    API_ERROR,
    VALIDATION_ERROR,
    TIMEOUT_ERROR,
    GENERIC
}

func show_error(
    type: ErrorType,
    message: String,
    details: String = "",
    http_code: int = 0,
    actions: Array[String] = ["Dismiss"]
) -> void

func show_api_error(code: int, message: String, details: String = "") -> void
func show_network_error(details: String = "") -> void
func hide_dialog() -> void
```

**Usage Example**:
```gdscript
# In scene controller
@onready var error_dialog: ErrorDialog = $ErrorDialog

# Simple network error
error_dialog.show_network_error()

# API error with details
error_dialog.show_api_error(500, "CV analysis failed", "Invalid response format")

# Custom error with retry action
error_dialog.show_error(
    ErrorDialog.ErrorType.API_ERROR,
    "Image conversion failed",
    "Server returned status 400: Invalid image format",
    400,
    ["Retry", "Cancel"]
)
error_dialog.action_pressed.connect(_on_error_action)
```

**Web Export Compatibility**:
- No platform-specific dialogs (AcceptDialog, ConfirmationDialog issues on web)
- Pure Control-based implementation with overlay
- Proper focus management for keyboard dismissal
- Touch-friendly dismiss areas

### Phase 3: Feature Module Extraction (Week 2)

#### 3.1 Image Processing Feature
**File**: `features/image_processing/image_processor_workflow.gd`

**Responsibilities**:
- Image loading from various sources
- Format detection and conversion
- Rotation and transformation
- Thumbnail generation
- Cache management

**Extracted From**:
- camera.gd: lines 295-332 (preview attempts)
- camera.gd: lines 158-206 (rotation)

#### 3.2 CV Analysis Feature
**File**: `features/cv_analysis/cv_analysis_workflow.gd`

**Responsibilities**:
- Manage two-step upload process
- Handle conversion → download → analyze flow
- Poll for job status
- Process multiple animal detection
- Create dex entries
- **Error handling and retry logic**

**Extracted From**:
- camera.gd: lines 477-623 (conversion and analysis)
- camera.gd: lines 647-698 (status polling)
- camera.gd: lines 699-852 (result processing)

**Error Handling Strategy**:
```gdscript
class_name CVAnalysisWorkflow extends Node

signal analysis_started
signal analysis_progress(stage: String, message: String)
signal analysis_complete(job_data: Dictionary)
signal analysis_failed(error_type: String, message: String, code: int)
signal retry_available

enum AnalysisStage {
    IDLE,
    CONVERTING,
    DOWNLOADING,
    ANALYZING,
    POLLING,
    COMPLETE,
    FAILED
}

var current_stage: AnalysisStage = AnalysisStage.IDLE
var last_error: Dictionary = {}  # Store for retry
var retry_count: int = 0
var max_retries: int = 3

# Start new analysis
func start_analysis(image_path: String, transformations: Dictionary = {}) -> void

# Retry last failed operation
func retry_analysis() -> void:
    if last_error.is_empty():
        return
    retry_count += 1
    # Resume from last successful stage

# Cancel ongoing analysis
func cancel_analysis() -> void

# Internal error handler
func _handle_error(stage: AnalysisStage, code: int, message: String) -> void:
    current_stage = AnalysisStage.FAILED
    last_error = {
        "stage": stage,
        "code": code,
        "message": message,
        "timestamp": Time.get_unix_time_from_system()
    }

    # Determine error type
    var error_type = "NETWORK_ERROR"
    if code >= 400 and code < 600:
        error_type = "API_ERROR"
    elif code == 0:
        error_type = "NETWORK_ERROR"

    analysis_failed.emit(error_type, message, code)

    # Offer retry if under limit
    if retry_count < max_retries:
        retry_available.emit()
```

**Retry Behavior**:
1. **Conversion errors**: Retry entire upload + conversion
2. **Download errors**: Retry download only (conversion already succeeded)
3. **Analysis submission errors**: Retry submission with cached converted image
4. **Polling errors**: Resume polling with exponential backoff
5. **Result parsing errors**: Show error, no automatic retry (likely server issue)

**State Preservation**:
- Store conversion_id after successful conversion
- Cache downloaded PNG for retry without re-download
- Preserve transformations (rotation) across retries
- Clear state on successful completion or manual cancellation

#### 3.3 Dex Feature
**File**: `features/dex/dex_entry_manager.gd`

**Responsibilities**:
- Create dex entries
- Update existing entries
- Handle local/remote sync
- Manage entry metadata
- Cache images locally

**Extracted From**:
- camera.gd: lines 903-1015 (entry creation)
- dex.gd: entry management code

### Phase 4: Data Model Components (Week 2-3)

#### 4.1 Animal Model
**File**: `features/data/models/animal_model.gd`

```gdscript
class_name AnimalModel extends Resource

@export var id: String
@export var creation_index: int
@export var scientific_name: String
@export var common_name: String
@export var genus: String
@export var species: String
@export var subspecies: String

func get_display_name() -> String:
    # Format for display

func from_dict(data: Dictionary) -> void:
    # Parse from API response
```

#### 4.2 Dex Entry Model
**File**: `features/data/models/dex_entry_model.gd`

```gdscript
class_name DexEntryModel extends Resource

@export var id: String
@export var animal: AnimalModel
@export var owner_id: String
@export var image_path: String
@export var notes: String
@export var visibility: String
@export var is_favorite: bool
@export var created_at: String
@export var updated_at: String
```

#### 4.3 Analysis Job Model
**File**: `features/data/models/analysis_job_model.gd`

```gdscript
class_name AnalysisJobModel extends Resource

@export var id: String
@export var status: String
@export var conversion_id: String
@export var detected_animals: Array[AnimalModel]
@export var selected_animal_index: int
@export var confidence_score: float
@export var error_message: String
```

### Phase 5: Scene Refactoring (Week 3-4)

#### 5.1 Camera Scene Refactor

**New Structure**:
```
scenes/camera/
├── camera.gd (150 lines - controller only)
├── camera.tscn
└── components/
    ├── file_selector.gd
    ├── analysis_results.gd
    └── animal_selection_popup.gd
```

**camera.gd** (refactored):
```gdscript
class_name CameraController extends BaseSceneController

# Components
@onready var image_display: ImageDisplay = $ImageDisplay
@onready var file_selector: FileSelector = $FileSelector
@onready var error_dialog: ErrorDialog = $ErrorDialog
@onready var cv_workflow: CVAnalysisWorkflow
@onready var analyze_button: Button = $AnalyzeButton
@onready var retry_button: Button = $RetryButton

func _on_scene_ready() -> void:
    scene_name = "Camera"

    # Initialize workflow
    cv_workflow = CVAnalysisWorkflow.new()
    add_child(cv_workflow)

    # Connect signals
    file_selector.file_selected.connect(_on_file_selected)
    cv_workflow.analysis_complete.connect(_on_analysis_complete)
    cv_workflow.analysis_failed.connect(_on_analysis_failed)
    cv_workflow.retry_available.connect(_on_retry_available)
    image_display.rotation_changed.connect(_on_rotation_changed)
    error_dialog.action_pressed.connect(_on_error_action)

    # Initial button state
    retry_button.visible = false

func _on_analysis_failed(error_type: String, message: String, code: int) -> void:
    # Hide analyze button, show retry button
    analyze_button.visible = false
    retry_button.visible = true

    # Show appropriate error dialog
    if error_type == "API_ERROR":
        error_dialog.show_api_error(code, message, "The CV analysis failed")
    else:
        error_dialog.show_network_error("Connection failed. Please try again.")

func _on_retry_available() -> void:
    # Enable retry button
    retry_button.disabled = false

func _on_retry_pressed() -> void:
    # Hide retry button, show analyze button in loading state
    retry_button.visible = false
    analyze_button.visible = true
    analyze_button.disabled = true
    analyze_button.text = "Retrying..."

    # Retry the analysis
    cv_workflow.retry_analysis()

func _on_analysis_complete(job_data: Dictionary) -> void:
    # Reset UI state to normal
    analyze_button.visible = true
    retry_button.visible = false
    analyze_button.disabled = false
    analyze_button.text = "Analyze Image"

    # Continue with normal flow...

func _on_error_action(action_name: String) -> void:
    if action_name == "Retry":
        _on_retry_pressed()
    elif action_name == "Cancel":
        # Reset to initial state
        _reset_camera_state()

# Called when navigating away or returning to scene
func _notification(what: int) -> void:
    if what == NOTIFICATION_VISIBILITY_CHANGED:
        if not visible:
            # Scene hidden - preserve state
            pass
        else:
            # Scene shown - check if we need to reset from error state
            if cv_workflow.current_stage == CVAnalysisWorkflow.AnalysisStage.FAILED:
                # Allow user to see error state and retry
                pass
    elif what == NOTIFICATION_EXIT_TREE:
        # Clean navigation away - reset state
        _reset_camera_state()

func _reset_camera_state() -> void:
    cv_workflow.cancel_analysis()
    analyze_button.visible = true
    retry_button.visible = false
    analyze_button.disabled = false
    analyze_button.text = "Analyze Image"
    error_dialog.hide_dialog()
```

**Key Error Handling Features**:
1. **Button State Management**:
   - Normal: "Analyze Image" button visible
   - Failed: "Retry" button replaces analyze button
   - Success: Returns to normal state

2. **Error Display**:
   - Network errors: Generic message via `error_dialog.show_network_error()`
   - API errors: Detailed message with code via `error_dialog.show_api_error(code, message)`
   - Errors are dismissible but retry button remains visible

3. **State Recovery**:
   - Successful retry: Returns to normal flow, proceeds with result
   - Navigation away: Cleans up state on exit
   - Navigation back: Preserves error state, allows retry
   - Manual cancel: Returns to image selection state

4. **User Experience**:
   - Clear visual feedback (button swap)
   - Actionable error messages
   - Easy dismissal of error dialog
   - Persistent retry option until success or cancel

#### 5.2 Dex Scene Refactor

**New Structure**:
```
scenes/dex/
├── dex.gd (200 lines - controller only)
├── dex.tscn
└── components/
    ├── dex_gallery.gd
    ├── entry_navigator.gd
    └── sync_controls.gd
```

### Phase 7: Error Handling Integration (Week 2-3)

#### 7.1 Global Error Handling
**File**: `features/error_handling/error_handler.gd`

**Responsibilities**:
- Centralized error classification
- Error logging and telemetry
- Retry strategy management
- Error recovery patterns

**Features**:
```gdscript
class_name ErrorHandler extends Node

enum ErrorSeverity { INFO, WARNING, ERROR, CRITICAL }

# Classify errors by HTTP code and context
func classify_error(code: int, message: String, context: String) -> Dictionary

# Determine if error is retryable
func is_retryable(error: Dictionary) -> bool

# Calculate retry delay with exponential backoff
func get_retry_delay(attempt: int) -> float

# Log error for debugging
func log_error(error: Dictionary, severity: ErrorSeverity) -> void

# Get user-friendly error message
func get_user_message(error: Dictionary) -> String
```

#### 7.2 Service-Level Error Handling

**Updates to API Services**:
```gdscript
# In api_client.gd or service files
func _handle_response_error(code: int, response: Dictionary, context: String) -> void:
    var error = ErrorHandler.classify_error(code, response.get("message", ""), context)

    # Emit standardized error signal
    request_failed.emit(error)

    # Log for debugging
    ErrorHandler.log_error(error, ErrorHandler.ErrorSeverity.ERROR)
```

#### 7.3 Scene-Level Error Integration

**Pattern for All Scenes**:
1. Add ErrorDialog component to scene tree
2. Connect to service/workflow error signals
3. Handle errors with consistent UX:
   ```gdscript
   func _on_operation_failed(error: Dictionary) -> void:
       var user_message = ErrorHandler.get_user_message(error)

       if error.get("retryable", false):
           error_dialog.show_error(
               ErrorDialog.ErrorType.API_ERROR,
               user_message,
               error.get("details", ""),
               error.get("code", 0),
               ["Retry", "Cancel"]
           )
       else:
           error_dialog.show_error(
               ErrorDialog.ErrorType.API_ERROR,
               user_message,
               error.get("details", ""),
               error.get("code", 0),
               ["Dismiss"]
           )
   ```

#### 7.4 Specific Error Scenarios

**CV Analysis Errors**:
- **Conversion failure**: Retry upload + conversion
- **Download timeout**: Retry download only
- **Invalid CV response**: Show error, log details, no retry (backend issue)
- **Multiple retry failures**: Escalate to "Report Issue" option

**Dex Sync Errors**:
- **Network timeout**: Auto-retry with exponential backoff
- **Auth failure**: Redirect to login
- **Partial sync failure**: Show which users failed, offer individual retry

**Image Upload Errors**:
- **File too large**: Show size limit, offer resize option
- **Unsupported format**: Show supported formats, offer conversion
- **Upload interrupted**: Resume from last chunk (if chunked upload implemented)

## Success Metrics

### Code Quality Metrics

- **Line Count Reduction**: Target 60-70% reduction per scene file
- **Duplication**: Eliminate 80% of duplicated code
- **Cyclomatic Complexity**: Reduce by 50%
- **Component Reuse**: Each component used in 2+ places

### Development Metrics

- **Bug Fix Time**: 40% reduction
- **Feature Development**: 30% faster
- **Code Review Time**: 25% reduction
- **Test Coverage**: Increase to 70%

### Performance Metrics

- **Load Time**: Maintain or improve
- **Memory Usage**: 10-15% reduction
- **Frame Rate**: Maintain 60 FPS
- **Bundle Size**: Minimal increase (<5%)

## Long-term Benefits

1. **Maintainability**: Easier to understand and modify code
2. **Testability**: Components can be tested in isolation
3. **Reusability**: Components shared across scenes
4. **Scalability**: Easier to add new features
5. **Team Collaboration**: Clear boundaries enable parallel work
6. **Documentation**: Self-documenting component architecture
7. **Performance**: Optimized components, better caching
8. **Debugging**: Isolated components easier to debug

## Conclusion

This refactoring plan transforms the BiologiDex client from a monolithic structure to a modular, component-based architecture. By extracting reusable components, implementing clear separation of concerns, and establishing robust patterns, we create a more maintainable, scalable, and testable codebase.

The incremental approach ensures minimal disruption while delivering immediate value. Each phase builds upon the previous, creating a solid foundation for future development. The investment in refactoring will pay dividends through reduced development time, fewer bugs, and improved developer experience.

## Appendix: File Structure

### Current Structure
```
scenes/
├── camera/
│   └── camera.gd (1095 lines)
├── dex/
│   └── dex.gd (636 lines)
└── [other scenes...]
```

### Proposed Structure
```
features/
├── base/
│   ├── base_scene_controller.gd
│   └── base_component.gd
├── cv_analysis/
│   ├── cv_analysis_workflow.gd
│   ├── models/
│   └── components/
├── dex/
│   ├── dex_entry_manager.gd
│   ├── models/
│   └── components/
├── image_processing/
│   ├── image_processor_workflow.gd
│   └── image_cache.gd
├── data/
│   ├── models/
│   └── repositories/
├── state/
│   └── state_machine.gd
├── ui/
│   └── components/
│       ├── error_dialog/
│       │   ├── error_dialog.gd
│       │   └── error_dialog.tscn
│       ├── image_display/
│       ├── loading_spinner/ [exists]
│       ├── progress_indicator/
│       ├── record_card/
│       └── user_selector/
├── error_handling/
│   ├── error_handler.gd
│   └── retry_strategy.gd
└── server_interface/ [existing API services]
    └── api/

utilities/
├── file/
│   └── file_utility.gd
├── validation/
│   └── validation_utility.gd
├── formatting/
│   └── format_utility.gd
├── polling/
│   └── polling_utility.gd
└── platform/
    └── platform_utility.gd

scenes/
├── camera/
│   ├── camera.gd (150 lines)
│   └── components/
├── dex/
│   ├── dex.gd (200 lines)
│   └── components/
└── [other scenes refactored...]
```

This structure provides clear organization, promotes reusability, and makes the codebase more navigable for both current and future developers.