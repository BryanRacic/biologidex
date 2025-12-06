# Infinite Texture Background Research & Audit

**Date**: 2025-12-05
**Goal**: Synchronize shader-based paper/grid background with UI elements during pan/zoom operations

---

## Problem Statement

The app displays UI elements (especially on the tree & dex feed) as if they're pictures, drawings, and text on realistic paper. Panning & zooming should move the grid, paper texture, and UI elements at the same speed, zoom, and with the same momentum. However, since the grid & paper texture are in shader code and the UI elements have their own interactive logic, there's a disconnect between the speed & amount of movement that breaks the illusion (especially noticeable the farther zoomed out you are).

---

## Current Implementation Analysis

### 1. Paper Shader (`shaders/paper.gdshader:62-66`)

```glsl
vec2 scaled_scroll = scroll / scale;
vec2 px = (FRAGCOORD.xy / scale) + scaled_scroll;
```

**Issue**: The shader operates in **screen space** (FRAGCOORD.xy), then attempts to fake world-space behavior by dividing by scale. This works at scale=1.0 but introduces progressive drift as you zoom out/in because:
- FRAGCOORD is always in screen pixels (fixed to viewport)
- The division only approximates world coordinates

### 2. Tree Controller (`scenes/tree/tree_controller.gd:256-266`)

```gdscript
var transform = Transform2D()
transform = transform.scaled(Vector2(_current_scale, _current_scale))
transform.origin = _viewport_center - _scroll_offset * _current_scale
```

The UI elements use a **proper world-space transform** where:
- `screen = (world - scroll_offset) * scale + viewport_center`

### 3. BackgroundTouchController (`features/ui/components/interactive_background/background_touch_controller.gd`)

The touch controller emits `scroll_offset` in **world-space units** (intended to be the world coordinate at viewport center), but the shader interprets it in screen-space.

### 4. The Disconnect

| Component | Scroll Units | Zoom Behavior |
|-----------|--------------|---------------|
| Shader | Screen pixels ÷ scale | Approximated |
| UI/TreeGraph | True world coords | Transform2D applied |

When zoomed to scale=0.5:
- UI elements: moved by `scroll_offset * 0.5` screen pixels
- Shader: moved by `scroll_offset / 0.5 = scroll_offset * 2` conceptually, then rendered at half scale

This causes the grid to drift relative to UI elements as you pan while zoomed out.

---

## File Locations

| File | Purpose |
|------|---------|
| `shaders/paper.gdshader` | Paper texture with grid, noise, speckles, fibers |
| `features/ui/components/interactive_background/interactive_background.gd` | Connects touch controller to shader |
| `features/ui/components/interactive_background/background_touch_controller.gd` | Pan/zoom gesture handler |
| `features/tree/tree_renderer.gd` | Tree visualization with world-space transforms |
| `scenes/tree/tree_controller.gd` | Orchestrates tree view, applies Transform2D |
| `features/dex_feed/feed_carousel_renderer.gd` | Feed carousel with screen-space positioning |
| `scenes/dex_feed/dex_feed.gd` | Dex feed controller |

---

## Research Findings

### Gold Standard Approaches

1. **Scroll Matrix Approach** (David Gouveia's method): Transform texture coordinates directly in the vertex shader, using a matrix that encodes camera position/zoom/rotation

2. **World Coordinate Pass-Through** (Stack Overflow Godot 4 solution): Pass world coordinates from vertex shader to fragment shader, eliminating screen-space calculations

3. **Unified Canvas Transform** (Godot Parallax2D): Use Godot's built-in Parallax2D node which handles all the math automatically

### Key Mathematical Formula

From Stack Overflow research, the correct formula for syncing shader with camera:

```
fixed_uv = displacement + scale * UV + TIME * velocity
```

Where:
- **displacement**: Camera's world position normalized by texture size
- **scale * UV**: Texture offset scaled to match displacement units
- **TIME * velocity**: Animation based on elapsed time

Setting scale to `viewport_size / texture_size` eliminates drift.

### Scroll Matrix Approach (Most Robust)

The foundation uses a custom transformation matrix with world-space ordering (Scale-Rotation-Translation):

```
Matrix = Translation(-Origin/texSize) ×
         Scale(1/Zoom) ×
         Rotation(angle) ×
         Translation(Origin/texSize) ×
         Translation(Position/texSize)
```

This matrix calculates where screen corners map within texture space, enabling "any camera orientation without the effect breaking."

---

## Recommended Solutions

### Solution 1: Pass World Position to Shader (Simplest)

Modify the shader to receive world position from the vertex shader instead of computing from FRAGCOORD:

```glsl
shader_type canvas_item;
render_mode skip_vertex_transform;

uniform vec2 scroll = vec2(0.0);
uniform float scale : hint_range(0.5, 4.0) = 1.0;
uniform float grid_scale : hint_range(8.0, 64.0, 0.5) = 24.0;
// ... other uniforms

varying vec2 world_pos;

void vertex() {
    // Apply standard canvas transform
    VERTEX = (CANVAS_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;

    // Pass world position (before canvas transform)
    // This gives us true world coordinates
    world_pos = VERTEX / scale + scroll;
}

void fragment() {
    // Use world_pos directly instead of FRAGCOORD math
    vec2 px = world_pos;
    float scaled_line = line_px;  // Line width in world units

    // ... rest of shader unchanged
}
```

**Pros**: Minimal changes, works immediately
**Cons**: Requires `skip_vertex_transform` which may affect other shaders

---

### Solution 2: Unified World-Space Coordinate System (Most Elegant)

Create a single source of truth for scroll/zoom and ensure all components use the same coordinate system:

**A. Modify BackgroundTouchController to track world-space viewport bounds:**

```gdscript
func _get_world_rect() -> Rect2:
    """Get viewport bounds in world coordinates."""
    var half_size = (get_viewport_rect().size / 2.0) / current_scale
    return Rect2(scroll_offset - half_size, half_size * 2.0)
```

**B. Update shader to use world-coordinate scroll with correct transform:**

```glsl
uniform vec2 viewport_size;

void fragment() {
    // Convert screen position to world position
    // screen_pos = (world_pos - scroll) * scale + viewport_center
    // world_pos = (screen_pos - viewport_center) / scale + scroll
    vec2 screen_center = viewport_size / 2.0;
    vec2 world_pos = (FRAGCOORD.xy - screen_center) / scale + scroll;

    // Now world_pos matches UI element coordinates exactly
    // Grid, noise, etc all use world_pos directly
    vec2 cell_pos = mod(world_pos, grid_scale);
    // ...
}
```

**C. Pass viewport_size as a uniform:**

```gdscript
# In InteractiveBackground._ready()
_shader_material.set_shader_parameter("viewport_size", get_viewport_rect().size)

# Handle viewport resize
func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _shader_material.set_shader_parameter("viewport_size", get_viewport_rect().size)
```

**Pros**: Clean mathematical model, easy to debug
**Cons**: Requires adding viewport_size uniform and resize handling

---

### Solution 3: Use Node2D Background with CanvasItem Shader (Most Performant)

Instead of a fullscreen ColorRect with FRAGCOORD manipulation, use a Node2D that gets the same Transform2D as your TreeGraph:

**Scene structure:**
```
BackgroundLayer (CanvasLayer, layer=-1)
├── BackgroundNode2D (Node2D)  ← Apply same transform as TreeGraph
│   └── InfiniteGridMesh (MeshInstance2D with procedural shader)
```

**Shader approach:**
```glsl
shader_type canvas_item;

uniform float grid_scale = 24.0;

void fragment() {
    // VERTEX already contains world position because
    // parent Node2D has the same transform as TreeGraph
    vec2 world_pos = UV * (some_large_size);  // or use varying from vertex

    // Grid calculation in pure world space
    vec2 cell = mod(world_pos, grid_scale);
    // ...
}
```

**Controller modification:**
```gdscript
# In _update_tree_transform()
if background_node:
    background_node.transform = tree_graph.transform
```

**Pros**:
- Perfect sync guaranteed (same transform)
- GPU-efficient (texture sampling in world-space)
- No math drift possible

**Cons**:
- Requires restructuring scene tree
- Background must be large enough or tile procedurally

---

### Solution 4: Tree Scene Using Shared Transform (Recommended)

Currently, the Tree scene has InteractiveBackground in a separate CanvasLayer at layer=-1, but TreeGraph is in the default layer (0). The shader receives scroll/scale signals but doesn't share the transform.

**Current structure:**
```
Tree (Node2D)
├── BackgroundLayer (CanvasLayer, layer=-1)
│   └── InteractiveBackground  ← Separate transform!
├── TreeGraph (Node2D)  ← Has Transform2D applied
│   ├── EdgesLayer
│   ├── NodesLayer
│   └── ...
```

**Recommended restructure:**
```
Tree (Node2D)
├── TreeGraph (Node2D)  ← Has Transform2D applied
│   ├── PaperBackgroundRect (ColorRect with shader)  ← Same transform!
│   ├── EdgesLayer
│   ├── NodesLayer
│   └── ...
├── UILayer (CanvasLayer, layer=10)  ← Fixed UI stays fixed
    └── Controls
```

This ensures the paper background receives the exact same transform as UI elements.

**Pros**:
- Architecturally cleanest
- Guarantees perfect sync
- No shader math changes needed

**Cons**:
- Requires scene restructuring
- Background needs to be sized appropriately (large quad or procedural tiling)

---

## Performance Considerations

| Approach | Draw Calls | GPU Cost | Sync Accuracy |
|----------|------------|----------|---------------|
| Current FRAGCOORD | 1 | Low | Drifts at zoom |
| Solution 1 (vertex pass) | 1 | Low | Good |
| Solution 2 (fixed formula) | 1 | Low | Perfect |
| Solution 3 (shared transform) | 1 | Low | Perfect |
| Solution 4 (restructure) | 1 | Low | Perfect |

---

## Recommendations

### For the Tree Scene
Use **Solution 4** (restructure to share transform) – it's architecturally cleanest and guarantees perfect sync.

Alternatively, **Solution 2** (fixed shader formula) requires minimal structural changes while providing perfect sync.

### For the Dex Feed
Since zoom is disabled (`min_scale = max_scale = 1.0`), the current implementation works fine. The issue only manifests when scale ≠ 1.0.

---

## Sources

- [Godot 4: Canvas Item Shader with Camera](https://stackoverflow.com/questions/75666385/godot-4-move-canvas-item-shader-with-camera) - Formula for fixing UV drift
- [Scrolling Textures with Zoom and Rotation](https://www.david-gouveia.com/scrolling-textures-with-zoom-and-rotation) - Scroll matrix approach
- [Infinite World Floor Grid Shader](https://gamedev.stackexchange.com/questions/182263/infinite-world-floor-grid-shader) - World-space grid techniques
- [Godot Parallax2D Progress Report](https://godotengine.org/article/parallax-progress-report/) - Built-in parallax node
- [Unity Grid Shader](https://techarthub.com/unity-grid-shader/) - Procedural world-space grid reference
- [Godot Shaders: Infinite Scrolling Texture](https://godotshaders.com/shader/infinite-scrolling-texture-with-angle-modifier/) - Scrolling texture patterns
- [GameMaker Shader Surface Scaling](https://forum.gamemaker.io/index.php?threads/zoom-scale-a-shader-surface-not-scaling-properly-or-shifting-to-view.94665/) - Common zoom/scale pitfalls
