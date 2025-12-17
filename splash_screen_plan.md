# BiologiDex Custom Splash Screen Implementation Plan

## Overview

This document outlines the implementation plan for a custom splash screen that displays "BiologiDex" with a character-by-character reveal animation tied to loading progress. The splash screen will serve as the new main scene, replacing the current `login.tscn` as the entry point.

### Requirements
- Display "BiologiDex" text matching the home scene styling (Fraunces font, 246px, black)
- Reveal characters progressively based on loading progress (B at 10%, x at 90%)
- Use paper-colored background (`Color(0.96, 0.94, 0.90)`) for visual consistency
- Follow web export best practices (primary deployment target)
- Transition to login scene when loading completes

---

## Table of Contents
1. [Architecture Decision](#1-architecture-decision)
2. [Technical Challenges](#2-technical-challenges)
3. [Design Solution](#3-design-solution)
4. [File Structure](#4-file-structure)
5. [Implementation Steps](#5-implementation-steps)
6. [Testing Strategy](#6-testing-strategy)
7. [Rollback Plan](#7-rollback-plan)
8. [Sources & References](#8-sources--references)

---

## 1. Architecture Decision

### Approach: Custom Splash Scene as Main Scene

Based on research, there are two approaches to splash screens in Godot:

| Approach | Pros | Cons |
|----------|------|------|
| **Boot Splash Image** | Simple, displays during engine init | Static only, no animations, platform inconsistencies |
| **Custom Splash Scene** | Full API access, animations, progress tracking | More complex, requires engine to initialize first |

**Decision: Custom Splash Scene**

Rationale:
- Character-by-character animation requires full GDScript access
- The boot splash `minimum_display_time` setting has [known platform bugs](https://github.com/godotengine/godot/issues/68798) (especially macOS)
- Custom scenes start running during boot splash anyway - animations begin before boot splash ends
- Full control over timing and transitions

### Scene Flow

```
[Engine Boot] → [Boot Splash (blank/brief)] → [splash.tscn] → [login.tscn] → [home.tscn]
                                                    ↓
                                            Load critical resources
                                            while showing animation
```

---

## 2. Technical Challenges

### Challenge 1: ResourceLoader Progress Bug

**Problem:** `ResourceLoader.load_threaded_get_status()` progress array is [known to be broken](https://github.com/godotengine/godot/issues/56882) in Godot 4.x - it always returns `[0]` or `[1]`, never intermediate values.

**Impact:** Cannot rely on actual resource loading progress for character reveal timing.

**Solution:** Hybrid progress tracking (see Section 3.1)

### Challenge 2: Web Export Constraints

**Problems:**
- Single-threaded mode recommended for web compatibility
- ResourceLoader behaves differently on web ([Issue #109914](https://github.com/godotengine/godot/issues/109914))
- Thread support can cause progress stuck at 0 in Firefox ([Issue #101325](https://github.com/godotengine/godot/issues/101325))

**Solution:** Use milestone-based progress with guaranteed minimum timing (see Section 3.2)

### Challenge 3: Autoload Initialization Timing

**Context:** BiologiDex has 8 autoloads that initialize before the main scene:
1. NavigationManager
2. TokenManager
3. APIManager
4. DexDatabase
5. TreeCache
6. SyncManager
7. DexImageLoader
8. FriendDexSyncService

**Consideration:** Autoloads are already ready when splash scene's `_ready()` runs. The splash screen primarily waits for:
- Scene preloading (login.tscn and dependencies)
- Optional: Initial API health check / token validation

---

## 3. Design Solution

### 3.1 Hybrid Progress Tracking

Since ResourceLoader progress is unreliable, use a **milestone-based system** with time-based interpolation:

```
Progress = max(milestone_progress, time_progress)
```

**Milestones (actual loading events):**
| Milestone | Progress | Event |
|-----------|----------|-------|
| 0 | 0% | Splash scene ready |
| 1 | 30% | Login scene load started |
| 2 | 60% | Login scene load complete |
| 3 | 80% | Optional: API health check complete |
| 4 | 100% | Ready to transition |

**Time-based fallback:**
- Minimum 2 second display time
- Progress advances automatically if milestones stall
- Ensures users always see the full animation

### 3.2 Character Reveal Mapping

"BiologiDex" = 10 characters

| Character | Index | Progress Range |
|-----------|-------|----------------|
| B | 0 | 10% |
| i | 1 | 19% |
| o | 2 | 28% |
| l | 3 | 37% |
| o | 4 | 46% |
| g | 5 | 55% |
| i | 6 | 64% |
| D | 7 | 73% |
| e | 8 | 82% |
| x | 9 | 91% (~90%) |

**Formula:**
```gdscript
const PROGRESS_START := 0.10  # B appears at 10%
const PROGRESS_END := 0.90    # x appears at 90%
const TEXT := "BiologiDex"

func _get_visible_characters(progress: float) -> int:
    if progress < PROGRESS_START:
        return 0
    if progress >= PROGRESS_END:
        return TEXT.length()

    var normalized := (progress - PROGRESS_START) / (PROGRESS_END - PROGRESS_START)
    return int(ceil(normalized * TEXT.length()))
```

### 3.3 Animation Approach

**Using `visible_characters` property** (not `visible_ratio`):

Rationale:
- `visible_characters` gives discrete character control
- `visible_ratio` would show partial characters (undesirable)
- Simpler to map progress to character count

**Animation Polish:**
- Each new character appears with a subtle scale/fade effect using Tween
- Optional: Slight horizontal offset animation per character (typewriter feel)

### 3.4 Background Choice: Simple ColorRect (Not PaperCameraScene)

**Why not PaperCameraScene?**

The `paper_camera.gdshader` (187 lines with FBM noise, speckles, fibers, grid lines) requires shader compilation when first rendered. On the Compatibility renderer (used for web), this causes a visible stutter/delay before the background appears - defeating the purpose of a splash screen.

**Solution:** Use a simple `ColorRect` with the paper's base color:

```gdscript
# Matches paper_camera.gdshader uniform
const PAPER_COLOR := Color(0.96, 0.94, 0.90, 1.0)  # Warm off-white
```

**Benefits:**
- Zero shader compilation delay
- Visually consistent with paper theme
- Text appears immediately
- PaperCameraScene shader compiles later on login scene (acceptable)

### 3.5 Web Export Compatibility

Following [CLAUDE.md web export patterns](./CLAUDE.md):

1. **Explicit node paths** - Don't use `%NodeName` lookups
2. **Guard `get_viewport_rect()`** - Check `is_inside_tree()` first
3. **Single-threaded mode** - Already configured in project

---

## 4. File Structure

```
client/biologidex-client/
├── scenes/
│   └── splash/
│       ├── splash.tscn          # Main splash scene
│       └── splash.gd            # Splash controller script
├── features/
│   └── splash/
│       └── splash_progress_tracker.gd  # Progress tracking utility
└── project.godot                # Update main_scene
```

### 4.1 Scene Structure (splash.tscn)

```
Splash (Node2D)
├── Background (ColorRect)           # Simple paper-colored background
│   color = Color(0.96, 0.94, 0.90, 1.0)
│   anchors_preset = 15 (full rect)
└── SplashUILayer (CanvasLayer)      # UI layer
    └── Control (full rect)
        └── CenterContainer
            └── VBoxContainer
                ├── TitleLabel (Label)       # "BiologiDex"
                └── LoadingIndicator (Label) # Optional subtle indicator
```

**Note:** Using ColorRect instead of PaperCameraScene avoids shader compilation delay (see Section 3.4).

---

## 5. Implementation Steps

### Step 1: Create Progress Tracker Utility

**File:** `features/splash/splash_progress_tracker.gd`

```gdscript
class_name SplashProgressTracker
extends RefCounted

signal progress_changed(progress: float)
signal loading_complete

const MIN_DISPLAY_TIME := 2.0  # seconds
const MILESTONE_WEIGHTS := {
    "started": 0.0,
    "login_load_started": 0.30,
    "login_load_complete": 0.60,
    "api_check_complete": 0.80,
    "ready": 1.0
}

var _current_milestone := "started"
var _milestone_progress := 0.0
var _time_elapsed := 0.0
var _time_progress := 0.0
var _is_complete := false

func update(delta: float) -> float:
    if _is_complete:
        return 1.0

    _time_elapsed += delta
    _time_progress = clamp(_time_elapsed / MIN_DISPLAY_TIME, 0.0, 1.0)

    var effective_progress := maxf(_milestone_progress, _time_progress * 0.9)
    progress_changed.emit(effective_progress)

    return effective_progress

func set_milestone(milestone: String) -> void:
    if MILESTONE_WEIGHTS.has(milestone):
        _current_milestone = milestone
        _milestone_progress = MILESTONE_WEIGHTS[milestone]

        if milestone == "ready" and _time_elapsed >= MIN_DISPLAY_TIME:
            _complete()

func _complete() -> void:
    if not _is_complete:
        _is_complete = true
        progress_changed.emit(1.0)
        loading_complete.emit()

func can_complete() -> bool:
    return _time_elapsed >= MIN_DISPLAY_TIME and _milestone_progress >= 1.0
```

### Step 2: Create Splash Scene

**File:** `scenes/splash/splash.tscn`

Key properties to match home.tscn Label:
- Font: `res://resources/fonts/Fraunces/Fraunces-VariableFont_SOFT,WONK,opsz,wght.ttf`
- Font size: 246
- Font color: Color(0, 0, 0, 1)
- Horizontal alignment: CENTER
- Vertical alignment: CENTER

**LabelSettings sub-resource** (matching home.tscn):
```
[sub_resource type="LabelSettings" id="LabelSettings_splash"]
font = ExtResource("font_path")
font_size = 246
font_color = Color(0, 0, 0, 1)
```

### Step 3: Create Splash Controller Script

**File:** `scenes/splash/splash.gd`

```gdscript
extends Node2D

# Splash screen controller
# Displays "BiologiDex" with character-by-character reveal based on loading progress
#
# Background: Uses simple ColorRect with paper color (0.96, 0.94, 0.90) instead of
# PaperCameraScene to avoid shader compilation delay on first render.

const SplashProgressTracker = preload("res://features/splash/splash_progress_tracker.gd")

const TITLE_TEXT := "BiologiDex"
const PROGRESS_START := 0.10  # First character at 10%
const PROGRESS_END := 0.90    # Last character at 90%
const LOGIN_SCENE := "res://scenes/login/login.tscn"

enum State { LOADING, TRANSITIONING, COMPLETE }

var _state: State = State.LOADING
var _progress_tracker: SplashProgressTracker
var _title_label: Label
var _current_visible_chars := 0

# Navigation manager (from autoload)
var navigation_manager


func _ready() -> void:
    print("[Splash] Scene loaded")

    # Initialize node references (explicit paths for web compatibility)
    _title_label = $SplashUILayer/Control/CenterContainer/VBoxContainer/TitleLabel

    # Get navigation manager
    navigation_manager = get_node_or_null("/root/NavigationManager")

    # Setup initial state
    _title_label.text = TITLE_TEXT
    _title_label.visible_characters = 0

    # Initialize progress tracker
    _progress_tracker = SplashProgressTracker.new()
    _progress_tracker.progress_changed.connect(_on_progress_changed)
    _progress_tracker.loading_complete.connect(_on_loading_complete)

    # Start loading login scene
    _start_loading()


func _process(delta: float) -> void:
    if _state == State.LOADING:
        _progress_tracker.update(delta)
        _check_loading_status()


func _start_loading() -> void:
    _progress_tracker.set_milestone("login_load_started")

    # Start async loading of login scene
    var error := ResourceLoader.load_threaded_request(LOGIN_SCENE)
    if error != OK:
        push_error("[Splash] Failed to start loading: %s" % error)
        # Fallback: load synchronously after animation
        _progress_tracker.set_milestone("login_load_complete")


func _check_loading_status() -> void:
    var status := ResourceLoader.load_threaded_get_status(LOGIN_SCENE)

    match status:
        ResourceLoader.THREAD_LOAD_LOADED:
            _progress_tracker.set_milestone("login_load_complete")
            # Skip API check for now, go to ready
            _progress_tracker.set_milestone("ready")
        ResourceLoader.THREAD_LOAD_FAILED:
            push_error("[Splash] Failed to load login scene")
            _progress_tracker.set_milestone("ready")
        ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
            push_error("[Splash] Invalid resource")
            _progress_tracker.set_milestone("ready")


func _on_progress_changed(progress: float) -> void:
    var target_chars := _calculate_visible_characters(progress)

    if target_chars > _current_visible_chars:
        _reveal_character(target_chars)


func _calculate_visible_characters(progress: float) -> int:
    if progress < PROGRESS_START:
        return 0
    if progress >= PROGRESS_END:
        return TITLE_TEXT.length()

    var normalized := (progress - PROGRESS_START) / (PROGRESS_END - PROGRESS_START)
    return int(ceil(normalized * TITLE_TEXT.length()))


func _reveal_character(target_count: int) -> void:
    # Animate to new character count
    var tween := create_tween()
    tween.tween_property(_title_label, "visible_characters", target_count, 0.1)
    _current_visible_chars = target_count


func _on_loading_complete() -> void:
    if _state != State.LOADING:
        return

    _state = State.TRANSITIONING
    print("[Splash] Loading complete, transitioning to login")

    # Ensure all characters visible
    _title_label.visible_characters = TITLE_TEXT.length()

    # Brief pause then transition
    var tween := create_tween()
    tween.tween_interval(0.3)
    tween.tween_callback(_transition_to_login)


func _transition_to_login() -> void:
    _state = State.COMPLETE

    var login_scene = ResourceLoader.load_threaded_get(LOGIN_SCENE)
    if login_scene:
        get_tree().change_scene_to_packed(login_scene)
    else:
        # Fallback to file-based load
        if navigation_manager:
            navigation_manager.navigate_to(LOGIN_SCENE, true)
        else:
            get_tree().change_scene_to_file(LOGIN_SCENE)
```

### Step 4: Update Project Settings

**File:** `project.godot`

```ini
[application]
run/main_scene="res://scenes/splash/splash.tscn"

# Optional: Set boot splash to blank/minimal
boot_splash/show_image=false
# OR use a blank PNG:
# boot_splash/image="res://resources/images/blank_splash.png"
```

### Step 5: Create Scene File

Build `splash.tscn` with this structure:

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scenes/splash/splash.gd" id="1_splash"]
[ext_resource type="FontFile" path="res://resources/fonts/Fraunces/Fraunces-VariableFont_SOFT,WONK,opsz,wght.ttf" id="2_font"]

[sub_resource type="LabelSettings" id="LabelSettings_title"]
font = ExtResource("2_font")
font_size = 246
font_color = Color(0, 0, 0, 1)

[node name="Splash" type="Node2D"]
script = ExtResource("1_splash")

[node name="Background" type="ColorRect" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0.96, 0.94, 0.9, 1)

[node name="SplashUILayer" type="CanvasLayer" parent="."]
layer = 10

[node name="Control" type="Control" parent="SplashUILayer"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2

[node name="CenterContainer" type="CenterContainer" parent="SplashUILayer/Control"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2

[node name="VBoxContainer" type="VBoxContainer" parent="SplashUILayer/Control/CenterContainer"]
layout_mode = 2
mouse_filter = 2
alignment = 1

[node name="TitleLabel" type="Label" parent="SplashUILayer/Control/CenterContainer/VBoxContainer"]
layout_mode = 2
text = "BiologiDex"
label_settings = SubResource("LabelSettings_title")
horizontal_alignment = 1
vertical_alignment = 1
visible_characters = 0
```

**Note:** The `Background` ColorRect uses `Color(0.96, 0.94, 0.9, 1)` which matches the `paper_color` uniform in `paper_camera.gdshader`, providing visual consistency without shader compilation overhead.

---

## 6. Testing Strategy

### 6.1 Unit Tests (Manual Verification)

| Test Case | Expected Result |
|-----------|-----------------|
| Progress at 0% | No characters visible |
| Progress at 10% | "B" visible (1 char) |
| Progress at 50% | "Biolog" visible (6 chars) |
| Progress at 90% | All 10 characters visible |
| Progress at 100% | Transition to login |

### 6.2 Platform Tests

| Platform | Focus Areas |
|----------|-------------|
| **Desktop (Editor)** | Basic functionality, timing |
| **Desktop (Export)** | Export settings, transitions |
| **Web (Chrome)** | WASM loading, progress tracking |
| **Web (Firefox)** | Thread support issues, fallbacks |
| **Web (Safari)** | WebGL compatibility |

### 6.3 Edge Cases

1. **Fast loading** - Verify minimum display time is respected
2. **Slow loading** - Verify time-based progress advances
3. **Load failure** - Verify graceful fallback to direct scene load
4. **Network offline** - Verify splash completes without API check

### 6.4 Performance Metrics

- Splash scene load time: < 100ms
- First character visible: < 500ms from scene ready
- Total splash duration: 2-4 seconds
- Memory usage: Minimal (just font + background shader)

---

## 7. Rollback Plan

If issues arise, rollback is straightforward:

### Immediate Rollback

Change `project.godot`:
```ini
run/main_scene="res://scenes/login/login.tscn"
```

### Files to Remove (if needed)
- `scenes/splash/splash.tscn`
- `scenes/splash/splash.gd`
- `features/splash/splash_progress_tracker.gd`

### Git Commands
```bash
# Revert main_scene change
git checkout -- client/biologidex-client/project.godot

# Or revert entire splash implementation
git revert <commit-hash>
```

---

## 8. Sources & References

### Official Documentation
- [Background loading - Godot Stable Docs](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html)
- [ResourceLoader - Godot Stable Docs](https://docs.godotengine.org/en/stable/classes/class_resourceloader.html)
- [Tween - Godot Stable Docs](https://docs.godotengine.org/en/stable/classes/class_tween.html)
- [Exporting for the Web - Godot Stable Docs](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- [Reducing shader compilation stutter - Godot Stable Docs](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html)

### GitHub Issues (Bug References)
- [ResourceLoader progress always [0] - Issue #56882](https://github.com/godotengine/godot/issues/56882)
- [Progress regression in 4.2.2 - Issue #90076](https://github.com/godotengine/godot/issues/90076)
- [minimum_display_time macOS bug - Issue #68798](https://github.com/godotengine/godot/issues/68798)
- [Web ResourceLoader issues - Issue #109914](https://github.com/godotengine/godot/issues/109914)
- [Firefox thread progress issue - Issue #101325](https://github.com/godotengine/godot/issues/101325)
- [OpenGL shader compilation stutter - Issue #76241](https://github.com/godotengine/godot/issues/76241) (why we avoid custom shaders in splash)
- [Vulkan shader compilation stutter - Issue #61233](https://github.com/godotengine/godot/issues/61233)

### Tutorials & Community
- [Loading Screen in Godot 4 - GoTut](https://www.gotut.net/loading-screen-in-godot-4/)
- [Threaded Loading Tutorial - Hortopan Blog](https://blog.hortopan.com/how-to-speed-up-loading-times-in-your-godot-game-by-using-resourceloader-load_threaded_request/)
- [ResourceLoader Complete Guide - GameDev Academy](https://gamedevacademy.org/resourceloader-in-godot-complete-guide/)
- [Typewriter Effect Options - Godot Forum](https://forum.godotengine.org/t/options-to-do-typewriter-effect-work/62255)
- [Tweening Labels in Godot 4](https://developmentanddinosaurs.co.uk/posts/tweening-labels-in-godot-4/)
- [Text Typing Animation Examples - GitHub](https://github.com/Drentsoft-Games/godot_text_typing_animation)

### Project-Specific
- [BiologiDex CLAUDE.md](./CLAUDE.md) - Web export patterns, PaperCameraScene usage
- [Splash Screen Research](./splash_screen_research.md) - Detailed boot splash analysis

---

## Summary

This implementation plan creates a custom splash screen that:

1. **Displays "BiologiDex"** with the exact styling from the home scene (Fraunces font, 246px, black)
2. **Reveals characters progressively** - B at 10% progress, x at 90% progress
3. **Uses hybrid progress tracking** to work around the ResourceLoader bug
4. **Follows web export best practices** from the existing codebase
5. **Provides graceful fallbacks** for edge cases and platform differences
6. **Uses simple ColorRect background** with paper color (`Color(0.96, 0.94, 0.90)`) to avoid shader compilation delays

**Why ColorRect instead of PaperCameraScene?**
The `paper_camera.gdshader` requires compilation on first render. On the Compatibility renderer (used for web), this would cause a visible stutter before the splash appears - defeating its purpose. The paper shader compiles later on the login scene where a brief delay is more acceptable.

The design prioritizes reliability over complexity, using time-based fallbacks to ensure the animation always completes smoothly regardless of actual loading behavior on different platforms.
