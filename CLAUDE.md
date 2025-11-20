# BiologiDex - Claude Context

## Project Overview
Pokedex-style social network for wildlife observations. Users photograph animals → CV/LLM identifies → add to personal dex → view in collaborative taxonomic tree with friends.

## Stack
- **Backend**: Django 4.2+ REST Framework, PostgreSQL 15, Redis, Celery, OpenAI Vision API
- **Frontend**: Godot 4.5 (web-primary), JWT auth, multi-user local storage
- **Infra**: Docker Compose, Nginx reverse proxy, Gunicorn, Prometheus monitoring
- **Storage**: Google Cloud Storage (media), local dex cache with deduplication

## Status (2025-11-20)
- ✅ Auth, CV pipeline, multi-user dex sync, image processing, production deployment
- ✅ Incremental sync, image deduplication, HTTP caching, retry logic
- ✅ Multi-stage taxonomy matching with synonym resolution (NameRelation support)
- ✅ Taxonomic tree visualization with Walker-Buchheim O(n) layout algorithm
- ✅ Two-step image upload workflow (convert → download → analyze)
- ✅ Multiple animal detection support with selection API
- ✅ Client-side image rotation with post-conversion transformations

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

**UI Layout**:
- `layout_mode`: 0=uncontrolled, 1=anchors, 2=container, 3=anchors preset
- Container children: `layout_mode = 2`
- AspectRatioContainer: `layout_mode = 1` with anchors
- Touch targets: min 44×44px for mobile

**Images & Camera Workflow (Updated 2025-11-20)**:
- **Two-step upload workflow**:
  1. Client uploads → `/images/convert/` → Server converts to PNG → Returns conversion_id
  2. Client downloads converted PNG, can rotate/preview → Submits to `/vision/jobs/` with conversion_id
- **State machine** (camera.gd): IDLE → IMAGE_SELECTED → IMAGE_CONVERTING → IMAGE_READY → ANALYZING → ANALYSIS_COMPLETE → (ANIMAL_SELECTION) → COMPLETED
- Image rotation: Client-side using `Image.rotate_90(CLOCKWISE)`, sent as `post_conversion_transformations`
- Multiple animal detection: Backend returns `detected_animals` array, client auto-selects if 1, shows selection UI if >1
- Never call `_update_record_image_size()` during rotation of simple preview
- RecordImage: Dual display (simple TextureRect + bordered AspectRatioContainer)

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

### Server (Django)
- **Apps**: accounts (User, profiles), animals (species DB), dex (user collections), social (friendships), vision (CV pipeline), graph (taxonomic tree), images (transformation system)
- **Settings**: `biologidex.settings.{development|production_local|production}`

**Key Models**:
- **User**: UUID pk, `friend_code` (8-char), `badges` JSONField
- **Animal**: Taxonomic hierarchy, `creation_index` (sequential), `verified` flag
- **Taxonomy**: COL data, `source_taxon_id`, hierarchy fields, `accepted_name` FK (often unpopulated)
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

**Godot Web Export**:
- Single-threaded mode: `variant/thread_support=false`
- 37MB WASM → 9MB gzipped
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

**Taxonomic Tree** (✅ implemented 2025-11-18):
- Walker-Buchheim O(n) layout algorithm for aesthetically pleasing, compact tree layouts
- No node overlaps, proper spacing for multiple animals per species
- Spatial chunking (2048x2048) for progressive loading
- Dynamic tree generation with modes: personal, friends, selected, global
- 5-minute server cache, dual-layer client cache (memory + disk)
- Endpoints: `/api/v1/graph/tree/`, `/tree/chunk/{x}/{y}/`, `/tree/search/`
- See `/server/graph/README.md` for algorithm details and performance characteristics

**Future** (post-MVP):
- Phase 6: Multiple images per entry, image history
- Phase 7: Shared collections, collaborator permissions
- Phase 8: Dex Pages (scrapbook/journaling)
- Phase 9: Offline queue, conflict resolution, predictive prefetch
- Phase 10: Activity feed, achievements, leaderboards, challenges
- Phase 11: Export/import (CSV/JSON/PDF), data portability, storage quotas