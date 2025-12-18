# Home + Lineage Tree Integration Plan

## Executive Summary

This document outlines the implementation plan for merging the lineage tree visualization into the home screen background, while maintaining code reusability and avoiding duplication. The user will be able to pan around the tree (with UI buttons moving in world-space), and a recenter button will appear when the view is off-center.

**Key Principles:**
- **Composition over Inheritance** - Create reusable components that can be instanced
- **No Code Duplication** - Extract shared logic into composable components
- **Web Export Compatibility** - Follow GitHub #101975 workarounds
- **Customizable Defaults** - Base components have sensible defaults, scenes can override

---

## Current Architecture Analysis

### Home Scene (`scenes/home/`)
- **Structure**: Node2D root with PaperCameraScene (unused for interaction) + HomeUILayer (CanvasLayer)
- **UI**: Centered VBoxContainer with navigation buttons in screen-space
- **Script**: Simple navigation handlers, no camera interaction
- **Pan/Zoom**: Disabled (background only)

### Tree Scene (`scenes/tree/`)
- **Structure**: Node2D root with PaperCameraScene (active pan/zoom) + UILayer (CanvasLayer)
- **Rendering**: TreeGraph + TreeRenderer created dynamically (web export workaround)
- **Script**: Complex - handles tree loading, friend sync, view management, zoom controls
- **UI**: Header with back button, search, mode dropdown, zoom controls, stats label

### PaperCameraScene (`features/camera_system/`)
- **Well-designed reusable component** with 30+ export variables
- **Signals**: `view_changed`, `tap_detected`, `gesture_started`, `gesture_ended`
- **Public API**: `center_on()`, `scroll_to()`, `set_zoom()`, `reset()`, `get_view_rect()`
- **Content container**: `content_container` for world-space children

---

## Architecture Decision: Composition Pattern

Based on [Godot best practices](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html) and the [Game Development Patterns with Godot 4](https://www.packtpub.com/en-mx/product/game-development-patterns-with-godot-4-9781835880289) book:

> "Composition is preferred. Embedding scenes as nodes (composition) maintains better encapsulation and reusability than complex inheritance trees."

**Why Composition:**
1. Avoids tight coupling between home and tree scenes
2. Each scene can customize behavior via export variables
3. Simpler mental model - components are self-contained
4. Matches existing PaperCameraScene pattern
5. Works naturally with Godot's node system and signals

---

## Component Design

### 1. TreeVisualization Component (NEW)
**Location**: `features/tree_visualization/`

Encapsulates all tree rendering logic into a reusable component.

```
TreeVisualization (Node2D, class_name TreeVisualization)
├── TreeGraph (created dynamically)
│   ├── EdgesLayer (z_index: -1)
│   ├── NodesLayer
│   ├── DexImagesLayer (z_index: 1)
│   └── LabelsLayer (z_index: 2)
└── TreeRenderer (script node)
```

**Responsibilities:**
- Create TreeGraph and layers dynamically
- Manage TreeRenderer lifecycle
- Handle tree data loading via APIManager
- Handle friend dex sync via FriendDexSyncService
- Expose signals for parent scene interaction

**Export Variables:**
```gdscript
## Tree Loading
@export var auto_load_on_ready: bool = true
@export var initial_mode: APITypes.TreeMode = APITypes.TreeMode.FRIENDS
@export var use_cache: bool = true

## Visual Settings (passthrough to TreeRenderer)
@export var dex_image_size: float = 1000.0
@export var branch_extension_enabled: bool = true
@export var min_zoom_for_labels: float = 0.3
```

**Signals:**
```gdscript
signal tree_loaded(tree_data: TreeDataModels.TreeData)
signal tree_load_failed(error: APITypes.APIError)
signal node_selected(node: TreeDataModels.TaxonomicNode)
signal node_hovered(node: TreeDataModels.TaxonomicNode)
signal loading_started()
signal loading_finished()
```

**Key Methods:**
```gdscript
func setup(paper_camera: PaperCameraScene) -> void
func load_tree(mode: APITypes.TreeMode = -1, use_cache: bool = true) -> void
func reload_tree() -> void
func set_mode(mode: APITypes.TreeMode) -> void
func get_root_position() -> Vector2
func clear() -> void
```

### 2. RecenterButton Component (NEW)
**Location**: `features/ui/components/recenter_button/`

Reusable button that appears when camera is off-center.

**Files:**
- `recenter_button.tscn` - Button scene with styling
- `recenter_button.gd` - Logic for visibility and interaction

**Export Variables:**
```gdscript
@export var center_threshold: float = 50.0  # World units - considered "centered" if within
@export var center_position: Vector2 = Vector2.ZERO  # Target center position
@export var fade_duration: float = 0.2  # Seconds for show/hide animation
@export var button_text: String = "Recenter"
@export var show_icon: bool = true  # Show ◎ icon
```

**Signals:**
```gdscript
signal recenter_requested()
```

**Key Methods:**
```gdscript
func connect_to_camera(camera: PaperCameraScene) -> void
func set_center_position(pos: Vector2) -> void
func update_visibility(camera_position: Vector2) -> void
func is_centered() -> bool
```

**Behavior:**
1. Connects to PaperCameraScene's `view_changed` signal
2. Compares camera position to `center_position`
3. Shows button (with fade) when distance > `center_threshold`
4. Hides button (with fade) when distance <= `center_threshold`
5. Emits `recenter_requested` when pressed

### 3. WorldSpaceUI Container (NEW)
**Location**: `features/ui/components/world_space_ui/`

Container for UI elements that should move with the world (pan with tree).

**Files:**
- `world_space_ui.gd` - Script with class_name

**Purpose:**
- Provides a clear organizational parent for world-space UI
- Can be added to PaperCameraScene's content_container
- Handles consistent sizing/positioning for child controls

```gdscript
extends Node2D
class_name WorldSpaceUI

## Position in world space where UI is centered
@export var anchor_position: Vector2 = Vector2.ZERO

func _ready() -> void:
    position = anchor_position
```

---

## Scene Modifications

### Home Scene (Modified)

**New Structure:**
```
Home (Node2D)
├── PaperCameraScene (instance, with tree configuration)
│   └── WorldContent/ContentContainer
│       ├── TreeVisualization (instance) - THE TREE BACKGROUND
│       └── HomeUI (WorldSpaceUI) - WORLD-SPACE UI
│           └── ... home buttons/labels ...
│
└── HomeOverlayLayer (CanvasLayer, layer=10) - SCREEN-SPACE OVERLAY
    └── Control (full rect)
        └── RecenterButton (top-right corner)
```

**Key Changes:**
1. Home buttons move from `HomeUILayer` to `WorldContent/ContentContainer/HomeUI`
2. Add `TreeVisualization` as sibling to HomeUI in world-space
3. Add `RecenterButton` in a new screen-space overlay layer
4. Configure PaperCameraScene with tree-appropriate settings
5. Remove "Lineage Tree" button (since tree is now the background)

**home.gd Changes:**
```gdscript
extends Node2D

# Components
var _paper_camera: PaperCameraScene = null
var _tree_visualization: TreeVisualization = null
var _recenter_button: RecenterButton = null

# World-space UI references (in WorldContent, pan with tree)
var _home_ui: WorldSpaceUI = null
var camera_button: Button = null
var dex_button: Button = null
var feed_button: Button = null
var social_button: Button = null
var menu_button: Button = null

func _ready() -> void:
    _initialize_services()
    if not token_manager.is_logged_in():
        navigation_manager.navigate_to("res://scenes/login/login.tscn", true)
        return

    _setup_components()
    _connect_signals()

func _setup_components() -> void:
    _paper_camera = $PaperCameraScene
    _tree_visualization = _create_tree_visualization()
    _home_ui = _create_home_ui()
    _setup_recenter_button()

func _create_tree_visualization() -> TreeVisualization:
    var tree_vis = preload("res://features/tree_visualization/tree_visualization.tscn").instantiate()
    _paper_camera.content_container.add_child(tree_vis)
    tree_vis.setup(_paper_camera)
    return tree_vis

func _create_home_ui() -> WorldSpaceUI:
    # Create world-space UI container
    var ui = WorldSpaceUI.new()
    ui.name = "HomeUI"
    ui.anchor_position = Vector2.ZERO  # Centered at origin
    _paper_camera.content_container.add_child(ui)

    # Create UI controls programmatically (or instance from scene)
    _build_home_buttons(ui)
    return ui

func _setup_recenter_button() -> void:
    _recenter_button = $HomeOverlayLayer/Control/RecenterButton
    _recenter_button.connect_to_camera(_paper_camera)
    _recenter_button.center_position = Vector2.ZERO
    _recenter_button.recenter_requested.connect(_on_recenter_requested)

func _on_recenter_requested() -> void:
    _paper_camera.scroll_to(Vector2.ZERO, true)  # Animated scroll to center
```

**PaperCameraScene Configuration (home.tscn):**
```
min_zoom = 0.5
max_zoom = 4.0
initial_zoom = 1.5
zoom_enabled = true
pan_enabled = true
inertia_enabled = true
```

### Tree Scene (Modified)

**Changes:**
1. Replace inline tree creation with `TreeVisualization` component
2. Keep existing UI (zoom controls, search, mode dropdown)
3. Keep tree-specific features (mode selection, search)

**tree_controller.gd Changes:**
```gdscript
extends BaseSceneNode

# Replace all inline tree logic with component
var _tree_visualization: TreeVisualization = null

func _on_scene_ready() -> void:
    _setup_ui_references()
    _setup_tree_visualization()
    _connect_signals()

func _setup_tree_visualization() -> void:
    _tree_visualization = TreeVisualization.new()
    _paper_camera.content_container.add_child(_tree_visualization)
    _tree_visualization.setup(_paper_camera)

    # Connect to tree visualization signals
    _tree_visualization.tree_loaded.connect(_on_tree_loaded)
    _tree_visualization.tree_load_failed.connect(_on_tree_load_failed)
    _tree_visualization.node_selected.connect(_on_node_selected)
    _tree_visualization.loading_started.connect(func(): _show_loading(true))
    _tree_visualization.loading_finished.connect(func(): _show_loading(false))

func _on_mode_selected(index: int) -> void:
    var new_mode = mode_dropdown.get_item_id(index) as APITypes.TreeMode
    _tree_visualization.set_mode(new_mode)
    _tree_visualization.load_tree()

# Most existing methods delegate to _tree_visualization
```

**Removed from tree_controller.gd:**
- `_setup_renderer()` - moved to TreeVisualization
- `tree_graph`, `_edges_layer`, `_nodes_layer`, `_labels_layer`, `_dex_images_layer` - internal to TreeVisualization
- `tree_renderer` - internal to TreeVisualization
- Direct API calls - delegated to TreeVisualization
- Friend sync handling - internal to TreeVisualization

---

## Implementation Phases

### Phase 1: Create Base Components

**1.1 TreeVisualization Component**
- Create `features/tree_visualization/tree_visualization.gd`
- Create `features/tree_visualization/tree_visualization.tscn`
- Extract tree creation logic from `tree_controller.gd`
- Extract API interaction and friend sync
- Add export variables for customization
- Add signals for parent scene integration

**1.2 RecenterButton Component**
- Create `features/ui/components/recenter_button/recenter_button.gd`
- Create `features/ui/components/recenter_button/recenter_button.tscn`
- Implement visibility logic based on camera position
- Add fade animation using Tween
- Style button to match app theme

**1.3 WorldSpaceUI Helper**
- Create `features/ui/components/world_space_ui/world_space_ui.gd`
- Simple Node2D-based container for world-space UI elements

### Phase 2: Refactor Tree Scene

**2.1 Update tree_controller.gd**
- Replace inline tree logic with TreeVisualization component
- Keep UI handling (zoom controls, search, mode dropdown)
- Update signal connections
- Verify all existing functionality works

**2.2 Test Tree Scene**
- Verify pan/zoom works correctly
- Verify tree loading and rendering
- Verify friend sync integration
- Verify node selection/hover
- Verify search functionality
- Test on web export

### Phase 3: Integrate Tree into Home

**3.1 Update home.tscn**
- Add TreeVisualization to content_container
- Move buttons from CanvasLayer to world-space
- Add HomeOverlayLayer with RecenterButton
- Configure PaperCameraScene settings
- Remove "Lineage Tree" navigation button

**3.2 Update home.gd**
- Initialize TreeVisualization component
- Create world-space UI programmatically (web export workaround)
- Connect RecenterButton
- Handle recenter navigation
- Maintain button press handlers

**3.3 Style World-Space UI**
- Ensure buttons are appropriately sized in world units
- Add background/border styling for visibility over tree
- Consider semi-transparent panel behind buttons

### Phase 4: Polish and Testing

**4.1 UX Refinements**
- Tune center threshold for RecenterButton
- Adjust initial zoom level for good default view
- Add subtle animation when recentering
- Consider adding recenter button keyboard shortcut

**4.2 Performance Testing**
- Profile home screen with tree background
- Ensure smooth pan/zoom on mobile
- Verify lazy image loading doesn't impact home UX

**4.3 Cross-Platform Testing**
- Test on web export (most critical)
- Test on desktop
- Test touch interactions on mobile

---

## File Structure (Final)

```
client/biologidex-client/
├── features/
│   ├── tree_visualization/          # NEW
│   │   ├── tree_visualization.gd
│   │   └── tree_visualization.tscn
│   │
│   ├── tree/                         # EXISTING (modified)
│   │   ├── tree_renderer.gd          # Unchanged
│   │   ├── tree_data_models.gd       # Unchanged
│   │   ├── tree_dex_image.gd         # Unchanged
│   │   └── tree_cache.gd             # Unchanged
│   │
│   ├── ui/components/
│   │   ├── recenter_button/          # NEW
│   │   │   ├── recenter_button.gd
│   │   │   └── recenter_button.tscn
│   │   │
│   │   └── world_space_ui/           # NEW
│   │       └── world_space_ui.gd
│   │
│   └── camera_system/                # EXISTING (unchanged)
│       ├── paper_camera_scene.gd
│       ├── paper_camera_scene.tscn
│       └── camera_touch_controller.gd
│
└── scenes/
    ├── home/                          # MODIFIED
    │   ├── home.gd
    │   └── home.tscn
    │
    └── tree/                          # MODIFIED
        ├── tree_controller.gd
        └── tree.tscn
```

---

## API & Signal Flow

### Home Screen Flow
```
User opens Home
    │
    ├──► TokenManager.is_logged_in() ──► Redirect to login if not
    │
    ├──► TreeVisualization.setup(_paper_camera)
    │        │
    │        └──► APIManager.tree.fetch_tree()
    │        └──► FriendDexSyncService.sync_friends()
    │        └──► TreeRenderer.render_tree()
    │
    ├──► RecenterButton.connect_to_camera(_paper_camera)
    │
    └──► User pans/zooms
             │
             ├──► PaperCameraScene.view_changed signal
             │        │
             │        ├──► TreeRenderer.update_view() (culling)
             │        └──► RecenterButton.update_visibility()
             │
             └──► User taps RecenterButton
                      │
                      └──► _paper_camera.scroll_to(Vector2.ZERO, true)
```

### Recenter Button Logic
```gdscript
func _on_view_changed(camera_pos: Vector2, _zoom: float) -> void:
    var distance = camera_pos.distance_to(center_position)
    var should_show = distance > center_threshold

    if should_show != visible:
        _animate_visibility(should_show)

func _animate_visibility(show: bool) -> void:
    var tween = create_tween()
    if show:
        visible = true
        modulate.a = 0.0
        tween.tween_property(self, "modulate:a", 1.0, fade_duration)
    else:
        tween.tween_property(self, "modulate:a", 0.0, fade_duration)
        tween.tween_callback(func(): visible = false)
```

---

## Web Export Considerations

### GitHub #101975 Workaround
The instanced scene children bug means:
- **TreeVisualization** must be created programmatically, not as a child in `.tscn`
- **Home world-space UI** must be created programmatically
- **RecenterButton** can be in `.tscn` since it's in a sibling CanvasLayer (not child of PaperCameraScene)

### Safe Pattern
```gdscript
# In _ready() or _on_scene_ready()
func _setup_components() -> void:
    # TreeVisualization - MUST be created in code
    _tree_visualization = TreeVisualization.new()
    _paper_camera.content_container.add_child(_tree_visualization)

    # World-space UI - MUST be created in code
    _home_ui = _create_home_ui()  # Creates buttons programmatically
    _paper_camera.content_container.add_child(_home_ui)

    # RecenterButton - CAN be in .tscn (sibling CanvasLayer is safe)
    _recenter_button = $HomeOverlayLayer/Control/RecenterButton
```

### Node Reference Pattern
Use explicit paths, not unique names:
```gdscript
# GOOD - explicit path
_recenter_button = $HomeOverlayLayer/Control/RecenterButton

# AVOID - unique name (may fail on web)
_recenter_button = get_node("%RecenterButton")
```

---

## Customization Points

### Home Scene Customizations
| Setting | Default | Home Value | Purpose |
|---------|---------|------------|---------|
| `initial_zoom` | 1.0 | 1.5 | Start zoomed in to see buttons clearly |
| `min_zoom` | 0.1 | 0.5 | Prevent zooming out too far from buttons |
| `max_zoom` | 10.0 | 4.0 | Limit zoom in |
| `auto_load_on_ready` | true | true | Load tree when home opens |
| `initial_mode` | FRIENDS | FRIENDS | Show friend tree by default |

### Tree Scene Customizations
| Setting | Default | Tree Value | Purpose |
|---------|---------|------------|---------|
| `initial_zoom` | 1.0 | 2.0 | Start more zoomed in for detail |
| `min_zoom` | 0.1 | 0.1 | Allow full zoom out |
| `max_zoom` | 10.0 | 10.0 | Allow deep zoom |
| `auto_load_on_ready` | true | true | Load tree when scene opens |

### RecenterButton Customizations
| Setting | Default | Home Value | Purpose |
|---------|---------|------------|---------|
| `center_threshold` | 50.0 | 100.0 | More tolerance before showing |
| `fade_duration` | 0.2 | 0.15 | Snappy appearance |
| `button_text` | "Recenter" | "Home" | Clearer meaning on home screen |

---

## Sources & References

- [Godot Scene Organization Best Practices](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html)
- [Composition in Godot 4 Tutorial](https://www.gotut.net/composition-in-godot-4/)
- [Game Development Patterns with Godot 4 - Chapter 4: Favoring Composition Over Inheritance](https://subscription.packtpub.com/book/game-development/9781835880289/5/ch05lvl1sec23/chapter-4-favoring-composition-over-inheritance)
- [Godot Design Philosophy](https://docs.godotengine.org/en/stable/getting_started/introduction/godot_design_philosophy.html)
- [Inherited Scenes Discussion](https://godotforums.org/d/35704-creating-inherited-scenes)
- [Mass-Producing NPCs with Editable Children and Scene Inheritance](https://uhiyama-lab.com/en/notes/godot/editable-children-vs-scene-inheritance/)

---

## Appendix A: World-Space UI Sizing

Since buttons will be in world-space and scale with zoom, we need to calculate appropriate sizes:

**Current button sizes (screen-space):**
- Navigation buttons: 80x44 pixels minimum
- Font size: 124pt

**World-space equivalent (at initial_zoom = 1.5):**
```
world_size = screen_size / initial_zoom
button_world_size = 80 / 1.5 = ~53 world units minimum
font_world_size = 124 / 1.5 = ~83 world units
```

**Recommendation:**
- Set button minimum size in world units: 100x60
- Use larger font in world-space: 120pt world-space
- Add semi-transparent background panel for contrast

---

## Appendix B: TreeVisualization Component Interface

```gdscript
## tree_visualization.gd
extends Node2D
class_name TreeVisualization

# Signals
signal tree_loaded(tree_data: TreeDataModels.TreeData)
signal tree_load_failed(error: APITypes.APIError)
signal node_selected(node: TreeDataModels.TaxonomicNode)
signal node_hovered(node: TreeDataModels.TaxonomicNode)
signal node_unhovered()
signal loading_started()
signal loading_finished()

# Export Variables
@export_group("Tree Loading")
@export var auto_load_on_ready: bool = true
@export var initial_mode: int = 1  # APITypes.TreeMode.FRIENDS
@export var use_cache: bool = true

@export_group("Visual Settings")
@export var dex_image_size: float = 1000.0
@export var branch_extension_enabled: bool = true
@export var min_zoom_for_labels: float = 0.3

# Public Methods
func setup(paper_camera: PaperCameraScene) -> void
func load_tree(mode: int = -1, use_cache_param: bool = true) -> void
func reload_tree() -> void
func set_mode(mode: int) -> void
func set_selected_friends(friend_ids: Array) -> void
func get_root_position() -> Vector2
func get_tree_data() -> TreeDataModels.TreeData
func get_stats() -> TreeDataModels.TreeStats
func clear() -> void

# Read-only Properties
var is_loading: bool:
    get: return _is_loading

var current_mode: int:
    get: return _current_mode

var tree_data: TreeDataModels.TreeData:
    get: return _tree_data
```

---

## Appendix C: RecenterButton Component Interface

```gdscript
## recenter_button.gd
extends Button
class_name RecenterButton

# Signals
signal recenter_requested()

# Export Variables
@export var center_threshold: float = 50.0
@export var center_position: Vector2 = Vector2.ZERO
@export var fade_duration: float = 0.2

# Public Methods
func connect_to_camera(camera: PaperCameraScene) -> void
func disconnect_from_camera() -> void
func set_center_position(pos: Vector2) -> void
func is_centered() -> bool

# Read-only Properties
var connected_camera: PaperCameraScene:
    get: return _camera
```
