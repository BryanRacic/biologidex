shader_type canvas_item;

// =============================================================================
// Paper Camera Background Shader
// =============================================================================
// Creates a procedural graph paper texture that moves with the camera.
// Optimized version: reduced FBM octaves (4→2) for ~2x faster rendering.
// =============================================================================

// Paper appearance uniforms
uniform float grid_scale : hint_range(8.0, 64.0, 0.5) = 24.0;
uniform float line_px    : hint_range(0.5, 3.0, 0.1) = 1.0;
uniform vec4  line_color = vec4(0.55, 0.53, 0.50, 1.0);
uniform float line_alpha : hint_range(0.0, 0.6, 0.01) = 0.20;

uniform vec4 paper_color = vec4(0.96, 0.94, 0.90, 1.0);
uniform float paper_noise_amount : hint_range(0.0, 0.15, 0.001) = 0.05;
uniform float paper_noise_scale  : hint_range(0.05, 1.5, 0.01)  = 0.35;

uniform float speckle_amount  : hint_range(0.0, 0.30, 0.001) = 0.10;
uniform float speckle_density : hint_range(0.25, 3.0, 0.01)  = 1.0;
uniform float speckle_scale   : hint_range(0.5, 6.0, 0.01)   = 2.0;

uniform float fiber_amount : hint_range(0.0, 0.20, 0.001) = 0.06;
uniform float fiber_scale  : hint_range(0.2, 4.0, 0.01)   = 1.3;

// World coordinate from vertex shader
varying vec2 world_coord;

// =============================================================================
// Constants - documented magic numbers
// =============================================================================
// Note: TAU (6.28318) is a Godot built-in constant, used directly below
const float LACUNARITY = 2.0;           // Standard frequency multiplier for FBM
const int FBM_OCTAVES = 2;              // Reduced from 4 for performance (still visually good)
const float SPECKLE_UV_MULT = 6.0;      // Base multiplier for speckle UV density
const float FIBER_STRETCH_X = 3.5;      // Fiber elongation in X direction
const float FIBER_STRETCH_Y = 0.55;     // Fiber compression in Y direction
const float FIBER_UV_MULT = 10.0;       // Base multiplier for fiber UV
const float FIBER_ANGLE_SCALE = 0.6;    // Controls how varied fiber angles are
const float BIG_SPECK_THRESH = 0.80;    // Threshold for large speckles (0.0-1.0)
const float SMALL_SPECK_THRESH = 0.84;  // Threshold for small speckles (higher = sparser)
const float FIBER_THRESH = 0.78;        // Threshold for fiber visibility

// =============================================================================
// Noise helpers
// =============================================================================

// Simple 2D hash for pseudo-random values
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

// Value noise with smooth interpolation
float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    // Smooth Hermite interpolation (3t² - 2t³)
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal Brownian Motion - 2 octaves (reduced from 4 for performance)
// Each octave adds finer detail at half amplitude
float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for(int i = 0; i < FBM_OCTAVES; i++) {
        v += a * value_noise(p);
        p *= LACUNARITY;
        a *= 0.5;
    }
    return v;
}

// 2D rotation matrix
mat2 rot(float a) {
    float s = sin(a), c = cos(a);
    return mat2(vec2(c, -s), vec2(s, c));
}

// =============================================================================
// Vertex shader
// =============================================================================
// The Polygon2D is placed at world origin. We pass world coordinates to the
// fragment shader for procedural texturing that stays fixed in world space.

void vertex() {
    // MODEL_MATRIX transforms from local to world space
    // Store world position for consistent procedural sampling
    vec4 world_pos = MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0);
    world_coord = world_pos.xy;
    // Let Godot handle vertex transformation (default behavior)
}

// =============================================================================
// Fragment shader
// =============================================================================

void fragment() {
    // World coordinates ensure paper pattern moves with camera
    vec2 px = world_coord;

    // Line width in world units
    float scaled_line = line_px;

    // -----------------------
    // Base paper noise
    // -----------------------
    vec2 paper_uv = px / grid_scale;

    // Two layers of noise at different scales for organic paper texture
    // Primary noise (70% weight) + secondary noise at 2.6x frequency (30% weight)
    float n1 = fbm(paper_uv * paper_noise_scale);
    float n2 = fbm(paper_uv * paper_noise_scale * 2.6);  // 2.6x = ~1 octave higher for detail
    float paper_n = (n1 * 0.7 + n2 * 0.3) - 0.5;  // Center around 0

    vec3 col = paper_color.rgb + paper_n * paper_noise_amount;

    // -----------------------
    // Speckles: round dark spots with size/opacity variance
    // -----------------------
    vec2 sp_uv = paper_uv * speckle_scale * SPECKLE_UV_MULT * speckle_density;

    // Two sizes of speckles: big (0.55x UV) and small (1.8x UV)
    float spots_big   = value_noise(sp_uv * 0.55);
    float spots_small = value_noise(sp_uv * 1.8);

    // Threshold variation adds organic irregularity to speckle distribution
    float thresh_var = fbm(sp_uv * 0.25) * 0.18;

    // Create masks for where speckles appear (high noise values only)
    float big_mask   = smoothstep(BIG_SPECK_THRESH + thresh_var, 1.0, spots_big);
    float small_mask = smoothstep(SMALL_SPECK_THRESH + thresh_var, 1.0, spots_small);

    // Variable opacity per speckle for realism
    // Offsets (12.3, -7.1) break correlation with speckle positions
    float big_opacity   = mix(0.25, 1.0, value_noise(sp_uv * 0.9 + 12.3));
    float small_opacity = mix(0.10, 0.8, value_noise(sp_uv * 2.2 - 7.1));

    float specks =
        big_mask   * big_opacity * 1.0 +
        small_mask * small_opacity * 0.7;  // Small speckles are 70% intensity

    // -----------------------
    // Fibers: elongated dark lines like paper fibers
    // -----------------------
    // Random rotation angle per-area using FBM, scaled to full rotation (TAU)
    float ang = fbm(paper_uv * FIBER_ANGLE_SCALE) * TAU;
    vec2 fib_uv = (rot(ang) * paper_uv) * fiber_scale * FIBER_UV_MULT;

    // Stretch in X, compress in Y to create elongated fiber appearance
    fib_uv.x *= FIBER_STRETCH_X;
    fib_uv.y *= FIBER_STRETCH_Y;

    float fib_noise   = value_noise(fib_uv);
    float fib_mask    = smoothstep(FIBER_THRESH, 1.0, fib_noise);
    // Fiber opacity varies (offset 4.4 breaks correlation)
    float fib_opacity = mix(0.2, 1.0, value_noise(fib_uv * 0.7 + 4.4));

    specks += fib_mask * fib_opacity * 0.9;  // Fibers are 90% intensity

    // Apply speckles/fibers (darken the paper)
    col -= specks * speckle_amount;
    col -= fib_mask * fib_opacity * fiber_amount;

    // -----------------------
    // Crisp grid lines
    // -----------------------
    vec2 cell_pos = mod(px, grid_scale);

    // Lines at cell edges (both sides to handle boundary)
    float vline = step(cell_pos.x, scaled_line) + step(grid_scale - cell_pos.x, scaled_line);
    float hline = step(cell_pos.y, scaled_line) + step(grid_scale - cell_pos.y, scaled_line);
    float grid_mask = clamp(vline + hline, 0.0, 1.0);

    col = mix(col, line_color.rgb, grid_mask * line_alpha);

    COLOR = vec4(col, 1.0);
}
