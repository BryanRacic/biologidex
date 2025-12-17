# BiologiDex Client Background/Paper/Shader Audit

**Date:** 2025-12-16
**Scope:** `client/biologidex-client/` - Background, paper, shader, and camera system code
**Status:** Comprehensive audit with findings and recommendations

---

## Executive Summary

The background and camera system underwent a significant refactor (documented in `background_overhaul.md`) moving from a Control-based `InteractiveBackground` to a Camera2D-based `PaperCameraScene` architecture. While the migration was largely successful, this audit identifies several **efficiency issues**, **dead code**, **settings bugs**, and **code quality concerns** that should be addressed.

### Critical Findings

| Severity | Issue | Location |
|----------|-------|----------|
| High | Shader runs expensive FBM noise (16+ samples/pixel/frame) | `paper_camera.gdshader` |
| High | 50,000x50,000 unit background causes massive overdraw | `paper_camera_scene.tscn` |
| Medium | `reset()` ignores `initial_zoom` setting | `camera_touch_controller.gd:397-401` |
| Medium | Dead code: unused `TreeCameraController` class | `features/tree/camera_controller.gd` |
| Medium | Dead code: unused `paper.gdshader` | `shaders/paper.gdshader` |
| Low | Magic numbers throughout shader without documentation | `paper_camera.gdshader` |
| Low | Redundant vertex shader for static geometry | `paper_camera.gdshader:59-70` |

---

## Files Audited

### Core Files

| File | Purpose | Lines |
|------|---------|-------|
| `shaders/paper_camera.gdshader` | Active paper background shader | 144 |
| `shaders/paper.gdshader` | **UNUSED** - legacy shader | 135 |
| `features/camera_system/paper_camera_scene.gd` | Main orchestrator component | 285 |
| `features/camera_system/paper_camera_scene.tscn` | Instancable scene definition | 57 |
| `features/camera_system/camera_touch_controller.gd` | Unified touch/gesture handler | 402 |
| `features/tree/camera_controller.gd` | **UNUSED** - legacy tree controller | 235 |

### Scene Usage

All 8 migrated scenes correctly use `PaperCameraScene`:
- `home.tscn`, `login.tscn`, `create_acct.tscn`, `camera.tscn`
- `dex.tscn`, `dex_feed.tscn`, `social.tscn`, `tree.tscn`

---

## Detailed Findings

### 1. SHADER PERFORMANCE ISSUES (High Severity)

#### 1.1 Excessive Per-Pixel Computation

**Location:** `shaders/paper_camera.gdshader:72-143`

The fragment shader performs extremely heavy computation for every pixel, every frame:

```glsl
// CURRENT: 4 FBM calls per pixel, each with 4 octaves = 16 value_noise samples
float n1 = fbm(paper_uv * paper_noise_scale);           // 4 noise samples
float n2 = fbm(paper_uv * paper_noise_scale * 2.6);     // 4 noise samples
float thresh_var = fbm(sp_uv * 0.25) * 0.18;            // 4 noise samples
float ang = fbm(paper_uv * 0.6) * 6.28318;              // 4 noise samples

// Plus additional value_noise calls for speckles and fibers:
float spots_big   = value_noise(sp_uv * 0.55);
float spots_small = value_noise(sp_uv * 1.8);
float big_opacity   = mix(0.25, 1.0, value_noise(...));
float small_opacity = mix(0.10, 0.8, value_noise(...));
float fib_noise   = value_noise(fib_uv);
float fib_opacity = mix(0.2, 1.0, value_noise(...));
```

**Impact:** At 1280x720 resolution, this is ~922,000 pixels * ~22 noise samples = **~20 million noise calculations per frame**.

**Recommendations:**

1. **Bake noise to texture** - Pre-compute the paper texture at startup or as a resource
2. **Reduce FBM octaves** - 2-3 octaves are often visually sufficient
3. **Use sampler2D noise texture** - Sample from pre-generated noise texture instead of procedural calculation
4. **Add LOD system** - Reduce detail when zoomed out (grid lines only at zoom < 0.5)

#### 1.2 Massive Background Overdraw

**Location:** `paper_camera_scene.tscn:40`

```
polygon = PackedVector2Array(-25000, -25000, 25000, -25000, 25000, 25000, -25000, 25000)
```

The background polygon covers **50,000 x 50,000 world units** but the viewport typically shows only ~1,280 x 720 units at zoom 1.0. This means:

- At zoom 1.0: **99.97% overdraw** (shader runs on invisible pixels)
- At zoom 0.1: Still ~96% overdraw

**Recommendations:**

1. **Dynamic polygon sizing** - Resize the polygon based on camera view bounds + margin
2. **Use viewport-sized ColorRect** - For non-infinite-canvas scenes (login, home), use a fixed viewport-sized background
3. **Shader discard for out-of-view** - Add early exit in shader (though GPU usually handles this)

#### 1.3 Redundant Vertex Shader

**Location:** `paper_camera.gdshader:59-70`

```glsl
void vertex() {
    vec4 world_pos = MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0);
    world_coord = world_pos.xy;
    // VERTEX stays unchanged - Godot will apply MODEL_MATRIX * CANVAS_MATRIX
}
```

The Polygon2D is placed at world origin and never moves. The MODEL_MATRIX is identity, making this computation redundant. The shader could directly use `VERTEX` coordinates.

**Recommendation:** Simplify to use `VERTEX` directly or remove the varying and pass world coordinates via uniform (as `paper.gdshader` does).

---

### 2. SETTINGS/CONFIGURATION BUGS (Medium Severity)

#### 2.1 `reset()` Ignores `initial_zoom`

**Location:** `camera_touch_controller.gd:397-401`

```gdscript
func reset() -> void:
    camera.position = Vector2.ZERO
    camera.zoom = Vector2(1.0, 1.0)  # BUG: Hardcoded, ignores initial_zoom
    _velocity = Vector2.ZERO
    _emit_view_changed()
```

**Compare to:** `paper_camera_scene.gd:264-267`
```gdscript
func reset() -> void:
    camera.position = Vector2.ZERO
    camera.zoom = Vector2(initial_zoom, initial_zoom)  # CORRECT
    view_changed.emit(camera.position, camera.zoom.x)
```

**Impact:** When `CameraTouchController.reset()` is called directly (not through PaperCameraScene), the initial_zoom setting is ignored. The tree scene's `zoom_reset_button` calls `_paper_camera.reset()` which works correctly, but this inconsistency could cause bugs.

**Recommendation:** The controller shouldn't have a `reset()` method, or it should accept an initial_zoom parameter. The parent scene should be the source of truth.

#### 2.2 Property Duplication

The same default values are defined in both `.tscn` and `.gd` files:

```gdscript
// paper_camera_scene.gd
@export_range(8.0, 64.0, 0.5) var grid_scale: float = 22.0

// paper_camera_scene.tscn (sub_resource)
shader_parameter/grid_scale = 22.0
```

**Impact:** If defaults diverge, behavior becomes unpredictable. Currently they match, but maintenance burden is doubled.

**Recommendation:** Remove defaults from `.tscn` ShaderMaterial; let `_sync_all_shader_params()` apply the GDScript defaults.

---

### 3. DEAD CODE (Medium Severity)

#### 3.1 Unused `paper.gdshader`

**Location:** `shaders/paper.gdshader`

This is the old shader from before the Camera2D migration. It requires manual `scroll` and `viewport_size` uniforms that the new architecture doesn't use. No scene references it.

**Recommendation:** Delete the file.

#### 3.2 Unused `TreeCameraController`

**Location:** `features/tree/camera_controller.gd`

This class (`class_name TreeCameraController`) is never instantiated. The tree scene now uses `CameraTouchController` from the camera_system. The only references are:
- Its own file
- `background_overhaul.md` documentation

**Recommendation:** Delete the file after verifying no dynamic instantiation.

---

### 4. CODE QUALITY ISSUES (Low Severity)

#### 4.1 Magic Numbers in Shader

**Location:** Throughout `paper_camera.gdshader`

```glsl
p *= 2.05;                    // Why 2.05? Standard lacunarity is 2.0
float paper_n = (n1 * 0.7 + n2 * 0.3) - 0.5;  // Why these weights?
vec2 sp_uv = paper_uv * speckle_scale * 6.0 * speckle_density;  // Why 6.0?
float ang = fbm(paper_uv * 0.6) * 6.28318;    // 6.28318 = TAU, but unlabeled
fib_uv.x *= 3.5;              // Why 3.5?
fib_uv.y *= 0.55;             // Why 0.55?
smoothstep(0.80 + thresh_var, 1.0, spots_big)  // Why 0.80?
```

**Recommendation:** Document magic numbers with comments or extract to named constants.

#### 4.2 Missing Guard in `_on_tap_detected`

**Location:** `paper_camera_scene.gd:181-185`

```gdscript
func _on_tap_detected(screen_pos: Vector2) -> void:
    var viewport_center := get_viewport_rect().size / 2.0  # Can fail if not in tree
    var world_pos := (screen_pos - viewport_center) / camera.zoom.x + camera.position
    tap_detected.emit(world_pos)
```

The `get_view_rect()` method has a guard (`if not is_inside_tree(): return Rect2()`), but `_on_tap_detected` does not. While this callback wouldn't normally fire when not in tree, consistency would be better.

#### 4.3 Inconsistent API Naming

```gdscript
// paper_camera_scene.gd
func get_current_zoom() -> float      // Method 1
func get_zoom() -> float               // Method 2 (duplicate!)

// camera_touch_controller.gd
func get_current_zoom() -> float       // Only one version
```

**Recommendation:** Pick one name and deprecate the other.

---

### 5. ARCHITECTURAL OBSERVATIONS

#### 5.1 Web Export Workarounds (Correct)

The codebase correctly implements workarounds for Godot's GitHub #101975 bug:
- UI is added as sibling CanvasLayer, not child of instanced scene
- Node references use explicit paths, not `%UniqueNames`
- World content is created programmatically, not in .tscn

#### 5.2 Settings Flow (Correct)

The settings flow is well-designed:
1. Export vars in `paper_camera_scene.gd` with setters
2. Setters call `_update_shader_param()` for live updates
3. `_ready()` calls `_sync_all_shader_params()` for initial sync
4. Scene overrides work via .tscn property assignments

#### 5.3 Separation of Concerns (Correct)

Good separation between:
- `PaperCameraScene` - orchestration and API
- `CameraTouchController` - input handling
- Shader - visual rendering

---

## Recommendations Summary

### Priority 1 (High Impact, Should Fix)

1. **Optimize shader performance:**
   - Bake paper texture to a Texture2D at scene start
   - OR reduce FBM to 2 octaves and remove redundant noise calls
   - OR create a simplified "static paper" shader for non-panning scenes

2. **Right-size the background polygon:**
   - For static scenes (login, home): Use viewport-sized quad
   - For dynamic scenes (tree): Dynamically resize based on content bounds

3. **Delete dead code:**
   - `shaders/paper.gdshader`
   - `features/tree/camera_controller.gd`

### Priority 2 (Medium Impact, Should Fix)

4. **Fix `reset()` consistency:**
   - Remove `reset()` from `CameraTouchController`
   - OR pass initial_zoom as parameter

5. **Remove property duplication:**
   - Remove shader defaults from .tscn, rely on GDScript sync

### Priority 3 (Low Impact, Nice to Have)

6. **Document magic numbers** in shader with comments
7. **Add `is_inside_tree()` guard** to `_on_tap_detected`
8. **Remove duplicate `get_zoom()`** method

---

## Performance Improvement Estimate

| Optimization | Estimated Improvement |
|--------------|----------------------|
| Bake noise to texture | 10-20x faster fragment shader |
| Right-size polygon | 10-100x less overdraw |
| Reduce FBM octaves (4->2) | 2x faster per-pixel |
| Remove redundant vertex math | Minimal (GPU optimizes) |

**Combined:** Potential **20-50x reduction** in GPU workload for paper rendering.

---

## Testing Recommendations

After implementing fixes:

1. **Visual regression:** Compare paper appearance before/after
2. **Performance profiling:** Use Godot's debugger to measure frame time
3. **Web export testing:** Verify all scenes work on web target
4. **Mobile testing:** Test touch gestures and scroll limits
5. **Settings verification:** Confirm `initial_zoom` works on tree scene (should start at 2.0x)

---

## References

- [Godot Shader Optimization](https://peerdh.com/blogs/programming-insights/shader-performance-optimization-techniques-in-godot)
- [CanvasItem Shaders Documentation](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html)
- `background_overhaul.md` - Original migration plan
- GitHub #101975 - Godot web export instanced scene bug
