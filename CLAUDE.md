# BiologiDex - Project Memory

## Project Overview
A Pokedex-style social network for sharing real-world zoological observations. Users photograph animals, which are identified via CV/LLM, then added to personal collections and a collaborative evolutionary tree shared with friends.

## Current Status (Updated 2025-10-20)
- ✅ **Backend API**: Django REST Framework - Phase 1 Complete
- ✅ **Database**: PostgreSQL with full schema implemented
- ✅ **CV Integration**: OpenAI Vision API with async processing
- ⏳ **Frontend**: Not started

---

## Technical Architecture

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
- Production: `biologidex.settings.production`
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

## Development Workflow

**Setup**: `poetry install` → `docker-compose up -d` → migrations → `runserver`

**Testing**: Use Swagger UI at `/api/docs/` for interactive testing

**Common Commands**:
```bash
poetry shell                           # Activate environment
python manage.py makemigrations       # Create migrations
python manage.py migrate              # Apply migrations
python manage.py createsuperuser      # Admin access
python manage.py runserver            # Dev server
celery -A biologidex worker -l info   # Start worker
```

**Debugging**:
- Set `DEBUG=True` in development settings
- Logs: `server/logs/biologidex.log`
- Check Celery worker output for async task errors
- Use Django admin panel for data inspection

---

## Next Steps (Phase 2+)
- Frontend development (React/Vue.js)
- Enhanced CV pipeline (multiple providers)
- Gamification features (achievements, leaderboards)
- Real-time updates (WebSockets)
- Mobile app considerations

## Environment Setup
- `.env` file in `server/` directory with all credentials
- Python 3.12+ with pyenv + Poetry
- Docker for PostgreSQL and Redis
- Google Cloud account for media storage