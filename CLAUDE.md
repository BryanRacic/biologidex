# BiologiDex - Claude Context

## Project Overview
Pokedex-style social network for wildlife observations. Users photograph animals → CV/LLM identifies → add to personal dex → view in collaborative taxonomic tree with friends.

## Stack
- **Backend**: Django 4.2+ REST Framework, PostgreSQL 15, Redis, Celery, OpenAI Vision API
- **Frontend**: Godot 4.5 (web-primary), JWT auth, multi-user local storage
- **Infra**: Docker Compose, Nginx reverse proxy, Gunicorn, Prometheus monitoring
- **Storage**: Google Cloud Storage (media), local dex cache with deduplication

## Status (2025-11-11)
- ✅ Auth, CV pipeline, multi-user dex sync, image processing, production deployment
- ✅ Incremental sync, image deduplication, HTTP caching, retry logic
- 📋 Taxonomic tree visualization (planned, ready to build)

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
- ✅ Callbacks: `func(response: Dictionary, code: int)` - always check `code == 200`
- ✅ Traditional callbacks with `.bind(context)`, NOT inline lambdas
- ✅ Positional arguments ONLY (no `param=value` syntax in GDScript)
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

**Images**:
- Camera: Upload native format → server converts → download dex-compatible PNG (max 2560x2560)
- Image rotation: Use `Image.rotate_90(CLOCKWISE)` for pixel-level rotation, update dimensions
- Never call `_update_record_image_size()` during rotation of simple preview
- Update `current_image_width/height` when changing displayed image
- RecordImage: Dual display (simple TextureRect + bordered AspectRatioContainer)

**Multi-User Dex (v2.0)**:
- DexDatabase: User-partitioned storage, auto-migrates v1→v2, image deduplication across users
- SyncManager: Tracks `last_sync` per user in `sync_state.json`
- DexService: `sync_user_dex()`, `sync_user_dex_with_retry()` with exponential backoff
- Signals: `sync_started`, `sync_progress`, `sync_user_completed`, `sync_user_failed`

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
- **DexEntry**: User↔Animal, `visibility` (private/friends/public), `customizations` JSONField, image fields (original/processed/source_vision_job)
- **Friendship**: Bidirectional, status (pending/accepted/rejected/blocked), helpers: `are_friends()`, `get_friends()`, `get_friend_ids()`
- **AnalysisJob**: CV tracking, `image` (original), `dex_compatible_image` (PNG ≤2560px), status, cost/tokens
- **ProcessedImage** (images app): Transformations, versioning, SHA256 checksums, EXIF data

**CV Pipeline**:
- ImageProcessor: Converts to PNG (RGBA→RGB white bg), resizes >2560px, metadata
- OpenAIVisionService: GPT-4 (`max_tokens`) vs GPT-5+ (`max_completion_tokens`)
- Celery task: ImageProcessor → Vision API → parse/create Animal
- EnhancedImageProcessor (images): EXIF rotation, transformations, deduplication

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
**Vision**: `/vision/jobs/` (create w/transforms), `/{id}/` (status), `/completed/`, `/{id}/retry/`
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
- Code changes require rebuilding images: `docker-compose -f docker-compose.production.yml build web celery_worker celery_beat && up -d`
- Simply restarting uses OLD cached images
- Host files NOT used by containers (they use `/app` inside)
- Use service names for connections: `DB_HOST=db`, `REDIS_HOST=redis` (not `localhost`)
- Password changes require volume rebuild: `down -v` (deletes data) then `up -d`

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
python manage.py makemigrations [accounts animals dex social vision images]
python manage.py migrate
python manage.py runserver
celery -A biologidex worker -l info
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

**Taxonomic Tree** (ready to implement):
- Server-side Reingold-Tilford layout, spatial chunking (2048x2048), 100k+ nodes at 60 FPS
- Endpoints: `/graph/taxonomic-tree-layout/`, `/graph/chunk/{x}/{y}/`, `/graph/search/`

**Future** (post-MVP):
- Phase 6: Multiple images per entry, image history
- Phase 7: Shared collections, collaborator permissions
- Phase 8: Dex Pages (scrapbook/journaling)
- Phase 9: Offline queue, conflict resolution, predictive prefetch
- Phase 10: Activity feed, achievements, leaderboards, challenges
- Phase 11: Export/import (CSV/JSON/PDF), data portability, storage quotas