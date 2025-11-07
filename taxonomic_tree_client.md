# Taxonomic Tree View - Client Implementation plan

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Scene Structure](#scene-structure)
3. [Data Management](#data-management)
4. [Tree Layout Algorithm](#tree-layout-algorithm)
5. [Rendering System](#rendering-system)
6. [Interaction System](#interaction-system)
7. [Optimization Strategies](#optimization-strategies)
8. [API Integration](#api-integration)
9. [Implementation Phases](#implementation-phases)
10. [Testing Strategy](#testing-strategy)

---

## 1. Architecture Overview

### Core Design Principles
- **SubViewport-based 2D canvas** for optimal performance
- **MultiMeshInstance2D batching** for rendering hundreds of thousands of nodes
- **Chunked data loading** with spatial indexing for scalability
- **Level-of-Detail (LOD)** system for dynamic detail adjustment
- **Precomputed layouts** from server-side for performance
- **Singleton pattern** for data management and caching

### Performance Targets
- Render 100,000+ nodes at 60 FPS on modern hardware
- Support smooth interaction on mobile devices
- Memory usage under 500MB for complete dataset
- Initial load time under 2 seconds
- Chunk loading time under 100ms

---

## 2. Scene Structure

### Scene Hierarchy
```
tree.tscn (Control)
├── TreeController (Node) [tree_controller.gd]
│   ├── DataManager (Node) [tree_data_manager.gd]
│   ├── LayoutEngine (Node) [reingold_tilford.gd]
│   └── ChunkManager (Node) [chunk_manager.gd]
├── VBoxContainer
│   ├── Toolbar (HBoxContainer)
│   │   ├── SearchBar (LineEdit)
│   │   ├── ZoomControls (HBoxContainer)
│   │   │   ├── ZoomInButton (Button)
│   │   │   ├── ZoomOutButton (Button)
│   │   │   └── ZoomResetButton (Button)
│   │   └── FilterDropdown (OptionButton)
│   └── ViewportContainer [custom_minimum_size: 1280x720]
│       └── SubViewport [size: 1280x720]
│           └── World2D (Node2D) [tree_world.gd]
│               ├── Camera2D [tree_camera.gd]
│               ├── Graph (Node2D) [tree_graph.gd]
│               │   ├── EdgeLayer (Node2D)
│               │   │   └── Edges (MultiMeshInstance2D)
│               │   ├── NodeLayer (Node2D)
│               │   │   └── Nodes (MultiMeshInstance2D)
│               │   └── LabelLayer (CanvasLayer)
│               │       └── LabelPool (Node2D) [label_pool.gd]
│               └── InputHandler (Node) [tree_input_handler.gd]
```

### Component Responsibilities

#### TreeController
- Main orchestrator for all tree operations
- Manages initialization and data flow
- Coordinates between components
- Handles API communication

#### DataManager
- Manages taxonomic data structure
- Handles caching and persistence
- Provides data queries and filtering
- Manages incremental loading

#### LayoutEngine
- Implements Reingold-Tilford algorithm
- Calculates node positions
- Handles layout updates
- Manages layout caching

#### ChunkManager
- Spatial indexing of nodes
- Chunk loading/unloading
- Visibility culling
- LOD management

#### World2D
- Manages transform for pan/zoom
- Coordinates rendering layers
- Handles viewport updates

#### Graph
- Manages MultiMeshInstance2D instances
- Updates visible geometry
- Handles material assignments
- Manages draw order

---

## 3. Data Management

### Data Models

```gdscript
# tree_data_models.gd

class_name TaxonomicNode extends Resource
    @export var id: String = ""
    @export var scientific_name: String = ""
    @export var common_name: String = ""
    @export var rank: String = ""  # kingdom, phylum, class, order, family, genus, species
    @export var parent_id: String = ""
    @export var children_ids: Array[String] = []
    @export var creation_index: int = -1
    @export var discovered: bool = false
    @export var position: Vector2 = Vector2.ZERO
    @export var depth: int = 0
    @export var subtree_size: int = 1

class_name TreeChunk extends Resource
    @export var chunk_id: Vector2i = Vector2i.ZERO  # Grid coordinates
    @export var world_bounds: Rect2 = Rect2()
    @export var node_ids: Array[String] = []
    @export var edge_pairs: Array[Vector2i] = []  # Indices into node_ids
    @export var lod_level: int = 0
    @export var is_loaded: bool = false

class_name TreeLayoutData extends Resource
    @export var total_nodes: int = 0
    @export var max_depth: int = 0
    @export var world_bounds: Rect2 = Rect2()
    @export var chunk_size: Vector2 = Vector2(2048, 2048)
    @export var chunks: Dictionary = {}  # Vector2i -> TreeChunk
    @export var root_id: String = ""
```

### Storage Strategy

#### Local Caching
```gdscript
# tree_cache.gd - Singleton autoload
extends Node

const CACHE_DIR = "user://tree_cache/"
const LAYOUT_CACHE = "layout_data.tres"
const CHUNK_CACHE_DIR = "chunks/"
const MAX_CACHED_CHUNKS = 50

var layout_data: TreeLayoutData
var loaded_chunks: Dictionary = {}  # chunk_id -> TreeChunk
var chunk_lru: Array[Vector2i] = []

func save_layout_data(data: TreeLayoutData) -> void:
    ResourceSaver.save(data, CACHE_DIR + LAYOUT_CACHE)

func load_chunk(chunk_id: Vector2i) -> TreeChunk:
    # Check memory cache first
    if chunk_id in loaded_chunks:
        _update_lru(chunk_id)
        return loaded_chunks[chunk_id]

    # Load from disk
    var path = CACHE_DIR + CHUNK_CACHE_DIR + str(chunk_id.x) + "_" + str(chunk_id.y) + ".tres"
    if FileAccess.file_exists(path):
        var chunk = load(path) as TreeChunk
        _add_to_cache(chunk_id, chunk)
        return chunk

    return null

func _add_to_cache(chunk_id: Vector2i, chunk: TreeChunk) -> void:
    if loaded_chunks.size() >= MAX_CACHED_CHUNKS:
        var oldest = chunk_lru.pop_front()
        loaded_chunks.erase(oldest)
    loaded_chunks[chunk_id] = chunk
    chunk_lru.append(chunk_id)
```

---

## 4. Tree Layout Algorithm

### Reingold-Tilford Implementation

```gdscript
# reingold_tilford.gd
class_name ReingoldTilford extends Node

class RTNode:
    var node: TaxonomicNode
    var x: float = 0.0
    var y: float = 0.0
    var mod: float = 0.0
    var thread: RTNode = null
    var ancestor: RTNode = null
    var change: float = 0.0
    var shift: float = 0.0
    var number: int = 0
    var children: Array[RTNode] = []
    var parent: RTNode = null

const NODE_WIDTH = 120.0
const NODE_HEIGHT = 60.0
const LEVEL_HEIGHT = 100.0
const SIBLING_SPACING = 20.0
const SUBTREE_SPACING = 40.0

func layout_tree(root: TaxonomicNode, nodes: Dictionary) -> Dictionary:
    # Build RT tree structure
    var rt_root = _build_rt_tree(root, nodes)

    # First pass - assign initial positions
    _first_walk(rt_root)

    # Second pass - compute absolute positions
    _second_walk(rt_root, -rt_root.x, 0)

    # Convert to world positions
    return _extract_positions(rt_root)

func _first_walk(node: RTNode, distance: float = 1.0) -> void:
    if node.children.is_empty():
        # Leaf node
        if node.number > 0:  # Has left sibling
            node.x = node.parent.children[node.number - 1].x + distance
        else:
            node.x = 0.0
    else:
        # Internal node
        var default_ancestor = node.children[0]
        for child in node.children:
            _first_walk(child, distance)
            default_ancestor = _apportion(child, default_ancestor, distance)

        _execute_shifts(node)

        var midpoint = (node.children[0].x + node.children[-1].x) / 2.0

        if node.number > 0:  # Has left sibling
            var left_sibling = node.parent.children[node.number - 1]
            node.x = left_sibling.x + distance
            node.mod = node.x - midpoint
        else:
            node.x = midpoint

func _second_walk(node: RTNode, m: float, depth: int) -> void:
    node.x += m
    node.y = depth * LEVEL_HEIGHT

    for child in node.children:
        _second_walk(child, m + node.mod, depth + 1)

func _apportion(node: RTNode, default_ancestor: RTNode, distance: float) -> RTNode:
    if node.number > 0:  # Has left sibling
        var left_sibling = node.parent.children[node.number - 1]
        var vip = node
        var vop = node
        var vim = left_sibling
        var vom = vip.parent.children[0]

        var sip = vip.mod
        var sop = vop.mod
        var sim = vim.mod
        var som = vom.mod

        while _next_right(vim) != null and _next_left(vip) != null:
            vim = _next_right(vim)
            vip = _next_left(vip)
            vom = _next_left(vom)
            vop = _next_right(vop)

            vop.ancestor = node
            var shift = (vim.x + sim) - (vip.x + sip) + distance

            if shift > 0:
                _move_subtree(_get_ancestor(vim, node, default_ancestor), node, shift)
                sip += shift
                sop += shift

            sim += vim.mod
            sip += vip.mod
            som += vom.mod
            sop += vop.mod

        if _next_right(vim) != null and _next_right(vop) == null:
            vop.thread = _next_right(vim)
            vop.mod += sim - sop

        if _next_left(vip) != null and _next_left(vom) == null:
            vom.thread = _next_left(vip)
            vom.mod += sip - som
            default_ancestor = node

    return default_ancestor
```

### Layout Optimization

```gdscript
# layout_optimizer.gd
class_name LayoutOptimizer extends Node

func optimize_for_display(positions: Dictionary, viewport_size: Vector2) -> void:
    # Apply scaling to fit viewport
    var bounds = _calculate_bounds(positions)
    var scale_factor = min(
        viewport_size.x / bounds.size.x,
        viewport_size.y / bounds.size.y
    ) * 0.9  # 90% of viewport

    # Center and scale
    var center = bounds.get_center()
    for node_id in positions:
        var pos = positions[node_id] as Vector2
        pos = (pos - center) * scale_factor
        positions[node_id] = pos

func apply_fisheye_distortion(positions: Dictionary, focus: Vector2, strength: float) -> void:
    # Optional: Apply fisheye effect for better focus area visibility
    for node_id in positions:
        var pos = positions[node_id] as Vector2
        var dist = pos.distance_to(focus)
        if dist > 0:
            var factor = 1.0 + strength * exp(-dist / 500.0)
            var direction = (pos - focus).normalized()
            positions[node_id] = focus + direction * dist * factor
```

---

## 5. Rendering System

### MultiMeshInstance2D Setup

```gdscript
# tree_renderer.gd
class_name TreeRenderer extends Node2D

@onready var node_multimesh: MultiMeshInstance2D = $NodeLayer/Nodes
@onready var edge_multimesh: MultiMeshInstance2D = $EdgeLayer/Edges

var node_mesh: QuadMesh
var edge_mesh: QuadMesh
var node_material: ShaderMaterial
var edge_material: ShaderMaterial

func _ready() -> void:
    _setup_node_rendering()
    _setup_edge_rendering()

func _setup_node_rendering() -> void:
    # Create quad mesh for nodes
    node_mesh = QuadMesh.new()
    node_mesh.size = Vector2(32, 32)  # Base size, scaled per instance

    # Create shader material for nodes
    node_material = ShaderMaterial.new()
    node_material.shader = preload("res://shaders/tree_node.gdshader")

    # Setup MultiMesh
    var multimesh = MultiMesh.new()
    multimesh.mesh = node_mesh
    multimesh.transform_format = MultiMesh.TRANSFORM_2D
    multimesh.use_colors = true
    multimesh.use_custom_data = true
    multimesh.instance_count = 0  # Will be set dynamically

    node_multimesh.multimesh = multimesh
    node_multimesh.material = node_material

func _setup_edge_rendering() -> void:
    # Create quad mesh for edges (will be stretched)
    edge_mesh = QuadMesh.new()
    edge_mesh.size = Vector2(2, 1)  # Width and base height

    # Create shader material for edges
    edge_material = ShaderMaterial.new()
    edge_material.shader = preload("res://shaders/tree_edge.gdshader")

    # Setup MultiMesh
    var multimesh = MultiMesh.new()
    multimesh.mesh = edge_mesh
    multimesh.transform_format = MultiMesh.TRANSFORM_2D
    multimesh.use_colors = true
    multimesh.instance_count = 0

    edge_multimesh.multimesh = multimesh
    edge_multimesh.material = edge_material

func update_visible_nodes(nodes: Array[TaxonomicNode], camera_rect: Rect2) -> void:
    var visible_nodes = []
    for node in nodes:
        if camera_rect.has_point(node.position):
            visible_nodes.append(node)

    # Update MultiMesh
    var multimesh = node_multimesh.multimesh
    multimesh.instance_count = visible_nodes.size()

    for i in range(visible_nodes.size()):
        var node = visible_nodes[i]
        var transform = Transform2D()
        transform.origin = node.position

        # Scale based on importance/zoom level
        var scale = _calculate_node_scale(node)
        transform = transform.scaled(Vector2(scale, scale))

        multimesh.set_instance_transform_2d(i, transform)
        multimesh.set_instance_color(i, _get_node_color(node))
        multimesh.set_instance_custom_data(i, Color(node.depth / 10.0, 0, 0, 1))

func update_visible_edges(edges: Array, camera_rect: Rect2) -> void:
    var visible_edges = []
    for edge in edges:
        var from_pos = edge[0] as Vector2
        var to_pos = edge[1] as Vector2

        # Simple line-rect intersection test
        if _line_intersects_rect(from_pos, to_pos, camera_rect):
            visible_edges.append(edge)

    var multimesh = edge_multimesh.multimesh
    multimesh.instance_count = visible_edges.size()

    for i in range(visible_edges.size()):
        var from_pos = visible_edges[i][0] as Vector2
        var to_pos = visible_edges[i][1] as Vector2

        # Create transform for line
        var transform = _create_line_transform(from_pos, to_pos)
        multimesh.set_instance_transform_2d(i, transform)
        multimesh.set_instance_color(i, Color(0.5, 0.5, 0.5, 0.8))

func _create_line_transform(from: Vector2, to: Vector2) -> Transform2D:
    var length = from.distance_to(to)
    var angle = from.angle_to_point(to)

    var transform = Transform2D()
    transform = transform.rotated(angle)
    transform = transform.scaled(Vector2(length / 2.0, 1.0))
    transform.origin = (from + to) / 2.0

    return transform
```

### Shader Implementation

```glsl
// tree_node.gdshader
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform vec4 discovered_color : source_color = vec4(0.2, 1.0, 0.2, 1.0);
uniform vec4 highlight_color : source_color = vec4(1.0, 1.0, 0.2, 1.0);
uniform float outline_width : hint_range(0.0, 0.1) = 0.05;

varying vec4 custom_data;

void vertex() {
    custom_data = INSTANCE_CUSTOM;
}

void fragment() {
    vec2 uv = UV * 2.0 - 1.0;
    float dist = length(uv);

    // Circle shape
    if (dist > 1.0) {
        discard;
    }

    // Outline
    vec4 color = base_color;
    if (dist > 1.0 - outline_width) {
        color = mix(color, vec4(0.0, 0.0, 0.0, 1.0), 0.5);
    }

    // Apply depth-based shading
    float depth_factor = custom_data.x;
    color.rgb *= (1.0 - depth_factor * 0.3);

    COLOR = color * MODULATE;
}
```

```glsl
// tree_edge.gdshader
shader_type canvas_item;

uniform vec4 edge_color : source_color = vec4(0.4, 0.4, 0.4, 0.6);
uniform float edge_width : hint_range(1.0, 5.0) = 2.0;

void fragment() {
    COLOR = edge_color * MODULATE;
}
```

---

## 6. Interaction System

### Touch and Gesture Handling

```gdscript
# tree_input_handler.gd
class_name TreeInputHandler extends Node

signal zoom_changed(zoom_level: float)
signal pan_changed(offset: Vector2)
signal node_selected(node_id: String)
signal node_hovered(node_id: String)

@export var zoom_sensitivity: float = 0.1
@export var pan_speed: float = 1.0
@export var inertia_friction: float = 0.92
@export var double_tap_time: float = 0.3
@export var pinch_threshold: float = 10.0

var touches: Dictionary = {}  # touch_index -> TouchData
var last_tap_time: float = 0.0
var pan_velocity: Vector2 = Vector2.ZERO
var is_panning: bool = false
var is_pinching: bool = false
var initial_pinch_distance: float = 0.0
var current_zoom: float = 1.0

class TouchData:
    var start_pos: Vector2
    var current_pos: Vector2
    var start_time: float
    var is_active: bool = true

func _ready() -> void:
    set_process_unhandled_input(true)
    set_physics_process(true)

func _unhandled_input(event: InputEvent) -> void:
    # Handle touch events
    if event is InputEventScreenTouch:
        _handle_touch(event)
    elif event is InputEventScreenDrag:
        _handle_drag(event)
    # Handle mouse events (desktop testing)
    elif event is InputEventMouseButton:
        _handle_mouse_button(event)
    elif event is InputEventMouseMotion:
        _handle_mouse_motion(event)
    # Handle keyboard shortcuts
    elif event is InputEventKey:
        _handle_keyboard(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
    if event.pressed:
        # Add new touch
        var touch = TouchData.new()
        touch.start_pos = event.position
        touch.current_pos = event.position
        touch.start_time = Time.get_ticks_msec() / 1000.0
        touches[event.index] = touch

        # Check for double tap
        var current_time = Time.get_ticks_msec() / 1000.0
        if current_time - last_tap_time < double_tap_time and touches.size() == 1:
            _handle_double_tap(event.position)
        last_tap_time = current_time

        # Start gesture detection
        _update_gesture_state()
    else:
        # Remove touch
        if event.index in touches:
            touches.erase(event.index)
        _update_gesture_state()

func _handle_drag(event: InputEventScreenDrag) -> void:
    if event.index in touches:
        var touch = touches[event.index]
        touch.current_pos = event.position

        if is_pinching and touches.size() >= 2:
            _update_pinch()
        elif is_panning and touches.size() == 1:
            _update_pan(event.relative)

func _update_gesture_state() -> void:
    if touches.size() == 0:
        is_panning = false
        is_pinching = false
    elif touches.size() == 1:
        is_panning = true
        is_pinching = false
        pan_velocity = Vector2.ZERO
    elif touches.size() >= 2:
        is_panning = false
        is_pinching = true
        initial_pinch_distance = _calculate_pinch_distance()

func _calculate_pinch_distance() -> float:
    if touches.size() < 2:
        return 0.0

    var positions = []
    for touch in touches.values():
        positions.append(touch.current_pos)

    return positions[0].distance_to(positions[1])

func _update_pinch() -> void:
    var current_distance = _calculate_pinch_distance()
    if abs(current_distance - initial_pinch_distance) > pinch_threshold:
        var zoom_delta = (current_distance / initial_pinch_distance - 1.0) * zoom_sensitivity
        current_zoom = clamp(current_zoom * (1.0 + zoom_delta), 0.1, 10.0)
        emit_signal("zoom_changed", current_zoom)
        initial_pinch_distance = current_distance

func _update_pan(delta: Vector2) -> void:
    var pan_delta = delta * pan_speed / current_zoom
    emit_signal("pan_changed", pan_delta)

    # Update velocity for inertia
    pan_velocity = pan_velocity * 0.8 + pan_delta * 0.2

func _physics_process(delta: float) -> void:
    # Apply inertial scrolling
    if not is_panning and pan_velocity.length() > 0.01:
        emit_signal("pan_changed", pan_velocity)
        pan_velocity *= inertia_friction

func _handle_double_tap(position: Vector2) -> void:
    # Zoom to node or reset zoom
    var world_pos = _screen_to_world(position)
    var node = _find_node_at_position(world_pos)
    if node:
        _zoom_to_node(node)
    else:
        _reset_zoom()
```

### Camera Controller

```gdscript
# tree_camera.gd
class_name TreeCamera extends Camera2D

@export var min_zoom: float = 0.1
@export var max_zoom: float = 10.0
@export var zoom_speed: float = 0.1
@export var pan_limits: Rect2 = Rect2(-10000, -10000, 20000, 20000)
@export var smooth_factor: float = 0.15

var target_zoom: float = 1.0
var target_position: Vector2 = Vector2.ZERO
var is_animating: bool = false

func _ready() -> void:
    # Set initial camera properties
    zoom = Vector2(1, 1)
    position = Vector2.ZERO

func _process(delta: float) -> void:
    # Smooth zoom and position
    if is_animating or zoom.x != target_zoom or position != target_position:
        zoom = zoom.lerp(Vector2(target_zoom, target_zoom), smooth_factor)
        position = position.lerp(target_position, smooth_factor)

        if zoom.distance_to(Vector2(target_zoom, target_zoom)) < 0.001:
            zoom = Vector2(target_zoom, target_zoom)
            is_animating = false

func set_zoom_level(level: float) -> void:
    target_zoom = clamp(level, min_zoom, max_zoom)

func pan_by(offset: Vector2) -> void:
    target_position += offset
    target_position.x = clamp(target_position.x, pan_limits.position.x, pan_limits.end.x)
    target_position.y = clamp(target_position.y, pan_limits.position.y, pan_limits.end.y)

func focus_on_node(node_position: Vector2, zoom_level: float = 2.0) -> void:
    target_position = node_position
    target_zoom = zoom_level
    is_animating = true

func reset_view() -> void:
    target_position = Vector2.ZERO
    target_zoom = 1.0
    is_animating = true

func get_visible_rect() -> Rect2:
    var viewport_size = get_viewport_rect().size
    var half_size = viewport_size / (2.0 * zoom.x)
    return Rect2(position - half_size, half_size * 2.0)
```

---

## 7. Optimization Strategies

### Chunking System

```gdscript
# chunk_manager.gd
class_name ChunkManager extends Node

signal chunks_loaded(chunks: Array[TreeChunk])
signal chunks_unloaded(chunk_ids: Array[Vector2i])

@export var chunk_size: Vector2 = Vector2(2048, 2048)
@export var load_radius: int = 2  # Chunks to load around visible area
@export var max_concurrent_loads: int = 4

var active_chunks: Dictionary = {}  # chunk_id -> TreeChunk
var loading_chunks: Dictionary = {}  # chunk_id -> bool
var load_queue: Array[Vector2i] = []
var current_loads: int = 0

func update_visible_chunks(camera_rect: Rect2) -> void:
    var required_chunks = _get_required_chunks(camera_rect)

    # Unload distant chunks
    var to_unload = []
    for chunk_id in active_chunks:
        if chunk_id not in required_chunks:
            to_unload.append(chunk_id)

    if to_unload.size() > 0:
        _unload_chunks(to_unload)

    # Queue new chunks for loading
    for chunk_id in required_chunks:
        if chunk_id not in active_chunks and chunk_id not in loading_chunks:
            load_queue.append(chunk_id)

    # Process load queue
    _process_load_queue()

func _get_required_chunks(camera_rect: Rect2) -> Array[Vector2i]:
    var chunks = []

    var min_chunk = Vector2i(
        int(camera_rect.position.x / chunk_size.x) - load_radius,
        int(camera_rect.position.y / chunk_size.y) - load_radius
    )
    var max_chunk = Vector2i(
        int(camera_rect.end.x / chunk_size.x) + load_radius,
        int(camera_rect.end.y / chunk_size.y) + load_radius
    )

    for x in range(min_chunk.x, max_chunk.x + 1):
        for y in range(min_chunk.y, max_chunk.y + 1):
            chunks.append(Vector2i(x, y))

    return chunks

func _process_load_queue() -> void:
    while current_loads < max_concurrent_loads and load_queue.size() > 0:
        var chunk_id = load_queue.pop_front()
        _load_chunk_async(chunk_id)

func _load_chunk_async(chunk_id: Vector2i) -> void:
    loading_chunks[chunk_id] = true
    current_loads += 1

    # Check cache first
    var cached = TreeCache.load_chunk(chunk_id)
    if cached:
        _on_chunk_loaded(chunk_id, cached)
        return

    # Load from server
    var api = APIManager
    api.request_chunk(chunk_id, _on_chunk_loaded.bind(chunk_id))

func _on_chunk_loaded(chunk_id: Vector2i, chunk: TreeChunk) -> void:
    loading_chunks.erase(chunk_id)
    current_loads -= 1

    if chunk:
        active_chunks[chunk_id] = chunk
        TreeCache.save_chunk(chunk_id, chunk)
        emit_signal("chunks_loaded", [chunk])

    # Continue processing queue
    _process_load_queue()

func _unload_chunks(chunk_ids: Array[Vector2i]) -> void:
    for chunk_id in chunk_ids:
        active_chunks.erase(chunk_id)
    emit_signal("chunks_unloaded", chunk_ids)
```

### Level of Detail (LOD) System

```gdscript
# lod_manager.gd
class_name LODManager extends Node

enum LODLevel {
    FULL = 0,      # All nodes and edges
    MEDIUM = 1,    # Important nodes only
    LOW = 2,       # Major branches only
    MINIMAL = 3    # Top-level only
}

@export var lod_distances: Array[float] = [1.0, 2.0, 4.0, 8.0]

func get_lod_level(zoom: float) -> LODLevel:
    for i in range(lod_distances.size()):
        if zoom >= lod_distances[i]:
            return i as LODLevel
    return LODLevel.MINIMAL

func filter_nodes_by_lod(nodes: Array[TaxonomicNode], lod: LODLevel) -> Array[TaxonomicNode]:
    match lod:
        LODLevel.FULL:
            return nodes
        LODLevel.MEDIUM:
            return nodes.filter(func(n): return n.subtree_size > 10 or n.discovered)
        LODLevel.LOW:
            return nodes.filter(func(n): return n.subtree_size > 100 or n.rank in ["kingdom", "phylum", "class"])
        LODLevel.MINIMAL:
            return nodes.filter(func(n): return n.rank in ["kingdom", "phylum"])
        _:
            return []

func filter_edges_by_lod(edges: Array, nodes: Array[TaxonomicNode], lod: LODLevel) -> Array:
    # Filter edges based on visible nodes
    var visible_ids = {}
    for node in nodes:
        visible_ids[node.id] = true

    return edges.filter(func(e):
        return e[0] in visible_ids and e[1] in visible_ids
    )
```

### Memory Management

```gdscript
# memory_monitor.gd
class_name MemoryMonitor extends Node

@export var memory_limit_mb: float = 500.0
@export var check_interval: float = 5.0

var timer: Timer

func _ready() -> void:
    timer = Timer.new()
    timer.wait_time = check_interval
    timer.timeout.connect(_check_memory)
    add_child(timer)
    timer.start()

func _check_memory() -> void:
    var memory_used = OS.get_static_memory_usage() / 1048576.0  # Convert to MB

    if memory_used > memory_limit_mb:
        _free_memory()

func _free_memory() -> void:
    # Clear caches
    TreeCache.clear_old_chunks()

    # Force garbage collection
    print("Memory pressure detected, clearing caches")

    # Reduce quality if needed
    if OS.get_static_memory_usage() / 1048576.0 > memory_limit_mb * 0.9:
        get_tree().call_group("renderers", "reduce_quality")
```

---

## 8. API Integration

CLAUDE: Note that client/biologidex-client/api_manager.gd already exists

### Data Fetching Service

```gdscript
# tree_api_service.gd
class_name TreeAPIService extends Node

const API_BASE = "/api/v1/graph/"

signal layout_received(layout: TreeLayoutData)
signal chunk_received(chunk_id: Vector2i, chunk: TreeChunk)
signal error_occurred(message: String)

func fetch_tree_layout() -> void:
    var api = APIManager
    api.make_request(
        HTTPClient.METHOD_GET,
        API_BASE + "taxonomic-tree-layout/",
        {},
        _on_layout_received,
        _on_error
    )

func fetch_chunk(chunk_id: Vector2i) -> void:
    var api = APIManager
    api.make_request(
        HTTPClient.METHOD_GET,
        API_BASE + "chunk/" + str(chunk_id.x) + "/" + str(chunk_id.y) + "/",
        {},
        _on_chunk_received.bind(chunk_id),
        _on_error
    )

func _on_layout_received(response: Dictionary) -> void:
    var layout = TreeLayoutData.new()
    layout.total_nodes = response.get("total_nodes", 0)
    layout.max_depth = response.get("max_depth", 0)
    layout.world_bounds = _parse_rect(response.get("world_bounds", {}))
    layout.root_id = response.get("root_id", "")

    emit_signal("layout_received", layout)

func _on_chunk_received(response: Dictionary, chunk_id: Vector2i) -> void:
    var chunk = TreeChunk.new()
    chunk.chunk_id = chunk_id
    chunk.world_bounds = _parse_rect(response.get("bounds", {}))
    chunk.node_ids = response.get("node_ids", [])
    chunk.edge_pairs = _parse_edge_pairs(response.get("edges", []))
    chunk.is_loaded = true

    emit_signal("chunk_received", chunk_id, chunk)

func _parse_rect(data: Dictionary) -> Rect2:
    return Rect2(
        data.get("x", 0),
        data.get("y", 0),
        data.get("width", 0),
        data.get("height", 0)
    )

func _parse_edge_pairs(data: Array) -> Array[Vector2i]:
    var pairs = []
    for edge in data:
        pairs.append(Vector2i(edge[0], edge[1]))
    return pairs
```

### Progressive Loading

```gdscript
# progressive_loader.gd
class_name ProgressiveLoader extends Node

signal loading_progress(progress: float)
signal loading_complete()

@export var initial_depth: int = 3
@export var load_delay: float = 0.1

var total_to_load: int = 0
var loaded_count: int = 0
var load_timer: Timer

func start_progressive_load(root: TaxonomicNode) -> void:
    total_to_load = _count_nodes_to_depth(root, initial_depth)
    loaded_count = 0

    load_timer = Timer.new()
    load_timer.wait_time = load_delay
    load_timer.timeout.connect(_load_next_batch)
    add_child(load_timer)
    load_timer.start()

    _load_next_batch()

func _load_next_batch() -> void:
    # Load nodes in breadth-first order
    var batch_size = 100
    var loaded_this_batch = 0

    # Implementation of batch loading...

    loaded_count += loaded_this_batch
    emit_signal("loading_progress", float(loaded_count) / float(total_to_load))

    if loaded_count >= total_to_load:
        load_timer.stop()
        load_timer.queue_free()
        emit_signal("loading_complete")
```

---

## 9. Implementation Phases

### Phase 1: Foundation
- [x] Create base scene structure
- [ ] Implement basic data models
- [ ] Set up singleton managers
- [ ] Create basic rendering with placeholder data
- [ ] Implement camera controls

### Phase 2: Layout Algorithm
- [ ] Implement Reingold-Tilford algorithm
- [ ] Create layout caching system
- [ ] Add layout optimization
- [ ] Test with sample data
- [ ] Create debug visualization

### Phase 3: Rendering System 
- [ ] Set up MultiMeshInstance2D for nodes
- [ ] Set up MultiMeshInstance2D for edges
- [ ] Implement shaders
- [ ] Add LOD system
- [ ] Optimize draw calls

### Phase 4: Interaction
- [ ] Implement touch gesture handling
- [ ] Add mouse controls for desktop
- [ ] Create node selection system
- [ ] Add hover effects
- [ ] Implement zoom-to-node functionality

### Phase 5: Optimization
- [ ] Implement chunking system
- [ ] Add culling optimization
- [ ] Create memory management
- [ ] Add progressive loading
- [ ] Performance profiling

### Phase 6: API Integration
- [ ] Connect to backend API
- [ ] Implement data fetching
- [ ] Add caching layer
- [ ] Handle offline mode
- [ ] Error handling and retry logic

### Phase 7: Polish
- [ ] Add search functionality
- [ ] Implement filtering
- [ ] Create animations
- [ ] Add visual effects
- [ ] Mobile optimization

### Phase 8: Testing & Deployment
- [ ] Unit testing
- [ ] Performance testing
- [ ] Device testing
- [ ] Bug fixes
- [ ] Documentation

---

## Appendix A: Configuration Files

### Project Settings
```ini
# project.godot additions
[rendering]
environment/defaults/default_clear_color=Color(0.1, 0.1, 0.1, 1)
2d/snap/snap_2d_transforms_to_pixel=true
2d/snap/snap_2d_vertices_to_pixel=true

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="viewport"
window/stretch/aspect="keep"

[input_devices]
pointing/emulate_touch_from_mouse=true

[rendering/limits]
rendering/max_renderable_elements=1000000
rendering/max_renderable_lights=32
```

---

## Appendix B: Sample Data Format

### Server Response Format
```json
{
    "layout": {
        "total_nodes": 150000,
        "max_depth": 7,
        "world_bounds": {
            "x": -50000,
            "y": 0,
            "width": 100000,
            "height": 70000
        },
        "root_id": "kingdom_animalia",
        "chunk_grid": {
            "size": [2048, 2048],
            "dimensions": [49, 35]
        }
    },
    "initial_chunk": {
        "chunk_id": [24, 0],
        "bounds": {
            "x": 49152,
            "y": 0,
            "width": 2048,
            "height": 2048
        },
        "nodes": [
            {
                "id": "kingdom_animalia",
                "scientific_name": "Animalia",
                "rank": "kingdom",
                "position": [50000, 100],
                "discovered": true,
                "children_count": 35
            }
        ],
        "edges": [[0, 1], [0, 2], [1, 3]]
    }
}
```

---

## Appendix C: Troubleshooting Guide

### Common Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Poor FPS with many nodes | Too many draw calls | Increase MultiMesh batching, implement LOD |
| Jerky pan/zoom | No smoothing | Add interpolation in camera controller |
| Memory leaks | Chunks not unloading | Implement proper chunk lifecycle management |
| Touch gestures not working | Input not propagating | Check SubViewport input handling |
| Layout overlapping | Algorithm error | Verify Reingold-Tilford implementation |
| Slow initial load | Loading all data | Implement progressive loading |
| Labels unreadable | Too many labels | Implement label culling and priority system |

---

## Conclusion

This implementation plan provides a comprehensive roadmap for building a high-performance taxonomic tree visualization in Godot 4.5. The architecture leverages MultiMeshInstance2D for efficient rendering, implements the Reingold-Tilford algorithm for elegant tree layouts, and includes sophisticated optimization techniques like chunking, LOD, and culling to handle massive datasets.

Key success factors:
- Start with a solid foundation and test each component
- Profile performance early and often
- Implement optimization incrementally
- Test on target devices throughout development
- Keep the user experience smooth and responsive

The modular design allows for iterative development and easy testing of individual components. Following this plan should result in a production-ready tree visualization capable of handling hundreds of thousands of nodes while maintaining 60 FPS performance.
