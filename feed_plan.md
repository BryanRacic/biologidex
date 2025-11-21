# Dex Feed Implementation Plan

## Executive Summary
This document outlines the comprehensive implementation plan for the BiologiDex feed feature, which displays friends' dex entries in a chronologically-sorted, scrollable feed. The implementation leverages existing multi-user dex infrastructure, image caching with deduplication, and incremental sync mechanisms.

## 1. Architecture Overview

### 1.1 Design Principles
- **Single Source of Truth**: DexDatabase manages all cached dex data
- **Resource Efficiency**: Share cached images across all scenes
- **Progressive Loading**: Use incremental sync with timestamps
- **Separation of Concerns**: Distinct layers for UI, business logic, and data
- **Event-Driven Updates**: Use signals for reactive UI updates
- **Non-Blocking Operations**: Async image loading and network requests

### 1.2 Component Architecture
```
┌─────────────────────────────────────────┐
│              Feed Scene UI              │
│         (dex_feed.gd + feed.tscn)       │
└────────────┬────────────────────────────┘
             │
┌────────────▼────────────────────────────┐
│          FeedController                 │
│   (Business Logic & Orchestration)      │
└────────────┬────────────────────────────┘
             │
┌────────────▼────────────────────────────┐
│     Data Layer (Singletons)             │
│  ┌──────────────┐ ┌─────────────┐       │
│  │ DexDatabase  │ │ SyncManager │       │
│  └──────────────┘ └─────────────┘       │
└────────────┬────────────────────────────┘
             │
┌────────────▼────────────────────────────┐
│         Service Layer                   │
│  ┌──────────────┐ ┌──────────────┐      │
│  │  DexService  │ │SocialService │      │
│  └──────────────┘ └──────────────┘      │
└─────────────────────────────────────────┘
```

## 2. Data Model

### 2.1 Feed Entry Structure
```gdscript
# Combined data from multiple sources
FeedEntry = {
    "dex_entry_id": String,        # UUID of dex entry
    "owner_id": String,            # Friend's user ID
    "owner_username": String,      # Friend's username
    "owner_avatar": String,        # Friend's avatar URL (nullable)
    "creation_index": int,         # Sequential ID in owner's dex
    "animal_id": String,           # Animal UUID
    "scientific_name": String,     # e.g., "Canis lupus"
    "common_name": String,         # e.g., "Gray Wolf"
    "catch_date": String,          # ISO timestamp
    "updated_at": String,          # ISO timestamp (for sorting & cache validation)
    "is_favorite": bool,           # Favorite status
    "cached_image_path": String,   # Local cache path
    "dex_compatible_url": String   # Server URL for image
}
```

### 2.2 Cache Structure
```
user://dex_cache/
├── self/
│   └── {image_hash}.png
├── {friend_uuid_1}/
│   └── {image_hash}.png
├── {friend_uuid_2}/
│   └── {image_hash}.png
└── shared/                    # Future: shared pool for dedup
    └── {image_hash}.png
```

## 3. Implementation Components

### 3.1 Scene Structure

#### 3.1.1 Feed Scene (`dex_feed.tscn`)
```
Control (dex_feed.gd)
└── VBoxContainer
    ├── Header
    │   ├── BackButton
    │   ├── Title ("Feed")
    │   └── RefreshButton
    ├── FilterBar
    │   ├── AllButton (default)
    │   ├── FriendsDropdown
    │   └── DateRangeSelector
    └── ScrollContainer
        └── VBoxContainer (feed_container)
            └── [FeedListItems dynamically added]
```

#### 3.1.2 Feed List Item (`feed_list_item.tscn`)
```
PanelContainer (feed_list_item.gd)
└── MarginContainer
    └── VBoxContainer
        ├── HeaderRow
        │   ├── UserAvatar
        │   ├── UserName
        │   ├── CatchDate
        │   └── FavoriteButton
        ├── ContentRow
        │   ├── DexImage (AspectRatioContainer)
        │   └── InfoPanel
        │       ├── ScientificName
        │       ├── CommonName
        │       └── DexNumber (#XXX)
        └── ActionRow
            ├── ViewInDexButton
            └── ShareButton (future)
```

### 3.2 Core Scripts

#### 3.2.1 `dex_feed.gd` - Main Feed Controller
```gdscript
extends Control

# Constants
const FEED_ITEM_SCENE = preload("res://scenes/dex_feed/components/feed_list_item.tscn")
const BATCH_SIZE = 20  # Items to load at once
const SYNC_INTERVAL_MS = 60000  # Auto-refresh every minute

# State Management
var feed_entries: Array[Dictionary] = []
var displayed_entries: Array[Dictionary] = []
var current_filter: String = "all"
var selected_friend_id: String = ""
var is_loading: bool = false
var sync_queue: Array[String] = []
var friends_data: Dictionary = {}  # user_id -> friend info

# UI References
@onready var feed_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer
@onready var scroll_container: ScrollContainer = $VBoxContainer/ScrollContainer
@onready var refresh_button: Button = $VBoxContainer/Header/RefreshButton
@onready var filter_dropdown: OptionButton = $VBoxContainer/FilterBar/FriendsDropdown
@onready var loading_indicator: Control = $LoadingOverlay

# Signals
signal feed_loaded(entry_count: int)
signal sync_started()
signal sync_completed()
signal entry_favorited(entry_id: String, is_favorite: bool)

func _ready():
    _setup_ui()
    _connect_signals()
    _initialize_feed()

func _initialize_feed():
    # 1. Check login status
    if not TokenManager.is_logged_in():
        NavigationManager.navigate_to("login")
        return

    # 2. Load friends list
    _load_friends_list()

    # 3. Start sync process for friends
    _sync_all_friends()

func _load_friends_list():
    APIManager.social.get_friends(_on_friends_loaded)

func _on_friends_loaded(response: Dictionary, code: int):
    if code != 200:
        print("Failed to load friends: ", response)
        return

    friends_data.clear()
    for friend in response.friends:
        friends_data[friend.id] = {
            "username": friend.username,
            "avatar": friend.get("avatar", ""),
            "friend_code": friend.friend_code
        }

    _populate_filter_dropdown()

func _sync_all_friends():
    sync_queue = friends_data.keys()
    _process_sync_queue()

func _process_sync_queue():
    if sync_queue.is_empty():
        _on_all_syncs_completed()
        return

    var friend_id = sync_queue.pop_front()
    APIManager.dex.sync_user_dex(friend_id, _on_friend_sync_completed.bind(friend_id))

func _on_friend_sync_completed(response: Dictionary, code: int, friend_id: String):
    # Continue with next friend regardless of result
    _process_sync_queue()

func _on_all_syncs_completed():
    _load_feed_entries()
    _display_feed()

func _load_feed_entries():
    feed_entries.clear()

    # Aggregate entries from all friends
    for friend_id in friends_data.keys():
        var friend_entries = DexDatabase.get_all_records_for_user(friend_id)
        for entry in friend_entries:
            var feed_entry = _create_feed_entry(entry, friend_id)
            feed_entries.append(feed_entry)

    # Sort by catch_date/updated_at (newest first)
    feed_entries.sort_custom(_sort_by_date_desc)

func _create_feed_entry(dex_record: Dictionary, owner_id: String) -> Dictionary:
    var friend_info = friends_data.get(owner_id, {})
    return {
        "dex_entry_id": dex_record.get("dex_entry_id", ""),
        "owner_id": owner_id,
        "owner_username": friend_info.get("username", "Unknown"),
        "owner_avatar": friend_info.get("avatar", ""),
        "creation_index": dex_record.creation_index,
        "animal_id": dex_record.get("animal_id", ""),
        "scientific_name": dex_record.scientific_name,
        "common_name": dex_record.common_name,
        "catch_date": dex_record.get("catch_date", dex_record.get("updated_at", "")),
        "updated_at": dex_record.get("updated_at", ""),
        "is_favorite": dex_record.get("is_favorite", false),
        "cached_image_path": dex_record.cached_image_path,
        "dex_compatible_url": dex_record.get("dex_compatible_url", "")
    }

func _sort_by_date_desc(a: Dictionary, b: Dictionary) -> bool:
    var date_a = a.get("updated_at", a.get("catch_date", ""))
    var date_b = b.get("updated_at", b.get("catch_date", ""))
    return date_a > date_b  # Newest first

func _display_feed():
    _clear_feed_display()

    # Apply filters
    displayed_entries = _apply_filters(feed_entries)

    # Display entries
    for entry in displayed_entries:
        _add_feed_item(entry)

    feed_loaded.emit(displayed_entries.size())

func _add_feed_item(entry: Dictionary):
    var item = FEED_ITEM_SCENE.instantiate()
    feed_container.add_child(item)
    item.setup(entry)
    item.favorite_toggled.connect(_on_entry_favorite_toggled)
    item.view_in_dex_pressed.connect(_on_view_in_dex)

func _on_entry_favorite_toggled(entry_id: String, is_favorite: bool):
    # Note: This affects the user's own favorite status for a friend's entry
    APIManager.dex.toggle_favorite(entry_id, _on_favorite_toggled.bind(entry_id))

func _on_view_in_dex(entry: Dictionary):
    # Switch to friend's dex and navigate to specific entry
    NavigationManager.set_context({
        "user_id": entry.owner_id,
        "creation_index": entry.creation_index
    })
    NavigationManager.navigate_to("dex")
```

#### 3.2.2 `feed_list_item.gd` - Individual Feed Entry
```gdscript
extends PanelContainer

# Entry data
var entry_data: Dictionary = {}

# UI References
@onready var user_avatar: TextureRect = $MarginContainer/VBoxContainer/HeaderRow/UserAvatar
@onready var user_name: Label = $MarginContainer/VBoxContainer/HeaderRow/UserName
@onready var catch_date: Label = $MarginContainer/VBoxContainer/HeaderRow/CatchDate
@onready var favorite_button: Button = $MarginContainer/VBoxContainer/HeaderRow/FavoriteButton
@onready var dex_image: TextureRect = $MarginContainer/VBoxContainer/ContentRow/DexImage/TextureRect
@onready var scientific_name: Label = $MarginContainer/VBoxContainer/ContentRow/InfoPanel/ScientificName
@onready var common_name: Label = $MarginContainer/VBoxContainer/ContentRow/InfoPanel/CommonName
@onready var dex_number: Label = $MarginContainer/VBoxContainer/ContentRow/InfoPanel/DexNumber
@onready var view_button: Button = $MarginContainer/VBoxContainer/ActionRow/ViewInDexButton

# Signals
signal favorite_toggled(entry_id: String, is_favorite: bool)
signal view_in_dex_pressed(entry: Dictionary)

func setup(entry: Dictionary):
    entry_data = entry
    _populate_ui()
    _load_image()

func _populate_ui():
    user_name.text = entry_data.owner_username
    catch_date.text = _format_date(entry_data.catch_date)
    scientific_name.text = entry_data.scientific_name
    common_name.text = entry_data.common_name
    dex_number.text = "#%03d" % entry_data.creation_index

    _update_favorite_button(entry_data.is_favorite)

    # Load avatar if available
    if entry_data.owner_avatar and entry_data.owner_avatar != "":
        _load_avatar(entry_data.owner_avatar)

func _load_image():
    var cached_path = entry_data.cached_image_path

    if cached_path and FileAccess.file_exists(cached_path):
        var image = Image.load_from_file(cached_path)
        if image:
            var texture = ImageTexture.create_from_image(image)
            dex_image.texture = texture
    elif entry_data.dex_compatible_url:
        # Trigger download if not cached
        _download_image()

func _download_image():
    var http_request = HTTPRequest.new()
    add_child(http_request)
    http_request.request_completed.connect(_on_image_downloaded.bind(http_request))
    http_request.request(entry_data.dex_compatible_url)

func _on_image_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest):
    http_request.queue_free()

    if response_code == 200:
        # Cache the image
        var cached_path = DexDatabase.cache_image(
            entry_data.dex_compatible_url,
            body,
            entry_data.owner_id
        )

        # Update entry data
        entry_data.cached_image_path = cached_path

        # Display image
        var image = Image.new()
        if image.load_png_from_buffer(body) == OK:
            var texture = ImageTexture.create_from_image(image)
            dex_image.texture = texture

func _format_date(iso_date: String) -> String:
    # Convert ISO date to readable format
    if iso_date == "":
        return "Unknown"

    # Parse and format (simplified version)
    var parts = iso_date.split("T")
    if parts.size() > 0:
        var date_parts = parts[0].split("-")
        if date_parts.size() == 3:
            return "%s/%s/%s" % [date_parts[1], date_parts[2], date_parts[0]]

    return iso_date

func _on_favorite_button_pressed():
    entry_data.is_favorite = not entry_data.is_favorite
    _update_favorite_button(entry_data.is_favorite)
    favorite_toggled.emit(entry_data.dex_entry_id, entry_data.is_favorite)

func _on_view_button_pressed():
    view_in_dex_pressed.emit(entry_data)
```

## 4. Implementation Phases

### Phase 1: Core Feed Infrastructure (2-3 days)
1. **Fix Scene Structure**
   - Create proper `dex_feed.gd` (replace social.gd reference)
   - Create `feed_list_item.gd` (replace friend_list_item.gd reference)
   - Update scene node references and layouts

2. **Basic Feed Loading**
   - Implement friends list loading via SocialService
   - Implement sequential sync of friends' dex entries
   - Create feed entry aggregation from DexDatabase

3. **Feed Display**
   - Implement feed item instantiation and population
   - Add chronological sorting (newest first)
   - Basic scrolling container setup

### Phase 2: Image Management (1-2 days)
1. **Image Loading Pipeline**
   - Implement cached image detection and loading
   - Add async image downloading for missing images
   - Ensure deduplication across users

2. **Update Checking**
   - Implement timestamp-based change detection (updated_at)
   - Add background image update mechanism
   - Handle image refresh on pull-to-refresh

### Phase 3: Advanced Features (2-3 days)
1. **Filtering & Sorting**
   - Friend-specific filtering
   - Date range filtering
   - Animal type filtering (future)

2. **Interactions**
   - Favorite toggling (own favorites on friends' entries)
   - Navigate to friend's dex view
   - Pull-to-refresh functionality

3. **Performance Optimizations**
   - Virtual scrolling for large feeds
   - Lazy loading of images
   - Batch sync optimization

### Phase 4: Polish & Edge Cases (1-2 days)
1. **Error Handling**
   - Network failure recovery
   - Partial sync failure handling
   - Missing image fallbacks

2. **UI Polish**
   - Loading states and progress indicators
   - Empty state messaging
   - Smooth transitions and animations

3. **Testing & Debugging**
   - Multi-user sync verification
   - Image cache validation
   - Performance profiling

## 5. Critical Implementation Details

### 5.1 Sync Strategy
```gdscript
# Optimal sync approach using batch endpoint
func _sync_all_friends_batch():
    var sync_requests = []

    # Add self
    sync_requests.append({
        "user_id": "self",
        "last_sync": SyncManager.get_last_sync(TokenManager.get_user_id())
    })

    # Add all friends
    for friend_id in friends_data.keys():
        sync_requests.append({
            "user_id": friend_id,
            "last_sync": SyncManager.get_last_sync(friend_id)
        })

    # Single batch request
    var body = {"sync_requests": sync_requests}
    APIManager.api_client.post("/dex/entries/batch_sync/", body, _on_batch_sync_completed)
```

### 5.2 Image Caching with Update Detection
```gdscript
func _ensure_image_updated(entry: Dictionary):
    var cached_path = entry.cached_image_path
    var server_updated_at = entry.updated_at

    # Check if image exists
    if not FileAccess.file_exists(cached_path):
        _download_image(entry)
        return

    # Check if local cache is stale using updated_at timestamp
    var local_record = DexDatabase.get_record_for_user(entry.creation_index, entry.owner_id)
    if local_record and local_record.has("updated_at"):
        var local_updated_at = local_record.updated_at
        # If server version is newer, re-download
        if server_updated_at > local_updated_at:
            _download_image(entry)  # Update needed
```

### 5.3 Navigation Integration
```gdscript
# Navigate from feed to specific dex entry
func _on_view_in_dex(entry: Dictionary):
    # Store context for dex scene
    NavigationManager.set_context({
        "user_id": entry.owner_id,
        "creation_index": entry.creation_index,
        "from_feed": true
    })

    # Switch to dex scene
    NavigationManager.navigate_to("dex")

# In dex.gd, handle feed navigation
func _ready():
    var context = NavigationManager.get_context()
    if context.has("from_feed"):
        current_user_id = context.user_id
        DexDatabase.switch_user(current_user_id)
        _navigate_to_index(context.creation_index)
```

## 6. API Integration Points

### 6.1 Required Service Methods
- ✅ `SocialService.get_friends()` - Load friends list
- ✅ `DexService.sync_user_dex(user_id)` - Sync friend's dex
- ✅ `DexService.toggle_favorite(entry_id)` - Toggle favorites
- ✅ `DexDatabase.get_all_records_for_user(user_id)` - Load cached entries
- ✅ `DexDatabase.cache_image()` - Cache downloaded images
- ✅ `SyncManager.get_last_sync(user_id)` - Check sync timestamps
- ✅ `SyncManager.update_last_sync(user_id, timestamp)` - Update sync state

### 6.2 New Endpoints (Optional Future Enhancement)
```python
# Server-side: Dedicated feed endpoint
@api_view(['GET'])
def get_feed(request):
    """
    Aggregated feed endpoint for better performance.
    Returns all friends' recent entries in one request.
    """
    user = request.user
    friends = user.get_friends()

    entries = DexEntry.objects.filter(
        owner__in=friends,
        visibility__in=['friends', 'public']
    ).select_related('animal', 'owner').order_by('-updated_at')[:100]

    serializer = FeedEntrySerializer(entries, many=True)
    return Response({
        'entries': serializer.data,
        'count': len(entries)
    })
```

## 7. Testing Strategy

### 7.1 Unit Tests
- Feed entry sorting logic
- Filter application logic
- Date formatting utilities
- Timestamp-based update detection

### 7.2 Integration Tests
- Multi-friend sync workflow
- Image caching across users
- Navigation between feed and dex
- Favorite toggling synchronization

### 7.3 Performance Tests
- Feed with 100+ entries
- Image loading performance
- Scroll performance
- Memory usage monitoring

### 7.4 Edge Cases
- User with no friends
- Friends with no dex entries
- Network failures during sync
- Corrupt cached images
- Concurrent sync operations
- User logout during sync

## 8. Security Considerations

1. **Permission Enforcement**
   - Server enforces visibility rules (friends/public only)
   - Cannot access private entries of non-friends

2. **Data Isolation**
   - Each user's cache is isolated in separate directories
   - DexDatabase partitions data by user_id

3. **Resource Protection**
   - Image download size limits
   - Sync request rate limiting
   - Cache size management

## 9. Performance Optimizations

### 9.1 Caching Strategy
- **Level 1**: In-memory cache for current session
- **Level 2**: Disk cache in `user://dex_cache/`
- **Level 3**: Server-side caching (5min dex, 2min overview)

### 9.2 Network Efficiency
- Use batch sync endpoint when possible
- Incremental sync with timestamps
- Conditional image downloads based on updated_at timestamps
- HTTP connection pooling via APIClient

### 9.3 UI Responsiveness
- Async image loading
- Virtual scrolling for large feeds
- Progressive feed population
- Debounced filter updates

## 10. Future Enhancements

1. **Real-time Updates**
   - WebSocket integration for live feed updates
   - Push notifications for new entries

2. **Social Features**
   - Comments on feed entries
   - Reactions/likes
   - Share to social media

3. **Advanced Filtering**
   - Search by species
   - Location-based filtering
   - Time-based grouping (today, this week, etc.)

4. **Media Enhancements**
   - Video support
   - Multiple images per entry
   - Image carousel in feed

5. **Offline Support**
   - Queue sync requests when offline
   - Optimistic UI updates
   - Conflict resolution

## 11. Success Metrics

### 11.1 Performance Targets
- Initial feed load: < 2 seconds
- Image display: < 500ms from cache
- Sync completion: < 5 seconds for 10 friends
- Memory usage: < 100MB for 1000 entries

### 11.2 User Experience Goals
- Zero perceived lag when scrolling
- Instant feedback on user actions
- Clear loading states
- Graceful error handling

## Conclusion

This implementation plan provides a robust, scalable foundation for the BiologiDex feed feature. By leveraging existing infrastructure (DexDatabase, SyncManager, DexService) and following established patterns from the dex scene implementation, we can deliver a performant, user-friendly feed that seamlessly integrates with the existing application architecture.

The phased approach ensures incremental value delivery while maintaining system stability. The emphasis on caching, deduplication, and incremental sync ensures optimal resource usage and performance even as the user base and data volume grow.