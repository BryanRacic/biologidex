# Dex Feed Overhaul Implementation Plan

## Overview

Transform the dex_feed scene from a traditional ScrollContainer-based list to an interactive, touch-driven vertical carousel that displays one DexRecordImage at a time with smooth drag-to-scroll navigation. Users can drag up/down to navigate between entries, with the next entry sliding into view before the previous one exits.

## Current State Analysis

### Existing dex_feed Implementation
- **Scene structure**: VBoxContainer with ScrollContainer containing FeedContainer (VBoxContainer)
- **Pattern**: Spawns all `feed_list_item` instances at once into FeedContainer
- **Problem**: Poor memory efficiency with large feeds, outdated UX pattern

### Relevant Codebase Patterns to Leverage

1. **BackgroundTouchController** (`features/ui/components/interactive_background/background_touch_controller.gd`)
   - Robust touch/mouse gesture handling with drag threshold detection
   - Inertia support with velocity sampling and exponential decay
   - Position-based tracking for web/iOS compatibility
   - Signals: `scroll_changed`, `scale_changed`, `gesture_started`, `gesture_ended`

2. **TreeRenderer Object Pooling** (`features/tree/tree_renderer.gd`)
   - Pre-allocated pool of `TreeDexImage` nodes (`DEX_IMAGE_POOL_SIZE = 100`)
   - `_get_available_dex_image()` / `deactivate()` pattern for reuse
   - View frustum culling with `_get_view_rect()` for visibility determination

3. **DexRecordImage Component** (`features/ui/components/dex_record_image/`)
   - Proportional sizing system (scales correctly at 80px to 400px+)
   - Unified API: `set_entry_data()`, `load_image_from_entry()`, `image_loaded` signal
   - Supports both bordered and simple display modes

4. **InteractiveBackground** (`features/ui/components/interactive_background/`)
   - Self-contained pan/zoom component
   - Connects TouchController signals to shader for parallax background effect

---

## Architecture Design

### Core Concept: Virtual Vertical Carousel

Instead of rendering all items, maintain a small pool of 3 DexRecordImage instances that are repositioned and recycled as the user scrolls. This is similar to how `TreeRenderer` manages `TreeDexImage` pooling but specialized for 1D vertical navigation.

```
┌─────────────────────────────────────┐
│           Header (fixed)            │
├─────────────────────────────────────┤
│                                     │
│    ┌─────────────────────────┐      │
│    │  DexRecordImage (prev)  │      │  ← Off-screen above (despawned when out of view)
│    └─────────────────────────┘      │
│                                     │
│    ┌─────────────────────────┐      │
│    │  DexRecordImage (curr)  │      │  ← Currently visible (centered)
│    └─────────────────────────┘      │
│                                     │
│    ┌─────────────────────────┐      │
│    │  DexRecordImage (next)  │      │  ← Partially visible when dragging
│    └─────────────────────────┘      │
│                                     │
└─────────────────────────────────────┘
```

### Key Differences from Tree Scene

| Aspect | Tree Scene | New Dex Feed |
|--------|------------|--------------|
| Scroll axis | 2D (pan in any direction) | 1D (vertical only) |
| Zoom | Pinch zoom supported | No zoom (fixed scale) |
| Content | Many small nodes | Few large cards |
| Snap behavior | Free scroll | Snap to item |
| Pool size | 100 images | 3 images |

---

## Component Architecture

### New Files to Create

```
client/biologidex-client/
├── features/
│   └── dex_feed/
│       ├── feed_touch_controller.gd      # Vertical-only touch controller
│       ├── feed_carousel_renderer.gd     # Manages DexRecordImage pool
│       └── feed_data_manager.gd          # Optional: data virtualization
└── scenes/
    └── dex_feed/
        ├── dex_feed.tscn                 # Updated scene structure
        └── dex_feed.gd                   # Updated controller
```

### Scene Tree Structure

```
DexFeed (Node2D)
├── UI (CanvasLayer)
│   ├── InteractiveBackground            # Existing component (optional, for paper effect)
│   ├── Control (full screen container)
│   │   ├── Header (HBoxContainer)
│   │   │   ├── BackButton
│   │   │   ├── StatusLabel
│   │   │   └── FilterControls
│   │   └── ContentArea (Control)        # Gesture capture area
│   │       └── CarouselContainer (Node2D or Control)
│   │           ├── DexRecordImage_0     # Pool slot 0
│   │           ├── DexRecordImage_1     # Pool slot 1
│   │           └── DexRecordImage_2     # Pool slot 2
└── LoadingOverlay
```

---

## Detailed Implementation Plan

### Phase 1: Feed Touch Controller

Create `feed_touch_controller.gd` - a simplified version of `BackgroundTouchController` for vertical-only scrolling.

#### Key Features
- **Vertical-only movement**: Constrain delta to Y axis only
- **Snap-to-item**: After gesture ends, animate to nearest item position
- **Inertia with snap**: Apply inertia, then snap when velocity drops
- **Drag threshold**: Same as existing (10px) to distinguish taps from drags

#### API Design
```gdscript
class_name FeedTouchController
extends Control

signal scroll_changed(offset: float)      # Vertical scroll offset
signal snap_requested(target_index: int)  # Request snap to specific item
signal item_selected(index: int)          # Tap on current item
signal gesture_started()
signal gesture_ended()

# Configuration
@export var item_height: float = 600.0    # Height of each carousel item
@export var snap_threshold: float = 0.3   # % of item height to trigger snap
@export var inertia_decay: float = 5.0
@export var snap_duration: float = 0.3    # Tween duration for snap animation

# State
var scroll_offset: float = 0.0           # Current scroll position (pixels)
var current_index: int = 0               # Current centered item index
var total_items: int = 0                 # Total items in feed

func set_total_items(count: int) -> void
func scroll_to_index(index: int, animated: bool = true) -> void
func get_visible_range() -> Vector2i     # Returns (first_visible, last_visible) indices
```

#### Snap Logic
```gdscript
func _start_snap() -> void:
    # Calculate target index based on current scroll position
    var raw_index := scroll_offset / item_height
    var target_index: int

    if absf(_velocity) > 100.0:
        # Fast swipe: snap in direction of velocity
        target_index = ceili(raw_index) if _velocity > 0 else floori(raw_index)
    else:
        # Slow drag: snap to nearest
        target_index = roundi(raw_index)

    target_index = clampi(target_index, 0, total_items - 1)
    _animate_to_index(target_index)

func _animate_to_index(index: int) -> void:
    var target_offset := float(index) * item_height
    var tween := create_tween()
    tween.tween_property(self, "scroll_offset", target_offset, snap_duration) \
        .set_trans(Tween.TRANS_CUBIC) \
        .set_ease(Tween.EASE_OUT)
    tween.tween_callback(_on_snap_completed.bind(index))
```

### Phase 2: Feed Carousel Renderer

Create `feed_carousel_renderer.gd` to manage the DexRecordImage pool and positioning.

#### Key Features
- **Pool management**: 3 DexRecordImage instances, recycled as needed
- **Visibility culling**: Only configure images that will be visible
- **Smooth transitions**: Images slide in/out based on scroll position
- **Loading states**: Handle async image loading gracefully

#### API Design
```gdscript
class_name FeedCarouselRenderer
extends Node2D

signal image_ready(index: int)
signal image_loading(index: int)
signal item_pressed(entry: Dictionary)

const POOL_SIZE: int = 3
const DEX_RECORD_IMAGE_SCENE = preload("res://features/ui/components/dex_record_image/dex_record_image.tscn")

# Pool
var _image_pool: Array[DexRecordImage] = []
var _active_assignments: Dictionary = {}  # {pool_index: data_index}

# Data
var _entries: Array[Dictionary] = []
var _item_height: float = 600.0
var _visible_height: float = 720.0

func setup(container_height: float, item_height: float) -> void
func set_entries(entries: Array[Dictionary]) -> void
func update_scroll(offset: float) -> void
func get_entry_at_index(index: int) -> Dictionary
```

#### Positioning Logic
```gdscript
func update_scroll(offset: float) -> void:
    _scroll_offset = offset

    # Calculate which indices should be visible
    var center_index := int(offset / _item_height)
    var visible_indices: Array[int] = []

    # We need: previous, current, and next
    for i in range(center_index - 1, center_index + 2):
        if i >= 0 and i < _entries.size():
            visible_indices.append(i)

    # Update pool assignments
    _update_pool_assignments(visible_indices)

    # Position all active images
    for pool_idx in _active_assignments:
        var data_idx: int = _active_assignments[pool_idx]
        var img: DexRecordImage = _image_pool[pool_idx]

        # Calculate Y position relative to scroll
        var target_y := float(data_idx) * _item_height - offset
        # Center in viewport
        target_y += (_visible_height - _item_height) / 2.0

        img.position.y = target_y
        img.visible = true
```

#### Pool Assignment Strategy
```gdscript
func _update_pool_assignments(visible_indices: Array[int]) -> void:
    # Find which pool slots are showing indices we no longer need
    var slots_to_reassign: Array[int] = []
    var indices_needing_slots: Array[int] = visible_indices.duplicate()

    for pool_idx in _active_assignments:
        var current_data_idx: int = _active_assignments[pool_idx]
        if current_data_idx in visible_indices:
            indices_needing_slots.erase(current_data_idx)
        else:
            slots_to_reassign.append(pool_idx)

    # Also include unused pool slots
    for i in range(_image_pool.size()):
        if not _active_assignments.has(i):
            slots_to_reassign.append(i)

    # Assign slots to indices that need them
    for data_idx in indices_needing_slots:
        if slots_to_reassign.is_empty():
            break

        var pool_idx: int = slots_to_reassign.pop_front()
        _assign_entry_to_slot(data_idx, pool_idx)

func _assign_entry_to_slot(data_idx: int, pool_idx: int) -> void:
    var img: DexRecordImage = _image_pool[pool_idx]
    var entry: Dictionary = _entries[data_idx]

    _active_assignments[pool_idx] = data_idx

    # Configure DexRecordImage
    var owner_id: String = entry.get("owner_id", "self")
    img.set_entry_data(entry, owner_id)
    img.load_image_from_entry()
```

### Phase 3: Updated dex_feed.gd Controller

Refactor the main scene controller to orchestrate the new components.

#### State Machine
```
IDLE              → User can interact
SCROLLING         → Active drag gesture
SNAPPING          → Tween animation to target
LOADING           → Initial data load
ERROR             → Display error state
```

#### Key Changes from Current Implementation
1. Replace ScrollContainer/VBoxContainer pattern with FeedCarouselRenderer
2. Connect FeedTouchController signals for gesture handling
3. Maintain feed_entries array but don't spawn all items
4. Add snap-to-item behavior after gestures

#### Updated Flow
```gdscript
func _on_scene_ready() -> void:
    scene_name = "DexFeed"

    _setup_touch_controller()
    _setup_carousel_renderer()
    _connect_sync_signals()
    _initialize_feed()

func _setup_touch_controller() -> void:
    _touch_controller = FeedTouchController.new()
    _touch_controller.scroll_changed.connect(_on_scroll_changed)
    _touch_controller.snap_requested.connect(_on_snap_requested)
    _touch_controller.gesture_ended.connect(_on_gesture_ended)
    _content_area.add_child(_touch_controller)

func _setup_carousel_renderer() -> void:
    _carousel = FeedCarouselRenderer.new()
    _carousel.item_pressed.connect(_on_item_pressed)
    _content_area.add_child(_carousel)

    # Configure sizing
    await get_tree().process_frame
    var viewport_size := get_viewport_rect().size
    var header_height := _header.size.y
    var content_height := viewport_size.y - header_height
    var item_height := content_height * 0.85  # 85% of available height

    _carousel.setup(content_height, item_height)
    _touch_controller.item_height = item_height

func _on_sync_completed(friends_data: Dictionary) -> void:
    # ... existing logic to build feed_entries ...

    # Update carousel with entries
    _carousel.set_entries(feed_entries)
    _touch_controller.set_total_items(feed_entries.size())

    if not feed_entries.is_empty():
        _touch_controller.scroll_to_index(0, false)

func _on_scroll_changed(offset: float) -> void:
    _carousel.update_scroll(offset)

func _on_gesture_ended() -> void:
    # Touch controller handles snap automatically
    pass
```

### Phase 4: Scene Structure Updates

Update `dex_feed.tscn` to reflect new architecture.

#### Removed Nodes
- ScrollContainer
- FeedContainer (VBoxContainer)

#### Added/Modified Nodes
- ContentArea (Control) - gesture capture area
- CarouselContainer (Control) - parent for pooled images

#### Updated Properties
```
[node name="ContentArea" type="Control" parent="UI/Control/VBoxContainer"]
layout_mode = 2
size_flags_vertical = 3
mouse_filter = 0  # STOP - capture all input for gestures
clip_contents = true  # Clip images outside bounds

[node name="CarouselContainer" type="Control" parent="UI/Control/VBoxContainer/ContentArea"]
layout_mode = 1
anchors_preset = 15  # Full rect
mouse_filter = 2  # IGNORE - let parent handle input
```

---

## Technical Considerations

### Memory Efficiency
- **Pool size of 3**: Minimum needed for smooth transitions (prev, current, next)
- **Lazy loading**: Images load only when their slot becomes visible
- **Deferred texture release**: DexRecordImage.clear_texture() when recycled

### Performance Optimizations
1. **Avoid per-frame allocations**: Pre-create all DexRecordImage instances
2. **Batch position updates**: Update all image positions in single update_scroll call
3. **Tween reuse**: Cancel existing tween before starting new snap animation

### Touch Handling Edge Cases
1. **Rapid swipes**: Queue snaps or interrupt with new gesture
2. **Boundary clamping**: Prevent scrolling past first/last item with rubber-band effect
3. **Multi-touch**: Ignore pinch gestures (no zoom in feed view)

### Web/Mobile Compatibility
- Use position-based touch tracking (not index) - matches existing BackgroundTouchController
- 10px drag threshold to distinguish taps from scrolls
- Emulate mouse from touch for button clicks

### Loading States
```gdscript
enum SlotState { EMPTY, LOADING, READY, ERROR }

func _update_slot_state(pool_idx: int, state: SlotState) -> void:
    var img: DexRecordImage = _image_pool[pool_idx]
    match state:
        SlotState.EMPTY:
            img.clear_texture()
            img.visible = false
        SlotState.LOADING:
            img.set_placeholder()
            img.visible = true
        SlotState.READY:
            img.visible = true
        SlotState.ERROR:
            img.set_placeholder(256, Color.RED)
            img.visible = true
```

---

## Testing Checklist

### Functional Tests
- [ ] Single item feed displays correctly
- [ ] Two item feed allows scrolling between items
- [ ] Large feed (100+ items) maintains performance
- [ ] Scroll snaps to nearest item after drag
- [ ] Fast swipe scrolls multiple items
- [ ] Tap on item triggers navigation (not scroll)
- [ ] Filter dropdown filters entries correctly
- [ ] Refresh button reloads data
- [ ] Back button navigates to previous scene

### Performance Tests
- [ ] Memory stable with 100+ entries
- [ ] 60fps maintained during scrolling
- [ ] No jank during image loading
- [ ] Smooth snap animations

### Edge Cases
- [ ] Empty feed shows appropriate message
- [ ] Single-entry feed (no scroll needed)
- [ ] Network error during image load
- [ ] Rapid scroll direction changes
- [ ] Scroll at boundaries (first/last item)

### Platform Tests
- [ ] Desktop mouse + scroll wheel
- [ ] Desktop touchpad gestures
- [ ] Mobile touch (iOS Safari)
- [ ] Mobile touch (Android Chrome)

---

## Migration Strategy

### Phase 1: Parallel Implementation
1. Create new components in `features/dex_feed/`
2. Keep existing `dex_feed.gd` functional
3. Add feature flag to switch between implementations

### Phase 2: Integration
1. Update `dex_feed.tscn` scene structure
2. Migrate `dex_feed.gd` to new architecture
3. Remove old ScrollContainer-based code

### Phase 3: Cleanup
1. Remove `feed_list_item.tscn` and `feed_list_item.gd`
2. Update CLAUDE.md with new architecture notes
3. Remove feature flag

---

## Estimated Complexity

| Component | Lines of Code | Complexity |
|-----------|---------------|------------|
| FeedTouchController | ~200 | Medium |
| FeedCarouselRenderer | ~250 | Medium |
| dex_feed.gd updates | ~150 (net change) | Low |
| dex_feed.tscn updates | - | Low |
| **Total** | ~600 | Medium |

This implementation leverages existing patterns from `BackgroundTouchController` and `TreeRenderer`, reducing the need to solve already-solved problems while creating a polished, memory-efficient carousel experience.

---

## References

- [Godot ScrollContainer Documentation](https://docs.godotengine.org/en/stable/classes/class_scrollcontainer.html)
- [Godot Tween Documentation](https://docs.godotengine.org/en/stable/classes/class_tween.html)
- [SmoothScroll Addon](https://godotengine.org/asset-library/asset/1017)
- [Virtual Scrolling Plugin (scroll_list)](https://echo17.itch.io/scroll-list-godot)
- [Implementing Multi-touch Camera Controls](https://devlog.levi.dev/2022/04/implementing-multi-touch-camera.html)
- [Godot Gesture Proposals](https://github.com/godotengine/godot-proposals/issues/4340)
