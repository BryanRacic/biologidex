# Export Templates

Custom templates for Godot web export.

## custom_html_shell.html

A custom HTML shell for web exports that fixes high DPI scaling issues on retina displays, high-resolution mobile devices, and MacBook Pros.

### Why This Exists

Godot's default web export has known issues with high DPI displays ([GitHub #93106](https://github.com/godotengine/godot/issues/93106)):
- Canvas renders at logical pixels instead of physical pixels
- Double-scaling occurs when both Godot and the browser try to handle DPI
- UI appears tiny on retina/high-DPI screens

### What It Fixes

1. **Viewport meta**: Adds `maximum-scale=1.0`, `user-scalable=no`, `viewport-fit=cover`
2. **Canvas sizing**: Uses `width: 100%; height: 100%` to fill the viewport properly
3. **Safe area support**: Handles notched devices (iPhone, etc.) with `env(safe-area-inset-*)`
4. **Mobile UX**: Prevents pull-to-refresh with `overscroll-behavior: none`

### Required Project Settings

These settings in `project.godot` work together with this HTML shell:

```ini
[display]
window/stretch/mode="canvas_items"    # Scales UI elements properly
window/dpi/allow_hidpi=true           # Enables DPI awareness

[gui]
theme/default_font_multichannel_signed_distance_field=true  # Crisp fonts
theme/default_font_generate_mipmaps=true                    # Font mipmaps
```

### Required Export Settings

In `export_presets.cfg`:

```ini
html/custom_html_shell="res://export_templates/custom_html_shell.html"
html/canvas_resize_policy=1    # "Project" policy - respects project resolution
```

### Template Variables

The shell uses Godot's template placeholders (replaced during export):
- `$GODOT_PROJECT_NAME` - Project name for `<title>`
- `$GODOT_URL` - Main JavaScript file
- `$GODOT_CONFIG` - Engine configuration JSON
- `$GODOT_THREADS_ENABLED` - Threading support flag
- `$GODOT_SPLASH` / `$GODOT_SPLASH_CLASSES` - Splash screen
- `$GODOT_HEAD_INCLUDE` - Custom head content from export settings

### Adding Custom Meta Tags

To add PWA theme color or other meta tags, use the export settings' "Html / Head Include" option:

```html
<meta name="theme-color" content="#242424">
```

### References

- [Godot Custom HTML Shell Docs](https://docs.godotengine.org/en/stable/tutorials/platform/web/customizing_html5_shell.html)
- [Godot Multiple Resolutions](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html)
- [Chickensoft Display Scaling Guide](https://chickensoft.games/blog/display-scaling)
