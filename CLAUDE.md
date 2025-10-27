# BiologiDex - Project Memory

## Project Overview
A Pokedex-style social network for sharing real-world zoological observations. Users photograph animals, which are identified via CV/LLM, then added to personal collections and a collaborative evolutionary tree shared with friends.

## Current Status (Updated 2025-10-26)
- ✅ **Backend API**: Django REST Framework - Phase 1 Complete
- ✅ **Database**: PostgreSQL with full schema implemented
- ✅ **CV Integration**: OpenAI Vision API with async processing
- ✅ **Frontend**: Godot 4.5 Client - Phase 1 Foundation Complete
- ✅ **Production Infrastructure**: Docker Compose, Nginx, Gunicorn, Monitoring - Complete
- ✅ **Health & Metrics**: Prometheus integration, health checks, operational monitoring

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
├── responsive.gd                # Base responsive behavior script
├── navigation_manager.gd        # Navigation singleton (autoload)
├── responsive_container.gd      # Auto-margin container class
├── theme.tres                   # Base theme resource
├── project.godot                # Project configuration
└── implementation-notes.md      # Phase 1 implementation details
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

**Common Gotchas**:
- GDScript type inference: `min()`, `max()`, and `Array[T].pop_back()` return Variant - always explicitly type as `float` or `String`
- Scene hierarchy: Main (Control) → Panel → AspectRatioContainer → MarginContainer → VBoxContainer
- Touch targets must be minimum 44×44 pixels for mobile
- MSDF fonts enable crisp rendering at all scales without rasterization

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

**Friendship (social.Friendship)**
- Bidirectional model with status (pending/accepted/rejected/blocked)
- Helper methods: `are_friends()`, `get_friends()`, `get_friend_ids()`
- Prevents self-friendship

**AnalysisJob (vision.AnalysisJob)**
- Tracks CV identification requests
- Stores: cost, tokens, processing time, raw API response
- Status: pending → processing → completed/failed
- Retry logic with exponential backoff

### Animal Identification Pipeline

**Flow**: Image upload → AnalysisJob created → Celery task → OpenAI Vision API → Parse response → Create/lookup Animal → Complete job

**Key Components**:
1. **ANIMAL_ID_PROMPT** (vision/constants.py): Standardized prompt requesting binomial nomenclature format
2. **OpenAIVisionService** (vision/services.py):
   - Handles GPT-4/5+ model differences (max_tokens vs max_completion_tokens)
   - Base64 image encoding
   - Cost calculation from token usage
3. **process_analysis_job** (vision/tasks.py): Celery task for async processing
4. **parse_and_create_animal**: Regex parsing of CV response, auto-creates Animal records

**Model Compatibility**:
- GPT-4 models: Use `max_tokens` parameter
- GPT-5+/o-series: Use `max_completion_tokens` parameter
- Auto-detection via model name prefix check

**Pricing Tracking**: All OpenAI pricing stored in `vision/constants.py` for cost calculation

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

**Social** (`/social/friendships/`):
- GET `/friends/` - Friends list
- GET `/pending/` - Incoming requests
- POST `/send_request/` - Send by friend_code or user_id
- POST `/{id}/respond/` - Accept/reject/block
- DELETE `/{id}/unfriend/` - Remove friendship

**Vision** (`/vision/jobs/`):
- POST `/` - Submit image, triggers async processing
- GET `/{id}/` - Check job status
- GET `/completed/` - View results
- POST `/{id}/retry/` - Retry failed job

**Graph** (`/graph/`):
- GET `/evolutionary-tree/` - Network graph (cached)
- POST `/invalidate-cache/` - Clear cache

### Critical Implementation Details

**Migrations Order**:
```bash
# Always create migrations in this order:
python manage.py makemigrations accounts animals dex social vision
python manage.py migrate
```
Reason: accounts.User is AUTH_USER_MODEL, must exist before admin/auth migrations

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
- `scripts/backup.sh`: Automated database backups
- `scripts/monitor.sh`: Real-time system monitoring dashboard
- `scripts/diagnose.sh`: Comprehensive diagnostics

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
  - Just use a single .env fil
- `init.sql` (runs only on first DB creation)
- Migration files (use new migrations for changes)

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
./scripts/deploy.sh                                       # Deploy updates
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
- Login/Registration scenes (connect to `/api/v1/auth/`)
- Home screen with tab navigation (Dex, Camera, Tree, Social)
- Profile view with stats and badges
- Camera integration placeholder

### Backend - Future Phases
- Enhanced CV pipeline (multiple providers)
- Gamification features (achievements, leaderboards)
- Real-time updates (WebSockets)

## Environment Setup
- `.env` file in `server/` directory with all credentials
- Python 3.12+ with pyenv + Poetry
- Docker for PostgreSQL and Redis
- Google Cloud account for media storage