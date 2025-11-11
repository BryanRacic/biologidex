# BiologiDex - Dex System Overhaul Implementation Plan

## Executive Summary

This document provides a comprehensive implementation plan for overhauling the BiologiDex "dex" system to support multi-user viewing, efficient synchronization, and future extensibility. The plan follows software architecture best practices with clear separation of concerns, progressive enhancement, and backwards compatibility.

## Current State Assessment

### Strengths (What We Have)
- **Backend**: Solid Django models (DexEntry, Animal), sync endpoint with checksums, dex-compatible image processing
- **Frontend**: Local storage (DexDatabase), gallery UI, image caching
- **API**: Authentication, basic CRUD operations, image upload pipeline

### Gaps (What We Need)
1. **Multi-User Support**: Can only view own dex, not friends'
2. **Efficient Sync**: No incremental sync tracking, re-downloads everything
3. **Data Architecture**: Single-user local storage model
4. **API Completeness**: Missing friend dex endpoints
5. **State Management**: No sync state persistence

## Architecture Design Principles

### 1. Data Ownership & Privacy
- Users own their dex entries
- Visibility controls (private/friends/public) enforced at API level
- Local caching respects privacy settings
- Friend relationships define access boundaries

### 2. Sync Strategy
- **Incremental Sync**: Only download changed entries
- **Checksums**: Detect image changes via SHA256
- **Timestamps**: Track last_sync per user/friend
- **Conflict Resolution**: Server is source of truth
- **Offline First**: Local data remains usable without network

### 3. Storage Architecture
- **User Partitioning**: Separate storage per user (own + friends)
- **Image Deduplication**: Share images across users when identical
- **Cache Management**: LRU eviction, size limits
- **Metadata Separation**: Store sync state separately from content

### 4. API Design
- **RESTful**: Consistent resource-based endpoints
- **Pagination**: Handle large collections efficiently
- **Filtering**: Support query parameters for optimization
- **Versioning**: Maintain backwards compatibility

## Implementation Phases

### Phase 1: Foundation Fixes 
**Goal**: Fix critical bugs and establish sync tracking

#### 1.1 Fix Sync Response Format Bug
```gdscript
# File: client/biologidex-client/api/services/dex_service.gd:171
# Change from:
if response.has("results"):
    var entries = response["results"]
# To:
if response.has("entries"):
    var entries = response["entries"]
```

#### 1.2 Implement Sync State Manager
Create new singleton for managing sync timestamps:

```gdscript
# client/biologidex-client/sync_manager.gd
extends Node

const SYNC_STATE_FILE = "user://sync_state.json"

var sync_timestamps: Dictionary = {}  # user_id -> ISO timestamp

func _ready():
    load_sync_state()

func get_last_sync(user_id: String = "self") -> String:
    return sync_timestamps.get(user_id, "")

func update_last_sync(user_id: String = "self", timestamp: String = ""):
    if timestamp.is_empty():
        timestamp = Time.get_datetime_string_from_system()
    sync_timestamps[user_id] = timestamp
    save_sync_state()

func save_sync_state():
    var file = FileAccess.open(SYNC_STATE_FILE, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(sync_timestamps))
        file.close()

func load_sync_state():
    if FileAccess.file_exists(SYNC_STATE_FILE):
        var file = FileAccess.open(SYNC_STATE_FILE, FileAccess.READ)
        if file:
            var json_string = file.get_as_text()
            file.close()
            var json = JSON.new()
            if json.parse(json_string) == OK:
                sync_timestamps = json.data
```

#### 1.3 Update Project Settings
Add SyncManager to autoload:
```ini
# client/biologidex-client/project.godot
[autoload]
SyncManager="*res://sync_manager.gd"
```

### Phase 2: Multi-User Data Architecture 
**Goal**: Refactor storage to support multiple users' dex data

#### 2.1 Refactor DexDatabase for Multi-User Support
```gdscript
# client/biologidex-client/dex_database_v2.gd
extends Node

const DATABASE_VERSION = "2.0"
const DATABASE_DIR = "user://dex_data/"
const CACHE_DIR = "user://dex_cache/"

# Structure: {user_id: {creation_index: record}}
var dex_data: Dictionary = {}
var current_user_id: String = "self"

func _ready():
    ensure_directories()
    migrate_from_v1()
    load_all_databases()

func ensure_directories():
    var dir = DirAccess.open("user://")
    if not dir.dir_exists(DATABASE_DIR):
        dir.make_dir(DATABASE_DIR)
    if not dir.dir_exists(CACHE_DIR):
        dir.make_dir(CACHE_DIR)

func get_database_path(user_id: String) -> String:
    return DATABASE_DIR + user_id + "_dex.json"

func get_cache_dir(user_id: String) -> String:
    return CACHE_DIR + user_id + "/"

func add_record(record: Dictionary, user_id: String = "self"):
    if not dex_data.has(user_id):
        dex_data[user_id] = {}

    var creation_index = record.get("creation_index", -1)
    dex_data[user_id][creation_index] = record
    save_database(user_id)
    record_added.emit(record, user_id)

func get_record(creation_index: int, user_id: String = "self") -> Dictionary:
    if dex_data.has(user_id) and dex_data[user_id].has(creation_index):
        return dex_data[user_id][creation_index]
    return {}

func get_all_records(user_id: String = "self") -> Array:
    if not dex_data.has(user_id):
        return []
    return dex_data[user_id].values()

func save_database(user_id: String):
    var file_path = get_database_path(user_id)
    var file = FileAccess.open(file_path, FileAccess.WRITE)
    if file:
        var data = {
            "version": DATABASE_VERSION,
            "user_id": user_id,
            "records": dex_data.get(user_id, {}),
            "last_updated": Time.get_datetime_string_from_system()
        }
        file.store_string(JSON.stringify(data))
        file.close()

func load_database(user_id: String):
    var file_path = get_database_path(user_id)
    if FileAccess.file_exists(file_path):
        var file = FileAccess.open(file_path, FileAccess.READ)
        if file:
            var json_string = file.get_as_text()
            file.close()
            var json = JSON.new()
            if json.parse(json_string) == OK:
                var data = json.data
                if data.has("records"):
                    dex_data[user_id] = data["records"]

signal record_added(record: Dictionary, user_id: String)
signal database_switched(user_id: String)
```

#### 2.2 Image Cache Management
```gdscript
# Extension to dex_database_v2.gd
func cache_image(image_url: String, image_data: PackedByteArray, user_id: String = "self") -> String:
    var cache_dir = get_cache_dir(user_id)
    ensure_directory(cache_dir)

    # Use URL hash for filename
    var hash = image_url.sha256_text()
    var file_path = cache_dir + hash + ".png"

    # Check for existing shared image
    var shared_path = check_shared_image(hash)
    if shared_path:
        return shared_path

    # Save new image
    var file = FileAccess.open(file_path, FileAccess.WRITE)
    if file:
        file.store_buffer(image_data)
        file.close()

    return file_path

func check_shared_image(hash: String) -> String:
    # Check if image exists in any user's cache
    var dir = DirAccess.open(CACHE_DIR)
    if dir:
        dir.list_dir_begin()
        var user_dir = dir.get_next()
        while user_dir != "":
            if dir.current_is_dir():
                var image_path = CACHE_DIR + user_dir + "/" + hash + ".png"
                if FileAccess.file_exists(image_path):
                    return image_path
            user_dir = dir.get_next()
    return ""
```

### Phase 3: Backend API Extensions 
**Goal**: Add friend dex viewing endpoints and optimize sync

#### 3.1 Friend Dex Endpoint
```python
# server/dex/views.py
from rest_framework.decorators import action
from social.models import Friendship

class DexEntryViewSet(viewsets.ModelViewSet):
    # ... existing code ...

    @action(detail=False, methods=['get'], url_path='user/(?P<user_id>[^/.]+)/entries')
    def user_entries(self, request, user_id=None):
        """Get dex entries for a specific user (if friends or public)"""
        try:
            target_user = User.objects.get(id=user_id)
        except User.DoesNotExist:
            return Response({'error': 'User not found'}, status=404)

        # Check permissions
        if target_user == request.user:
            # Own entries
            visibility_filter = Q()
        elif Friendship.are_friends(request.user, target_user):
            # Friend's entries (friends or public)
            visibility_filter = Q(visibility__in=['friends', 'public'])
        else:
            # Stranger's entries (public only)
            visibility_filter = Q(visibility='public')

        entries = DexEntry.objects.filter(
            user=target_user
        ).filter(visibility_filter).select_related(
            'animal', 'source_vision_job'
        ).order_by('animal__creation_index')

        # Support incremental sync
        last_sync = request.query_params.get('last_sync')
        if last_sync:
            try:
                sync_datetime = datetime.fromisoformat(last_sync)
                entries = entries.filter(updated_at__gt=sync_datetime)
            except (ValueError, TypeError):
                pass

        serializer = DexEntrySyncSerializer(entries, many=True)
        return Response({
            'entries': serializer.data,
            'server_time': timezone.now().isoformat(),
            'user_id': str(target_user.id),
            'total_count': entries.count()
        })

    @action(detail=False, methods=['get'])
    def friends_overview(self, request):
        """Get summary of all friends' dex for discovery"""
        friends = Friendship.get_friends(request.user)

        overview = []
        for friend in friends:
            entry_count = DexEntry.objects.filter(
                user=friend,
                visibility__in=['friends', 'public']
            ).count()

            latest_entry = DexEntry.objects.filter(
                user=friend,
                visibility__in=['friends', 'public']
            ).order_by('-created_at').first()

            overview.append({
                'user_id': str(friend.id),
                'username': friend.username,
                'friend_code': friend.friend_code,
                'total_entries': entry_count,
                'latest_update': latest_entry.updated_at.isoformat() if latest_entry else None
            })

        return Response({'friends': overview})
```

#### 3.2 Batch Sync Endpoint
```python
# server/dex/views.py
@action(detail=False, methods=['post'])
def batch_sync(self, request):
    """Sync multiple users' dex in one request"""
    sync_requests = request.data.get('sync_requests', [])

    results = {}
    for sync_req in sync_requests:
        user_id = sync_req.get('user_id', 'self')
        last_sync = sync_req.get('last_sync')

        if user_id == 'self':
            target_user = request.user
        else:
            try:
                target_user = User.objects.get(id=user_id)
                # Check permissions
                if not Friendship.are_friends(request.user, target_user):
                    results[user_id] = {'error': 'Not friends'}
                    continue
            except User.DoesNotExist:
                results[user_id] = {'error': 'User not found'}
                continue

        # Get entries
        entries = self._get_sync_entries(target_user, request.user, last_sync)
        results[user_id] = {
            'entries': DexEntrySyncSerializer(entries, many=True).data,
            'count': entries.count()
        }

    return Response({
        'results': results,
        'server_time': timezone.now().isoformat()
    })
```

### Phase 4: Frontend Sync Implementation 
**Goal**: Implement comprehensive sync logic with progress tracking

#### 4.1 Enhanced Dex Service
```gdscript
# client/biologidex-client/api/services/dex_service.gd
extends BaseService

signal sync_started(user_id: String)
signal sync_progress(user_id: String, current: int, total: int)
signal sync_completed(user_id: String, entries_updated: int)
signal sync_failed(user_id: String, error: String)

func sync_user_dex(user_id: String = "self", callback: Callable = Callable()):
    sync_started.emit(user_id)

    # Get last sync timestamp
    var last_sync = SyncManager.get_last_sync(user_id)

    # Determine endpoint
    var endpoint = ""
    if user_id == "self":
        endpoint = "/dex/entries/sync_entries/"
    else:
        endpoint = "/dex/entries/user/" + user_id + "/entries/"

    # Build request
    var params = {}
    if not last_sync.is_empty():
        params["last_sync"] = last_sync

    # Make request
    _make_request(
        endpoint,
        HTTPClient.METHOD_GET,
        params,
        _handle_sync_response.bind(user_id, callback)
    )

func _handle_sync_response(response: Dictionary, code: int, user_id: String, callback: Callable):
    if code != 200:
        sync_failed.emit(user_id, "Failed to fetch entries")
        if callback:
            callback.call(null, code)
        return

    var entries = response.get("entries", [])
    var server_time = response.get("server_time", "")

    if entries.is_empty():
        sync_completed.emit(user_id, 0)
        SyncManager.update_last_sync(user_id, server_time)
        if callback:
            callback.call(response, code)
        return

    # Process entries with progress
    _process_sync_entries(entries, user_id, server_time, callback)

func _process_sync_entries(entries: Array, user_id: String, server_time: String, callback: Callable):
    var total = entries.size()
    var processed = 0

    for entry in entries:
        # Update local database
        DexDatabase.add_record({
            "creation_index": entry.get("creation_index"),
            "scientific_name": entry.get("scientific_name"),
            "common_name": entry.get("common_name"),
            "image_checksum": entry.get("image_checksum"),
            "dex_compatible_url": entry.get("dex_compatible_url"),
            "updated_at": entry.get("updated_at")
        }, user_id)

        # Download image if needed
        var local_image = DexDatabase.get_cached_image_path(
            entry.get("creation_index"),
            user_id
        )

        if not FileAccess.file_exists(local_image) or _needs_image_update(entry, user_id):
            _download_dex_image(entry.get("dex_compatible_url"), entry, user_id)

        processed += 1
        sync_progress.emit(user_id, processed, total)

    # Update sync timestamp
    SyncManager.update_last_sync(user_id, server_time)
    sync_completed.emit(user_id, total)

    if callback:
        callback.call({"entries": entries, "count": total}, 200)

func sync_all_friends(callback: Callable = Callable()):
    """Sync own dex and all friends' dex"""
    # First get friends overview
    _make_request(
        "/dex/entries/friends_overview/",
        HTTPClient.METHOD_GET,
        {},
        _handle_friends_overview.bind(callback)
    )

func _handle_friends_overview(response: Dictionary, code: int, callback: Callable):
    if code != 200:
        return

    var friends = response.get("friends", [])

    # Build batch sync request
    var sync_requests = [{"user_id": "self", "last_sync": SyncManager.get_last_sync("self")}]

    for friend in friends:
        var friend_id = friend.get("user_id")
        sync_requests.append({
            "user_id": friend_id,
            "last_sync": SyncManager.get_last_sync(friend_id)
        })

    # Execute batch sync
    _make_request(
        "/dex/entries/batch_sync/",
        HTTPClient.METHOD_POST,
        {"sync_requests": sync_requests},
        callback
    )
```

#### 4.2 Updated Dex Gallery UI
```gdscript
# client/biologidex-client/dex.gd
extends Control

@onready var user_selector: OptionButton = $UserSelector
@onready var sync_button: Button = $SyncButton
@onready var sync_progress: ProgressBar = $SyncProgress
@onready var record_display: Control = $RecordDisplay

var current_viewing_user: String = "self"
var is_syncing: bool = false

func _ready():
    setup_ui()
    connect_signals()
    populate_user_selector()
    load_current_user_dex()

func setup_ui():
    sync_progress.visible = false
    sync_button.text = "Sync"

func connect_signals():
    APIManager.dex.sync_started.connect(_on_sync_started)
    APIManager.dex.sync_progress.connect(_on_sync_progress)
    APIManager.dex.sync_completed.connect(_on_sync_completed)
    APIManager.dex.sync_failed.connect(_on_sync_failed)

    user_selector.item_selected.connect(_on_user_selected)
    sync_button.pressed.connect(_on_sync_pressed)

func populate_user_selector():
    user_selector.clear()
    user_selector.add_item("My Dex", 0)
    user_selector.set_item_metadata(0, "self")

    # Add friends
    var friends = DexDatabase.get_cached_friends()
    for i in range(friends.size()):
        var friend = friends[i]
        user_selector.add_item(friend.get("username", "Friend"), i + 1)
        user_selector.set_item_metadata(i + 1, friend.get("user_id"))

func _on_user_selected(index: int):
    current_viewing_user = user_selector.get_item_metadata(index)
    load_current_user_dex()

func load_current_user_dex():
    var records = DexDatabase.get_all_records(current_viewing_user)
    display_records(records)

func _on_sync_pressed():
    if is_syncing:
        return

    if current_viewing_user == "self":
        APIManager.dex.sync_user_dex("self", _on_sync_callback)
    else:
        APIManager.dex.sync_user_dex(current_viewing_user, _on_sync_callback)

func _on_sync_started(user_id: String):
    if user_id == current_viewing_user:
        is_syncing = true
        sync_button.disabled = true
        sync_progress.visible = true
        sync_progress.value = 0

func _on_sync_progress(user_id: String, current: int, total: int):
    if user_id == current_viewing_user:
        sync_progress.max_value = total
        sync_progress.value = current

func _on_sync_completed(user_id: String, entries_updated: int):
    if user_id == current_viewing_user:
        is_syncing = false
        sync_button.disabled = false
        sync_progress.visible = false
        load_current_user_dex()

        if entries_updated > 0:
            show_message("Updated %d entries" % entries_updated)

func _on_sync_failed(user_id: String, error: String):
    if user_id == current_viewing_user:
        is_syncing = false
        sync_button.disabled = false
        sync_progress.visible = false
        show_error(error)
```

### Phase 5: Performance & Polish 
**Goal**: Optimize performance and handle edge cases

#### 5.1 Performance Optimizations

**Database Indexing**:
```python
# server/dex/models.py
class DexEntry(models.Model):
    class Meta:
        indexes = [
            models.Index(fields=['user', 'animal__creation_index']),
            models.Index(fields=['user', 'updated_at']),
            models.Index(fields=['visibility', 'updated_at']),
        ]
```

**Caching Strategy**:
```python
# server/dex/views.py
from django.core.cache import cache

def get_user_dex_cache_key(user_id, last_sync=None):
    if last_sync:
        return f"dex:user:{user_id}:since:{last_sync}"
    return f"dex:user:{user_id}:all"

@action(detail=False, methods=['get'])
def sync_entries(self, request):
    last_sync = request.query_params.get('last_sync')
    cache_key = get_user_dex_cache_key(request.user.id, last_sync)

    # Try cache first
    cached = cache.get(cache_key)
    if cached:
        return Response(cached)

    # Generate response
    response_data = self._generate_sync_response(request.user, last_sync)

    # Cache for 5 minutes
    cache.set(cache_key, response_data, 300)

    return Response(response_data)
```

**Client-Side Optimizations**:
```gdscript
# Lazy loading for large collections
func load_dex_page(page: int = 0, page_size: int = 20):
    var all_records = DexDatabase.get_all_records(current_viewing_user)
    var start_idx = page * page_size
    var end_idx = min(start_idx + page_size, all_records.size())

    var page_records = all_records.slice(start_idx, end_idx)
    display_records(page_records)

    # Preload next page images in background
    if end_idx < all_records.size():
        preload_next_page(page + 1, page_size)
```

#### 5.2 Error Handling & Recovery

```gdscript
# Retry logic with exponential backoff
func sync_with_retry(user_id: String, max_retries: int = 3):
    var retry_count = 0
    var backoff_ms = 1000

    while retry_count < max_retries:
        var result = await sync_user_dex(user_id)
        if result.success:
            return result

        retry_count += 1
        await get_tree().create_timer(backoff_ms / 1000.0).timeout
        backoff_ms *= 2

    sync_failed.emit(user_id, "Max retries exceeded")
```

#### 5.3 Migration Support

```gdscript
# Migrate from v1 single-user database
func migrate_from_v1():
    var old_db_path = "user://dex_database.json"
    if FileAccess.file_exists(old_db_path):
        print("Migrating from v1 database...")
        var file = FileAccess.open(old_db_path, FileAccess.READ)
        if file:
            var json_string = file.get_as_text()
            file.close()
            var json = JSON.new()
            if json.parse(json_string) == OK:
                var old_records = json.data.get("records", [])
                for record in old_records:
                    add_record(record, "self")

                # Rename old file
                DirAccess.rename_absolute(old_db_path, old_db_path + ".v1.backup")
                print("Migration complete. Backup saved.")
```

## Testing Strategy

### Unit Tests
- DexDatabase CRUD operations
- Sync timestamp management
- Image cache deduplication
- API response parsing

### Integration Tests
- End-to-end sync flow
- Friend permissions
- Incremental sync accuracy
- Error recovery

### Performance Tests
- Load 10,000 entries
- Sync 100 friends
- Image cache with 1GB data
- Network interruption handling

## Security Considerations

### API Security
- Validate user permissions on every request
- Rate limit sync endpoints (10 req/min)
- Sanitize user inputs
- Use HTTPS for all communication

### Local Storage Security
- Don't store sensitive data in plain text
- Clear cache on logout
- Validate image checksums
- Limit cache size to prevent DoS

## Future Additions Implementation

### 1. Image Replacement Feature
**Requirements**: Allow users to replace dex entry images with any photo of that animal

**Implementation**:
```python
# server/dex/models.py
class DexEntryImage(models.Model):
    """Additional images for a dex entry"""
    dex_entry = models.ForeignKey(DexEntry, on_delete=models.CASCADE)
    image = models.ImageField(upload_to='dex/alternate/')
    is_primary = models.BooleanField(default=False)
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-is_primary', '-uploaded_at']

# server/dex/views.py
@action(detail=True, methods=['post'])
def add_alternate_image(self, request, pk=None):
    entry = self.get_object()
    # ... handle image upload
    # ... optionally set as primary
```

### 2. Collaborative Dex Collections
**Requirements**: Shared collections combining entries from multiple users

**Implementation**:
```python
# server/dex/models.py
class DexCollection(models.Model):
    name = models.CharField(max_length=100)
    description = models.TextField(blank=True)
    owner = models.ForeignKey(User, on_delete=models.CASCADE)
    collaborators = models.ManyToManyField(User, related_name='shared_collections')
    is_public = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

class CollectionEntry(models.Model):
    collection = models.ForeignKey(DexCollection, on_delete=models.CASCADE)
    dex_entry = models.ForeignKey(DexEntry, on_delete=models.CASCADE)
    added_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True)
    notes = models.TextField(blank=True)
    position = models.IntegerField(default=0)  # For custom ordering
```

### 3. Dex Pages (Scrapbook Feature)
**Requirements**: Customizable journal pages combining dex and animal data

**Implementation**:
```python
# server/dex/models.py
class DexPage(models.Model):
    dex_entry = models.OneToOneField(DexEntry, on_delete=models.CASCADE)
    layout_template = models.CharField(max_length=50, default='standard')
    custom_css = models.TextField(blank=True)  # For advanced customization

    # Content blocks stored as JSON
    content_blocks = models.JSONField(default=dict)
    # Example: {
    #   "title": {"text": "My First Eagle", "style": "heading1"},
    #   "observation": {"text": "Saw this at the lake...", "style": "paragraph"},
    #   "weather": {"text": "Sunny, 72°F", "style": "metadata"},
    #   "companions": {"text": "With Sarah and Mike", "style": "metadata"}
    # }

    # Media attachments
    additional_photos = models.ManyToManyField('DexPagePhoto')
    audio_notes = models.FileField(upload_to='dex/audio/', blank=True)

    is_public = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class DexPageTemplate(models.Model):
    """Predefined templates users can choose from"""
    name = models.CharField(max_length=50)
    description = models.TextField()
    layout_config = models.JSONField()  # Defines available blocks and positions
    preview_image = models.ImageField(upload_to='templates/')
    is_active = models.BooleanField(default=True)
```

**Client Implementation**:
```gdscript
# Visual page editor
class DexPageEditor extends Control:
    var current_page: Dictionary
    var available_templates: Array
    var content_blocks: Array = []

    func add_content_block(type: String, position: Vector2):
        var block = {
            "type": type,
            "position": position,
            "content": "",
            "style": get_default_style(type)
        }
        content_blocks.append(block)
        create_visual_block(block)

    func apply_template(template_id: String):
        var template = get_template(template_id)
        content_blocks = template.default_blocks
        refresh_editor()
```

### 4. Advanced Features Roadmap

#### 4.1 Offline Sync Queue
- Queue API calls when offline
- Retry when connection restored
- Conflict resolution for concurrent edits

#### 4.2 Smart Caching
- Predictive prefetching based on usage patterns
- Compress cached data
- Cloud backup of local database

#### 4.3 Social Features
- Share dex entries to social media
- Achievement system for collections
- Leaderboards for discovery

#### 4.4 Export/Import
- Export dex as PDF/CSV
- Import from other apps
- Backup to cloud storage

## Success Metrics

### Performance KPIs
- Sync completes in <5 seconds for 100 entries
- Image load time <200ms from cache
- Memory usage <100MB for 1000 cached entries
- 60 FPS maintained during scroll

### User Experience KPIs
- Zero data loss during sync
- Offline mode fully functional
- Friend dex loads within 2 seconds
- Error recovery without user intervention

### Technical KPIs
- 90% code coverage for sync logic
- <1% sync failure rate
- API response time <500ms p95
- Cache hit rate >80%

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Large dex sync timeout | High | Implement pagination, batch sync |
| Image storage costs | Medium | Compress images, set retention policy |
| Privacy breach | High | Strict permission checks, audit logs |
| Data corruption | High | Checksums, backup strategy |
| Network unreliability | Medium | Retry logic, offline queue |

## Conclusion

This implementation plan transforms the dex overhaul goals into a robust, scalable architecture that:
1. **Fixes immediate issues** (sync bug, single-user limitation)
2. **Establishes solid foundation** (multi-user storage, sync tracking)
3. **Enables future growth** (collections, pages, social features)
4. **Follows best practices** (separation of concerns, progressive enhancement)
5. **Maintains backwards compatibility** (v1 migration, graceful degradation)

The phased approach ensures each milestone delivers value while building toward the complete vision. The architecture is designed to scale from hundreds to millions of users without major refactoring.