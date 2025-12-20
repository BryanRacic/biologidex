# BiologiDex - Claude Context

## Project Overview
Pokedex-style social network for wildlife observations. Users photograph animals → CV/LLM identifies → add to personal dex → view in collaborative taxonomic tree with friends.

## Stack
- **Backend**: Django 4.2+ REST Framework, PostgreSQL 15, Redis, Celery, OpenAI Vision API
- **Frontend**: Godot 4.5 (web-primary), JWT auth, multi-user local storage
- **Infra**: Docker Compose, Nginx reverse proxy, Gunicorn, Prometheus monitoring
- **Storage**: Google Cloud Storage (media), local dex cache with deduplication

---

## ⚠️ COORDINATE SPACE CONVENTIONS (Common Bug Source)

**Many positioning bugs stem from mixing coordinate spaces.** When debugging position issues, first verify which space you're working in:

| Space | Units | Origin | Used For |
|-------|-------|--------|----------|
| **Screen** | Pixels | Top-left (0,0) | UI, input events, viewport dimensions |
| **World** | World units | Scene origin | Node.position, camera offset, world content |
| **Tree-local** | World units | Tree root (0,0) | Server-provided node positions |

### Critical Formulas
- `scroll_offset` = world position that appears at viewport center
- When `scroll_offset = (0,0)`, world origin is centered on screen
- `world_to_screen(W)` = `(W - scroll_offset) * scale + viewport_center`
- `screen_to_world(S)` = `(S - viewport_center) / scale + scroll_offset`

### Common Coordinate Mistakes
- ❌ Applying scale to scroll_offset when centering: `scroll_offset = pos * scale` → WRONG
- ✅ To center on world pos: `scroll_offset = pos` (no scale!)
- ❌ Mixing screen-space margins with world-space comparisons
- ❌ Forgetting tree-local → world conversion when tree has transform
- ❌ Using `get_viewport_rect()` before node is in tree (guard with `is_inside_tree()`)
- Culling margins: define in **screen pixels**, convert to world via `margin / scale`
- View rect center = `scroll_offset` directly (NOT scaled)

### Vector2 Documentation Standard
**ALWAYS document coordinate space for Vector2 variables.** Use suffix or comment:
```gdscript
# Option 1: Suffix naming
var scroll_offset_world: Vector2
var node_position_tree_local: Vector2
var click_pos_screen: Vector2

# Option 2: Inline comment (acceptable for locals)
var pos: Vector2  # screen space
var target: Vector2  # tree-local

# Option 3: Docstring for class members
## Arrow position in tree-local coordinates (same space as node.position)
var arrow_position: Vector2
```
- ✅ Functions accepting/returning Vector2 must document space in docstring
- ✅ Conversion functions should name both spaces: `_screen_to_tree_local()`, `_world_to_screen()`
- ❌ Never leave Vector2 space ambiguous - causes subtle positioning bugs

---

## Client Architecture (Godot 4.5)

- 1280×720 base, canvas_items stretch, MSDF fonts
- **Singletons**: APIManager, TokenManager, NavigationManager, DexDatabase (v2.0), SyncManager
- **API Layer**: HTTPClientCore → APIClient → Services → APIManager
- **Storage**: `user://dex_data/{user_id}_dex.json`, `user://dex_cache/{user_id}/`

### ⚠️ Critical Client Gotchas

**API Usage**:
- ✅ `APIManager.<service>.<method>()` for all calls
- ✅ Callbacks: `func(response: Dictionary, code: int)` - check `code == 200 or 201`
- ✅ Use `.bind(context)` for callbacks
- ✅ `request_get()`, `post()`, `put()`, `delete()` (NOT `.get()`)
- ✅ Always check `callback.is_valid()` before calling (prevents freed scene crashes)
- ✅ URL params: use `&` not `&amp;` (HTML encoding breaks server)
- ❌ Never inline lambdas in service methods (causes parse errors)
- ❌ Never call `api_client` directly

**GDScript**:
- `min()`, `max()`, `Array[T].pop_back()` return Variant → cast explicitly
- `class_name` is reserved → use `animal_class`
- `await get_tree().process_frame` before reading dynamic Control sizes
- Positional args ONLY (no `param=value` syntax)
- Dictionary value access needs explicit types: `var x: float = dict.value`

**Multi-User Dex**:
- **Camera must create BOTH** local (DexDatabase) AND server-side entries
- Auto-sync when: database empty OR `SyncManager.get_last_sync()` returns null

**Auth**: Use `TokenManager.is_logged_in()` NOT `has_valid_token()`

---

## ⚠️ Web Export Critical Issues (Godot 4.5)

**Baseline Config**:
- Single-threaded mode required (`variant/thread_support=false`)
- `HTTPRequest.accept_gzip = false` (avoid double decompression)
- **High DPI fix**: Custom HTML shell at `export_templates/custom_html_shell.html`
  - `canvas_resize_policy=1` (Project setting) prevents double-scaling
  - `stretch/mode="canvas_items"` + `allow_hidpi=true` in project settings
  - Safe area insets for notched devices

**CRITICAL - Instanced Scene Children Bug (GitHub #101975)**:
- Nodes added as children of instanced scenes in .tscn files **DON'T LOAD** on web
- Symptom: UI works in editor/desktop but nodes are null/missing on web
- ❌ BROKEN: Adding children to `InstancedScene/InternalNode/` in parent .tscn
- ✅ FIX: Add UI as SIBLING to instanced scene with separate CanvasLayer
- Pattern: Create `{Scene}UILayer` (CanvasLayer, layer=10) as sibling to PaperCameraScene
- **All scenes using PaperCameraScene must follow this pattern**

**Unique Name Lookups Can Fail** on web export even for sibling nodes:
- Symptom: `%NodeName` returns null on web but works in editor/desktop
- ✅ FIX: Use explicit paths (`$UILayer/Control/VBoxContainer/Header/BackButton`) instead of `%BackButton`
- Initialize node references in `_on_scene_ready()` or `_ready()`, not with `@onready`
- Tree scene uses this pattern for all UI nodes

**World Content in Instanced Scenes** must be created programmatically:
- ❌ BROKEN: Adding nodes to `PaperCameraScene/WorldContent/ContentContainer/` in .tscn
- ✅ FIX: Create in code using `_paper_camera.content_container.add_child(node)`
- Tree scene creates TreeGraph and all layers (EdgesLayer, NodesLayer, etc.) in `_setup_renderer()`

**Control.size Unreliable** - dynamically created Controls may report incorrect `size`:
- ✅ FIX: Pass dimensions explicitly via `setup(width, height)` and store them
- FeedCarouselRenderer uses `_container_width`/`_container_height` instead of `size`

**get_viewport_rect() Timing** - async callbacks can fire before node is in tree:
- ✅ FIX: Guard with `if not is_inside_tree(): return` before calling `get_viewport_rect()`
- Added to: `tree_renderer.gd:update_view()`, `paper_camera_scene.gd:get_view_rect()`

**CORS for Media Files**: Nginx must add CORS headers for `/media/` location (see `nginx.conf`)

---

## Key Components Reference

| Component | Location | Key Info |
|-----------|----------|----------|
| **PaperCameraScene** | `features/camera_system/` | Pan/zoom for all scenes. UI must be SIBLING CanvasLayer (web bug). Signals: `view_changed`, `tap_detected` |
| **TreeVisualization** | `features/tree_visualization/` | Composition pattern. Create programmatically, call `setup(paper_camera)` after adding. Signals: `tree_loaded`, `node_selected`, `navigation_requested` |
| **TreeNavigationArrows** | `features/tree_visualization/` | Shows arrows for node closest to screen center. Uses `_input()` hit detection (not Area2D). Min 44px touch targets |
| **DexRecordImage** | `features/ui/components/dex_record_image/` | Type as `DexRecordImage` not `AspectRatioContainer`. Proportional sizing (borders/fonts scale with size) |
| **RadialMenu*** | `features/ui/components/radial_menu/` | Two variants: RadialMenuRing (arcs), RadialMenuCircles (circles). Set properties BEFORE adding to tree |
| **JournalTabs** | `features/ui/components/journal_tabs/` | Pre-sizes `_tab_rects` array before drawing for correct hit detection |
| **RecenterButton** | `features/ui/components/recenter_button/` | Fade animation. Uses world units for threshold |
| **WorldSpaceUI** | `features/ui/components/world_space_ui/` | Container that pans with world (tree background) |
| **ClipboardHelper** | `features/ui/components/clipboard/` | Web clipboard read restricted; requires user interaction for write |

### Scene Structure Pattern (Web-Compatible)
```
{Scene} (Node2D)
├── PaperCameraScene (background + camera)
│   └── WorldContent/ContentContainer (ADD WORLD CONTENT PROGRAMMATICALLY)
└── {Scene}UILayer (CanvasLayer, layer=10) ← SIBLING, not child!
```

---

## Tree Visualization Specifics

**Root**: Animalia at depth 0, positioned at world origin (0,0)

**Rendering Rules**:
- Re-render edges on ANY view change (scroll OR scale), not just scale
- Edge visibility: bounding box intersection (`Rect2.expand().intersects()`), not endpoint checks
- Label culling: priority-based + zoom-filtered by taxonomic rank

**Branch Extension** (reduces dex image overlap):
- Even siblings: base extension (0.6 × DEX_IMAGE_SIZE)
- Odd siblings: base + alt extension (0.6 + 0.5 × DEX_IMAGE_SIZE)
- Extended positions in `extended_positions` dict; edges draw to extended endpoints

**Navigation Arrows**:
- Only show for node closest to screen center (updates as user pans)
- Coordinate conversion: screen → world → tree-local via `_screen_to_tree_local()`
- Extra offset near dex images; diff-circle aware at root
- Max 40% of edge length; hidden on short edges (<120 units)

**Image Loading**:
- Lazy load via VisibleOnScreenNotifier2D (500 world unit margin)
- Queue prioritized by distance to viewport center
- Max 4 concurrent loads, 1 new per frame
- LoadState: IDLE → QUEUED → LOADING → LOADED/FAILED

**Visibility Throttling**:
- Dirty flag: recalculate only when view moves >50 world units
- Minimum update interval during fast scrolling

---

## Camera Workflow

**Two-step upload**: POST `/images/convert/` → download PNG → POST `/vision/jobs/` with conversion_id

**State machine** (camera.gd): IDLE → IMAGE_SELECTED → IMAGE_CONVERTING → IMAGE_READY → ANALYZING → ANALYSIS_COMPLETE → (ANIMAL_SELECTION) → COMPLETED

**Multiple animals**: Backend returns `detected_animals` array; client auto-selects if 1, shows selection UI if >1

---

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
- **CRITICAL BUG (GitHub #101975)**: Children added to instanced scenes in .tscn files don't load on web export. See "Web Export" section in Critical Patterns & Gotchas for workaround.

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

**Taxonomic Tree** (✅ implemented 2025-11-18, radial overhaul 2025-12-03, root centering fix 2025-12-18):
- **Radial layout**: Eades algorithm with angular wedge allocation (guaranteed no overlaps)
- **Vertical layout**: Walker-Buchheim O(n) for rectangular trees
- **Root centering**: Single kingdom (Animalia) promoted to root at depth 0, centered at origin (0,0). Multi-kingdom case uses "Life" as explicit root.
- Spatial chunking (2048x2048) for progressive loading
- Dynamic tree generation with modes: personal, friends, selected, global
- 5-minute server cache, dual-layer client cache (memory + disk)
- Endpoints: `/api/v1/graph/tree/`, `/tree/chunk/{x}/{y}/`, `/tree/search/`
- Layout files: `eades_radial.py` (radial), `reingold_tilford.py` (vertical)
- Service: `services_dynamic.py:DynamicTaxonomicTreeService` - hierarchy building, layout, caching

**Future** (post-MVP):
- Phase 6: Multiple images per entry, image history
- Phase 7: Shared collections, collaborator permissions
- Phase 8: Dex Pages (scrapbook/journaling)
- Phase 9: Offline queue, conflict resolution, predictive prefetch
- Phase 10: Activity feed, achievements, leaderboards, challenges
- Phase 11: Export/import (CSV/JSON/PDF), data portability, storage quotas