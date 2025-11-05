# BiologiDex - Project Memory

## Project Overview
A Pokedex-style social network for sharing real-world zoological observations. Users photograph animals, which are identified via CV/LLM, then added to personal collections and a collaborative evolutionary tree shared with friends.

## Current Status (Updated 2025-11-05)
- ✅ **Backend API**: Django REST Framework - Phase 1 Complete
- ✅ **Database**: PostgreSQL with full schema implemented
- ✅ **CV Integration**: OpenAI Vision API with async processing
- ✅ **Frontend**: Godot 4.5 Client - Phase 1 Foundation Complete
- ✅ **Authentication**: Login and registration flows implemented in Godot client
- ✅ **Local Dex Database**: Client-side animal collection with JSON persistence
- ✅ **Dex Gallery**: Browse discovered animals with prev/next navigation
- ✅ **Production Infrastructure**: Docker Compose, Nginx, Gunicorn, Monitoring - Complete
- ✅ **Health & Metrics**: Prometheus integration, health checks, operational monitoring
- ✅ **Web Client Deployment**: Godot web export served via nginx at root path - Complete
- ✅ **Image Processing Pipeline**: Standardized dex-compatible images with server-side conversion
- ✅ **Image Transformations**: Client-side rotation UI with server-side processing and EXIF support
- ✅ **Dex Sync API**: Server endpoint for syncing dex entries with image checksums

---

## Technical Architecture

### Frontend Stack (Godot 4.5)
- **Engine**: Godot 4.5 (GL Compatibility renderer)
- **Target Platforms**: Web (primary), Mobile, Desktop
- **Base Resolution**: 1280×720 (16:9)
- **Stretch Mode**: canvas_items with expand aspect
- **Font Rendering**: MSDF (Multichannel Signed Distance Field)

### Client Structure
```
client/biologidex-client/
├── main.tscn                    # Main responsive scene
├── login.tscn / login.gd        # Login scene with token refresh
├── create_acct.tscn / create_account.gd  # Registration scene
├── home.tscn / home.gd          # Main app scene (post-auth)
├── camera.tscn / camera.gd      # Photo upload scene with CV integration
├── dex.tscn / dex.gd            # Dex gallery with prev/next navigation
├── record_image.tscn            # Animal record card component
├── api_manager.gd               # Global HTTP API singleton (autoload)
├── token_manager.gd             # JWT token persistence (autoload)
├── navigation_manager.gd        # Navigation singleton (autoload)
├── dex_database.gd              # Local dex storage singleton (autoload)
├── responsive.gd                # Base responsive behavior script
├── responsive_container.gd      # Auto-margin container class
├── theme.tres                   # Base theme resource
├── project.godot                # Project configuration
├── export_presets.cfg           # Web export configuration (single-threaded)
├── implementation-notes.md      # Phase 1 implementation details
└── export/web/                  # Godot web export output
    ├── index.html               # Entry point
    ├── index.wasm               # WebAssembly binary (~36MB)
    ├── index.pck                # Game data package
    ├── index.js                 # JavaScript loader
    └── [PWA assets]             # Manifest, service worker, icons
```

### Key Godot Patterns

**Responsive Design System**:
- AspectRatioContainer maintains 16:9 proportions
- Dynamic margin adjustment per device class (mobile: 16px, tablet: 32px, desktop: 48px)
- Viewport size monitoring with automatic layout updates
- Device class detection: mobile (<800px), tablet (800-1280px), desktop (>1280px)

**Navigation System**:
- Global NavigationManager singleton with history stack (max 10 scenes)
- Scene validation before navigation
- Back navigation support with `go_back()`
- Signals: `scene_changed`, `navigation_failed`

**Authentication Flow**:
- APIManager provides `login()` and `register()` methods
- Registration endpoint: `POST /users/` (username, email, password, password_confirm)
- Successful registration → auto-login → navigate to home with cleared history
- Form validation pattern: client-side checks before API call
- Error handling: parse field-specific errors from API response arrays
- Security: password fields cleared on errors, passwords redacted in logs
- Loading states: disable all inputs during API calls

**Camera Scene & CV Integration** (camera.tscn):
- FileAccessWeb plugin for HTML5 file selection (base64 → PackedByteArray)
- **Editor test cycling**: Auto-cycles through `TEST_IMAGES` array; increments index after each upload completes
- **Original format upload**: Images uploaded in native format (JPEG, PNG, etc.) - NO client-side conversion
- **Format handling**: Attempts preview with fallback; shows warning for unsupported formats but allows upload
- **Dex-compatible images**: After analysis, downloads server-processed PNG (max 2560x2560) from `dex_compatible_url`
- **Local caching**: Stores dex images in `user://dex_cache/` using URL hash as filename
- **Auto-save to DexDatabase**: After successful CV identification, saves record with creation_index to local database
- Two-stage image display:
  1. Simple preview (RecordImage/Image) during upload/analysis - may fail for unsupported formats
  2. Bordered display (RecordImage/ImageBorderAspectRatio) after identification - uses dex-compatible image
- Vision API workflow: Upload original → poll job status → download dex image → save to DexDatabase → display
- Display format: "Scientific name - common name" (e.g., "Recurvirostra americana - American Avocet")
- **Critical**: Update `current_image_width/height` with dex image dimensions before sizing calculations

**DexDatabase Singleton** (dex_database.gd):
- Manages local storage of discovered animals at `user://dex_database.json`
- Record format: `{creation_index: int, scientific_name: String, common_name: String, cached_image_path: String}`
- Navigation helpers: `get_next_index()`, `get_previous_index()`, `get_first_index()`
- Auto-saves on every `add_record()` call; loads on startup
- Maintains sorted array of creation_indices for efficient navigation
- Emits `record_added` signal when new animals discovered

**Dex Gallery Scene** (dex.tscn):
- Browse discovered animals in creation_index order
- Previous/Next buttons for navigation (auto-disable at boundaries)
- Loads images from `user://dex_cache/` using cached_image_path
- Empty state: "No animals discovered yet!" when database empty
- Uses same RecordImage component and sizing logic as camera scene
- Responds to DexDatabase signals for real-time updates

**RecordImage Component** (record_image.tscn):
- Dual image display: simple TextureRect + bordered AspectRatioContainer
- Dynamic aspect ratio: Calculate from texture, update container ratio, set custom_minimum_size.y
- Aspect ratio sizing: `await get_tree().process_frame` then `height = width / aspect_ratio`
- Label overlay: "Scientific name - common name" format on bordered display
- Image stretch modes: simple (keep aspect centered), bordered (scale to fill)

**Common Gotchas**:
- GDScript type inference: `min()`, `max()`, and `Array[T].pop_back()` return Variant - always explicitly type as `float` or `String`
- Reserved keywords: `class_name` is reserved, use `animal_class` or similar for variables
- `layout_mode` values: 0 = uncontrolled (no positioning), 1 = anchors, 2 = container, 3 = anchors preset only
- Children of containers need `layout_mode = 2`, not anchors
- AspectRatioContainer must use anchors (`layout_mode = 1`) to fill its parent Control
- Dynamic sizing: Use `await get_tree().process_frame` before reading calculated sizes
- Touch targets must be minimum 44×44 pixels for mobile
- MSDF fonts enable crisp rendering at all scales without rasterization
- **TokenManager**: Use `is_logged_in()` not `has_valid_token()` to check auth status
- **Image dimensions**: Always update `current_image_width/height` when changing displayed image
- **Web export gzip**: Set `HTTPRequest.accept_gzip = false` for web builds to avoid double decompression (browsers handle gzip automatically, causes `stream_peer_gzip.cpp` errors if Godot tries to decompress again)

### Backend Stack
- **Framework**: Django 4.2+ with Django REST Framework
- **Database**: PostgreSQL 15 (development via Docker)
- **Caching**: Redis (shared with Celery)
- **Task Queue**: Celery with Redis backend
- **Storage**: Google Cloud Storage (media files)
- **Authentication**: JWT via djangorestframework-simplejwt
- **API Docs**: drf-spectacular (OpenAPI/Swagger)

### Project Structure
```
server/
├── biologidex/          # Main config (settings split: base/dev/prod)
├── accounts/            # Custom User, profiles, friend codes
├── animals/             # Canonical animal species database
├── dex/                 # User's animal collection entries
├── social/              # Friendships, friend requests
├── vision/              # CV/AI identification pipeline
└── graph/               # Evolutionary tree generation
```

### Key Models

**User (accounts.User)**
- Extends AbstractUser with UUID primary key
- `friend_code`: 8-char unique code for friend discovery
- `badges`: JSONField for achievements
- Auto-creates UserProfile via signals

**Animal (animals.Animal)**
- Full taxonomic hierarchy (kingdom → species)
- `creation_index`: Sequential discovery number (Pokedex-style)
- `verified`: Admin approval flag
- Auto-parsed genus/species from scientific_name

**DexEntry (dex.DexEntry)**
- Links User ↔ Animal with images and metadata
- `visibility`: private/friends/public
- `customizations`: JSONField for card styling
- GPS coordinates optional
- Auto-updates user profile stats via signals
- **Image fields**:
  - `original_image`: User's uploaded image
  - `processed_image`: Optional cropped/edited version
  - `source_vision_job`: FK to AnalysisJob (provides dex_compatible_image)
  - `display_image_url` property: Smart fallback (dex_compatible → processed → original)

**Friendship (social.Friendship)**
- Bidirectional model with status (pending/accepted/rejected/blocked)
- Helper methods: `are_friends()`, `get_friends()`, `get_friend_ids()`
- Prevents self-friendship

**AnalysisJob (vision.AnalysisJob)**
- Tracks CV identification requests
- Stores: cost, tokens, processing time, raw API response
- Status: pending → processing → completed/failed
- Retry logic with exponential backoff
- **Image fields**:
  - `image`: Original uploaded file (any format) - stored in `vision/analysis/original/%Y/%m/`
  - `dex_compatible_image`: Standardized PNG (max 2560x2560) - stored in `vision/analysis/dex_compatible/%Y/%m/`
  - `image_conversion_status`: pending/processing/completed/failed/unnecessary
- **API response**: Includes `dex_compatible_url` for client to download processed image

### Animal Identification Pipeline

**Flow**: Image upload → AnalysisJob created → Celery task → Image processing → OpenAI Vision API → Parse response → Create/lookup Animal → Complete job

**Key Components**:
1. **ImageProcessor** (vision/image_processor.py): Server-side image standardization
   - Converts images to PNG format (handles RGBA/transparency → RGB with white background)
   - Resizes images >2560px while maintaining aspect ratio (using Pillow/LANCZOS)
   - Returns `None` if original already meets criteria (triggers `unnecessary` status)
   - Stores metadata: original format, dimensions, resize/conversion flags
2. **ANIMAL_ID_PROMPT** (vision/constants.py): Standardized prompt requesting binomial nomenclature format
3. **OpenAIVisionService** (vision/services.py):
   - Handles GPT-4/5+ model differences (max_tokens vs max_completion_tokens)
   - Base64 image encoding
   - Cost calculation from token usage
   - **Uses dex-compatible image** for CV analysis (fallback to original if conversion fails)
4. **process_analysis_job** (vision/tasks.py): Celery task for async processing
   - **Step 1**: Process image with ImageProcessor (creates dex_compatible_image)
   - **Step 2**: Send dex-compatible image to Vision API
   - **Step 3**: Parse response and create/lookup Animal
5. **parse_and_create_animal**: Regex parsing of CV response, auto-creates Animal records

**Model Compatibility**:
- GPT-4 models: Use `max_tokens` parameter
- GPT-5+/o-series: Use `max_completion_tokens` parameter
- Auto-detection via model name prefix check

**Pricing Tracking**: All OpenAI pricing stored in `vision/constants.py` for cost calculation

### Image Transformation System

**Overview**: Client-side image rotation with server-side processing, enabling users to correct image orientation before CV analysis.

**Client-Side (camera.gd)**:
- Programmatically created rotation controls (Rotate Left/Right buttons)
- Visible when image preview loads successfully
- Tracks rotation state (0°, 90°, 180°, 270°) in `current_rotation` variable
- Stores transformations in `pending_transformations` dictionary
- Visual preview applies rotation using `rotation_degrees` property
- Swaps width/height dimensions when rotated 90° or 270° for aspect ratio calculations
- Transformations sent with image upload via multipart form data

**Server-Side Components**:
1. **images app** (server/images/): New Django app for centralized image management
   - **ProcessedImage model**: Tracks transformations, versioning, and checksums
     - Fields: original_file, processed_file, thumbnail, transformations (JSONField)
     - Metadata: original/processed dimensions, format, file size, EXIF data
     - Versioning: parent_image FK for image history
     - Deduplication: SHA256 checksums for original and processed files
   - **EnhancedImageProcessor** (images/processor.py):
     - `apply_transformations()`: Apply rotation, crop, and future transforms
     - `auto_rotate_from_exif()`: Auto-rotate based on EXIF orientation tag
     - `extract_exif_data()`: Extract and store EXIF metadata
     - `process_image_with_transformations()`: Combined processing pipeline

2. **Vision API Integration** (vision/views.py):
   - `create_vision_job()` accepts optional `transformations` parameter (JSON string or dict)
   - Parses and validates transformations before passing to Celery task

3. **Async Processing** (vision/tasks.py):
   - `process_analysis_job()` accepts `transformations` parameter
   - Uses EnhancedImageProcessor if transformations provided
   - Applies transformations before CV analysis
   - Falls back to basic ImageProcessor if no transformations

**Dex Sync API** (dex/views.py):
- `GET /api/v1/dex/entries/sync_entries/`: Sync endpoint for client
  - Query param: `last_sync` (ISO 8601 datetime) - returns entries updated after this time
  - Returns: Array of dex entries with image metadata
  - Includes: creation_index, scientific/common names, dex_compatible_url, image_checksum, updated_at
- **DexEntrySyncSerializer**: Specialized serializer with image checksums for comparison
  - Calculates SHA256 checksums of dex-compatible images
  - Returns absolute URLs for image downloads
  - Tracks image update timestamps for change detection

**Multipart Form Data** (api_manager.gd):
- `_build_multipart_body_with_fields()`: Handles multiple form fields
- Supports both file uploads (with filename/content-type) and text fields
- Used for sending image + transformations JSON in single request

**Implementation Files**:
- Server: `images/models.py`, `images/processor.py`, `images/admin.py`
- Server: `vision/tasks.py` (updated), `vision/views.py` (updated)
- Server: `dex/views.py` (sync endpoint), `dex/serializers.py` (DexEntrySyncSerializer)
- Client: `camera.gd` (rotation UI), `api_manager.gd` (multipart body builder)
- Migration: `images/migrations/0001_initial.py`

### API Endpoints

**Base URL**: `/api/v1/`

**Authentication** (`/auth/`):
- POST `/login/` - Returns JWT + user data
- POST `/refresh/` - Refresh access token

**Users** (`/users/`):
- POST `/` - Register (no auth required)
- GET `/me/` - Current user profile
- GET `/friend-code/` - Get your friend code
- POST `/lookup_friend_code/` - Find user by code

**Animals** (`/animals/`):
- GET `/` - List all (public, paginated, filterable)
- POST `/lookup_or_create/` - Used by CV pipeline

**Dex Entries** (`/dex/entries/`):
- POST `/` - Create entry (after CV identification)
- GET `/my_entries/` - User's collection
- GET `/favorites/` - Favorite entries
- POST `/{id}/toggle_favorite/` - Toggle favorite
- GET `/sync_entries/` - Sync entries with image checksums (accepts `last_sync` query param)

**Social** (`/social/friendships/`):
- GET `/friends/` - Friends list
- GET `/pending/` - Incoming requests
- POST `/send_request/` - Send by friend_code or user_id
- POST `/{id}/respond/` - Accept/reject/block
- DELETE `/{id}/unfriend/` - Remove friendship

**Vision** (`/vision/jobs/`):
- POST `/` - Submit image (accepts optional `transformations` JSON), triggers async processing
- GET `/{id}/` - Check job status
- GET `/completed/` - View results
- POST `/{id}/retry/` - Retry failed job (accepts optional `transformations` JSON)

**Graph** (`/graph/`):
- GET `/evolutionary-tree/` - Network graph (cached)
- POST `/invalidate-cache/` - Clear cache

### Critical Implementation Details

**Migrations Order**:
```bash
# Always create migrations in this order:
python manage.py makemigrations accounts animals dex social vision images
python manage.py migrate
```
Reason: accounts.User is AUTH_USER_MODEL, must exist before admin/auth migrations. images app is independent and can be added last.

**Settings Configuration**:
- Development: `biologidex.settings.development`
- Production Local: `biologidex.settings.production_local` (Docker/local server)
- Production Cloud: `biologidex.settings.production` (GCP/cloud)
- manage.py defaults to development

**Required Environment Variables**:
- `SECRET_KEY`, `DB_PASSWORD`, `OPENAI_API_KEY`
- `GCS_BUCKET_NAME`, `GCS_PROJECT_ID`, `GOOGLE_APPLICATION_CREDENTIALS`
- See `.env.example` for complete list

**Celery Tasks**:
- `process_analysis_job`: CV identification
- `cleanup_old_analysis_jobs`: Periodic cleanup (optional)

**Caching Strategy**:
- Animal records: TTL from `ANIMAL_CACHE_TTL` (default 1 hour)
- Graph data: TTL from `GRAPH_CACHE_TTL` (default 2 minutes)
- Invalidation: Auto on model save, manual via API

### Design Philosophy
- **Modularity**: Each app self-contained (models, serializers, views, urls, admin)
- **Extensibility**: Abstract base classes (CVMethod) for adding services
- **Best Practices**:
  - Services layer for complex logic
  - Signals for cross-app updates
  - Proper permissions (IsAuthenticated, IsOwnerOrReadOnly)
  - Optimized queries (select_related, prefetch_related)
  - Comprehensive indexes

### Benchmarking System
Original CV benchmarking code (`scripts/animal_id_benchmark.py`) integrated into production vision app. Key learnings applied:
- Model parameter differences (GPT-4 vs GPT-5+)
- Cost tracking per API call
- Token usage monitoring
- Retry logic for reliability

---

## Production Infrastructure (Added 2025-10-26)

### Infrastructure Components

**Docker Compose Stack** (`docker-compose.production.yml`):
- **Nginx**: Reverse proxy, SSL termination, static files
- **Gunicorn**: Application server (workers = CPU*2+1)
- **PostgreSQL 15**: With pgBouncer connection pooling
- **Redis**: Cache + Celery broker (256MB, LRU policy)
- **Celery**: Worker + Beat for async tasks

### Configuration Files

**Critical Files Created**:
- `gunicorn.conf.py`: Worker management, logging, timeout settings
- `redis.conf`: Production Redis with persistence, security
- `init.sql`: PostgreSQL optimization, indexes, monitoring users
- `nginx/nginx.conf`: Reverse proxy, caching, security headers
- `biologidex/monitoring.py`: Prometheus metrics middleware
- `biologidex/health.py`: Health check endpoints

### Monitoring & Health

**Health Endpoints**:
- `/api/v1/health/`: Comprehensive health (DB, Redis, Celery, storage)
- `/health/`: Liveness check (simple alive status)
- `/ready/`: Readiness check (ready for traffic)
- `/metrics/`: Prometheus metrics endpoint

**Key Metrics Available**:
- `django_http_requests_total`: Request counts by endpoint
- `django_http_request_duration_seconds`: Response times
- `cv_processing_total`: CV job statistics
- `celery_tasks_total`: Task execution counts
- `active_users`, `total_dex_entries`: Business metrics

### Operational Scripts

**Deployment & Setup**:
- `scripts/setup.sh`: Complete Ubuntu server setup
- `scripts/deploy.sh`: Zero-downtime deployment with rollback
- `scripts/export-to-prod.sh`: Godot web client export and deployment
- `scripts/backup.sh`: Automated database backups
- `scripts/monitor.sh`: Real-time system monitoring dashboard
- `scripts/diagnose.sh`: Comprehensive diagnostics

**Documentation**:
- `client-host.md`: Detailed plan for Godot web client hosting architecture

### Production Settings

**Key Differences from Dev** (`production_local.py`):
- `DEBUG=False`, strict `ALLOWED_HOSTS`
- Connection pooling: `CONN_MAX_AGE=600`
- PrometheusMiddleware for metrics
- Structured JSON logging
- Security headers enabled
- Static file optimization

### Docker Production Patterns

**Multi-stage Dockerfile**:
1. Python dependencies stage (poetry install)
2. Build stage (collect static)
3. Production stage (minimal, non-root user)

**Health Checks**: All services have health checks for orchestration
**Volumes**: Persistent for postgres_data, redis_data, media_files
**Networks**: Isolated biologidex-network bridge

### Cloudflare Tunnel Integration

**Setup**: `cloudflared tunnel create biologidex`
**Config**: `/etc/cloudflared/config.yml` with ingress rules
**DNS**: Auto-configured via `cloudflared tunnel route dns`

### Critical Learnings

**Database Optimization**:
- Always use pgBouncer for connection pooling
- Create indexes AFTER Django migrations
- Use `ATOMIC_REQUESTS=True` for transaction safety

**Redis Configuration**:
- Set `maxmemory-policy allkeys-lru` for cache behavior
- Rename dangerous commands (FLUSHDB, KEYS)
- Use password auth even in private networks

**Gunicorn Tuning**:
- `max_requests=1000` prevents memory leaks
- `preload_app=True` for faster worker spawns
- Access logs essential for debugging

**Monitoring Best Practices**:
- Instrument early (PrometheusMiddleware)
- Multiple health check levels (liveness vs readiness)
- Log aggregation with structured JSON

**Docker Compose Patterns**:
- Always use health checks for dependencies
- Scale with `--scale web=N` for load testing
- (Deprecated) Use `.env.production` for secrets (never commit)
  - Just use a single .env file

### Troubleshooting Quick Reference

| Issue | Check | Fix |
|-------|-------|-----|
| 502 Bad Gateway | `docker-compose ps web` | Restart web service |
| DB Connection Errors | `docker-compose exec db pg_isready` | Check pgBouncer config |
| Celery Tasks Stuck | `celery inspect active` | Restart workers |
| High Memory | `docker stats` | Reduce Gunicorn workers |
| Slow API | Check `/metrics/` endpoint | Add caching/indexes |

### Files to Never Modify in Production
- (Deprecated)`.env.production` (use environment-specific overrides)
  - Just use a single .env file
- `init.sql` (runs only on first DB creation)
- Migration files (use new migrations for changes)

---

## Godot Web Client Deployment (Added 2025-10-29)

### Overview
Godot 4.5 web client served via nginx at root path (`/`), with Django API at `/api/` and admin at `/admin/`.

### Export Configuration

**Single-Threaded Mode** (Best Compatibility):
- `export_presets.cfg`: `variant/thread_support=false`
- `progressive_web_app/ensure_cross_origin_isolation_headers=false`
- No COOP/COEP headers required
- Works on all browsers including Safari/iOS
- Compatible with all hosting platforms (itch.io, Newgrounds, etc.)

### Deployment Workflow

**Export Script**: `server/scripts/export-to-prod.sh`
- Automated Godot CLI export using headless mode
- Pre-compression (gzip) for performance
- Backup system (keeps last 5 deployments)
- Rollback capability on failure
- Zero-downtime deployment

**Usage**:
```bash
cd server
./scripts/export-to-prod.sh              # Full export + deploy
./scripts/export-to-prod.sh --skip-export  # Deploy existing export
```

### File Structure

**Production Path**: `server/client_files/`
- Mounted in nginx container at `/var/www/biologidex/client/`
- Served directly by nginx (no proxy)
- Automatic backups in `server/client_files_backup/`

### Nginx Configuration

**URL Routing**:
```
/                  → Godot web client (index.html)
/api/              → Django REST API (proxied to port 8000)
/admin/            → Django admin panel (proxied to port 8000)
/static/           → Django static files
/media/            → User uploaded media
```

**MIME Types**:
- `.wasm` → `application/wasm` (already in default mime.types)
- `.pck` → `application/octet-stream`

**Caching Strategy**:
- `.wasm`, `.pck`: 7 days, immutable
- `.html`: 1 hour, must-revalidate
- `.js`, `.css`: 1 hour, public
- PWA files (manifest.json, service.worker.js): no-cache

**Compression**:
- gzip enabled for all text assets and wasm
- Pre-compressed .gz files served via `gzip_static on`
- Brotli optional (requires module)

### Docker Integration

**Volume Mount** (docker-compose.production.yml):
```yaml
nginx:
  volumes:
    - ./client_files:/var/www/biologidex/client:ro
```

**Deployment**:
```bash
# After running export-to-prod.sh
docker-compose -f docker-compose.production.yml exec nginx nginx -s reload
```

### Cloudflare Tunnel Configuration

**Critical**: Tunnel must point to **nginx (port 80)**, not Django (port 8000)

**Token-based setup** (via Cloudflare dashboard):
1. Navigate to Zero Trust → Networks → Tunnels
2. Configure tunnel → Public Hostname
3. Set service URL: `http://localhost:80`

**Config-based setup** (/etc/cloudflared/config.yml):
```yaml
ingress:
  - hostname: biologidex.io
    service: http://localhost:80  # nginx, not 8000
```

**HTTPS Gotcha** (Mixed Content Prevention):
- Cloudflare Tunnel terminates SSL externally, forwards HTTP to nginx
- Must force `X-Forwarded-Proto: https` in nginx proxy headers (not `$scheme`)
- Django's `build_absolute_uri()` checks this header via `SECURE_PROXY_SSL_HEADER`
- Without this: API returns `http://` URLs causing mixed content errors in browser
- Config: `proxy_set_header X-Forwarded-Proto https;` in `/api/` and `/admin/` locations

### Critical Learnings

**Environment Variable Parsing**:
- `.env` files **cannot have inline comments** after values
- BAD: `DB_HOST=db  # Docker service name`
- GOOD: `DB_HOST=db`
- Inline comments are parsed as part of the value

**Docker Compose env_file**:
- `docker-compose.production.yml` references specific env file
- Default is `.env`, not `.env.production`
- Must explicitly rename or update compose file

**Database Connection in Docker**:
- Use service names, not `localhost`
- `DB_HOST=db` (Docker service name)
- `REDIS_HOST=redis` (Docker service name)
- `localhost` only works outside containers

**Password Changes Require Volume Rebuild**:
- PostgreSQL and Redis store credentials in volumes
- Changing passwords in `.env` doesn't update running containers
- Must remove volumes and reinitialize:
  ```bash
  docker-compose down -v  # Removes ALL volumes (deletes data)
  docker-compose up -d    # Fresh start with new passwords
  ```

**Nginx Location Directive Gotchas**:
- Cannot use nested `location` blocks inside `location` with `alias`
- Regex locations (`~*`) evaluated before prefix locations
- Use `root` with regex, `alias` with prefix
- `try_files` with `alias` requires careful syntax

**Docker Production Code Deployment** (Critical):
- Production uses **built Docker images**, NOT mounted volumes
- Code changes require **rebuilding images**: `docker-compose -f docker-compose.production.yml build web celery_worker celery_beat`
- After rebuild, **restart containers**: `docker-compose -f docker-compose.production.yml up -d`
- Simply restarting containers (`restart`) uses OLD cached images
- Host files at `/opt/biologidex/server` are NOT used by running containers (they use `/app` inside container)

**Migration State Sync Issues**:
- Migrations can show as applied in `django_migrations` table but columns missing in actual database
- Fix: Fake unapply then reapply: `migrate vision 0001 --fake` then `migrate vision`
- Always verify actual database schema with `\d table_name` in psql, not just migration status
- Python bytecode cache can cause stale code issues - full container rebuild resolves this

### Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| 404 at root path | Cloudflare tunnel points to Django | Point tunnel to port 80 (nginx) |
| Client files not found | Volume not mounted | Check docker-compose.yml volume mount |
| 301 redirect loop | try_files directive issue | Simplify to `try_files $uri /index.html` |
| Black screen | CORS/MIME type issues | Check browser console for errors |
| DB connection refused | DB_HOST=localhost in container | Set DB_HOST=db (service name) |
| Inline comment in env value | Bash treats everything after `=` as value | Remove inline comments from .env |

### Performance Optimization

**Asset Loading**:
- 37MB WASM file compresses to ~9MB with gzip
- Enable gzip_static to serve pre-compressed files
- Use CDN for static assets in production (future)

**Browser Cache**:
- Long cache for immutable assets (.wasm, .pck)
- Short cache for HTML (allows updates)
- No cache for PWA files (service worker control)

---

## Development Workflow

**Setup**: `poetry install` → `docker-compose up -d` → migrations → `runserver`

**Testing**: Use Swagger UI at `/api/docs/` for interactive testing

**Common Commands**:
```bash
# Development
poetry shell                           # Activate environment
python manage.py makemigrations       # Create migrations
python manage.py migrate              # Apply migrations
python manage.py createsuperuser      # Admin access
python manage.py runserver            # Dev server
celery -A biologidex worker -l info   # Start worker

# Production
docker-compose -f docker-compose.production.yml up -d     # Start all services
docker-compose -f docker-compose.production.yml logs -f   # View logs
docker-compose -f docker-compose.production.yml ps        # Check status
./scripts/deploy.sh                                       # Deploy backend updates
./scripts/export-to-prod.sh                               # Deploy Godot client
./scripts/monitor.sh                                      # Real-time monitoring
./scripts/diagnose.sh                                     # System diagnostics
```

**Debugging**:
- Set `DEBUG=True` in development settings
- Logs: `server/logs/biologidex.log`
- Check Celery worker output for async task errors
- Use Django admin panel for data inspection

---

## Next Steps

### Frontend - Phase 2: Core Pages
- ✅ Login/Registration scenes (connect to `/api/v1/auth/`)
- Home screen with tab navigation (Dex, Camera, Tree, Social)
- Profile view with stats and badges
- Camera integration placeholder
- Dex entry creation flow (capture → identify → create entry)

### Backend - Future Phases
- Enhanced CV pipeline (multiple providers)
- Gamification features (achievements, leaderboards)
- Real-time updates (WebSockets)

## Environment Setup
- `.env` file in `server/` directory with all credentials
- Python 3.12+ with pyenv + Poetry
- Docker for PostgreSQL and Redis
- Google Cloud account for media storage