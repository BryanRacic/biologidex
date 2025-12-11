# BiologiDex - Claude Context

## Project Overview
Pokedex-style social network for wildlife observations. Users photograph animals → CV/LLM identifies → add to personal dex → view in collaborative taxonomic tree with friends.

## Stack
- **Backend**: Django 4.2+ REST Framework, PostgreSQL 15, Redis, Celery, OpenAI Vision API
- **Frontend**: Godot 4.5 (web-primary), JWT auth, multi-user local storage
- **Infra**: Docker Compose, Nginx reverse proxy, Gunicorn, Prometheus monitoring
- **Storage**: Google Cloud Storage (media), local dex cache with deduplication

## Status (2025-12-05)
- ✅ Auth, CV pipeline, multi-user dex sync, image processing, production deployment
- ✅ Incremental sync, image deduplication, HTTP caching, retry logic
- ✅ Multi-stage taxonomy matching with synonym resolution (NameRelation support)
- ✅ Taxonomic tree visualization with Eades radial layout (angular wedge allocation)
- ✅ Two-step image upload workflow (convert → download → analyze)
- ✅ Multiple animal detection support with selection API
- ✅ Client-side image rotation with post-conversion transformations
- ✅ Touch-interactive paper background with pan/zoom (all scenes via InteractiveBackground component)
- ✅ DexRecordImage reusable component with unified API for image display/loading
- ✅ Dex feed vertical carousel with snap-to-item and pooled DexRecordImage rendering
- ✅ Social scene with lab book styling, touch scrolling, and copyable friend codes

---

## Architecture

### Client (Godot 4.5)
- 1280×720 base, canvas_items stretch, MSDF fonts
- **Singletons (autoload)**: APIManager, TokenManager, NavigationManager, DexDatabase (v2.0), SyncManager
- **API Layer** (4-layer): HTTPClientCore → APIClient (auth/retry/queue) → Services (auth, vision, dex, social, tree) → APIManager
- **Scenes**: login, create_acct, home, camera (CV integration), dex (multi-user gallery), record_image
- **Storage**: `user://dex_data/{user_id}_dex.json`, `user://dex_cache/{user_id}/`, `user://sync_state.json`

### Critical Patterns & Gotchas

**API Usage**:
- ✅ `APIManager.<service>.<method>()` for all API calls
- ✅ Callbacks: `func(response: Dictionary, code: int)` - check `code == 200 or code == 201` (services may normalize 201→200)
- ✅ Traditional callbacks with `.bind(context)`, NOT inline lambdas
- ✅ Positional arguments ONLY (no `param=value` syntax in GDScript)
- ✅ APIClient methods: `request_get()`, `post()`, `put()`, `delete()` (NOT `.get()`)
- ✅ **Callback validation**: Always check `callback.is_valid()` before calling (prevents crashes on freed scenes)
- ✅ **URL building**: Use plain `&` to join query params, NOT `&amp;` (HTML encoding breaks server parsing)
- ❌ Never call `api_client` directly - use service methods
- ❌ Never inline lambdas in service methods - causes "assignment in expression" errors

**GDScript**:
- Type inference: `min()`, `max()`, `Array[T].pop_back()` return Variant - cast to `float`/`String`
- Reserved: `class_name` - use `animal_class` for variables
- `await get_tree().process_frame` before reading dynamic sizes

**Godot Architecture Best Practices**:
- ✅ **Use built-in nodes/functions** for UI, 2D, scaling - don't write custom viewport math or scaling logic in scripts
- ✅ **Prefer "proper Godot" architecture** even if it requires restructuring - cleaner long-term maintainability
- ✅ **Proportional sizing**: Calculate UI element sizes (borders, fonts, margins) as percentages of content dimensions for consistent proportions at any display size
- ❌ **Don't** write custom scaling math across multiple scripts - consolidate in proper node architecture

**UI Layout**:
- `layout_mode`: 0=uncontrolled, 1=anchors, 2=container, 3=anchors preset
- Container children: `layout_mode = 2`
- AspectRatioContainer: `layout_mode = 1` with anchors
- Touch targets: min 44×44px for mobile

**Images & Camera Workflow (Updated 2025-12-04)**:
- **Two-step upload workflow**:
  1. Client uploads → `/images/convert/` → Server converts to PNG → Returns conversion_id
  2. Client downloads converted PNG, can rotate/preview → Submits to `/vision/jobs/` with conversion_id
- **State machine** (camera.gd): IDLE → IMAGE_SELECTED → IMAGE_CONVERTING → IMAGE_READY → ANALYZING → ANALYSIS_COMPLETE → (ANIMAL_SELECTION) → COMPLETED
- Image rotation: Client-side using `Image.rotate_90(CLOCKWISE)`, sent as `post_conversion_transformations`
- Multiple animal detection: Backend returns `detected_animals` array, client auto-selects if 1, shows selection UI if >1

**DexRecordImage Component (Updated 2025-12-04)**:
- **Location**: `features/ui/components/dex_record_image/`
- **Files**: `dex_record_image.tscn` (scene), `dex_record_image.gd` (script with `class_name DexRecordImage`)
- **Structure**: AspectRatioContainer root
  - Bordered mode: `ImageBorder` (PanelContainer) + `BorderedImage` (TextureRect) + `RecordLabel` (Label)
  - Simple mode: `SimpleImage` (TextureRect) for preview/rotation
- **Scaling requirement**: Border widths, font sizes, and margins should be proportional to content size so the component looks identical at any display size (tree 80px, dex 400px, etc.)
- **Usage pattern** (type as `DexRecordImage`, not `AspectRatioContainer`):
  ```gdscript
  @onready var record_image: DexRecordImage = get_node("%RecordImage")

  # For displaying existing entries (dex.gd, feed_list_item.gd, tree_dex_image.gd):
  record_image.set_entry_data(entry_dict, user_id)  # Sets data + updates label
  record_image.load_image_from_entry()               # Loads via DexImageLoader
  record_image.image_loaded.connect(_on_image_loaded)  # Signal: (success: bool)

  # For camera preview/capture workflow:
  record_image.show_simple()                         # Preview mode
  record_image.set_simple_texture(texture)           # Set preview
  record_image.get_simple_texture()                  # Get for rotation
  record_image.copy_simple_to_bordered()             # Transfer to card
  record_image.show_bordered()                       # Show final card
  record_image.update_label_from_data(sci, common, user, date)  # Manual label
  ```
- **Key methods**: `set_entry_data()`, `load_image_from_entry()`, `set_texture()`, `set_simple_texture()`, `get_simple_texture()`, `show_bordered()`, `show_simple()`, `copy_simple_to_bordered()`, `update_label_from_data()`, `clear_texture()`, `set_placeholder()`
- **Signals**: `image_loaded(success: bool)`, `image_load_failed`
- **Used by**: dex.gd, FeedCarouselRenderer, tree_dex_image.gd, camera.gd

**Multi-User Dex (v2.0)**:
- DexDatabase: User-partitioned storage, auto-migrates v1→v2, image deduplication across users
- SyncManager: Tracks `last_sync` per user in `sync_state.json`
- DexService: `sync_user_dex()`, `sync_user_dex_with_retry()` with exponential backoff
- Signals: `sync_started`, `sync_progress`, `sync_user_completed`, `sync_user_failed`
- **Critical**: Camera must create BOTH local (DexDatabase) AND server-side (APIManager.dex.create_entry) entries
- **Auto-sync**: Trigger sync when database empty OR never synced (check `SyncManager.get_last_sync()`)

**Auth**:
- TokenManager: Use `is_logged_in()` not `has_valid_token()`
- Services handle auth injection automatically

**Web Export**:
- Single-threaded mode (best compatibility)
- `HTTPRequest.accept_gzip = false` - avoid double decompression
- **High DPI fix**: Custom HTML shell at `export_templates/custom_html_shell.html`
  - `canvas_resize_policy=1` (Project) prevents double-scaling
  - `stretch/mode="canvas_items"` + `allow_hidpi=true` in project settings
  - Safe area insets for notched devices

**Touch-Interactive Background (Updated 2025-12-05)**:
- **InteractiveBackground** (`features/ui/components/interactive_background/`): Self-contained reusable component
  - `interactive_background.tscn`: Prefab scene - just instance it, no wiring needed
  - `interactive_background.gd`: Auto-connects shader to touch controller signals
  - `background_touch_controller.gd`: Pan/zoom gesture handler with threshold-based detection
- **paper.gdshader** (`shaders/paper.gdshader`): Accepts `scroll` (Vector2) and `scale` (float) uniforms
- **Gesture support**: Single-finger/mouse drag (pan), two-finger pinch (zoom), scroll wheel (zoom)
- **Inertia**: Momentum-based scrolling with exponential decay after release
- **Web compatibility**: Uses position-based touch tracking (not index) to work around iOS web bugs
  - GitHub issues: #95941 (iOS index overflow), #94346 (multitouch relative), #3772 (cross-platform)
- **Optional Scroll Limits** (for bounded scrolling like feeds):
  - `scroll_limits_enabled`: Enable bounded scrolling with rubber-banding
  - `scroll_min`/`scroll_max`: Vector2 limits (use INF/-INF for unbounded axes)
  - `rubber_band_enabled`/`rubber_band_factor`/`rubber_band_max`: Overscroll resistance
  - `snap_back_lerp`: Speed of snap-back animation when released past limits
  - `set_scroll_limits(min, max)`: Runtime API to configure limits
  - `scroll_to(offset, animated)`: Programmatic scrolling
  - `tap_detected` signal: Emitted when gesture ends without drag (tap on background)
  - **Zoom behavior**: Bounded mode zooms in-place (no scroll adjustment); infinite canvas keeps cursor point stationary
- **Project settings** (`project.godot`):
  - `pointing/emulate_touch_from_mouse = true` (desktop testing)
  - `pointing/emulate_mouse_from_touch = true` (mobile buttons work via emulated mouse clicks)
- **Input handling strategy**:
  - TouchController uses `MOUSE_FILTER_PASS` (not STOP) to allow events through to buttons
  - 10px `drag_threshold` distinguishes taps from drags - taps pass through, drags are consumed
  - Touch events only tracked for pinch zoom; single-touch handled via mouse emulation
  - Buttons receive emulated mouse clicks on mobile, work correctly
- **Scene integration**: Instance `InteractiveBackground` as first child in UI CanvasLayer
- **Critical**: UI overlay containers must have `mouse_filter = 2` (IGNORE) to pass events through; buttons keep default STOP
- **Scenes using component**: home, login, create_acct, camera, dex, dex_feed, social (NOT tree)

**Taxonomic Tree Visualization (Updated 2025-12-10)**:
- **Coordinate Space Convention** (CRITICAL - must be consistent across all tree code):
  - `scroll_offset`: World-space position that appears at viewport center
  - When `scroll_offset = (0,0)`, world origin is at viewport center
  - Transform formula: `screen = (world - scroll_offset) * scale + viewport_center`
  - To center on world position `pos`: `scroll_offset = pos` (NOT `pos * scale`)
- **View culling**: `_get_view_rect()` returns world-space rect; center = `scroll_offset` directly
- **Coordinate conversion**:
  - `world_to_screen(W)`: `(W - scroll_offset) * scale + viewport_center`
  - `screen_to_world(S)`: `(S - viewport_center) / scale + scroll_offset`
- **Edge rendering**: Must re-render on ANY view change (scroll OR scale), not just scale changes
- **Edge visibility**: Use bounding box intersection (`Rect2.expand().intersects()`), not endpoint visibility
- **Culling margin**: Define in screen-space pixels, convert to world-space (`margin / scale`)
- **Label overlap**: Priority-based culling with screen-space distance checks; zoom-based filtering by taxonomic rank
- **Branch extension** (reduces dex image overlap):
  - `BRANCH_EXTENSION_ENABLED`: Toggle feature on/off (default: true)
  - `BRANCH_EXTENSION_BASE_RATIO`: Base extension as ratio of DEX_IMAGE_SIZE (default: 0.6 = 600 world units)
  - `BRANCH_EXTENSION_ALT_RATIO`: Additional extension for alternating siblings (default: 0.5 = 500 world units)
  - Alternation pattern: Even siblings get base extension, odd siblings get base + alt extension
  - Extended positions stored in `extended_positions` dictionary, edges draw to extended endpoints
- **Dex Image Lazy Loading** (optimizes scrolling performance):
  - `TreeDexImage`: Uses `VisibleOnScreenNotifier2D` with 500 world unit preload margin
  - `LoadState` enum: IDLE → QUEUED → LOADING → LOADED (or FAILED)
  - Images activated without loading; `start_load()` called by queue processor
  - Signals: `visibility_entered`, `visibility_exited`, `load_state_changed`
- **Visibility Throttling** (TreeRenderer):
  - Dirty flag system: Only recalculates when view moves >50 world units
  - Minimum update interval prevents excessive recalculation during fast scrolling
  - `_process()` handles deferred visibility updates and queue processing
- **Image Loading Queue** (TreeRenderer):
  - `_pending_loads`: Priority queue sorted by distance to viewport center
  - `_loading_in_progress`: Tracks concurrent HTTP requests
  - `IMAGES_PER_FRAME`: Max new loads started per frame (default: 1)
  - `MAX_CONCURRENT_LOADS`: Max simultaneous HTTP requests (default: 4)
- **Files**: `tree_controller.gd` (orchestration), `tree_renderer.gd` (rendering), `tree_data_models.gd` (data), `tree_dex_image.gd` (pooled image wrapper)

**Tree Camera Scene (Updated 2025-12-10)** (Camera2D-based tree - WORKING):
- **Purpose**: Tree visualization using Camera2D for **perfect background/foreground sync** (solves the parallax drift issue)
- **Location**: `scenes/tree_camera/` (tree_camera.tscn, tree_camera_controller.gd)
- **Architecture**:
  - `Camera2D`: Single source of truth for view transform (position, zoom)
  - `TreeCameraController` (`features/tree/camera_controller.gd`): Direct pan/zoom/touch handling (no smoothing/inertia)
  - `paper_camera.gdshader`: Computes world coords in vertex shader, Godot handles camera transform
  - `WorldContent` (Node2D): Contains background + tree graph, transforms with camera automatically
- **Why It Works**:
  - Camera2D transforms ALL Node2D children uniformly (both background and tree nodes)
  - Shader passes world coordinates via `varying`, fragment shader uses them for procedural texture
  - Background is `Polygon2D` (Node2D-based), NOT `ColorRect` (Control) - Camera2D only transforms Node2D!
  - No manual coordinate conversion needed - everything stays in world space
- **Critical Implementation Details**:
  - Background MUST be `Polygon2D` or `Sprite2D` (Node2D), NOT `ColorRect` (Control won't transform with Camera2D)
  - Shader does NOT use `skip_vertex_transform` - let Godot handle the transform chain
  - Vertex shader: `world_coord = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy` to capture world position
  - Fragment shader uses interpolated `world_coord` for procedural texturing
- **Scene Structure**:
  ```
  TreeCamera (Node2D)
  ├── Camera2D (enabled=true) ← Single source of truth
  │   └── CameraController ← Pan/zoom/touch handling
  ├── WorldContent (Node2D) ← Camera automatically transforms this
  │   ├── PaperBackground (Polygon2D + paper_camera.gdshader)
  │   └── TreeGraph (Node2D)
  │       ├── EdgesLayer, NodesLayer, DexImagesLayer, LabelsLayer
  └── UILayer (CanvasLayer, layer=10) ← Fixed UI (not affected by camera)
  ```
- **Camera Controller Features** (`features/tree/camera_controller.gd`):
  - Direct pan/zoom response (no smoothing or inertia - immediate 1:1 input)
  - Touch gestures: Single-finger pan, two-finger pinch zoom
  - Mouse: Left-drag to pan, scroll wheel to zoom
  - Cursor-centric zoom (zoom toward cursor position)
  - Uses `_input()` not `_unhandled_input()` to ensure events are captured
  - Export vars: `min_zoom`, `max_zoom`, `zoom_step`, `pinch_sensitivity`, `scroll_sensitivity`, `drag_threshold`, `pan_sensitivity`
  - Public API: `center_on()`, `set_zoom()`, `get_view_rect()`, `reset()`
- **Paper Background Exports** (on root TreeCamera node):
  - Grid: `grid_scale`, `grid_line_px`, `grid_line_color`, `grid_line_alpha`
  - Paper: `paper_color`, `paper_noise_amount`, `paper_noise_scale`
  - Speckles: `speckle_amount`, `speckle_density`, `speckle_scale`
  - Fibers: `fiber_amount`, `fiber_scale`
- **Home Screen Access**: "Tree (Camera2D)" button navigates to this scene
- **Testing**: Run `godot --path . res://scenes/tree_camera/tree_camera.tscn`

**Dex Feed Carousel (Updated 2025-12-05)**:
- **Architecture**: Touch-driven vertical carousel with organic scrapbook-style randomization
- **Location**: `features/dex_feed/` (FeedCarouselRenderer), `scenes/dex_feed/` (dex_feed.gd/tscn)
- **Key Design**: Pool of 5 DexRecordImage instances, recycled as user scrolls for memory efficiency
- **Components**:
  - `BackgroundTouchController`: Shared with InteractiveBackground, configured with scroll limits for feed
  - `FeedCarouselRenderer`: Pooled DexRecordImage instances with per-entry randomization
  - `dex_feed.gd`: State machine orchestrating sync, filter, and carousel components
- **State Machine**: IDLE → LOADING → SCROLLING → (back to IDLE or ERROR)
- **Randomization Export Vars** (configurable in editor):
  - `min_space`: Minimum vertical spacing between entries (default: 40px)
  - `max_rand_space`: Additional random spacing 0 to max (default: 80px)
  - `max_rand_size`: Size variation +/- percentage (default: 0.15 = 15%)
  - `max_rand_offset`: Horizontal offset +/- percentage of width (default: 0.1 = 10%)
  - `max_rand_rotate`: Rotation +/- degrees (default: 8°)
- **Per-entry Random Caching**: `_entry_randoms` array stores consistent random values per entry
- **Touch Behavior** (via BackgroundTouchController with scroll limits):
  - Free scroll up/down with configurable vertical limits (0 to max_scroll_y)
  - Horizontal scroll bounded to ±50% of viewport width
  - 10px drag threshold (tap passes through to navigate to dex)
  - Rubber-banding at boundaries with smooth snap-back
  - Scroll wheel support for desktop
- **Pool Management Pattern** (similar to TreeRenderer):
  - `_active_assignments: Dictionary = {}` tracks {pool_index: data_index}
  - Visibility buffer: scroll_offset ± 0.5-1.5× viewport height
- **Signals**: FeedCarouselRenderer emits `item_pressed`, `image_ready`, `layout_calculated`

**Social Scene (Updated 2025-12-05)**:
- **Architecture**: Lab book "table of contents" style with BackgroundTouchController scrolling
- **Location**: `scenes/social/` (social.gd/tscn), `scenes/social/components/` (friend_list_item, pending_request_item)
- **Features**:
  - InteractiveBackground with vertical-only scrolling (zoom disabled)
  - Copyable friend codes with "Copied!" feedback animation
  - Friend entries show: username, catches, unique species, copyable friend code, action buttons
  - Pending requests section (hidden when empty)
- **Components**:
  - `friend_list_item.tscn/gd`: Friend entry with stats, copyable code button, View Dex/Tree/Remove buttons
  - `pending_request_item.tscn/gd`: Pending request with Accept/Reject/Block buttons
- **State Machine**: IDLE → LOADING → SCROLLING → (back to IDLE)

**ClipboardHelper (Updated 2025-12-05)**:
- **Location**: `features/ui/components/clipboard/clipboard_helper.gd`
- **Purpose**: Cross-platform clipboard support (desktop + web)
- **Usage**:
  ```gdscript
  const ClipboardHelper = preload("res://features/ui/components/clipboard/clipboard_helper.gd")

  var success := ClipboardHelper.copy_to_clipboard("text to copy")
  var text := ClipboardHelper.get_from_clipboard()  # May be empty on web
  ```
- **Desktop**: Uses `DisplayServer.clipboard_set()` / `clipboard_get()`
- **Web**: Uses `JavaScriptBridge.eval()` with `navigator.clipboard.writeText()` + fallback to `execCommand('copy')`
- **Limitations**: Web clipboard read heavily restricted by browsers; requires user interaction for write

### Server (Django)
- **Apps**: accounts (User, profiles), animals (species DB), dex (user collections), social (friendships), vision (CV pipeline), graph (taxonomic tree), images (transformation system)
- **Settings**: `biologidex.settings.{development|production_local|production}`

**Key Models**:
- **User**: UUID pk, `friend_code` (8-char), `badges` JSONField
- **Animal**: Taxonomic hierarchy, `creation_index` (sequential), `verified` flag
- **Taxonomy**: COL data, `source_taxon_id`, hierarchy fields, `accepted_name` FK, `parent` FK
  - `accepted_name`: For synonyms, points to the accepted taxon (linked via `link_col_parents`)
  - `parent`: For accepted taxa, points to taxonomic parent (linked via `link_col_parents`)
  - Without parent linking, synonym lookups won't resolve to accepted names with full hierarchy
- **NameRelation**: Synonym relationships from COL `NameRelation.tsv` (spelling corrections, basionyms, etc.)
- **DexEntry**: User↔Animal, `visibility` (private/friends/public), `customizations` JSONField, image fields (original/processed/source_vision_job)
- **Friendship**: Bidirectional, status (pending/accepted/rejected/blocked), helpers: `are_friends()`, `get_friends()`, `get_friend_ids()`
- **AnalysisJob**: CV tracking with **NEW multi-animal support**:
  - `source_conversion` FK to ImageConversion (new workflow)
  - `image` (DEPRECATED - legacy direct upload)
  - `dex_compatible_image` (PNG ≤2560px)
  - `detected_animals` JSONField list (all CV detections)
  - `selected_animal_index` (user's choice from multiple)
  - `post_conversion_transformations` (client-side rotation, etc.)
  - Legacy `identified_animal` FK (first/selected animal for backward compat)
- **ImageConversion** (images app): Temporary image storage (30-min TTL):
  - `original_image`, `converted_image` (dex-compatible PNG)
  - `transformations` applied during conversion
  - `checksum` SHA256 for deduplication
  - `used_in_job` flag, `expires_at` timestamp
  - Auto-cleanup via Celery (every 10 min)
- **ProcessedImage** (images app): Long-term transformations, versioning, SHA256 checksums, EXIF data

**CV Pipeline & Taxonomy Matching (Updated 2025-11-20)**:
- **NEW Two-Step Upload Workflow**:
  1. Client → `POST /images/convert/` → Server converts → Returns conversion_id
  2. Client downloads converted PNG, displays with rotation
  3. Client → `POST /vision/jobs/` with conversion_id + post_conversion_transformations
  4. Server uses pre-converted image, applies final transforms, runs CV
- **Multiple Animal Detection**: `parse_and_create_animals()` returns list, supports pipe-delimited (`|`) format
- ImageProcessor: Converts to PNG (RGBA→RGB white bg), resizes >2560px, metadata
- OpenAIVisionService: GPT-4 (`max_tokens`) vs GPT-5+ (`max_completion_tokens`)
- Celery task: ImageProcessor → Vision API → parse ALL animals → store in `detected_animals`
- EnhancedImageProcessor (images): EXIF rotation, transformations, deduplication

**Taxonomy Matching** (`taxonomy/services.py:lookup_or_create_from_cv`):
- **6-stage matching**: (1) Exact fields (genus+species+subspecies), (2) Exact scientific name, (3) Exact common name, (4) Fuzzy fields, (5) Fuzzy scientific name, (6) Fuzzy common name
- **3-stage synonym resolution**: (1) `accepted_name` FK, (2) `NameRelation` table lookup, (3) Name parsing ("Canis lupus familiaris" → "Canis familiaris")
- **Field population**: Auto-populates empty genus/species/subspecies fields by parsing scientific name
- **Critical**: Stage 2 (exact scientific name) catches synonyms with empty genus fields (COL data quality issue)

**Dex Sync (v2.0)**:
- `/sync_entries/`: Own dex, cached 5m, `last_sync` param
- `/user/{id}/entries/`: Any user (permission-based), incremental sync
- `/friends_overview/`: Friends summary, cached 2m
- `/batch_sync/`: Multi-user in one request
- DexEntrySyncSerializer: Image checksums, absolute URLs
- Indexes: `(owner, updated_at)`, `(visibility, updated_at)`, `(updated_at)`

## API Reference (`/api/v1/`)

**Auth**: `/login/` (JWT), `/refresh/` (token)
**Users**: `/users/` (register), `/me/`, `/friend-code/`, `/lookup_friend_code/`
**Animals**: `/animals/` (list), `/lookup_or_create/` (CV pipeline)
**Dex**: `/dex/entries/` (create), `/my_entries/`, `/favorites/`, `/{id}/toggle_favorite/`, `/sync_entries/` (cached 5m), `/user/{id}/entries/` (multi-user), `/friends_overview/` (cached 2m), `/batch_sync/`
**Social**: `/social/friendships/` (CRUD), `/friends/`, `/pending/`, `/send_request/`, `/{id}/respond/`, `/{id}/unfriend/`
**Vision**: `/vision/jobs/` (create w/conversion_id), `/{id}/` (status), `/{id}/select_animal/` (multi-animal), `/completed/`, `/{id}/retry/`
**Images**: `/images/convert/` (upload & convert), `/images/convert/{id}/download/` (get PNG), `/images/convert/{id}/` (metadata)
**Graph**: `/graph/taxonomic-tree/` (cached), `/invalidate-cache/`

## Critical Details

**Migrations**: `makemigrations accounts animals dex social vision images` (accounts first - AUTH_USER_MODEL)
**Settings**: `biologidex.settings.{development|production_local|production}`
**Env Vars**: `SECRET_KEY`, `DB_PASSWORD`, `OPENAI_API_KEY`, `GCS_*`, `GOOGLE_APPLICATION_CREDENTIALS`
**Celery**: `process_analysis_job` (CV), `cleanup_old_analysis_jobs`
**Caching TTL**: Animals 1h, Graph 2m, Dex sync 5m (full) / 2m (friends overview)

## Production

**Stack**: Nginx (reverse proxy) → Gunicorn → Django, PostgreSQL 15 + pgBouncer, Redis (cache/Celery), Celery workers
**Monitoring**: Prometheus (`/metrics/`), health endpoints (`/health/`, `/ready/`, `/api/v1/health/`)
**Deployment**: `scripts/deploy.sh` (backend), `scripts/export-to-prod.sh` (Godot client)

### Critical Production Gotchas

**Docker**:
- Code changes (including migrations) require rebuilding: `docker-compose -f docker-compose.production.yml build web celery_worker celery_beat && up -d`
- Simply restarting uses OLD cached images - code/migrations won't update
- Host files NOT used by containers (they use `/app` inside) - must rebuild after code changes
- Use service names for connections: `DB_HOST=db`, `REDIS_HOST=redis` (not `localhost`)
- Password changes require volume rebuild: `down -v` (deletes data) then `up -d`
- **Migration workflow**: Create migration in dev → copy to prod dir → rebuild containers → run migrate

**Nginx**:
- Cloudflare Tunnel must point to **nginx (port 80)**, not Django (8000)
- Must force `X-Forwarded-Proto: https` in proxy headers (not `$scheme`) - prevents mixed content errors
- URL routing: `/` → Godot client, `/api/` → Django, `/admin/` → Django admin
- Client files: `server/client_files/` mounted at `/var/www/biologidex/client/`
- Caching: `.wasm/.pck` 7d immutable, `.html` 1h, PWA no-cache

**Environment**:
- `.env` files: NO inline comments after values (`DB_HOST=db  # comment` is invalid)
- Use single `.env` file (not `.env.production`)

**Database**:
- Always use pgBouncer for connection pooling
- Create indexes AFTER Django migrations
- Migration sync issues: Fake unapply then reapply (`migrate app 0001 --fake` then `migrate app`)
- Verify schema with `\d table_name` in psql, not just migration status
- **Bulk operations on large tables** (5M+ rows):
  - Store IDs only (not ORM objects) in lookup dicts to avoid OOM
  - Use `SET statement_timeout = 0` for long-running UPDATEs
  - Use PostgreSQL temp tables + chunked UPDATEs (10k rows/chunk)
  - Taxonomy table uses UUID primary keys (not INTEGER)

**Godot Web Export**:
- Single-threaded mode: `variant/thread_support=false`
- 37MB WASM → 9MB gzipped
- Custom HTML shell: `export_templates/custom_html_shell.html` (high DPI fix)
- `scripts/export-to-prod.sh` handles export, gzip, backup, deployment

## Commands

**Dev**:
```bash
poetry shell
python manage.py makemigrations [accounts animals dex social vision images taxonomy]
python manage.py migrate
python manage.py runserver
celery -A biologidex worker -l info
python manage.py import_col  # Import COL taxonomy + NameRelation data
python manage.py link_col_parents [--dry-run]  # Link synonym→accepted + parent IDs
```

**Prod**:
```bash
cd server
docker-compose -f docker-compose.production.yml up -d
docker-compose -f docker-compose.production.yml logs -f
./scripts/deploy.sh              # Backend
./scripts/export-to-prod.sh      # Client
./scripts/monitor.sh             # Monitoring
```

**Testing**: Swagger UI at `/api/docs/`
**Logs**: `server/logs/biologidex.log`, Celery worker output
**Debug**: Set `DEBUG=True` in dev settings, use Django admin

---

## Planned Features

**Taxonomic Tree** (✅ implemented 2025-11-18, radial overhaul 2025-12-03):
- **Radial layout**: Eades algorithm with angular wedge allocation (guaranteed no overlaps)
- **Vertical layout**: Walker-Buchheim O(n) for rectangular trees
- Spatial chunking (2048x2048) for progressive loading
- Dynamic tree generation with modes: personal, friends, selected, global
- 5-minute server cache, dual-layer client cache (memory + disk)
- Endpoints: `/api/v1/graph/tree/`, `/tree/chunk/{x}/{y}/`, `/tree/search/`
- Layout files: `eades_radial.py` (radial), `reingold_tilford.py` (vertical)

**Future** (post-MVP):
- Phase 6: Multiple images per entry, image history
- Phase 7: Shared collections, collaborator permissions
- Phase 8: Dex Pages (scrapbook/journaling)
- Phase 9: Offline queue, conflict resolution, predictive prefetch
- Phase 10: Activity feed, achievements, leaderboards, challenges
- Phase 11: Export/import (CSV/JSON/PDF), data portability, storage quotas