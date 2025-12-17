# Godot 4.5.1 Splash Screen Research

## Table of Contents
1. [Overview](#overview)
2. [Boot Splash vs Custom Splash Scene](#boot-splash-vs-custom-splash-scene)
3. [Project Settings](#project-settings)
4. [What Happens During Boot](#what-happens-during-boot)
5. [Minimum Display Time](#minimum-display-time)
6. [Web Export Considerations](#web-export-considerations)
7. [Platform-Specific Issues](#platform-specific-issues)
8. [Initialization Order](#initialization-order)
9. [Best Practices](#best-practices)
10. [Sources](#sources)

---

## Overview

Godot has **two distinct splash screen mechanisms**:

1. **Boot Splash Image** - A static PNG image displayed during engine initialization
2. **Custom Splash Scene** - A full Godot scene set as your main scene that can include animations, sounds, loading bars, etc.

The boot splash "performs an important function of initializing the application" - it's displayed while the engine sets up core systems. It is **not** a full-fledged splash screen with transitions or sounds; it's just a static image.

---

## Boot Splash vs Custom Splash Scene

### Boot Splash Image (Static)

**What it is:**
- Replaces the static Godot Engine logo with your own PNG image
- Displayed during engine initialization before any GDScript runs
- Very simple to implement (just set an image in project settings)

**Limitations:**
- Static image only - no animations
- No sound or video
- No loading progress indicators
- Limited control over timing and transitions

### Custom Splash Scene (Dynamic) - **Recommended Approach**

**What it is:**
- A full Godot scene set as your `Main Scene` in project settings
- Has full access to the Godot API (animations, sound, video, etc.)
- Can dynamically load game resources while displaying a loading bar
- Transitions to your "actual" main scene when ready

**Implementation:**
1. Create a new scene (e.g., `splash.tscn`) with your splash screen content
2. In **Project Settings → Application → Run → Main Scene**, set your splash scene
3. Optionally set the boot splash image to a blank/black image to hide the Godot logo
4. Use `ResourceLoader.load_threaded_request()` for async background loading
5. When loading completes, transition to your actual main menu scene

**Key Insight:** Custom animated splash screens instanced as main scenes will **start playing during the built-in boot splash**. This means animations begin before the boot splash ends - your custom splash is already running in the background during engine initialization.

---

## Project Settings

All boot splash settings are under **Project Settings → Application → Boot Splash**:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `image` | String (path) | Empty | Path to the PNG image to display. If empty, shows default Godot logo. **Only PNG format is supported.** |
| `show_image` | bool | `true` | Whether to display the boot splash image. If `false`, only shows `bg_color`. |
| `bg_color` | Color | Black | Background color shown behind/around the image. For transparency, set to `Color(0, 0, 0, 0)` (requires `per_pixel_transparency`). |
| `fullsize` | bool | `true` | If true, scales the image to fill the screen (maintaining aspect ratio). |
| `use_filter` | bool | `true` | If true, uses linear filtering when scaling (smooth). If false, uses nearest-neighbor (sharp pixels - good for pixel art). |
| `minimum_display_time` | int | `0` | Minimum time in **milliseconds** to display the splash. See [Minimum Display Time](#minimum-display-time) for caveats. |
| `stretch_mode` | String | Various | Options: "Disabled", "Keep", "Keep Width", "Keep Height", "Cover", "Ignore" |

### Important Notes

- **PNG only**: Using another image format will result in an error
- **Editor splash**: Your custom boot splash image is also used when the Godot editor opens your project
- **Advanced settings**: You may need to enable "Advanced Settings" in Project Settings to see all options

---

## What Happens During Boot

The boot splash is displayed while Godot performs critical engine initialization. Understanding this helps explain boot times.

### Initialization Sequence (main.cpp)

1. **Engine Singleton Setup** - Creates core engine instance
2. **Display Server Creation** - `DisplayServer::create()` initializes the window/display
3. **Boot Logo Loading** - `ImageLoader::load_image()` loads your splash PNG
4. **Rendering Server Setup** - `RenderingServer::get_singleton()->set_boot_image_with_stretch()`
5. **Shader Compilation** - This is the major bottleneck in Godot 4

### Shader Compilation (Major Performance Factor)

**Godot 4 uses GPU-based rendering for the boot splash**, unlike Godot 3.x which used the windowing system. This requires compiling shaders before the splash can display.

| Renderer | Approximate Shaders | Impact |
|----------|--------------------|----|
| Mobile | ~18 shaders | Faster startup |
| Forward+ | ~50+ shaders | Slower startup |

Shaders compiled include:
- ParticlesShader
- CanvasShader
- SceneForwardMobile/SceneForwardClustered
- SDFGI shaders
- Volumetric fog shaders
- Screen-space effects

**Godot 4.5's Shader Baker** (new feature) pre-compiles shaders at **export time**, significantly reducing runtime startup delays. This can make startup times up to 20x faster in some cases.

### Known Issues

- **Window visibility timing**: The main window may appear before GPU initialization completes, creating visual flicker
- **Minimum display time starts early**: The timer includes pre-display initialization time, so slower machines show the splash longer
- **20-60 second freezes**: Some users report significant delays in Godot 4.0 due to shader cache rebuilding (GitHub #74292)

---

## Minimum Display Time

The `minimum_display_time` setting controls the minimum duration the boot splash is shown, in milliseconds.

### How It Works

```cpp
// Simplified from main.cpp
if (elapsed_time < minimum_time) {
    OS::get_singleton()->delay_usec(minimum_time - elapsed_time);
}
```

The delay is applied at the **end of `Main::start()`** after initialization.

### Intended Use

Without this setting, the splash disappears as soon as the engine is loaded (which can be near-instant on fast machines). This allows you to:
- Display studio branding for a consistent duration
- Show legal notices or attributions
- Ensure users see your splash even with fast hardware

### Platform-Specific Issues

**macOS Bug (Issue #68798):**
- The delay executes **before** the window becomes visible
- Result: Screen stays black during the delay, then splash appears briefly before transitioning to main scene
- The minimum display time is effectively invisible to users on macOS

**iOS Compatibility Mode:**
- Boot splash may not show at all with Compatibility renderer
- Works correctly with Vulkan Mobile renderer

**Linux/Windows:**
- Works as expected - splash displays for full minimum duration

### Recommendation

**Don't rely heavily on `minimum_display_time`** for critical content. Instead, use a custom splash scene where you have full control over timing.

---

## Web Export Considerations

Web exports have unique behaviors and limitations for boot splash.

### Export File Structure

Web exports create these files:
- `.wasm` - WebAssembly module (the engine) - ~40MB uncompressed, ~5MB with Brotli
- `.pck` - Your game's packed resources
- `.js` - Startup JavaScript
- `.html` - HTML page that loads everything
- `.png` - Boot splash image (for custom HTML pages)

### Boot Splash in Web Exports

- The boot splash image is exported as `$GODOT_BASENAME.png`
- **Not used by default HTML page** - included for custom HTML templates
- Can be used in `<img>` elements in custom HTML

### Known Issues (Godot 4.3)

**Background Color Bug (GitHub #96874):**
- `bg_color` setting doesn't apply to web exports in Godot 4.3
- Fixed in Godot 4.4 (PR #96625)

**Workaround for 4.3:**
Add CSS in **Project Settings → HTML → Head Include**:
```html
<style>#status { background-color: red; }</style>
```

### Custom HTML Shell

For full control over the web loading experience:
1. Create a custom HTML shell (see Godot docs)
2. Use JavaScript to control loading: `Promise.all([engine.init(myWasm), engine.preloadFile(myPck)])`
3. Display your own loading UI during WASM/PCK loading

### WASM Loading Notes

- **MIME type must be `application/wasm`** for optimizations
- **Can't run locally via file://** - requires a web server
- Use `python -m http.server` for local testing
- Gzip compression highly recommended (WASM compresses to ~25% original size)

---

## Platform-Specific Issues

### Android

**Image Scaling Issues:**
- Boot splash may appear miniaturized (like an icon) even with "Fullsize" enabled
- Only middle 1/4 of image may be shown in some cases
- Scaling issues were addressed in Godot 4.3 (Issue #69317)

**Blank Screen Before Splash:**
- 10-15 second blank screen before boot splash can appear
- This is the Godot engine itself loading/starting up
- Native Android splash screens can help (requires native code modifications)

### iOS

**iOS Launch Screens:**
- iOS apps already have a system launch screen before the app runs
- Having Godot's splash screen after this is often unnecessary
- Compatibility renderer may not show boot splash at all
- Vulkan Mobile works correctly

### macOS

**Minimum Display Time Bug:**
- See [Minimum Display Time](#minimum-display-time) section
- Window remains invisible during delay period

### Windows/Linux

- Generally work as expected
- Pixel art may appear blurry if `use_filter` is true

---

## Initialization Order

Understanding when things load is crucial for splash screen design.

### Complete Startup Sequence

1. **Engine Binary Loads** (pre-boot splash)
2. **Shader Compilation** (major delay in Godot 4)
3. **Boot Splash Image Displayed**
4. **Autoloads Instantiated** (in order listed in Project Settings)
   - `_enter_tree()` called on each
   - `_ready()` called on each
5. **Main Scene Loaded**
   - `_enter_tree()` called
   - `_ready()` called on nodes (children before parents)
6. **Game Loop Begins** (`_process()`, `_physics_process()`)

### Key Insight

**Autoloads are fully ready before your main scene loads.** This means:
- Autoloads can safely set up systems during their `_ready()`
- Your splash scene's `_ready()` can assume all autoloads are initialized
- If using a custom splash scene, you can immediately start loading resources

---

## Best Practices

### Recommended Approach for Production Games

1. **Use a Custom Splash Scene as Main Scene**
   - Full control over timing, animations, and transitions
   - Can display loading progress for actual resource loading
   - Platform-consistent behavior

2. **Set Boot Splash to Blank/Black Image**
   - Prevents Godot logo flash
   - Your splash scene appears immediately after engine init

3. **Use `ResourceLoader.load_threaded_request()` for Background Loading**
   ```gdscript
   func _ready():
       ResourceLoader.load_threaded_request("res://scenes/main_menu.tscn")

   func _process(_delta):
       var progress = []
       var status = ResourceLoader.load_threaded_get_status("res://scenes/main_menu.tscn", progress)
       update_progress_bar(progress[0])

       if status == ResourceLoader.THREAD_LOAD_LOADED:
           var scene = ResourceLoader.load_threaded_get("res://scenes/main_menu.tscn")
           get_tree().change_scene_to_packed(scene)
   ```

4. **Consider Godot 4.5's Shader Baker**
   - Enable pre-compilation at export time
   - Can dramatically reduce startup times (up to 20x faster)

5. **Test on All Target Platforms**
   - Boot splash behavior varies significantly between platforms
   - Web, mobile, and desktop all have quirks

### Things to Avoid

- **Don't rely on `minimum_display_time`** for critical content (platform bugs)
- **Don't assume consistent timing** across platforms
- **Don't use non-PNG images** for boot splash (will error)
- **Don't put critical loading in autoloads that block startup** - use async loading instead

---

## Sources

### Official Documentation
- [Splash screen - Godot 3.3 Docs](https://docs.godotengine.org/en/3.3/getting_started/step_by_step/splash_screen.html)
- [Background loading - Godot Stable Docs](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html)
- [Singletons (Autoload) - Godot 4.5 Docs](https://docs.godotengine.org/en/4.5/tutorials/scripting/singletons_autoload.html)
- [Reducing shader compilation stutter - Godot Stable Docs](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html)
- [Exporting for the Web - Godot Stable Docs](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- [Custom HTML page for Web export](https://trinovantes.github.io/godot-docs/tutorials/platform/web/customizing_html5_shell.html)

### GitHub Issues & PRs
- [Boot Splash slow in Godot 4 beta - Issue #71350](https://github.com/godotengine/godot/issues/71350)
- [Splash screen minimum display time macOS bug - Issue #68798](https://github.com/godotengine/godot/issues/68798)
- [Minimum display time feature request - Issue #8867](https://github.com/godotengine/godot/issues/8867)
- [Boot splash bg_color not honored - Issue #88881](https://github.com/godotengine/godot/issues/88881)
- [Web export bg_color issue - Issue #96874](https://github.com/godotengine/godot/issues/96874)
- [Android blank screen before splash - Forum Discussion](https://godotforums.org/d/42159-android-10-15s-blank-screen-before-boot-splash-need-native-loading-screen)
- [Add splash screen tutorial - Docs Issue #392](https://github.com/godotengine/godot-docs/issues/392)
- [Slow startup from shader cache - Issue #74292](https://github.com/godotengine/godot/issues/74292)
- [Android boot splash scaling - Issue #69317](https://github.com/godotengine/godot/issues/69317)
- [Pixel art boot splash blurry - Issue #19415](https://github.com/godotengine/godot/issues/19415)
- [main.cpp source code](https://github.com/godotengine/godot/blob/master/main/main.cpp)

### Release Notes & Articles
- [Godot 4.5 Beta 1 Release](https://godotengine.org/article/dev-snapshot-godot-4-5-beta-1/)
- [Web Export in 4.3 Progress Report](https://godotengine.org/article/progress-report-web-export-in-4-3/)
- [Godot Interactive Changelog](https://godotengine.github.io/godot-interactive-changelog/)

### Community Resources
- [godot-awesome-splash plugin](https://github.com/duongvituan/godot-awesome-splash)
- [SplashScreenWizard plugin](https://github.com/ThePat02/SplashScreenWizard)
- [Building a splash screen in Godot Engine (CyberGlads)](https://cyberglads.com/making-cyberglads-5-splash-screen.html)
- [Loading Screen in Godot 4 Tutorial](https://www.gotut.net/loading-screen-in-godot-4/)

---

## Summary

**Key Takeaway:** The boot splash is just a static image shown during engine initialization. For production games, you should use a **custom splash scene as your main scene**, which gives you full control over the splash experience and allows async resource loading. Set the boot splash image to a blank/black PNG to avoid the Godot logo flash.

**For BiologiDex specifically:** Given the web-primary target and existing architecture with multiple autoload singletons, a custom splash scene would integrate well. The splash scene can:
1. Show your branded loading animation
2. Initialize API connections during the splash
3. Perform any required sync operations
4. Transition smoothly to the login/home scene when ready

The boot splash `minimum_display_time` setting is unreliable across platforms (especially macOS and web), so don't depend on it for consistent behavior.
