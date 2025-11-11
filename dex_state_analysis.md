# BiologiDex System - Current Implementation State Analysis

## Executive Summary

The dex system has a **solid foundation** with core functionality implemented on both backend and client, but **lacks the friend dex viewing capability and proper sync implementation**. The system is currently single-user focused (users only see their own dex). The overhaul goals require implementing multi-user dex viewing and a robust sync system.

---

## Backend Implementation Status

### Models & Database Layer ✅ (Mostly Complete)

**DexEntry Model** (`server/dex/models.py`):
- ✅ Full schema with all fields implemented
- ✅ Three visibility levels: private, friends, public
- ✅ Image management (original, processed, dex-compatible via vision job)
- ✅ Location data (lat/lon, location_name)
- ✅ User notes and customizations
- ✅ Favorite flag (is_favorite)
- ✅ Proper indexes on owner, visibility, catch_date
- ✅ Created/updated timestamps for sync
- ⚠️ **Missing**: creation_index field on DexEntry itself (stored on Animal model)

**Animal Model** (`server/animals/models.py`):
- ✅ creation_index field implemented (auto-incremented, Pokedex-style numbering)
- ✅ Auto-assigns next sequential creation_index on save
- ✅ Indexed for efficient lookups
- ✅ Full taxonomic hierarchy
- ✅ Properly linked to DexEntry via ForeignKey

**Friendship Model** (`server/social/models.py`):
- ✅ Bidirectional friendship relationships
- ✅ Helper methods: `are_friends()`, `get_friends()`, `get_friend_ids()`
- ✅ Proper status tracking (pending/accepted/rejected/blocked)
- ⚠️ Used for permissioning dex entries but no dedicated friend dex endpoint

### API Views & Endpoints ⚠️ (Partial Implementation)

**DexEntryViewSet** (`server/dex/views.py`):
- ✅ `/dex/entries/` - Create/list entries (paginated)
- ✅ `/dex/entries/my_entries/` - Get current user's entries
- ✅ `/dex/entries/favorites/` - Get user's favorites
- ✅ `/dex/entries/{id}/toggle_favorite/` - Toggle favorite status
- ✅ `/dex/entries/recent/` - Get recent entries from user and friends
- ✅ `/dex/entries/by_animal/` - Get all entries for specific animal (visibility-respecting)
- ✅ `/dex/entries/sync_entries/` - Sync endpoint with last_sync parameter
- ⚠️ **MISSING**: Endpoint to view a specific friend's dex (no `/dex/user/{user_id}/entries/` or similar)
- ⚠️ **MISSING**: Filter/sort by user in list endpoint

**Permission Layer** (`IsOwnerOrReadOnly`):
- ✅ Checks visibility levels for read access
- ✅ Uses `Friendship.are_friends()` to verify friend status
- ✅ Enforces write-only for owner
- ✅ Properly integrated into viewset

### Serializers ✅ (Complete)

**DexEntrySerializer** (`server/dex/serializers.py`):
- ✅ Full serializer with animal details, owner username
- ✅ Includes location coords, customizations

**DexEntryListSerializer**:
- ✅ Lightweight version for list endpoints

**DexEntryCreateSerializer**:
- ✅ Auto-sets owner from request context

**DexEntryUpdateSerializer**:
- ✅ Allows updating visibility, favorites, notes, customizations, location

**DexEntrySyncSerializer** ✅:
- ✅ Includes creation_index from animal
- ✅ Includes scientific_name, common_name
- ✅ Includes dex_compatible_url (smart fallback to processed/original)
- ✅ Calculates image_checksum (SHA256)
- ✅ Includes image_updated_at timestamp
- ✅ Builds absolute URLs for image downloads

### Signal Handlers ✅ (Cache Invalidation)

**Tree cache invalidation** (`server/dex/signals.py`):
- ✅ Post-save signal invalidates tree caches when new dex entry created
- ✅ Invalidates owner's cache AND friend caches
- ✅ Post-delete signal also invalidates caches
- ✅ Calls `DynamicTaxonomicTreeService.invalidate_user_caches()`

---

## Frontend Implementation Status

### Local Storage ✅ (Complete)

**DexDatabase Singleton** (`client/biologidex-client/dex_database.gd`):
- ✅ Stores records locally at `user://dex_database.json`
- ✅ Record format: creation_index, scientific_name, common_name, cached_image_path
- ✅ Navigation helpers: `get_next_index()`, `get_previous_index()`, `get_first_index()`
- ✅ `has_record()` lookup by creation_index
- ✅ Auto-saves on `add_record()`
- ✅ Emits `record_added` signal for real-time updates
- ✅ Maintains sorted indices array for efficient navigation
- ⚠️ **Missing**: Multi-user support (only stores own dex, no per-user databases)

### Dex Gallery Scene ✅ (Complete)

**dex.gd**:
- ✅ Browse discovered animals in creation_index order
- ✅ Previous/Next buttons with auto-disable at boundaries
- ✅ Loads images from local cache (`user://dex_cache/`)
- ✅ Empty state handling ("No animals discovered yet!")
- ✅ Responds to DexDatabase signals for real-time updates
- ✅ Displays "Scientific name - common name" format
- ✅ RecordImage component with aspect ratio calculation
- ⚠️ **Missing**: Friend dex viewing tab/mode
- ⚠️ **Missing**: User selection/switching
- ⚠️ **Missing**: Sync UI/progress indication

### API Integration ✅ (Endpoints Configured)

**APIConfig** (`client/biologidex-client/api/core/api_config.gd`):
- ✅ All dex endpoints configured:
  - `/dex/entries/`
  - `/dex/entries/my_entries/`
  - `/dex/entries/favorites/`
  - `/dex/entries/{id}/toggle_favorite/`
  - `/dex/entries/sync_entries/`
- ⚠️ **Missing**: Friend dex endpoint config (no `/dex/user/{user_id}/entries/` or similar)

**DexService** (`client/biologidex-client/api/services/dex_service.gd`):
- ✅ `create_entry()` - Create new dex entry
- ✅ `get_my_entries()` - Fetch user's entries
- ✅ `get_favorites()` - Fetch favorite entries
- ✅ `toggle_favorite()` - Toggle favorite status on entry
- ✅ `sync_entries(last_sync: String)` - Sync with server
  - Sends `last_sync` query param
  - Expects `entries` array in response
  - ⚠️ **Issue**: Response parsing expects `response.get("results", [])` but sync endpoint returns `response.get("entries", [])` - **MISMATCH**
- ⚠️ **Missing**: `get_friend_entries()` - Fetch a friend's dex

### Camera Scene Integration ⚠️ (Needs Work)

**camera.gd**:
- ✅ Uploads image for CV analysis
- ✅ Polls for job status
- ✅ Downloads dex-compatible image after identification
- ✅ Caches image locally at `user://dex_cache/{hash}.png`
- ✅ Auto-saves to DexDatabase after successful identification
- ⚠️ **Missing**: Last sync timestamp tracking
- ⚠️ **Missing**: Integration with sync workflow

---

## Current Dex Data Flow

### Creating a New Dex Entry:
1. User selects photo in camera scene
2. Camera scene uploads image → CV analysis job created
3. Polls `/vision/jobs/{job_id}/` until complete
4. Server processes image → dex_compatible_image created
5. Client downloads dex-compatible image → caches locally
6. **Manually saved to DexDatabase** (no sync marker)
7. Dex gallery displays in next/prev order

### Viewing Dex:
1. User navigates to dex.gd scene
2. Scene loads data from DexDatabase singleton
3. Displays records by creation_index in navigation
4. **No server sync** occurs
5. **No multi-user support**

---

## What's MISSING for Dex Overhaul Goals

### 1. Friend Dex Viewing ❌

**Backend**:
- ❌ No endpoint to list a specific user's dex entries (only owner sees via visibility filter)
- ❌ No endpoint like `/dex/user/{user_id}/entries/` or `/dex/entries/friend/{user_id}/`
- **Need**: Public endpoint that respects visibility (public + friends-only for actual friends)

**Frontend**:
- ❌ No UI to select which friend's dex to view
- ❌ No mechanism to fetch friend dex entries
- ❌ No per-user local databases (only `user://dex_database.json`)
- ❌ DexService lacks `get_friend_entries(friend_id)` method
- **Need**: Friend selection UI, per-user local storage, sync for multiple users

### 2. Robust Sync System ❌

**Backend**:
- ⚠️ Sync endpoint returns `"entries"` key in response (not `"results"`)
- ⚠️ No metadata about sync status (incomplete, needs retry, etc.)
- ⚠️ No progress tracking for large syncs

**Frontend**:
- ❌ DexService.sync_entries() expects wrong response format (`results` vs `entries`)
- ❌ No last_sync tracking (where/how to store timestamp per user?)
- ❌ No automatic sync trigger on app launch
- ❌ No sync progress UI
- ❌ No image download progress tracking
- ❌ No handling of partial/incomplete syncs
- **Need**: Client-side sync state management, retry logic, progress tracking

### 3. Image Caching Strategy ❌

**Frontend**:
- Current: Single shared cache at `user://dex_cache/`
- ⚠️ **Problem**: Friend dex images would overwrite own dex images (same cache location)
- **Need**: Separate cache directories per user or content-aware caching

### 4. Multi-User State Management ❌

**Frontend**:
- ❌ DexDatabase is a singleton - stores only one user's data
- ❌ No concept of "current_dex_user" vs "logged_in_user"
- ❌ No way to load multiple users' dex entries simultaneously
- **Need**: Refactor to support multiple per-user local databases

### 5. API Response Format Mismatch ⚠️

**Current Bug**:
```
# Sync endpoint returns:
{
  "entries": [...],      # <-- Array
  "server_time": "...",
  "count": 5
}

# DexService expects:
response.get("results", [])  # <-- Expects "results" key
```

**Fix needed**: Either update endpoint to use `"results"` or update service to parse `"entries"`

---

## Technical Debt & Issues

| Issue | Severity | Impact | Location |
|-------|----------|--------|----------|
| DexService parsing `"results"` instead of `"entries"` | HIGH | Sync will silently fail (empty array) | dex_service.gd line 171 |
| No last_sync timestamp persistence | HIGH | Full resync every time | Frontend missing |
| No friend dex endpoint | HIGH | Can't view friends' dex | Backend missing |
| Single DexDatabase for all users | HIGH | Can't support multi-user local storage | Frontend architecture |
| Image cache collision | MEDIUM | Friend images could overwrite own | Frontend cache strategy |
| No sync UI/progress | MEDIUM | Users unaware of background sync | Frontend missing |
| No retry/resume on sync failure | MEDIUM | Partial syncs abandoned | Frontend missing |

---

## Recommendations for Dex Overhaul

### Phase 1: Fix Response Format & Sync Foundation
1. **Update DexService**: Fix `sync_entries()` to parse correct response format (`"entries"` key)
2. **Add last_sync tracking**: Store timestamp in TokenManager or dedicated manager
3. **Test sync flow**: Verify image download + local DB update works end-to-end

### Phase 2: Multi-User Support
1. **Add backend endpoint**: `/dex/user/{user_id}/entries/` (respects visibility + friendship)
2. **Refactor DexDatabase**: Support multiple users or create separate local databases
3. **Add DexService method**: `get_friend_entries(user_id: String, friend_id: String)`
4. **Fix image cache**: Separate by user or use content-based naming

### Phase 3: Friend Dex Viewing
1. **UI layer**: Add friend selector to dex.gd (tabs, dropdown, or list)
2. **Navigation**: Track "viewing_user" separate from "logged_in_user"
3. **Real-time sync**: Sync friend's dex when selected
4. **Permissions**: Only show if friends or entries are public

### Phase 4: Sync Infrastructure
1. **Progress tracking**: Add UI indicators for sync status
2. **Retry logic**: Handle network failures gracefully
3. **Background sync**: Optional auto-sync on app launch
4. **Partial sync**: Resume interrupted downloads

### Phase 5: Polish & Optimization
1. **Cache management**: Cleanup old entries, manage storage
2. **Performance**: Index by creation_index for fast navigation
3. **Offline support**: Handle viewing cached dex without network
4. **Error messaging**: User-friendly sync error messages

---

## Code Locations Reference

### Backend Key Files:
- **Models**: `/home/bryan/Development/Git/biologidex/server/dex/models.py` (DexEntry)
- **Views**: `/home/bryan/Development/Git/biologidex/server/dex/views.py` (DexEntryViewSet)
- **Serializers**: `/home/bryan/Development/Git/biologidex/server/dex/serializers.py` (DexEntrySyncSerializer)
- **Signals**: `/home/bryan/Development/Git/biologidex/server/dex/signals.py` (Cache invalidation)
- **URLs**: `/home/bryan/Development/Git/biologidex/server/dex/urls.py`

### Frontend Key Files:
- **Local Storage**: `/home/bryan/Development/Git/biologidex/client/biologidex-client/dex_database.gd`
- **Gallery UI**: `/home/bryan/Development/Git/biologidex/client/biologidex-client/dex.gd`
- **API Service**: `/home/bryan/Development/Git/biologidex/client/biologidex-client/api/services/dex_service.gd`
- **Config**: `/home/bryan/Development/Git/biologidex/client/biologidex-client/api/core/api_config.gd`
- **Camera**: `/home/bryan/Development/Git/biologidex/client/biologidex-client/camera.gd` (image caching)

### Infrastructure:
- **Documentation**: `/home/bryan/Development/Git/biologidex/dex_overhaul.md` (goals)
- **Project Memory**: `/home/bryan/Development/Git/biologidex/CLAUDE.md`

---

## Next Steps

1. **Review this analysis** with project owner
2. **Prioritize phases** based on MVP requirements
3. **Fix immediate bugs** (sync response format mismatch)
4. **Design friend dex UI** (where/how to select friends)
5. **Implement backend endpoint** for friend dex viewing
6. **Refactor client-side storage** for multi-user support

