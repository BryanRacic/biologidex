shader_type canvas_item;

// Paper appearance uniforms (same as original paper.gdshader)
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

// -----------------------
// Noise helpers
// -----------------------
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for(int i = 0; i < 4; i++) {
        v += a * value_noise(p);
        p *= 2.05;
        a *= 0.5;
    }
    return v;
}

mat2 rot(float a) {
    float s = sin(a), c = cos(a);
    return mat2(vec2(c, -s), vec2(s, c));
}

void vertex() {
    // Goal: Pass world coordinates to fragment shader for procedural texturing.
    // Without skip_vertex_transform, Godot handles the standard transform chain.
    //
    // MODEL_MATRIX transforms from local to world space.
    // We store world position for procedural texture sampling.
    vec4 world_pos = MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0);
    world_coord = world_pos.xy;

    // Let Godot handle vertex transformation (default behavior)
    // VERTEX stays unchanged - Godot will apply MODEL_MATRIX * CANVAS_MATRIX
}

void fragment() {
    // Use world coordinates from vertex shader
    // This ensures the paper pattern stays fixed in world space
    // and moves in perfect sync with tree nodes
    vec2 px = world_coord;

    // Line width in world units - scales with zoom like real paper
    float scaled_line = line_px;

    // -----------------------
    // Base paper noise
    // -----------------------
    vec2 paper_uv = px / grid_scale;

    float n1 = fbm(paper_uv * paper_noise_scale);
    float n2 = fbm(paper_uv * paper_noise_scale * 2.6);
    float paper_n = (n1 * 0.7 + n2 * 0.3) - 0.5;

    vec3 col = paper_color.rgb + paper_n * paper_noise_amount;

    // -----------------------
    // Speckles: round + size/opacity variance
    // -----------------------
    vec2 sp_uv = paper_uv * speckle_scale * 6.0 * speckle_density;

    float spots_big   = value_noise(sp_uv * 0.55);
    float spots_small = value_noise(sp_uv * 1.8);

    float thresh_var = fbm(sp_uv * 0.25) * 0.18;

    float big_mask   = smoothstep(0.80 + thresh_var, 1.0, spots_big);
    float small_mask = smoothstep(0.84 + thresh_var, 1.0, spots_small);

    float big_opacity   = mix(0.25, 1.0, value_noise(sp_uv * 0.9 + 12.3));
    float small_opacity = mix(0.10, 0.8, value_noise(sp_uv * 2.2 - 7.1));

    float specks =
        big_mask   * big_opacity * 1.0 +
        small_mask * small_opacity * 0.7;

    // -----------------------
    // Fibers: long thin speckles
    // -----------------------
    float ang = fbm(paper_uv * 0.6) * 6.28318;
    vec2 fib_uv = (rot(ang) * paper_uv) * fiber_scale * 10.0;

    fib_uv.x *= 3.5;
    fib_uv.y *= 0.55;

    float fib_noise   = value_noise(fib_uv);
    float fib_mask    = smoothstep(0.78, 1.0, fib_noise);
    float fib_opacity = mix(0.2, 1.0, value_noise(fib_uv * 0.7 + 4.4));

    specks += fib_mask * fib_opacity * 0.9;

    // Apply speckles/fibers (darken)
    col -= specks * speckle_amount;
    col -= fib_mask * fib_opacity * fiber_amount;

    // -----------------------
    // Crisp grid
    // -----------------------
    vec2 cell_pos = mod(px, grid_scale);

    float vline = step(cell_pos.x, scaled_line) + step(grid_scale - cell_pos.x, scaled_line);
    float hline = step(cell_pos.y, scaled_line) + step(grid_scale - cell_pos.y, scaled_line);
    float grid_mask = clamp(vline + hline, 0.0, 1.0);

    col = mix(col, line_color.rgb, grid_mask * line_alpha);

    COLOR = vec4(col, 1.0);
}
