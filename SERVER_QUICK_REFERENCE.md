# BiologiDex Server Architecture - Quick Reference Summary

## System Overview
- **Framework**: Django REST Framework 4.2+
- **Database**: PostgreSQL 15 with pgBouncer connection pooling
- **Async Jobs**: Celery with Redis broker
- **Caching**: Redis with Django cache framework
- **Image Processing**: Pillow with OpenAI Vision API integration
- **Authentication**: JWT via djangorestframework-simplejwt
- **Deployment**: Docker Compose with Nginx, Gunicorn, production-ready

## Core Components (7 Django Apps)

### 1. Accounts (User Management)
- Custom `User` model with UUID pk, unique email, friend_code (8-char unique)
- `UserProfile` OneToOne auto-created with stats tracking
- JWT authentication with 60-min access token, 7-day refresh
- Friend code system for peer discovery

### 2. Animals (Species Database)
- Master `Animal` model: scientific_name (unique), common_name, creation_index (Pokedex #)
- Full taxonomic hierarchy: kingdom → phylum → class → order → family → genus → species
- Conservation status (IUCN codes), verified flag, description, habitat, diet, facts (JSON)
- Auto-increments creation_index on save, auto-parses genus/species from binomial name
- Caching with 1-hour TTL, invalidated on every change

### 3. Dex (User Captures)
- `DexEntry`: Links User ↔ Animal with images and metadata
- Supports multiple captures of same animal (unique on owner + animal + catch_date)
- Image handling: original_image → processed_image → dex_compatible_image (fallback chain)
- Location data (lat/lon), customization (JSON), visibility (private/friends/public)
- Sync endpoint with image checksums for client caching

### 4. Social (Friendships)
- Bidirectional `Friendship` model with status workflow: pending → accepted/rejected/blocked
- Class methods for easy queries: `are_friends()`, `get_friends()`, `get_friend_ids()`
- Prevents self-friendship, duplicate requests

### 5. Vision (CV Pipeline)
- `AnalysisJob`: Tracks image → processing → OpenAI API call → animal identification
- Stores cost, token usage, processing time, raw API response
- Status workflow: pending → processing → completed/failed (with retry logic)
- `OpenAIVisionService`: Handles GPT-4/GPT-5 model differences (max_tokens vs max_completion_tokens)
- Celery task `process_analysis_job`: Async processing with exponential backoff retry (max 3 attempts)
- `parse_and_create_animal()`: Regex-based binomial nomenclature parsing, auto-creates Animal if needed

### 6. Images (Image Processing)
- `ProcessedImage`: Centralized image tracking with transformation versioning
- Stores original/processed/thumbnail, original format, dimensions, file sizes
- SHA256 checksums for deduplication, EXIF metadata extraction
- `ImageProcessor`: Basic conversion to PNG (max 2560x2560)
- `EnhancedImageProcessor`: Applies user transformations (rotation, crop), auto-rotates from EXIF

### 7. Graph (Evolutionary Trees)
- `EvolutionaryGraphService`: Builds graph of animals captured by user + friends
- Returns nodes (with taxonomy, discoverer info), edges (taxonomic relationships), stats
- Caches with 2-minute TTL, manual invalidation support
- Uses family grouping for relationship edges

## Database Model Relationships

```
User (UUID pk)
├── UserProfile (OneToOne) - stats tracking
├── AnalysisJob (1:N) - CV jobs
├── Animal (1:N) - discovered animals (created_by)
├── DexEntry (1:N) - owned dex entries
├── Friendship (1:N as from_user) - sent requests
├── Friendship (1:N as to_user) - received requests
└── Comment/Reaction (future)

Animal (UUID pk)
├── DexEntry (1:N) - captures
├── AnalysisJob (1:N) - identification records
└── User (FK) - created_by

DexEntry (UUID pk)
├── User (FK) - owner
├── Animal (FK)
├── AnalysisJob (FK optional) - source vision job

AnalysisJob (UUID pk)
├── User (FK)
├── Animal (FK optional) - identified animal
└── ProcessedImage (1:1 optional) - dex_compatible_image
```

## Key Design Patterns

1. **Auto-Increment Creation Index**: Sequential Pokedex-style numbering on Animal.save()
2. **Smart Image Fallback**: dex_compatible → processed → original URL selection
3. **Bidirectional Friendship**: Single model with query helpers (not two separate edges)
4. **Signal-Based Caching**: Automatic invalidation on model updates
5. **Celery Retry with Exponential Backoff**: 60s, 120s, 240s wait times
6. **Factory Pattern**: CVServiceFactory for extensible CV providers
7. **Dual Serializers**: Lightweight list vs. detailed view serializers
8. **Rate Limiting**: Per-endpoint throttle rates (anon: 100/hr, user: 1000/hr)

## Critical Implementation Details

**Binomial Nomenclature Parsing:**
- Pattern: `([A-Z][a-z]+)[,\s]+([a-z]+(?:\s+[a-z]+)?)\s*(?:\(([^)]+)\))?`
- Extracts: Genus, species [subspecies] (optional common name)
- Handles markdown italics via regex cleanup

**Model Compatibility (Vision API):**
- GPT-4 models: `max_tokens=300`
- GPT-5+/o-series: `max_completion_tokens=300`
- Auto-detection: Check model name prefix

**Image Processing Workflow:**
1. Client rotates image 90° (pixel-level, saves as PNG)
2. Upload sends pre-rotated image + image in original format
3. Server creates dex-compatible PNG (standardization)
4. Server sends dex-compatible image to Vision API
5. Result stored, Animal created/linked, DexEntry created

**Authentication Flow:**
- POST /auth/login/ → JWT access + refresh tokens
- POST /auth/refresh/ → New access token
- Refresh tokens rotate automatically, old ones blacklisted
- Access token expires in 60 minutes (configurable)

## API Response Patterns

**List Endpoint** (e.g., GET /animals/):
- Pagination: `{count: int, next: url, previous: url, results: [...]}`
- Filtering: Query params (conservation_status, verified, kingdom, etc.)
- Search: ?search=string searches scientific_name, common_name, genus, species
- Ordering: ?ordering=creation_index or -created_at

**Detail Endpoint** (e.g., GET /animals/{id}/):
- Full serialization with taxonomic_tree, discovery_count computed
- Related data: created_by_username, verified status

**Status Endpoints** (Vision/AnalysisJob):
- status: pending/processing/completed/failed
- results: {parsed_prediction, identified_animal, cost_usd, processing_time}
- retry_count: Current retry attempt (max 3)

## Data Import (Not Yet Implemented)

**Catalogue of Life Dataset Available:**
- Location: `/resources/catalogue_of_life/`
- Size: 3.2 GB total, 9.4M species records
- Files: NameUsage.tsv (taxonomy), VernacularName.tsv (common names), Distribution.tsv, Reference.tsv

**Planned Architecture:**
1. Create `RawCatalogueOfLife` model from NameUsage.tsv
2. Create normalized `Taxonomy` model (combined from sources)
3. Add source tracking to Animal model
4. Management command for data import + update jobs

**Mapping:**
- col:scientificName → scientific_name (unique key)
- col:rank = 'species' required
- col:status = 'accepted' for valid entries
- Full taxonomic hierarchy: kingdom, phylum, class, order, family, genus, species
- Common names from VernacularName.tsv (language='en', preferred=true)

## File Locations

**Models:**
- `/server/accounts/models.py` - User, UserProfile
- `/server/animals/models.py` - Animal
- `/server/dex/models.py` - DexEntry
- `/server/social/models.py` - Friendship
- `/server/vision/models.py` - AnalysisJob
- `/server/images/models.py` - ProcessedImage

**Services:**
- `/server/vision/services.py` - OpenAIVisionService
- `/server/vision/tasks.py` - Celery tasks
- `/server/graph/services.py` - EvolutionaryGraphService
- `/server/vision/image_processor.py` - ImageProcessor, EnhancedImageProcessor

**Views/Serializers:**
- `/server/{app}/views.py` - ViewSets for each app
- `/server/{app}/serializers.py` - DRF serializers
- `/server/{app}/urls.py` - REST routing

**Management:**
- `/server/accounts/management/commands/seed_test_users.py` - Test data

**Configuration:**
- `/server/biologidex/settings/base.py` - All settings
- `/server/biologidex/settings/development.py` - Local overrides
- `/server/biologidex/settings/production_local.py` - Docker overrides
- `/server/pyproject.toml` - Dependencies

## Environment Variables (Key)

```
DB_HOST=postgres              # PostgreSQL service
DB_NAME=biologidex
DB_USER=postgres
DB_PASSWORD=***
CELERY_BROKER_URL=redis://redis:6379/0  # Async jobs
OPENAI_API_KEY=***            # Vision API (optional)
DEBUG=False                   # Production
SECRET_KEY=***                # Django secret
GCS_BUCKET_NAME=***           # Google Cloud Storage
```

## Testing

- Framework: pytest + pytest-django
- Coverage: pytest-cov
- Config: pyproject.toml
- Test paths: accounts, animals, dex, social, vision, graph

## Production Ready

- Docker multi-stage build
- Gunicorn WSGI server (workers = CPU*2+1)
- Nginx reverse proxy + static file serving
- PrometheusMiddleware for metrics
- Health endpoints: /health/, /ready/, /metrics/
- Structured JSON logging
- Connection pooling
- Rate limiting
- CORS configured
- Token blacklist on refresh rotation

---

## What Exists vs. What's Needed

### Currently Implemented
- All 7 Django apps with full models
- REST API endpoints for all core features
- User authentication (JWT)
- CV identification pipeline (async Celery)
- Image processing (basic + transformations)
- Social features (friendships)
- Evolutionary graph generation
- Production Docker setup
- Comprehensive admin interface

### Not Yet Implemented
- Catalogue of Life data import
- Raw data models for COL
- Data synchronization jobs
- Taxonomic data deduplication logic
- Management command for import
- Tests (pytest setup ready, tests not written)
- WebSocket support (real-time updates)
- Advanced filtering/search (infrastructure ready)

