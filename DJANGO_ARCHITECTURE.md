# BiologiDex Django Server - Comprehensive Architecture Analysis

## Executive Summary

BiologiDex is a Pokedex-style social network for zoological observations built with Django REST Framework. The server is a comprehensive backend system with 7 Django apps managing users, animal taxonomy, dex entries, social features, CV analysis, image processing, and evolutionary graphs. The project is production-ready with Docker containerization, Celery async tasks, PostgreSQL persistence, Redis caching, and OpenAI Vision API integration.

---

## Project Structure Overview

```
server/
├── biologidex/              # Django project config (7 apps)
│   ├── settings/
│   │   ├── base.py         # Shared settings (all environments)
│   │   ├── development.py
│   │   ├── production.py   # Cloud deployment
│   │   └── production_local.py  # Docker/local production
│   ├── middleware/
│   ├── urls.py             # Main URL router
│   └── wsgi.py
├── accounts/               # User management (Custom User + Profiles)
├── animals/                # Taxonomic species database
├── dex/                    # User dex entries (captures)
├── social/                 # Friendship/social features
├── vision/                 # CV/AI identification pipeline
├── graph/                  # Evolutionary tree generation
├── images/                 # Image processing & transformation
├── scripts/                # Deployment scripts
├── docker-compose.*.yml    # Container orchestration
├── Dockerfile.production   # Multi-stage production image
├── pyproject.toml          # Poetry dependencies
└── manage.py               # Django CLI
```

---

## Django Apps Architecture

### 1. ACCOUNTS APP - User Management
**Purpose:** Custom user model, profiles, and authentication

**Models:**
- `User` (extends AbstractUser)
  - Fields: UUID pk, email (unique), friend_code (8-char unique), bio, avatar, badges (JSON), created_at, updated_at
  - Methods: Auto-generates unique friend_code, validates uniqueness on save
  - Indexes: friend_code, email, created_at

- `UserProfile` (OneToOne with User)
  - Fields: total_catches, unique_species, preferred_card_style (JSON), join_date, last_catch_date
  - Methods: `update_stats()` recalculates stats from DexEntry records
  - Auto-created via signals when User created

**Key Features:**
- Custom AUTH_USER_MODEL for project-wide use
- Friend code system for peer discovery
- Stat tracking via signals from DexEntry
- UUID primary keys for all models

**Files:**
- `models.py` - User, UserProfile models
- `serializers.py` - User/profile serializers (likely)
- `views.py` - Registration, login, friend code lookup (REST endpoints)
- `urls.py` - Auth endpoints
- `admin.py` - Django admin config

**Management Commands:**
- `seed_test_users.py` - Creates testuser, admin, verified test users (--force flag to recreate)

---

### 2. ANIMALS APP - Species Taxonomy Database
**Purpose:** Master database of species with taxonomic and ecological data

**Model: Animal**
- **Primary Fields:**
  - id (UUID), scientific_name (unique), common_name, creation_index (sequential Pokedex #)
  - Taxonomic hierarchy: kingdom, phylum, class_name, order, family, genus, species
  - Description, habitat, diet, conservation_status (IUCN codes: LC, EN, CR, etc.)
  - interesting_facts (JSON list)
  - created_by (FK to User), verified (boolean), created_at, updated_at

- **Unique Constraints:**
  - scientific_name is globally unique
  - creation_index is globally unique (auto-incremented on save)

- **Properties & Methods:**
  - `discovery_count` - Number of unique users who captured this animal
  - `get_taxonomic_tree()` - Returns full taxonomy as dict

- **Indexes:** scientific_name, common_name, genus+species, creation_index, verified, created_at

- **Auto-Save Logic:**
  - If creation_index not set: Auto-assigns next sequential number
  - If genus/species empty: Parses from scientific_name (expects "Genus species" format)
  - Invalidates cache on every save

**Serializers:**
- `AnimalSerializer` - Full serialization with taxonomic_tree, discovery_count
- `AnimalListSerializer` - Lightweight for list views
- `AnimalCreateSerializer` - For CV pipeline

**ViewSet: AnimalViewSet**
- **Permissions:**
  - list/retrieve: AllowAny
  - create: IsAuthenticated
  - update/delete: IsAdminUser

- **Filtering:** conservation_status, verified, kingdom, phylum, family
- **Search:** scientific_name, common_name, genus, species
- **Ordering:** creation_index, created_at, scientific_name

- **Custom Actions:**
  - `GET /recent` - Last 20 discovered animals
  - `GET /popular` - Most captured animals
  - `GET /{id}/taxonomy` - Full taxonomy tree
  - `POST /lookup_or_create` - CV pipeline endpoint (find by scientific_name or create)

**Caching:**
- Animals cached with `ANIMAL_CACHE_TTL` (default 3600s)
- Cached via `Animal.get_cached(animal_id)` classmethod
- Cache invalidated on save

---

### 3. DEX APP - User Dex Entries (Animal Captures)
**Purpose:** User's personal record of captured/observed animals

**Model: DexEntry**
- **Relationships:**
  - owner (FK to User)
  - animal (FK to Animal)
  - source_vision_job (FK to AnalysisJob, optional)

- **Image Fields:**
  - original_image - User's uploaded image (any format)
  - processed_image - Optional user-edited version
  - `display_image_url` property - Smart fallback (dex_compatible → processed → original)

- **Location Data:**
  - location_lat, location_lon (decimal precision)
  - location_name (human-readable)
  - `get_location_coords()` method returns (lat, lon) tuple or None

- **Customization:**
  - notes (user notes)
  - customizations (JSON - card styling)
  - catch_date (when observed)
  - visibility (private/friends/public)
  - is_favorite (boolean)

- **Unique Constraint:** (owner, animal, catch_date) - User can capture same animal multiple times, tracked by date

- **Indexes:** (owner, animal), (owner, catch_date), (owner, visibility), (animal, visibility), catch_date, is_favorite

**Serializers:**
- `DexEntrySerializer` - Full entry with related data
- `DexEntrySyncSerializer` - For sync endpoint with checksums

**API Endpoints:**
- `POST /` - Create entry
- `GET /my_entries/` - User's collection
- `GET /favorites/` - Favorite entries
- `POST /{id}/toggle_favorite/` - Toggle favorite
- `GET /sync_entries/` - Sync with checksums (accepts `last_sync` datetime param)

---

### 4. SOCIAL APP - Friendships & Social Features
**Purpose:** Friend management and social connectivity

**Model: Friendship**
- **Bidirectional Model:**
  - from_user (FK to User, sender)
  - to_user (FK to User, receiver)
  - status (pending/accepted/rejected/blocked)
  - created_at, updated_at

- **Unique Constraint:** (from_user, to_user) - Prevents duplicate requests

- **Status Workflow:**
  - pending → created by `create_request()`
  - accepted → via `accept()` method
  - rejected → via `reject()` method
  - blocked → via `block()` method
  - unfriended → via `unfriend()` (deletes record)

- **Key Class Methods:**
  - `are_friends(user1, user2)` - Bidirectional check
  - `get_friends(user)` - Returns User queryset
  - `get_friend_ids(user)` - Returns list of friend UUIDs
  - `get_pending_requests(user)` - Requests user received
  - `create_request(from_user, to_user)` - Create with validation

- **Indexes:** (from_user, status), (to_user, status), (status, created_at)

**API Endpoints:**
- `GET /friends/` - Friends list
- `GET /pending/` - Pending requests
- `POST /send_request/` - Send by friend_code or user_id
- `POST /{id}/respond/` - Accept/reject/block
- `DELETE /{id}/unfriend/` - Remove friendship

---

### 5. VISION APP - CV/AI Identification Pipeline
**Purpose:** OpenAI Vision API integration for animal identification

**Model: AnalysisJob**
- **Tracks:** Image → Processing → Identification → Result

- **Input Fields:**
  - image (original uploaded file, any format)
  - dex_compatible_image (standardized PNG, max 2560x2560)
  - image_conversion_status (pending/processing/completed/failed/unnecessary)
  - user (FK to User who submitted)

- **Processing Fields:**
  - status (pending/processing/completed/failed)
  - cv_method (openai, fallback)
  - model_name (gpt-4o, gpt-5-mini, etc.)
  - detail_level (auto, low, high)

- **Results:**
  - raw_response (JSON from API)
  - parsed_prediction (extracted text)
  - identified_animal (FK to Animal or None)
  - confidence_score (0-1 if available)

- **Metrics:**
  - cost_usd, processing_time, input_tokens, output_tokens

- **Error Handling:**
  - error_message, retry_count (max 3)

- **Timestamps:** created_at, started_at, completed_at

- **Helper Methods:**
  - `mark_processing()` - Sets status, started_at
  - `mark_completed(**kwargs)` - Bulk sets fields
  - `mark_failed(error_message)` - Sets error, completed_at
  - `increment_retry()` - Increments retry counter

**Indexes:** (user, status), (status, created_at), identified_animal, created_at

**Services: OpenAIVisionService**
- **Methods:**
  - `identify_animal(image_path)` - Main identification
  - `encode_image(path)` - File → base64
  - `encode_image_from_bytes(bytes)` - Bytes → base64
  - `_calculate_cost(usage)` - Pricing per model

- **Model Handling:**
  - GPT-4 models: Use `max_tokens` param
  - GPT-5+/o-series: Use `max_completion_tokens` param
  - Auto-detection via model name prefix

**Celery Task: process_analysis_job(job_id, transformations=None)**
- **Workflow:**
  1. Get AnalysisJob record
  2. Process image to create dex-compatible PNG (ImageProcessor)
  3. Send dex-compatible image to OpenAI Vision API
  4. Parse response to extract scientific/common name
  5. Create/lookup Animal record
  6. Mark job complete with results
  
- **Retry Logic:** Exponential backoff (60s, 120s, 240s), max 3 retries
- **Image Processing:** Uses EnhancedImageProcessor if transformations provided

**Task: parse_and_create_animal(prediction, user)**
- **Input:** CV prediction string (expected format: "Genus species (common name)")
- **Parsing:** Regex extraction of binomial nomenclature
- **Output:** Animal instance (created or looked up)
- **Fallbacks:** Creates Animal if not found, auto-generates common_name if empty

**Constants:**
- `ANIMAL_ID_PROMPT` - Standardized prompt for CV
- `OPENAI_PRICING` - Dict of model pricing (Oct 2025 rates)

**API Endpoints:**
- `POST /jobs/` - Submit image for analysis
- `GET /jobs/{id}/` - Check job status
- `GET /jobs/completed/` - View results
- `POST /jobs/{id}/retry/` - Retry failed job

---

### 6. IMAGES APP - Image Processing & Transformation
**Purpose:** Centralized image management with transformation tracking

**Model: ProcessedImage**
- **Purpose:** Track all processed images with versioning and deduplication

- **Source Tracking:**
  - source_type (vision_job/user_upload/dex_edit)
  - source_id (UUID of source object)

- **Files:**
  - original_file, processed_file, thumbnail (all optional except original)

- **Metadata:**
  - original_format (JPEG, PNG, etc.)
  - original_dimensions, processed_dimensions (JSON)
  - file_size_bytes

- **Transformations:** transformations (JSON dict of applied transforms)
- **Processing Logs:** processing_warnings, processing_errors (JSON)
- **EXIF:** exif_data (extracted EXIF metadata)

- **Versioning:**
  - version (integer)
  - parent_image (FK to self for history)

- **Deduplication:**
  - original_checksum, processed_checksum (SHA256)

- **Helper Method:**
  - `calculate_checksum(file_field)` - SHA256 static method

- **Indexes:** (source_type, source_id), original_checksum, processed_checksum, created_at

**Services: ImageProcessor (Basic)**
- `process_image(image_file)` - Convert to PNG, resize if needed
  - Returns (processed_file, metadata_dict)
  - metadata: original_format, original_dims, processed_dims, resize_applied, error

**Services: EnhancedImageProcessor**
- `process_image_with_transformations(image_file, transformations, apply_exif_rotation=True)`
  - Applies user transformations (rotation, crop, etc.)
  - Auto-rotates based on EXIF orientation
  - Returns (processed_file, metadata_dict)

- `apply_transformations(image, transforms_dict)` - Apply transformations
- `auto_rotate_from_exif(image)` - Extract & apply EXIF rotation
- `extract_exif_data(image)` - Extract all EXIF metadata

**Usage Pattern:**
- Camera scene rotates image client-side (90° increments)
- Rotated PNG sent in upload request
- Server receives pre-rotated image (no transform needed)
- ImageProcessor converts to dex-compatible format

---

### 7. GRAPH APP - Evolutionary Tree Generation
**Purpose:** Generate taxonomic/evolutionary network graphs for visualization

**Service: EvolutionaryGraphService**
- **Purpose:** Build graph data showing animals discovered by user and friends

- **Main Method: get_graph_data(use_cache=True)**
  - Returns: `{nodes: [...], edges: [...], stats: {...}, metadata: {...}}`
  - Caches with `GRAPH_CACHE_TTL` (default 120s)

- **Private Methods:**
  - `_get_relevant_animals()` - Animals captured by user + friends
  - `_build_nodes(animals)` - Create node list with metadata
  - `_build_edges(animals)` - Create taxonomic relationship edges
  - `_calculate_stats(animals)` - Compute graph statistics

- **Node Structure:**
  ```json
  {
    "id": "uuid",
    "scientific_name": "Genus species",
    "common_name": "Common name",
    "creation_index": 42,
    "taxonomy": {...},
    "conservation_status": "LC",
    "verified": true,
    "captured_by_user": true,
    "capture_count": 2,
    "discoverer": {
      "user_id": "uuid",
      "username": "discoverer",
      "is_friend": true,
      "is_self": false
    }
  }
  ```

- **Edge Structure:**
  ```json
  {
    "source": "animal1_uuid",
    "target": "animal2_uuid",
    "relationship": "same_family",
    "family": "Felidae"
  }
  ```

- **Stats:** total_animals, user_captures, user_unique_species, friend_captures, friend_count, taxonomic_diversity

- **Cache Invalidation:** `invalidate_cache(user_id)` - Called when new animals discovered

**API Endpoints:**
- `GET /evolutionary-tree/` - Get graph data (cached)
- `POST /invalidate-cache/` - Invalidate cache manually

---

## Database Configuration

**Type:** PostgreSQL 15 (via docker-compose)

**Connection Pooling:**
- pgBouncer for production (via docker-compose.production.yml)
- `CONN_MAX_AGE=600` - 10-minute connection pooling in Django

**Models Table Summary:**
```
accounts_user             - Custom user with UUID pk, friend_code
accounts_userprofile      - Auto-created profile with stats
animals_animal            - Species taxonomy with creation_index
dex_dexentry              - User captures of animals
social_friendship         - Bidirectional friend relationships
vision_analysisjob        - CV identification jobs
images_processedimage     - Processed images with transformations
```

**All models use:**
- UUID primary keys (except through tables)
- created_at/updated_at timestamps
- Selective indexing on search fields

---

## API Architecture

**Base URL:** `/api/v1/`

**Authentication:** JWT (djangorestframework-simplejwt)
- Access token lifetime: 60 minutes (configurable)
- Refresh token lifetime: 7 days
- Token refresh endpoint: `POST /auth/refresh/`

**Endpoints by App:**

```
/auth/
  POST /login/           - User login (returns JWT + user data)
  POST /register/        - Create account
  POST /refresh/         - Refresh access token

/users/
  POST /                 - Register (no auth)
  GET /me/               - Current user profile
  GET /friend-code/      - Get your friend code
  POST /lookup_friend_code/  - Find user by code

/animals/
  GET /                  - List all animals (paginated, filtered)
  POST /                 - Create animal (IsAuthenticated)
  GET /{id}/             - Retrieve animal details
  GET /recent/           - Last 20 discovered
  GET /popular/          - Most captured
  GET /{id}/taxonomy/    - Full taxonomy tree
  POST /lookup_or_create/  - CV pipeline endpoint

/dex/entries/
  POST /                 - Create dex entry
  GET /my_entries/       - User's collection
  GET /favorites/        - Favorite entries
  POST /{id}/toggle_favorite/  - Toggle favorite
  GET /sync_entries/     - Sync with checksums (query: last_sync)

/social/friendships/
  GET /friends/          - Friends list
  GET /pending/          - Pending requests
  POST /send_request/    - Send friend request
  POST /{id}/respond/    - Accept/reject/block
  DELETE /{id}/unfriend/ - Remove friendship

/vision/jobs/
  POST /                 - Submit image for analysis
  GET /{id}/             - Check job status
  GET /completed/        - View results
  POST /{id}/retry/      - Retry failed job

/graph/
  GET /evolutionary-tree/  - Get graph data (cached)
  POST /invalidate-cache/  - Clear cache
```

---

## Data Import & Taxonomic Data Plan

**Current Status:** Catalogue of Life dataset (v2025-10-10) downloaded but not yet integrated

**File Structure:**
- NameUsage.tsv - 9.4M records with complete taxonomy
- VernacularName.tsv - 638K common name records
- Distribution.tsv - 2.7M geographic records
- Reference.tsv - 2M scientific references
- Others: NameRelation, TypeMaterial, SpeciesEstimate, TaxonProperty

**Architecture Plan:**
1. Create raw_catalogue_of_life table (from NameUsage.tsv)
2. Create taxonomy table (normalized from raw tables)
3. Link animals.Animal to taxonomy via source ID
4. Create data import management command

**Key Fields to Map:**
```
COL NameUsage → Django Animal
col:scientificName     → scientific_name
col:scientificName     → (extract genus, species)
col:rank               → (ignore if not species)
col:status             → (filter for 'accepted')
col:kingdom            → kingdom
col:phylum             → phylum
col:class              → class_name
col:order              → order
col:family             → family
col:genus              → genus
col:species            → species
```

**VernacularName → Animal common_name**
- Join via col:taxonID
- Filter for language='en', preferred=true

---

## Key Services & Patterns

### Service Layer Architecture
- `CVService` (abstract base) → `OpenAIVisionService` (implementation)
- `CVServiceFactory.create()` - Factory pattern for service instantiation
- `EvolutionaryGraphService` - Graph generation with caching

### Celery Task Pattern
```python
@shared_task(bind=True, max_retries=3)
def process_analysis_job(self, job_id, transformations=None):
    try:
        # Process
        ...
    except Exception as e:
        if job.retry_count < 3:
            raise self.retry(exc=e, countdown=60 * (2 ** job.retry_count))
        else:
            job.mark_failed(str(e))
```

### Caching Pattern
- Django cache framework with Redis backend
- Cache TTL configured per entity type
- Automatic invalidation on model save via signals
- Used for: animals, graphs, user profiles

### Signal Pattern (assumed)
- UserProfile auto-created on User creation
- Cache invalidation on model updates
- Graph cache invalidation on DexEntry creation

---

## Environment Variables

**Required:**
- `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` - PostgreSQL
- `SECRET_KEY` - Django secret
- `OPENAI_API_KEY` - OpenAI Vision API (optional, CV disabled if not set)

**Optional:**
- `DEBUG` (True/False)
- `ALLOWED_HOSTS` (comma-separated)
- `JWT_ACCESS_TOKEN_LIFETIME_MINUTES` (default 60)
- `GRAPH_CACHE_TTL`, `ANIMAL_CACHE_TTL` (in seconds)
- `GCS_BUCKET_NAME`, `GCS_PROJECT_ID` - Google Cloud Storage
- `MAX_UPLOAD_SIZE_MB` (default 10)
- `CELERY_BROKER_URL` - Redis URL (development: redis://localhost:6379/0)
- `THROTTLE_*_RATE` - Rate limiting

---

## Testing & Development

**Test Framework:** pytest with pytest-django
- Config in pyproject.toml
- Coverage reporting
- Test paths: accounts, animals, dex, social, vision, graph

**Development Tools:**
- Django Debug Toolbar (dev only)
- django-extensions
- black (code formatting, line-length 100)
- flake8 (linting)

**Management Commands:**
- `seed_test_users` - Create test users
- Standard Django migrations commands
- Celery worker/beat commands

---

## Production Deployment

**Container Setup:**
- Multi-stage Dockerfile.production
- Docker Compose with services: web, db, redis, celery
- Nginx reverse proxy, Gunicorn app server

**Monitoring:**
- Prometheus metrics middleware
- Health check endpoints (/health/, /ready/, /metrics/)
- Structured JSON logging
- Sentry integration (optional)

**Database:**
- PostgreSQL 15 with pgBouncer
- Automated migrations on startup
- Connection pooling

**Static Files:**
- Collected to /staticfiles/
- Served by Nginx
- CloudFlare CDN integration

---

## Key Architectural Decisions

1. **UUID Primary Keys** - Better for distributed systems, privacy
2. **Custom User Model** - Friend code system, badges (JSON), extensible
3. **Creation Index** - Pokedex-style sequential numbering for UX
4. **Async CV Processing** - Celery tasks to avoid blocking requests
5. **Dex-Compatible Images** - Server-side standardization for consistency
6. **Dual-Serializer Pattern** - List vs. detail serializers for performance
7. **Image Smart Fallback** - dex_compatible → processed → original
8. **Signal-Based Caching** - Automatic invalidation on model updates
9. **Factory Pattern** - Extensible CV service implementations
10. **Rate Limiting** - Per-user quotas for API access

---

## Notable Code Patterns

**Parsing Binomial Nomenclature:**
```python
pattern = r'([A-Z][a-z]+)[,\s]+([a-z]+(?:\s+[a-z]+)?)\s*(?:\(([^)]+)\))?'
# Genus, species [subspecies] (optional common name)
```

**Auto-Assigning Creation Index:**
```python
if self.creation_index is None:
    max_index = Animal.objects.aggregate(max_index=models.Max('creation_index'))['max_index']
    self.creation_index = (max_index or 0) + 1
```

**Bidirectional Friendship Check:**
```python
@classmethod
def are_friends(cls, user1, user2):
    return cls.objects.filter(
        models.Q(from_user=user1, to_user=user2, status='accepted') |
        models.Q(from_user=user2, to_user=user1, status='accepted')
    ).exists()
```

**Smart Image URL Selection:**
```python
@property
def display_image_url(self):
    if self.source_vision_job and self.source_vision_job.dex_compatible_image:
        return self.source_vision_job.dex_compatible_image.url
    elif self.processed_image:
        return self.processed_image.url
    else:
        return self.original_image.url
```

---

## Integration Points

1. **Frontend (Godot Client)**
   - Auth: POST /auth/login/, /auth/refresh/
   - Upload: POST /vision/jobs/
   - Sync: GET /dex/entries/sync_entries/
   - Check Status: GET /vision/jobs/{id}/

2. **CV System**
   - Image upload triggers AnalysisJob creation
   - Celery task processes and calls OpenAI API
   - Result stored, Animal created/linked
   - DexEntry created with dex-compatible image

3. **Social Features**
   - Friend code lookup via POST /lookup_friend_code/
   - Bidirectional friendship creation
   - Graph generation scoped to friends

4. **Admin Panel**
   - Mark animals as verified
   - Bulk operations on animals
   - Full CRUD for all models

---

## Future Extensibility

1. **Multiple CV Providers** - CVServiceFactory ready for new implementations
2. **Data Sources** - Taxonomic system designed for multiple sources
3. **Real-time Updates** - WebSocket support can be added
4. **Machine Learning** - Custom animal identification model slot
5. **Gamification** - Badge system in User.badges (JSON)
6. **Localization** - Uses Django i18n framework
7. **Advanced Filtering** - DjangoFilterBackend supports custom filters
8. **Rate Limiting** - Per-endpoint throttle rates configurable

---

## Critical Files & Locations

**Settings:**
- `/server/biologidex/settings/base.py` - Shared configuration
- `/server/biologidex/settings/development.py` - Local development
- `/server/biologidex/settings/production_local.py` - Docker production

**Models:**
- `/server/accounts/models.py` - User, UserProfile
- `/server/animals/models.py` - Animal taxonomy
- `/server/dex/models.py` - DexEntry captures
- `/server/vision/models.py` - AnalysisJob CV tracking
- `/server/images/models.py` - ProcessedImage

**Services:**
- `/server/vision/services.py` - OpenAIVisionService
- `/server/vision/tasks.py` - Celery tasks + parse_and_create_animal()
- `/server/graph/services.py` - EvolutionaryGraphService

**Management Commands:**
- `/server/accounts/management/commands/seed_test_users.py` - Create test data

**Data:**
- `/resources/catalogue_of_life/` - 3GB+ Catalogue of Life dataset (not yet integrated)
- `/resources/catalogue_of_life/catalogue_of_life.md` - CoL documentation

