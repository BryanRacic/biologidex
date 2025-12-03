# Tree Scene Overhaul: Radial Layout with Integrated Touch Controls

## Overview

This document outlines a comprehensive implementation plan to overhaul the taxonomic tree visualization with three major changes:

1. **Remove SubViewport** - Tree renders directly over InteractiveBackground
2. **Radial Reingold-Tilford Layout** - Nodes radiate from center instead of vertical hierarchy
3. **Integrated Pan/Zoom** - Tree movement synchronized with InteractiveBackground gestures

## Table of Contents

1. [Architecture Changes](#1-architecture-changes)
2. [Server-Side: Radial Layout Algorithm](#2-server-side-radial-layout-algorithm)
3. [Client-Side: Scene Restructuring](#3-client-side-scene-restructuring)
4. [Client-Side: Tree Controller Refactoring](#4-client-side-tree-controller-refactoring)
5. [Client-Side: Tree Renderer Updates](#5-client-side-tree-renderer-updates)
6. [Edge Rendering for Radial Layout](#6-edge-rendering-for-radial-layout)
7. [Coordinate System & Hit Detection](#7-coordinate-system--hit-detection)
8. [Migration & Backward Compatibility](#8-migration--backward-compatibility)
9. [Testing Plan](#9-testing-plan)
10. [File Change Summary](#10-file-change-summary)

---

## 1. Architecture Changes

### Current Architecture

```
tree.tscn
├── UI (CanvasLayer)
│   ├── InteractiveBackground (unused for tree pan/zoom)
│   └── Control
│       └── VBoxContainer
│           ├── Header (controls)
│           └── ViewportContainer (SubViewportContainer)
│               └── SubViewport (4107x2780)
│                   └── TreeWorld (Node2D)
│                       ├── Camera2D (pan/zoom controller)
│                       └── Graph (tree rendering)
```

**Problems:**
- SubViewport adds complexity and potential rendering overhead
- Separate Camera2D means pan/zoom logic duplicated from InteractiveBackground
- Tree doesn't benefit from shared gesture handling infrastructure
- Vertical layout doesn't visualize taxonomic hierarchy radiating from "life"

### Target Architecture

```
tree.tscn
├── TreeGraph (Node2D) - root, receives transform from touch controller
│   ├── EdgesLayer (Node2D, z_index: -1)
│   ├── NodesLayer (Node2D, z_index: 0)
│   └── LabelsLayer (Node2D, z_index: 2)
│
├── UI (CanvasLayer)
│   ├── InteractiveBackground - pan/zoom signals drive TreeGraph transform
│   └── Control
│       └── VBoxContainer
│           ├── Header (controls)
│           └── TreeContainer (Control) - tree viewport area
```

**Benefits:**
- Direct Node2D rendering (no SubViewport overhead)
- Tree transforms driven by InteractiveBackground signals (scroll_offset, scale)
- Single gesture system for entire app
- Radial layout naturally shows taxonomic hierarchy emanating from root
- Simpler scene structure

---

## 2. Server-Side: Radial Layout Algorithm

### 2.1 Algorithm Overview

The radial Reingold-Tilford algorithm works in two phases:

1. **Standard Layout**: Run Walker-Buchheim to get Cartesian (x, y) coordinates
2. **Polar Projection**: Transform coordinates where:
   - `x` (horizontal position) → `angle` (0° to 360°)
   - `y` (depth/level) → `radius` (distance from center)

### 2.2 Mathematical Transformation

```python
def cartesian_to_polar(x: float, y: float, angle_spread: float = 360.0,
                       radius_scale: float = 150.0) -> Tuple[float, float]:
    """
    Convert Cartesian tree coordinates to polar/radial coordinates.

    Args:
        x: Horizontal position (will become angle)
        y: Vertical depth (will become radius)
        angle_spread: Total angular spread in degrees (360 = full circle)
        radius_scale: Pixels per depth level

    Returns:
        (px, py): Cartesian coordinates for radial display
    """
    # Normalize x to angle range
    angle_deg = x  # x is already normalized from layout
    angle_rad = (angle_deg - 90) * (math.pi / 180)  # -90 to start at top

    # y becomes radius (depth 0 = center)
    radius = y * radius_scale / 150.0  # Scale to desired radius

    # Convert polar to Cartesian for final position
    px = radius * math.cos(angle_rad)
    py = radius * math.sin(angle_rad)

    return (px, py)
```

### 2.3 File: `server/graph/layout/reingold_tilford.py`

Add a new class `RadialReingoldTilfordLayout` that extends the existing implementation:

```python
class RadialReingoldTilfordLayout(ReingoldTilfordLayout):
    """
    Radial variant of Walker-Buchheim layout.
    Positions nodes in concentric circles radiating from center.
    """

    def __init__(self,
                 angle_spread: float = 360.0,
                 radius_per_level: float = 150.0,
                 min_radius: float = 100.0,
                 sibling_separation: float = 1.0):
        """
        Initialize radial layout engine.

        Args:
            angle_spread: Total angular spread (360 = full circle, 180 = semicircle)
            radius_per_level: Distance between depth levels
            min_radius: Minimum radius for first level (root at center)
            sibling_separation: Base separation between siblings (scaled by depth)
        """
        # Initialize parent with horizontal spacing that maps to angular space
        super().__init__(h_spacing=100.0, v_spacing=radius_per_level, min_distance=100.0)

        self.angle_spread = angle_spread
        self.radius_per_level = radius_per_level
        self.min_radius = min_radius
        self.sibling_separation = sibling_separation

    def calculate_layout(self, hierarchy: Dict) -> Dict[str, Tuple[float, float]]:
        """
        Calculate radial positions for all nodes.

        1. Run standard Walker-Buchheim to get (x, y) in tree space
        2. Transform to polar coordinates (angle, radius)
        3. Convert back to Cartesian for rendering
        """
        # Phase 1: Standard layout (x = horizontal, y = depth)
        root = self._build_tree_nodes(hierarchy)

        if not root:
            return {}

        self._first_walk(root)
        self._second_walk(root, -root.prelim)

        # Get bounds for normalization
        min_x, max_x = self._get_x_bounds(root)
        max_depth = self._get_max_depth(root)

        # Phase 2: Transform to radial coordinates
        positions = self._transform_to_radial(root, min_x, max_x, max_depth)

        logger.info(f"Radial layout calculated for {len(positions)} nodes")
        return positions

    def _get_x_bounds(self, root: TreeNode) -> Tuple[float, float]:
        """Get min/max x values for angular normalization."""
        min_x = float('inf')
        max_x = float('-inf')

        def traverse(node: TreeNode):
            nonlocal min_x, max_x
            min_x = min(min_x, node.x)
            max_x = max(max_x, node.x)
            for child in node.children:
                traverse(child)

        traverse(root)
        return (min_x, max_x)

    def _get_max_depth(self, root: TreeNode) -> int:
        """Get maximum depth of tree."""
        max_depth = 0

        def traverse(node: TreeNode, depth: int):
            nonlocal max_depth
            max_depth = max(max_depth, depth)
            for child in node.children:
                traverse(child, depth + 1)

        traverse(root, 0)
        return max_depth

    def _transform_to_radial(self, root: TreeNode, min_x: float, max_x: float,
                             max_depth: int) -> Dict[str, Tuple[float, float]]:
        """Transform tree coordinates to radial positions."""
        positions = {}
        x_range = max_x - min_x if max_x != min_x else 1.0

        def transform_node(node: TreeNode, depth: int):
            if depth == 0:
                # Root at center
                positions[node.id] = (0.0, 0.0)
            else:
                # Normalize x to angle (0 to angle_spread degrees)
                normalized_x = (node.x - min_x) / x_range
                angle_deg = normalized_x * self.angle_spread

                # Offset by -90 degrees so tree grows upward from center
                angle_rad = math.radians(angle_deg - 90)

                # Calculate radius based on depth
                radius = self.min_radius + (depth - 1) * self.radius_per_level

                # Apply separation scaling (nodes closer at higher depths get more space)
                separation_factor = 1.0 / math.sqrt(depth) if depth > 0 else 1.0

                # Convert to Cartesian
                px = radius * math.cos(angle_rad)
                py = radius * math.sin(angle_rad)

                positions[node.id] = (px, py)

            for child in node.children:
                transform_node(child, depth + 1)

        transform_node(root, 0)
        return positions

    def get_layout_metadata(self, positions: Dict[str, Tuple[float, float]]) -> Dict:
        """Return metadata about the radial layout for client rendering hints."""
        if not positions:
            return {}

        # Calculate bounds
        all_x = [p[0] for p in positions.values()]
        all_y = [p[1] for p in positions.values()]

        return {
            "layout_type": "radial",
            "angle_spread": self.angle_spread,
            "radius_per_level": self.radius_per_level,
            "min_radius": self.min_radius,
            "bounds": {
                "min_x": min(all_x),
                "max_x": max(all_x),
                "min_y": min(all_y),
                "max_y": max(all_y),
            },
            "center": (0, 0)  # Root always at center
        }
```

### 2.4 File: `server/graph/services_dynamic.py`

Update `DynamicTaxonomicTreeService` to support layout mode selection:

```python
from graph.layout.reingold_tilford import ReingoldTilfordLayout, RadialReingoldTilfordLayout

class DynamicTaxonomicTreeService:
    # Add layout_type parameter
    LAYOUT_VERTICAL = 'vertical'
    LAYOUT_RADIAL = 'radial'

    def __init__(self, user, mode: TreeMode = TreeMode.FRIENDS,
                 friend_ids: list = None, layout_type: str = LAYOUT_RADIAL):
        self.user = user
        self.mode = mode
        self.friend_ids = friend_ids or []
        self.layout_type = layout_type

        # Initialize appropriate layout engine
        if layout_type == self.LAYOUT_RADIAL:
            self.layout_engine = RadialReingoldTilfordLayout(
                angle_spread=360.0,
                radius_per_level=150.0,
                min_radius=100.0
            )
        else:
            self.layout_engine = ReingoldTilfordLayout(
                h_spacing=100.0,
                v_spacing=150.0
            )

    def get_tree_data(self, use_cache: bool = True) -> Dict:
        # ... existing implementation ...

        # Add layout metadata to response
        response['layout']['metadata'] = self.layout_engine.get_layout_metadata(positions)
        response['layout']['type'] = self.layout_type

        return response
```

### 2.5 File: `server/graph/views.py`

Add query parameter for layout type:

```python
class TaxonomicTreeView(APIView):
    def get(self, request):
        # ... existing params ...
        layout_type = request.query_params.get('layout', 'radial')

        service = DynamicTaxonomicTreeService(
            request.user,
            mode=mode,
            friend_ids=friend_ids,
            layout_type=layout_type
        )

        return Response(service.get_tree_data(use_cache))
```

---

## 3. Client-Side: Scene Restructuring

### 3.1 File: `client/biologidex-client/scenes/tree/tree.tscn`

Complete restructure of the scene:

```gdscript
[gd_scene load_steps=4 format=3 uid="uid://he08vkkhgca1"]

[ext_resource type="Script" uid="uid://bsgksie5hpp5l" path="res://scenes/tree/tree_controller.gd" id="1_tree_controller"]
[ext_resource type="PackedScene" path="res://features/ui/components/interactive_background/interactive_background.tscn" id="2_interactive_bg"]
[ext_resource type="Theme" uid="uid://dj81j7tgoh3qp" path="res://theme.tres" id="3_theme"]

[node name="Tree" type="Node2D"]
script = ExtResource("1_tree_controller")

# Tree rendering layer - below UI, transforms with gestures
[node name="TreeGraph" type="Node2D" parent="."]
unique_name_in_owner = true

[node name="EdgesLayer" type="Node2D" parent="TreeGraph"]
unique_name_in_owner = true
z_index = -1

[node name="NodesLayer" type="Node2D" parent="TreeGraph"]
unique_name_in_owner = true
z_index = 0

[node name="LabelsLayer" type="Node2D" parent="TreeGraph"]
unique_name_in_owner = true
z_index = 2

# UI layer - fixed position, overlays tree
[node name="UI" type="CanvasLayer" parent="."]

[node name="InteractiveBackground" parent="UI" instance=ExtResource("2_interactive_bg")]
unique_name_in_owner = true

[node name="Control" type="Control" parent="UI"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
theme = ExtResource("3_theme")

[node name="VBoxContainer" type="VBoxContainer" parent="UI/Control"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="Header" type="HBoxContainer" parent="UI/Control/VBoxContainer"]
custom_minimum_size = Vector2(0, 60)
layout_mode = 2

[node name="BackButton" type="Button" parent="UI/Control/VBoxContainer/Header"]
unique_name_in_owner = true
custom_minimum_size = Vector2(44, 44)
layout_mode = 2
text = "<<"

[node name="SearchBar" type="LineEdit" parent="UI/Control/VBoxContainer/Header"]
unique_name_in_owner = true
custom_minimum_size = Vector2(200, 44)
layout_mode = 2
size_flags_horizontal = 3
placeholder_text = "Search animals..."

[node name="ModeDropdown" type="OptionButton" parent="UI/Control/VBoxContainer/Header"]
unique_name_in_owner = true
custom_minimum_size = Vector2(120, 44)
layout_mode = 2

[node name="ZoomControls" type="HBoxContainer" parent="UI/Control/VBoxContainer/Header"]
layout_mode = 2
theme_override_constants/separation = 5

[node name="ZoomInButton" type="Button" parent="UI/Control/VBoxContainer/Header/ZoomControls"]
unique_name_in_owner = true
custom_minimum_size = Vector2(44, 44)
layout_mode = 2
text = "+"

[node name="ZoomOutButton" type="Button" parent="UI/Control/VBoxContainer/Header/ZoomControls"]
unique_name_in_owner = true
custom_minimum_size = Vector2(44, 44)
layout_mode = 2
text = "-"

[node name="ZoomResetButton" type="Button" parent="UI/Control/VBoxContainer/Header/ZoomControls"]
unique_name_in_owner = true
custom_minimum_size = Vector2(44, 44)
layout_mode = 2
text = "○"

[node name="CenterButton" type="Button" parent="UI/Control/VBoxContainer/Header/ZoomControls"]
unique_name_in_owner = true
custom_minimum_size = Vector2(44, 44)
layout_mode = 2
tooltip_text = "Center on root"
text = "◎"

[node name="LoadingLabel" type="Label" parent="UI/Control/VBoxContainer"]
unique_name_in_owner = true
visible = false
layout_mode = 2
text = "Loading tree..."
horizontal_alignment = 1

[node name="StatsLabel" type="Label" parent="UI/Control/VBoxContainer"]
unique_name_in_owner = true
layout_mode = 2
horizontal_alignment = 1

[node name="Spacer" type="Control" parent="UI/Control/VBoxContainer"]
layout_mode = 2
size_flags_vertical = 3
mouse_filter = 2
```

**Key Changes:**
- Removed `ViewportContainer`, `SubViewport`, `TreeWorld`, `Camera2D`
- Added `TreeGraph` as direct child of root (before UI layer)
- `InteractiveBackground` now drives tree transform
- Added `CenterButton` for centering on root node

---

## 4. Client-Side: Tree Controller Refactoring

### 4.1 File: `client/biologidex-client/scenes/tree/tree_controller.gd`

Major refactoring to use InteractiveBackground for gestures:

```gdscript
@tool
"""
TreeController - Orchestrates radial taxonomic tree visualization.
Refactored to use InteractiveBackground for pan/zoom gestures.
"""
extends BaseSceneNode

const APITypes = preload("res://features/server_interface/api/core/api_types.gd")
const TreeRenderer = preload("res://features/tree/tree_renderer.gd")
const BackgroundTouchController = preload("res://features/ui/components/interactive_background/background_touch_controller.gd")

# Editor preview
const EDITOR_PREVIEW_PATH: String = "res://resources/tree.json"
@export var editor_preview: bool = false:
    set(value):
        editor_preview = value
        if Engine.is_editor_hint() and value:
            _load_editor_preview()

# Node references
@onready var tree_graph: Node2D = %TreeGraph
@onready var interactive_bg: Control = %InteractiveBackground
@onready var search_bar: LineEdit = %SearchBar
@onready var mode_dropdown: OptionButton = %ModeDropdown
@onready var zoom_in_button: Button = %ZoomInButton
@onready var zoom_out_button: Button = %ZoomOutButton
@onready var zoom_reset_button: Button = %ZoomResetButton
@onready var center_button: Button = %CenterButton
@onready var loading_label: Label = %LoadingLabel
@onready var stats_label: Label = %StatsLabel

# Touch controller reference (from InteractiveBackground)
var touch_controller: BackgroundTouchController = null

# Tree data
var current_tree_data: TreeDataModels.TreeData = null
var current_mode: APITypes.TreeMode = APITypes.TreeMode.FRIENDS
var selected_friend_ids: Array = []

# Renderer
var tree_renderer: TreeRenderer = null

# State
var is_initialized: bool = false

# Transform state (synced with touch controller)
var _scroll_offset: Vector2 = Vector2.ZERO
var _current_scale: float = 1.0
var _viewport_center: Vector2 = Vector2.ZERO

# =============================================================================
# Initialization
# =============================================================================

func _on_scene_ready() -> void:
    """Called by BaseSceneNode after managers are initialized."""
    if Engine.is_editor_hint():
        return

    scene_name = "TreeController"
    print("[TreeController] Scene ready (radial layout)")

    # Get viewport center for transform calculations
    await get_tree().process_frame
    _viewport_center = get_viewport_rect().size / 2.0

    # Wire up back button
    back_button = %BackButton
    if back_button and not back_button.pressed.is_connected(_on_back_pressed):
        back_button.pressed.connect(_on_back_pressed)

    # Connect UI signals
    search_bar.text_submitted.connect(_on_search_submitted)
    mode_dropdown.item_selected.connect(_on_mode_selected)
    zoom_in_button.pressed.connect(_on_zoom_in)
    zoom_out_button.pressed.connect(_on_zoom_out)
    zoom_reset_button.pressed.connect(_on_zoom_reset)
    center_button.pressed.connect(_on_center_on_root)

    # Setup touch controller integration
    _setup_touch_controller()

    # Connect API signals
    APIManager.tree.tree_loaded.connect(_on_tree_loaded)
    APIManager.tree.tree_load_failed.connect(_on_tree_load_failed)
    APIManager.tree.search_results_received.connect(_on_search_results)
    APIManager.tree.search_failed.connect(_on_search_failed)

    # Handle friend context from navigation
    if NavigationManager.has_context():
        var context: Dictionary = NavigationManager.get_context()
        if context.has("user_id"):
            current_mode = APITypes.TreeMode.SELECTED
            selected_friend_ids = [context.get("user_id")]
            NavigationManager.clear_context()

    # Setup mode dropdown
    _setup_mode_dropdown()

    # Setup renderer
    _setup_renderer()

    # Initial load
    load_tree()


func _setup_touch_controller() -> void:
    """Connect to InteractiveBackground's touch controller."""
    if not interactive_bg:
        push_error("[TreeController] InteractiveBackground not found")
        return

    # Get the TouchController child
    touch_controller = interactive_bg.get_node_or_null("TouchController")
    if not touch_controller:
        push_error("[TreeController] TouchController not found in InteractiveBackground")
        return

    # Connect to scroll/scale signals
    touch_controller.scroll_changed.connect(_on_scroll_changed)
    touch_controller.scale_changed.connect(_on_scale_changed)

    # Initialize with current values
    _scroll_offset = touch_controller.scroll_offset
    _current_scale = touch_controller.current_scale

    print("[TreeController] Touch controller connected")


func _setup_renderer() -> void:
    """Setup TreeRenderer for visualization."""
    tree_renderer = TreeRenderer.new()
    tree_renderer.name = "TreeRenderer"
    tree_graph.add_child(tree_renderer)

    # Pass node containers to renderer
    tree_renderer.setup_containers(
        %EdgesLayer,
        %NodesLayer,
        %LabelsLayer
    )

    # Connect renderer signals
    tree_renderer.node_selected.connect(_on_node_selected)
    tree_renderer.node_hovered.connect(_on_node_hovered)
    tree_renderer.node_unhovered.connect(_on_node_unhovered)

    print("[TreeController] TreeRenderer initialized")


# =============================================================================
# Transform Handling
# =============================================================================

func _on_scroll_changed(offset: Vector2) -> void:
    """Handle scroll offset changes from touch controller."""
    _scroll_offset = offset
    _update_tree_transform()


func _on_scale_changed(new_scale: float) -> void:
    """Handle scale changes from touch controller."""
    _current_scale = new_scale
    _update_tree_transform()


func _update_tree_transform() -> void:
    """Apply current scroll/scale to tree graph."""
    if not tree_graph:
        return

    # Transform: translate to center, scale, then apply scroll offset
    # This keeps the tree centered and properly scaled
    var transform = Transform2D()

    # Scale around viewport center
    transform = transform.scaled(Vector2(_current_scale, _current_scale))

    # Apply scroll (inverted - scroll_offset is in screen space)
    transform.origin = _viewport_center - _scroll_offset * _current_scale

    tree_graph.transform = transform

    # Update renderer for culling/labels
    if tree_renderer:
        tree_renderer.update_view(_scroll_offset, _current_scale, _viewport_center)


func _process(_delta: float) -> void:
    """Update viewport center on resize."""
    if Engine.is_editor_hint():
        return

    var new_center = get_viewport_rect().size / 2.0
    if new_center != _viewport_center:
        _viewport_center = new_center
        _update_tree_transform()


# =============================================================================
# Zoom Controls
# =============================================================================

func _on_zoom_in() -> void:
    """Zoom in via button."""
    if touch_controller:
        var new_scale = clampf(_current_scale * 1.2, touch_controller.min_scale, touch_controller.max_scale)
        touch_controller.current_scale = new_scale
        touch_controller.scale_changed.emit(new_scale)


func _on_zoom_out() -> void:
    """Zoom out via button."""
    if touch_controller:
        var new_scale = clampf(_current_scale / 1.2, touch_controller.min_scale, touch_controller.max_scale)
        touch_controller.current_scale = new_scale
        touch_controller.scale_changed.emit(new_scale)


func _on_zoom_reset() -> void:
    """Reset zoom and position."""
    if touch_controller:
        touch_controller.reset()


func _on_center_on_root() -> void:
    """Center view on tree root (center of radial layout)."""
    if touch_controller:
        # Reset scroll to center (root is at 0,0 in radial layout)
        touch_controller.scroll_offset = Vector2.ZERO
        touch_controller.scroll_changed.emit(Vector2.ZERO)


# =============================================================================
# Tree Loading (largely unchanged)
# =============================================================================

func load_tree(use_cache: bool = true) -> void:
    """Load tree data from API."""
    if is_loading:
        return

    is_loading = true
    _show_loading(true)

    print("[TreeController] Loading tree (mode: %s, layout: radial)" % APITypes.get_tree_mode_string(current_mode))

    # Request radial layout from server
    APIManager.tree.fetch_tree(current_mode, selected_friend_ids, use_cache, "radial")


func _on_tree_loaded(tree_data: TreeDataModels.TreeData) -> void:
    """Handle successful tree load."""
    print("[TreeController] Tree loaded: %d nodes, %d edges" % [tree_data.nodes.size(), tree_data.edges.size()])

    current_tree_data = tree_data
    is_loading = false
    is_initialized = true

    _show_loading(false)
    _update_stats_display()
    _render_tree()

    # Center on root after loading
    _on_center_on_root()


func _render_tree() -> void:
    """Render the tree visualization."""
    if not current_tree_data or not tree_renderer:
        return

    tree_renderer.render_tree(current_tree_data)
    _update_tree_transform()


# ... (rest of the file: mode selection, search, stats display, etc. - largely unchanged)
# See section 10 for complete file listing
```

### 4.2 Key Changes Summary

| Aspect | Before | After |
|--------|--------|-------|
| Pan/Zoom Input | Manual `_input()` with Camera2D | Touch controller signals |
| Transform | Camera2D.position/.zoom | Node2D.transform matrix |
| Coordinate Space | SubViewport local | Scene global |
| Viewport | SubViewportContainer+SubViewport | Direct Node2D rendering |
| Gesture Handling | Duplicated from InteractiveBackground | Shared BackgroundTouchController |

---

## 5. Client-Side: Tree Renderer Updates

### 5.1 File: `client/biologidex-client/features/tree/tree_renderer.gd`

Update renderer to work with external transform and radial layout:

```gdscript
@tool
"""
TreeRenderer - Renders radial taxonomic tree.
Updated to work with external transform control (no internal camera).
"""
extends Node2D
class_name TreeRenderer

const TreeDataModels = preload("res://features/tree/tree_data_models.gd")

# Signals
signal node_selected(node: TreeDataModels.TaxonomicNode)
signal node_hovered(node: TreeDataModels.TaxonomicNode)
signal node_unhovered()

# Visual settings (unchanged)
const NODE_SIZE_BASE: float = 10.0
const NODE_SIZE_USER: float = 16.0
const NODE_SIZE_FRIEND: float = 14.0
# ... (other constants unchanged)

# Rendering containers (injected from controller)
var edges_container: Node2D = null
var nodes_container: Node2D = null  # NodesLayer
var labels_container: Node2D = null

# MultiMesh for batch rendering
var nodes_multimesh: MultiMeshInstance2D = null

# State
var tree_data: TreeDataModels.TreeData = null
var render_nodes: Array[NodeRenderData] = []
var visible_nodes: Array[NodeRenderData] = []
var selected_node: TreeDataModels.TaxonomicNode = null
var hovered_node: TreeDataModels.TaxonomicNode = null

# View state (updated by controller)
var _scroll_offset: Vector2 = Vector2.ZERO
var _current_scale: float = 1.0
var _viewport_center: Vector2 = Vector2.ZERO
var _viewport_size: Vector2 = Vector2(1280, 720)

# Spatial indexing
var nodes_by_position: Dictionary = {}

# =============================================================================
# Initialization
# =============================================================================

func _ready() -> void:
    print("[TreeRenderer] Initializing radial renderer")


func setup_containers(edges: Node2D, nodes: Node2D, labels: Node2D) -> void:
    """Setup rendering containers from controller."""
    edges_container = edges
    nodes_container = nodes
    labels_container = labels

    # Create MultiMesh in nodes container
    _setup_multimesh()

    print("[TreeRenderer] Containers configured")


func _setup_multimesh() -> void:
    """Setup MultiMeshInstance2D for batch rendering."""
    if not nodes_container:
        return

    nodes_multimesh = MultiMeshInstance2D.new()
    nodes_container.add_child(nodes_multimesh)

    var multimesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_2D
    multimesh.use_colors = true
    multimesh.use_custom_data = false
    multimesh.mesh = _create_circle_mesh(NODE_SIZE_BASE)

    nodes_multimesh.multimesh = multimesh
    nodes_multimesh.z_index = 1


# =============================================================================
# Public API
# =============================================================================

func render_tree(data: TreeDataModels.TreeData) -> void:
    """Render the complete tree data."""
    if not data:
        push_error("[TreeRenderer] No tree data provided")
        return

    tree_data = data
    render_nodes.clear()
    visible_nodes.clear()
    nodes_by_position.clear()

    # Build render data
    for node in data.nodes:
        var render_data = NodeRenderData.new(node)
        render_data.color = _get_node_color(node)
        render_data.scale = _get_node_scale(node)
        render_nodes.append(render_data)

        # Spatial index
        var grid_key = _get_grid_key(node.position)
        if not nodes_by_position.has(grid_key):
            nodes_by_position[grid_key] = []
        nodes_by_position[grid_key].append(render_data)

    print("[TreeRenderer] Built %d render nodes" % render_nodes.size())

    _update_visible_nodes()
    _update_multimesh()
    _render_radial_edges()
    _render_labels()


func update_view(scroll: Vector2, scale: float, center: Vector2) -> void:
    """Update view parameters (called when transform changes)."""
    _scroll_offset = scroll
    _current_scale = scale
    _viewport_center = center
    _viewport_size = get_viewport_rect().size

    if tree_data:
        _update_visible_nodes()
        _update_multimesh()
        _render_labels()


# =============================================================================
# Frustum Culling
# =============================================================================

func _update_visible_nodes() -> void:
    """Update visible nodes based on current view."""
    visible_nodes.clear()

    # Calculate view bounds in world space
    var view_rect = _get_view_rect()

    for render_data in render_nodes:
        if view_rect.has_point(render_data.position):
            render_data.is_visible = true
            visible_nodes.append(render_data)
        else:
            render_data.is_visible = false

        if visible_nodes.size() >= MAX_VISIBLE_NODES:
            break


func _get_view_rect() -> Rect2:
    """Get current view rectangle in world coordinates."""
    # View bounds considering scroll and scale
    var half_size = (_viewport_size / 2.0) / _current_scale + Vector2(CULL_MARGIN, CULL_MARGIN)
    var center = _scroll_offset / _current_scale

    return Rect2(center - half_size, half_size * 2)


# =============================================================================
# Radial Edge Rendering
# =============================================================================

func _render_radial_edges() -> void:
    """Render edges as curved lines for radial layout."""
    # Clear existing
    for child in edges_container.get_children():
        child.queue_free()

    if not tree_data:
        return

    var visible_ids = {}
    for rd in visible_nodes:
        visible_ids[rd.node.id] = true

    var rendered = 0
    var max_edges = 10000

    for edge in tree_data.edges:
        if visible_ids.has(edge.source) and visible_ids.has(edge.target):
            _draw_radial_edge(edge)
            rendered += 1
            if rendered >= max_edges:
                break


func _draw_radial_edge(edge: TreeDataModels.TreeEdge) -> void:
    """Draw a radial edge (curved for aesthetic)."""
    var source = tree_data.get_node_by_id(edge.source)
    var target = tree_data.get_node_by_id(edge.target)

    if not source or not target:
        return

    var line = Line2D.new()

    # For radial layout, use curved edges
    # Curve through a point that's at the average radius but midpoint angle
    var source_radius = source.position.length()
    var target_radius = target.position.length()

    if source_radius < 1.0:
        # Source is root (center) - straight line
        line.add_point(source.position)
        line.add_point(target.position)
    else:
        # Curved edge using quadratic bezier approximation
        var points = _calculate_curved_edge(source.position, target.position)
        for p in points:
            line.add_point(p)

    line.antialiased = true
    line.width = _get_edge_width(source, target)
    line.default_color = _get_edge_color(source, target)

    edges_container.add_child(line)


func _calculate_curved_edge(from: Vector2, to: Vector2, segments: int = 8) -> Array[Vector2]:
    """Calculate curved edge points for radial layout."""
    var points: Array[Vector2] = []

    var from_radius = from.length()
    var to_radius = to.length()

    # Control point: at parent's radius, midpoint angle
    var from_angle = from.angle()
    var to_angle = to.angle()

    # Handle angle wrapping
    var angle_diff = to_angle - from_angle
    if angle_diff > PI:
        angle_diff -= TAU
    elif angle_diff < -PI:
        angle_diff += TAU

    var mid_angle = from_angle + angle_diff * 0.5
    var control_radius = from_radius  # Control point at parent's radius
    var control = Vector2(cos(mid_angle), sin(mid_angle)) * control_radius

    # Quadratic bezier curve
    for i in range(segments + 1):
        var t = float(i) / float(segments)
        var p = _quadratic_bezier(from, control, to, t)
        points.append(p)

    return points


func _quadratic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
    """Calculate point on quadratic bezier curve."""
    var u = 1.0 - t
    return u * u * p0 + 2.0 * u * t * p1 + t * t * p2


func _get_edge_width(source: TreeDataModels.TaxonomicNode, target: TreeDataModels.TaxonomicNode) -> float:
    """Get edge width based on node types."""
    if source.is_taxonomic() and target.is_taxonomic():
        return 2.0
    elif source.is_taxonomic() and target.is_animal():
        return 1.5
    return 1.0


func _get_edge_color(source: TreeDataModels.TaxonomicNode, target: TreeDataModels.TaxonomicNode) -> Color:
    """Get edge color based on node types."""
    if source.is_taxonomic() and target.is_taxonomic():
        return Color(0.4, 0.4, 0.4, 0.5)
    return Color(0.4, 0.4, 0.4, 0.6)


# =============================================================================
# Click Detection (World Space)
# =============================================================================

func _input(event: InputEvent) -> void:
    """Handle input for node interaction."""
    if Engine.is_editor_hint():
        return

    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            _handle_click(event.position)
    elif event is InputEventMouseMotion:
        _handle_mouse_motion(event.position)
    elif event is InputEventScreenTouch and event.pressed:
        _handle_click(event.position)


func _handle_click(screen_pos: Vector2) -> void:
    """Handle click/tap for node selection."""
    var world_pos = _screen_to_world(screen_pos)
    var node = get_node_at_position(world_pos)

    if node:
        select_node(node)
    else:
        clear_selection()


func _screen_to_world(screen_pos: Vector2) -> Vector2:
    """Convert screen position to world coordinates."""
    # Account for current transform: position = (screen - center) / scale + scroll / scale
    return (screen_pos - _viewport_center) / _current_scale + _scroll_offset / _current_scale


func get_node_at_position(world_pos: Vector2, radius: float = 20.0) -> TreeDataModels.TaxonomicNode:
    """Get node at world position."""
    var grid_key = _get_grid_key(world_pos)

    # Search radius scales with zoom
    var search_radius = radius / _current_scale

    for dx in range(-1, 2):
        for dy in range(-1, 2):
            var check_key = Vector2i(grid_key.x + dx, grid_key.y + dy)
            if nodes_by_position.has(check_key):
                for render_data in nodes_by_position[check_key]:
                    if not render_data.is_visible:
                        continue

                    var dist = render_data.position.distance_to(world_pos)
                    var node_radius = NODE_SIZE_BASE * render_data.scale

                    if dist <= node_radius + search_radius:
                        return render_data.node

    return null


# ... (remaining methods: _get_node_color, _get_node_scale, select_node, etc. - largely unchanged)
```

---

## 6. Edge Rendering for Radial Layout

### 6.1 Edge Curve Types

For a radial layout, edges benefit from curved rendering to avoid visual clutter:

| Connection Type | Curve Style | Rationale |
|----------------|-------------|-----------|
| Root → Level 1 | Straight | Short distance, no occlusion |
| Same level | Arc (circular) | Follow concentric circle |
| Parent → Child | Quadratic bezier | Natural flow outward |
| Long-distance | Avoid crossing | Route around tree |

### 6.2 Bezier Control Point Strategy

```
          target (t)
           •
          /
         /   <- quadratic bezier
        ○ control (at parent radius, mid-angle)
         \
          \
           •
         source (s)
```

The control point placement ensures:
- Edges curve outward naturally
- No edges cross through the tree center
- Visual hierarchy is maintained

### 6.3 Performance Considerations

- Pre-calculate edge curves during `render_tree()`
- Cache Line2D points (don't recalculate on view update)
- Only re-render edges when tree data changes, not on pan/zoom

---

## 7. Coordinate System & Hit Detection

### 7.1 Coordinate Spaces

| Space | Origin | Usage |
|-------|--------|-------|
| Screen | Top-left | Input events, UI |
| World | Tree root (0,0) | Node positions, edges |
| Local | TreeGraph.position | After transform applied |

### 7.2 Transform Chain

```
Screen Position (e.g., click at 640, 360)
    │
    ▼ subtract viewport center
Centered Position (-0, 0 at center)
    │
    ▼ divide by scale
Scaled Position (accounts for zoom)
    │
    ▼ add scroll offset / scale
World Position (in tree coordinate space)
```

### 7.3 Conversion Functions

```gdscript
func _screen_to_world(screen_pos: Vector2) -> Vector2:
    return (screen_pos - _viewport_center) / _current_scale + _scroll_offset / _current_scale

func _world_to_screen(world_pos: Vector2) -> Vector2:
    return (world_pos - _scroll_offset / _current_scale) * _current_scale + _viewport_center
```

---

## 8. Migration & Backward Compatibility

### 8.1 API Compatibility

The server API adds a new `layout` query parameter but defaults to `radial`:

```
GET /api/v1/graph/tree/?layout=radial  (default)
GET /api/v1/graph/tree/?layout=vertical  (legacy)
```

Existing clients without the parameter will receive radial layout.

### 8.2 Client Data Model Updates

Update `tree_data_models.gd` to include layout metadata:

```gdscript
class TreeLayoutData extends Resource:
    var positions: Dictionary
    var world_bounds: Rect2
    var chunk_metadata: Dictionary
    var chunk_size: Vector2

    # New fields for radial layout
    var layout_type: String = "radial"
    var center: Vector2 = Vector2.ZERO
    var max_radius: float = 0.0
    var angle_spread: float = 360.0
```

### 8.3 Migration Steps

1. Deploy server changes first (backward compatible)
2. Update client to request radial layout
3. Remove SubViewport code after confirming stability
4. Optionally add layout toggle in UI for user preference

---

## 10. File Change Summary

### Server Files

| File | Change Type | Description |
|------|-------------|-------------|
| `server/graph/layout/reingold_tilford.py` | **Modify** | Add `RadialReingoldTilfordLayout` class |
| `server/graph/services_dynamic.py` | **Modify** | Add layout_type parameter, use radial by default |
| `server/graph/views.py` | **Modify** | Add `layout` query parameter |
| `server/graph/tests/test_radial_layout.py` | **Create** | Unit tests for radial algorithm |

### Client Files

| File | Change Type | Description |
|------|-------------|-------------|
| `client/.../scenes/tree/tree.tscn` | **Rewrite** | Remove SubViewport, restructure hierarchy |
| `client/.../scenes/tree/tree_controller.gd` | **Major Edit** | Use touch controller, remove Camera2D logic |
| `client/.../features/tree/tree_renderer.gd` | **Major Edit** | External transform, curved edges, new coordinate conversion |
| `client/.../features/tree/tree_data_models.gd` | **Minor Edit** | Add layout metadata fields |
| `client/.../features/server_interface/api/services/tree_service.gd` | **Minor Edit** | Add layout parameter to fetch_tree() |

### Estimated Lines Changed

| Component | Lines Added | Lines Removed | Net |
|-----------|-------------|---------------|-----|
| Server layout | ~200 | ~0 | +200 |
| Server services | ~30 | ~10 | +20 |
| Client scene | ~60 | ~40 | +20 |
| Client controller | ~100 | ~80 | +20 |
| Client renderer | ~150 | ~50 | +100 |
| Tests | ~200 | ~0 | +200 |
| **Total** | **~740** | **~180** | **+560** |

---

## Appendix A: Complete tree_controller.gd

```gdscript
@tool
"""
TreeController - Orchestrates radial taxonomic tree visualization.
Uses InteractiveBackground for pan/zoom gestures.
"""
extends BaseSceneNode

const APITypes = preload("res://features/server_interface/api/core/api_types.gd")
const TreeRenderer = preload("res://features/tree/tree_renderer.gd")
const BackgroundTouchController = preload("res://features/ui/components/interactive_background/background_touch_controller.gd")

# Editor preview
const EDITOR_PREVIEW_PATH: String = "res://resources/tree.json"
@export var editor_preview: bool = false:
    set(value):
        editor_preview = value
        if Engine.is_editor_hint() and value:
            _load_editor_preview()

# Node references
@onready var tree_graph: Node2D = %TreeGraph
@onready var interactive_bg: Control = %InteractiveBackground
@onready var search_bar: LineEdit = %SearchBar
@onready var mode_dropdown: OptionButton = %ModeDropdown
@onready var zoom_in_button: Button = %ZoomInButton
@onready var zoom_out_button: Button = %ZoomOutButton
@onready var zoom_reset_button: Button = %ZoomResetButton
@onready var center_button: Button = %CenterButton
@onready var loading_label: Label = %LoadingLabel
@onready var stats_label: Label = %StatsLabel

# Touch controller
var touch_controller: BackgroundTouchController = null

# Data
var current_tree_data: TreeDataModels.TreeData = null
var current_mode: APITypes.TreeMode = APITypes.TreeMode.FRIENDS
var selected_friend_ids: Array = []

# Renderer
var tree_renderer: TreeRenderer = null

# State
var is_initialized: bool = false
var _scroll_offset: Vector2 = Vector2.ZERO
var _current_scale: float = 1.0
var _viewport_center: Vector2 = Vector2.ZERO


func _load_editor_preview() -> void:
    if not Engine.is_editor_hint():
        return

    if not FileAccess.file_exists(EDITOR_PREVIEW_PATH):
        push_warning("[TreeController] Preview file not found")
        return

    var file = FileAccess.open(EDITOR_PREVIEW_PATH, FileAccess.READ)
    var json = JSON.new()
    if json.parse(file.get_as_text()) != OK:
        return

    current_tree_data = TreeDataModels.TreeData.new(json.data)

    if not tree_renderer and tree_graph:
        _setup_renderer_for_editor()

    _render_tree()


func _setup_renderer_for_editor() -> void:
    tree_renderer = TreeRenderer.new()
    tree_renderer.name = "EditorTreeRenderer"
    tree_graph.add_child(tree_renderer)
    tree_renderer.setup_containers(%EdgesLayer, %NodesLayer, %LabelsLayer)


func _on_scene_ready() -> void:
    if Engine.is_editor_hint():
        return

    scene_name = "TreeController"

    await get_tree().process_frame
    _viewport_center = get_viewport_rect().size / 2.0

    back_button = %BackButton
    if back_button:
        back_button.pressed.connect(_on_back_pressed)

    search_bar.text_submitted.connect(_on_search_submitted)
    mode_dropdown.item_selected.connect(_on_mode_selected)
    zoom_in_button.pressed.connect(_on_zoom_in)
    zoom_out_button.pressed.connect(_on_zoom_out)
    zoom_reset_button.pressed.connect(_on_zoom_reset)
    center_button.pressed.connect(_on_center_on_root)

    _setup_touch_controller()

    APIManager.tree.tree_loaded.connect(_on_tree_loaded)
    APIManager.tree.tree_load_failed.connect(_on_tree_load_failed)
    APIManager.tree.search_results_received.connect(_on_search_results)
    APIManager.tree.search_failed.connect(_on_search_failed)

    if NavigationManager.has_context():
        var ctx = NavigationManager.get_context()
        if ctx.has("user_id"):
            current_mode = APITypes.TreeMode.SELECTED
            selected_friend_ids = [ctx.get("user_id")]
            NavigationManager.clear_context()

    _setup_mode_dropdown()
    _setup_renderer()
    load_tree()


func _setup_touch_controller() -> void:
    if not interactive_bg:
        return

    touch_controller = interactive_bg.get_node_or_null("TouchController")
    if not touch_controller:
        return

    touch_controller.scroll_changed.connect(_on_scroll_changed)
    touch_controller.scale_changed.connect(_on_scale_changed)
    _scroll_offset = touch_controller.scroll_offset
    _current_scale = touch_controller.current_scale


func _setup_mode_dropdown() -> void:
    mode_dropdown.clear()
    mode_dropdown.add_item("Personal", APITypes.TreeMode.PERSONAL)
    mode_dropdown.add_item("Friends", APITypes.TreeMode.FRIENDS)
    mode_dropdown.add_item("Selected", APITypes.TreeMode.SELECTED)
    mode_dropdown.select(APITypes.TreeMode.FRIENDS)


func _setup_renderer() -> void:
    tree_renderer = TreeRenderer.new()
    tree_renderer.name = "TreeRenderer"
    tree_graph.add_child(tree_renderer)
    tree_renderer.setup_containers(%EdgesLayer, %NodesLayer, %LabelsLayer)
    tree_renderer.node_selected.connect(_on_node_selected)
    tree_renderer.node_hovered.connect(_on_node_hovered)
    tree_renderer.node_unhovered.connect(_on_node_unhovered)


func _on_scroll_changed(offset: Vector2) -> void:
    _scroll_offset = offset
    _update_tree_transform()


func _on_scale_changed(new_scale: float) -> void:
    _current_scale = new_scale
    _update_tree_transform()


func _update_tree_transform() -> void:
    if not tree_graph:
        return

    var transform = Transform2D()
    transform = transform.scaled(Vector2(_current_scale, _current_scale))
    transform.origin = _viewport_center - _scroll_offset * _current_scale
    tree_graph.transform = transform

    if tree_renderer:
        tree_renderer.update_view(_scroll_offset, _current_scale, _viewport_center)


func _process(_delta: float) -> void:
    if Engine.is_editor_hint():
        return

    var new_center = get_viewport_rect().size / 2.0
    if new_center != _viewport_center:
        _viewport_center = new_center
        _update_tree_transform()


func _on_zoom_in() -> void:
    if touch_controller:
        var s = clampf(_current_scale * 1.2, touch_controller.min_scale, touch_controller.max_scale)
        touch_controller.current_scale = s
        touch_controller.scale_changed.emit(s)


func _on_zoom_out() -> void:
    if touch_controller:
        var s = clampf(_current_scale / 1.2, touch_controller.min_scale, touch_controller.max_scale)
        touch_controller.current_scale = s
        touch_controller.scale_changed.emit(s)


func _on_zoom_reset() -> void:
    if touch_controller:
        touch_controller.reset()


func _on_center_on_root() -> void:
    if touch_controller:
        touch_controller.scroll_offset = Vector2.ZERO
        touch_controller.scroll_changed.emit(Vector2.ZERO)


func load_tree(use_cache: bool = true) -> void:
    if is_loading:
        return

    is_loading = true
    _show_loading(true)
    APIManager.tree.fetch_tree(current_mode, selected_friend_ids, use_cache, "radial")


func _on_tree_loaded(tree_data: TreeDataModels.TreeData) -> void:
    current_tree_data = tree_data
    is_loading = false
    is_initialized = true
    _show_loading(false)
    _update_stats_display()
    _render_tree()
    _on_center_on_root()


func _on_tree_load_failed(error: APITypes.APIError) -> void:
    is_loading = false
    _show_loading(false)
    stats_label.text = "Error: " + error.message
    stats_label.add_theme_color_override("font_color", Color.RED)


func reload_tree() -> void:
    load_tree(false)


func _render_tree() -> void:
    if not current_tree_data or not tree_renderer:
        return
    tree_renderer.render_tree(current_tree_data)
    _update_tree_transform()


func _on_mode_selected(index: int) -> void:
    var new_mode = mode_dropdown.get_item_id(index) as APITypes.TreeMode
    if new_mode == current_mode:
        return
    current_mode = new_mode
    load_tree()


func _on_search_submitted(query: String) -> void:
    if query.strip_edges().is_empty():
        return
    APIManager.tree.search_tree(query, current_mode, selected_friend_ids, 50)


func _on_search_results(results: Array) -> void:
    if results.is_empty():
        stats_label.text = "No results found"
        return

    # Navigate to first result
    var first = results[0] as Dictionary
    var pos_arr = first.get("position", [0, 0])
    if pos_arr is Array and pos_arr.size() >= 2:
        var pos = Vector2(pos_arr[0], pos_arr[1])
        if touch_controller:
            touch_controller.scroll_offset = pos * _current_scale
            touch_controller.scroll_changed.emit(touch_controller.scroll_offset)


func _on_search_failed(error: APITypes.APIError) -> void:
    stats_label.text = "Search error: " + error.message


func _on_node_selected(node: TreeDataModels.TaxonomicNode) -> void:
    if node.is_taxonomic():
        stats_label.text = "%s (%s)" % [node.name, _get_rank_name(node.rank)]
    else:
        var info = "%s (%s)" % [node.scientific_name, node.common_name]
        if node.captured_by_user:
            info += " - Captured"
        stats_label.text = info
    stats_label.remove_theme_color_override("font_color")


func _get_rank_name(rank: int) -> String:
    match rank:
        TreeDataModels.TaxonomicRank.ROOT: return "Root"
        TreeDataModels.TaxonomicRank.KINGDOM: return "Kingdom"
        TreeDataModels.TaxonomicRank.PHYLUM: return "Phylum"
        TreeDataModels.TaxonomicRank.CLASS: return "Class"
        TreeDataModels.TaxonomicRank.ORDER: return "Order"
        TreeDataModels.TaxonomicRank.FAMILY: return "Family"
        TreeDataModels.TaxonomicRank.SUBFAMILY: return "Subfamily"
        TreeDataModels.TaxonomicRank.GENUS: return "Genus"
        TreeDataModels.TaxonomicRank.SPECIES: return "Species"
        _: return "Unknown"


func _on_node_hovered(_node: TreeDataModels.TaxonomicNode) -> void:
    pass


func _on_node_unhovered() -> void:
    pass


func _show_loading(show: bool) -> void:
    if loading_label:
        loading_label.visible = show


func _update_stats_display() -> void:
    if not current_tree_data or not stats_label:
        return

    var stats = current_tree_data.stats
    var metadata = current_tree_data.metadata

    stats_label.text = "Mode: %s | Animals: %d | Nodes: %d" % [
        metadata.mode.capitalize(),
        stats.total_animals,
        stats.total_nodes
    ]
    stats_label.remove_theme_color_override("font_color")


func _exit_tree() -> void:
    if Engine.is_editor_hint():
        if tree_renderer:
            tree_renderer.clear()
            tree_renderer.queue_free()
        return

    if tree_renderer:
        tree_renderer.clear()
        tree_renderer.queue_free()

    if APIManager.tree.tree_loaded.is_connected(_on_tree_loaded):
        APIManager.tree.tree_loaded.disconnect(_on_tree_loaded)
    if APIManager.tree.tree_load_failed.is_connected(_on_tree_load_failed):
        APIManager.tree.tree_load_failed.disconnect(_on_tree_load_failed)
```

---

## Appendix B: References

- [Reingold-Tilford Algorithm Explained](https://towardsdatascience.com/reingold-tilford-algorithm-explained-with-walkthrough-be5810e8ed93/)
- [D3.js Radial Tree Layout](https://d3js.org/d3-hierarchy/tree)
- [Most Basic Radial Dendrogram (D3)](https://d3-graph-gallery.com/graph/dendrogram_radial_basic.html)
- [Radial Links in D3](https://d3js.org/d3-shape/radial-link)
- [Buchheim et al. 2002 - Improving Walker's Algorithm](https://dl.acm.org/doi/10.1007/3-540-36151-0_32)
- [Tim Gentry's Radial RT Gist](https://gist.github.com/timgentry/5aeb33a7df2bfbc161056f09a9f401d5)

---

## Revision History

| Date | Version | Changes |
|------|---------|---------|
| 2025-12-02 | 1.0 | Initial comprehensive plan |
