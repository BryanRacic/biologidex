# BiologiDex Server

A production-ready Django REST Framework API for BiologiDex - a Pokedex-style social network for sharing real-world zoological observations.

## Table of Contents

- [System Overview](#system-overview)
- [Django Apps Architecture](#django-apps-architecture)
- [Infrastructure Components](#infrastructure-components)
- [Quick Start](#quick-start)
- [Development](#development)
- [API Documentation](#api-documentation)
- [Database & Models](#database--models)
- [Key Patterns & Implementation](#key-patterns--implementation)
- [Configuration](#configuration)
- [Monitoring & Health](#monitoring--health)
- [Security](#security)
- [Deployment](#deployment)
- [Backup & Recovery](#backup--recovery)
- [Troubleshooting](#troubleshooting)
- [Data Import Planning](#data-import-planning)
- [Future Extensibility](#future-extensibility)

---

## System Overview

### Technology Stack

- **Framework**: Django 4.2+ with Django REST Framework
- **Database**: PostgreSQL 15 with pgBouncer connection pooling
- **Async Jobs**: Celery with Redis broker
- **Caching**: Redis with Django cache framework
- **Image Processing**: Pillow with OpenAI Vision API integration
- **Authentication**: JWT via djangorestframework-simplejwt
- **Deployment**: Docker Compose with Nginx, Gunicorn

### System Architecture

```
Internet
    ↓
[Cloudflare Tunnel / Load Balancer]
    ↓
[Nginx Reverse Proxy]
    ↓
[Django Application (Gunicorn)]
    ↓
[PostgreSQL] [Redis] [Celery Workers]
```

### Component Overview

| Component | Purpose | Technology | Configuration |
|-----------|---------|------------|---------------|
| **Web Server** | Reverse proxy, static files | Nginx | nginx/nginx.conf |
| **Application Server** | Django application | Gunicorn + Django 4.2 | gunicorn.conf.py |
| **Database** | Primary data storage | PostgreSQL 15 | init.sql, pgBouncer for pooling |
| **Cache** | Session storage, task queue | Redis 7 | redis.conf |
| **Task Queue** | Async processing | Celery | celery_worker, celery_beat |
| **Storage** | Media files | Local filesystem / GCS | /var/lib/biologidex/media |
| **Monitoring** | Metrics and health checks | Prometheus + Grafana | monitoring.py |

---

## Django Apps Architecture

BiologiDex is organized into 8 modular Django apps, each with a specific domain responsibility:

### 1. Accounts - User Management

**Purpose:** Custom user model, profiles, and authentication

**Models:**

- **User** (extends AbstractUser)
  - UUID primary key, unique email, 8-character unique friend_code
  - Fields: bio, avatar, badges (JSON), created_at, updated_at
  - Auto-generates unique friend_code on creation
  - Indexes: friend_code, email, created_at

- **UserProfile** (OneToOne with User)
  - Fields: total_catches, unique_species, preferred_card_style (JSON)
  - Auto-created via signals when User is created
  - `update_stats()` method recalculates stats from DexEntry records

**Key Features:**
- Custom AUTH_USER_MODEL for project-wide use
- Friend code system for peer discovery
- Stat tracking via signals from DexEntry creation
- UUID primary keys for all models

**Management Commands:**
- `seed_test_users` - Creates testuser, admin, verified test users (--force flag to recreate)

---

### 2. Animals - Species Taxonomy Database

**Purpose:** Master database of species with full taxonomic and ecological data

**Model: Animal**

**Primary Fields:**
- id (UUID), scientific_name (unique), common_name, creation_index (sequential Pokedex #)
- Full taxonomic hierarchy: kingdom, phylum, class_name, order, family, genus, species
- Description, habitat, diet, conservation_status (IUCN codes: LC, EN, CR, etc.)
- interesting_facts (JSON list)
- created_by (FK to User), verified (boolean), created_at, updated_at

**Unique Constraints:**
- scientific_name is globally unique
- creation_index is globally unique (auto-incremented on save)

**Properties & Methods:**
- `discovery_count` - Number of unique users who captured this animal
- `get_taxonomic_tree()` - Returns full taxonomy as dict

**Auto-Save Logic:**
- If creation_index not set: Auto-assigns next sequential number
- If genus/species empty: Parses from scientific_name (expects "Genus species" format)
- Invalidates cache on every save

**Indexes:** scientific_name, common_name, (genus, species), creation_index, verified, created_at

**Serializers:**
- `AnimalSerializer` - Full serialization with taxonomic_tree, discovery_count
- `AnimalListSerializer` - Lightweight for list views
- `AnimalCreateSerializer` - For CV pipeline

**ViewSet: AnimalViewSet**

Permissions:
- list/retrieve: AllowAny
- create: IsAuthenticated
- update/delete: IsAdminUser

Filtering: conservation_status, verified, kingdom, phylum, family
Search: scientific_name, common_name, genus, species
Ordering: creation_index, created_at, scientific_name

Custom Actions:
- `GET /recent/` - Last 20 discovered animals
- `GET /popular/` - Most captured animals
- `GET /{id}/taxonomy/` - Full taxonomy tree
- `POST /lookup_or_create/` - CV pipeline endpoint (find by scientific_name or create)

**Caching:**
- Animals cached with `ANIMAL_CACHE_TTL` (default 3600s)
- Cached via `Animal.get_cached(animal_id)` classmethod
- Cache invalidated on save

---

### 3. Dex - User Dex Entries (Animal Captures)

**Purpose:** User's personal record of captured/observed animals

**Model: DexEntry**

**Relationships:**
- owner (FK to User)
- animal (FK to Animal)
- source_vision_job (FK to AnalysisJob, optional)

**Image Fields:**
- original_image - User's uploaded image (any format)
- processed_image - Optional user-edited version
- `display_image_url` property - Smart fallback: dex_compatible → processed → original

**Location Data:**
- location_lat, location_lon (decimal precision)
- location_name (human-readable)
- `get_location_coords()` method returns (lat, lon) tuple or None

**Customization:**
- notes (user notes)
- customizations (JSON - card styling)
- catch_date (when observed)
- visibility (private/friends/public)
- is_favorite (boolean)

**Unique Constraint:** (owner, animal, catch_date) - User can capture same animal multiple times, tracked by date

**Indexes:** (owner, animal), (owner, catch_date), (owner, visibility), (animal, visibility), catch_date, is_favorite

**Serializers:**
- `DexEntrySerializer` - Full entry with related data
- `DexEntrySyncSerializer` - For sync endpoint with checksums

**API Endpoints:**
- `POST /` - Create entry
- `GET /my_entries/` - User's collection
- `GET /favorites/` - Favorite entries
- `POST /{id}/toggle_favorite/` - Toggle favorite
- `GET /sync_entries/` - Sync with checksums (query param: `last_sync` ISO 8601 datetime)

---

### 4. Social - Friendships & Social Features

**Purpose:** Friend management and social connectivity

**Model: Friendship**

**Bidirectional Model:**
- from_user (FK to User, sender)
- to_user (FK to User, receiver)
- status (pending/accepted/rejected/blocked)
- created_at, updated_at

**Unique Constraint:** (from_user, to_user) - Prevents duplicate requests

**Status Workflow:**
- pending → created by `create_request()`
- accepted → via `accept()` method
- rejected → via `reject()` method
- blocked → via `block()` method
- unfriended → via `unfriend()` (deletes record)

**Key Class Methods:**
- `are_friends(user1, user2)` - Bidirectional check
- `get_friends(user)` - Returns User queryset
- `get_friend_ids(user)` - Returns list of friend UUIDs
- `get_pending_requests(user)` - Requests user received
- `create_request(from_user, to_user)` - Create with validation

**Indexes:** (from_user, status), (to_user, status), (status, created_at)

**API Endpoints:**
- `GET /friends/` - Friends list
- `GET /pending/` - Pending requests
- `POST /send_request/` - Send by friend_code or user_id
- `POST /{id}/respond/` - Accept/reject/block
- `DELETE /{id}/unfriend/` - Remove friendship

---

### 5. Vision - CV/AI Identification Pipeline

**Purpose:** OpenAI Vision API integration for animal identification

**Model: AnalysisJob**

Tracks: Image → Processing → Identification → Result

**Input Fields:**
- image (original uploaded file, any format)
- dex_compatible_image (standardized PNG, max 2560x2560)
- image_conversion_status (pending/processing/completed/failed/unnecessary)
- user (FK to User who submitted)

**Processing Fields:**
- status (pending/processing/completed/failed)
- cv_method (openai, fallback)
- model_name (gpt-4o, gpt-5-mini, etc.)
- detail_level (auto, low, high)

**Results:**
- raw_response (JSON from API)
- parsed_prediction (extracted text)
- identified_animal (FK to Animal or None)
- confidence_score (0-1 if available)

**Metrics:**
- cost_usd, processing_time, input_tokens, output_tokens

**Error Handling:**
- error_message, retry_count (max 3)

**Helper Methods:**
- `mark_processing()` - Sets status, started_at
- `mark_completed(**kwargs)` - Bulk sets fields
- `mark_failed(error_message)` - Sets error, completed_at
- `increment_retry()` - Increments retry counter

**Indexes:** (user, status), (status, created_at), identified_animal, created_at

**Services: OpenAIVisionService**

Methods:
- `identify_animal(image_path)` - Main identification
- `encode_image(path)` - File → base64
- `encode_image_from_bytes(bytes)` - Bytes → base64
- `_calculate_cost(usage)` - Pricing per model

Model Handling:
- GPT-4 models: Use `max_tokens` param
- GPT-5+/o-series: Use `max_completion_tokens` param
- Auto-detection via model name prefix

**Celery Task: process_analysis_job(job_id, transformations=None)**

Workflow:
1. Get AnalysisJob record
2. Process image to create dex-compatible PNG (ImageProcessor)
3. Send dex-compatible image to OpenAI Vision API
4. Parse response to extract scientific/common name
5. Create/lookup Animal record
6. Mark job complete with results

Retry Logic: Exponential backoff (60s, 120s, 240s), max 3 retries
Image Processing: Uses EnhancedImageProcessor if transformations provided

**Task: parse_and_create_animal(prediction, user)**

- Input: CV prediction string (expected format: "Genus species (common name)")
- Parsing: Regex extraction of binomial nomenclature
- Output: Animal instance (created or looked up)
- Fallbacks: Creates Animal if not found, auto-generates common_name if empty

**Constants:**
- `ANIMAL_ID_PROMPT` - Standardized prompt for CV
- `OPENAI_PRICING` - Dict of model pricing (Oct 2025 rates)

**API Endpoints:**
- `POST /jobs/` - Submit image for analysis (accepts optional `transformations` JSON)
- `GET /jobs/{id}/` - Check job status
- `GET /jobs/completed/` - View results
- `POST /jobs/{id}/retry/` - Retry failed job (accepts optional `transformations` JSON)

---

### 6. Images - Image Processing & Transformation

**Purpose:** Centralized image management with transformation tracking

**Model: ProcessedImage**

**Source Tracking:**
- source_type (vision_job/user_upload/dex_edit)
- source_id (UUID of source object)

**Files:**
- original_file, processed_file, thumbnail (all optional except original)

**Metadata:**
- original_format (JPEG, PNG, etc.)
- original_dimensions, processed_dimensions (JSON)
- file_size_bytes

**Transformations:**
- transformations (JSON dict of applied transforms)
- processing_warnings, processing_errors (JSON)

**EXIF:**
- exif_data (extracted EXIF metadata)

**Versioning:**
- version (integer)
- parent_image (FK to self for history)

**Deduplication:**
- original_checksum, processed_checksum (SHA256)
- `calculate_checksum(file_field)` - SHA256 static method

**Indexes:** (source_type, source_id), original_checksum, processed_checksum, created_at

**Services: ImageProcessor (Basic)**
- `process_image(image_file)` - Convert to PNG, resize if needed
- Returns (processed_file, metadata_dict)
- metadata: original_format, original_dims, processed_dims, resize_applied, error

**Services: EnhancedImageProcessor**
- `process_image_with_transformations(image_file, transformations, apply_exif_rotation=True)`
- Applies user transformations (rotation, crop, etc.)
- Auto-rotates based on EXIF orientation
- Returns (processed_file, metadata_dict)

Methods:
- `apply_transformations(image, transforms_dict)` - Apply transformations
- `auto_rotate_from_exif(image)` - Extract & apply EXIF rotation
- `extract_exif_data(image)` - Extract all EXIF metadata

**Usage Pattern:**
- Camera scene rotates image client-side (90° increments)
- Rotated PNG sent in upload request
- Server receives pre-rotated image (no transform needed)
- ImageProcessor converts to dex-compatible format

---

### 7. Taxonomy - Authoritative Taxonomic Database

**Purpose:** Centralized taxonomic data system with Catalogue of Life integration for validating CV identifications

**Models:**

- **DataSource** - Registry of taxonomic databases (COL, GBIF, etc.)
  - Fields: name, short_code, url, api_endpoint, update_frequency, license, priority
  - Tracks source authority and priority for conflict resolution

- **ImportJob** - Tracks data import jobs
  - Fields: source, version, status, records_imported/failed, error_log
  - Status workflow: pending → downloading → processing → importing → completed/failed
  - Async processing via Celery with retry logic

- **TaxonomicRank** - Reference table for taxonomic ranks
  - 20 standard ranks from kingdom (level=10) to form (level=80)
  - Includes plural forms for display

- **Taxonomy** - Normalized taxonomic records
  - Full hierarchical data: kingdom → phylum → class → order → family → genus → species
  - Extended hierarchy: subkingdom, subphylum, tribe, subspecies, variety, form
  - Metadata: extinct status, environment (marine/terrestrial/freshwater), nomenclatural code
  - Synonym resolution: Links to accepted_name if status='synonym'
  - Quality metrics: completeness_score, confidence_score
  - Unique constraint: (source, source_taxon_id)

- **CommonName** - Vernacular names in multiple languages
  - Fields: name, language (ISO 639-3), country (ISO 3166-1), is_preferred
  - Unique constraint: (taxonomy, name, language, country)

- **GeographicDistribution** - Native regions and conservation data
  - Fields: area_code, area_name, establishment_means, occurrence_status, threat_status
  - IUCN categories for conservation tracking

- **RawCatalogueOfLife** - Staging table for COL imports
  - Temporary storage before normalization
  - BigAutoField for 9M+ records
  - Processing flag: is_processed

**Services: TaxonomyService**

Methods:
- `lookup_by_scientific_name(name, include_synonyms, source_code)` - Search with caching
- `lookup_or_create_from_cv(name, common_name, confidence)` - Validate CV identifications
- `search_taxonomy(query, rank, kingdom, limit)` - Full-text search
- `get_hierarchy_stats()` - Database statistics (cached)
- `get_taxonomic_lineage(taxonomy)` - Complete ancestry chain
- `get_children(taxonomy, direct_only)` - Descendant taxa
- `validate_scientific_name(name)` - Format validation

**Integration with Animals:**

Updated Animal model fields:
- subfamily, native_regions (array), establishment_means
- taxonomy_id (UUID link), taxonomy_source, taxonomy_source_url
- taxonomy_confidence, last_verified_at, verification_method

**Services: AnimalService**

Methods:
- `create_or_update_from_taxonomy(taxonomy, common_name, cv_confidence)` - Creates enriched animals
- `lookup_or_create_from_cv(scientific_name, common_name, confidence)` - CV integration

Workflow:
1. CV identifies animal → Parse scientific name
2. TaxonomyService.lookup_by_scientific_name() → Check against COL
3. If found: Create/update Animal with full taxonomy + conservation data
4. If not found: Create basic Animal record (requires manual review)

**Import Pipeline:**

Base Components:
- `BaseImporter` - Abstract base class for all importers
- `CatalogueOfLifeImporter` - COL-specific implementation

COL Import Workflow:
1. Download latest dataset via API (3GB+, 9.4M records)
2. Extract NameUsage.tsv from zip
3. Bulk import to RawCatalogueOfLife (batches of 5000)
4. Normalize to Taxonomy model (batches of 1000)
5. Calculate completeness scores
6. Update caches

**Management Commands:**

`import_col` - Import Catalogue of Life data
```bash
poetry run python manage.py import_col [--async] [--force] [--file path]
```
Options:
- --async: Run as Celery task (recommended for full imports)
- --force: Skip recent import check
- --file: Use local zip file instead of downloading

**Celery Tasks:**

- `run_import_job(job_id)` - Async import with retry logic
- `sync_taxonomy_to_animals()` - Daily sync of new taxonomy → animals
- `cleanup_old_imports()` - Delete old raw data (30 days)
- `update_taxonomy_completeness_scores()` - Recalculate quality metrics
- `cache_taxonomy_stats()` - Pre-cache statistics

**API Endpoints:**

- `GET /api/v1/taxonomy/` - List records (paginated)
- `GET /api/v1/taxonomy/search/?q=...` - Search by name
- `POST /api/v1/taxonomy/validate/` - Validate scientific name
- `GET /api/v1/taxonomy/stats/` - Database statistics
- `GET /api/v1/taxonomy/{id}/lineage/` - Complete lineage
- `GET /api/v1/taxonomy/{id}/children/` - Child taxa
- `GET /api/v1/sources/` - List data sources

**Performance Optimizations:**

- Indexes on all search fields (scientific_name, genus, species, etc.)
- GIN index on environment array field
- Bulk operations for imports (5000 records/batch)
- Redis caching with 1-hour TTL
- Connection pooling for PostgreSQL
- Progress logging every 50k records

**Vision Pipeline Integration:**

Updated `parse_and_create_animal()` in vision/tasks.py:
- Automatically validates against taxonomy database
- Creates enriched Animal records with full hierarchy
- Flags unverified animals for manual review
- Logs taxonomy lookup results

**Data Quality:**

- Completeness score: 0-1 based on filled hierarchy fields
- Confidence score: From source data quality
- Synonym resolution: Automatic redirect to accepted names
- Status tracking: accepted/synonym/provisional/doubtful

**Caching Strategy:**

- Individual taxonomy lookups: 1 hour TTL
- Hierarchy statistics: 1 hour TTL
- Automatic invalidation on new imports
- Cache warming via scheduled tasks

---

### 8. Graph - Taxonomic Tree Generation

**Purpose:** Generate taxonomic/evolutionary network graphs for visualization

**Service: EvolutionaryGraphService**

**Main Method: get_graph_data(use_cache=True)**
- Returns: `{nodes: [...], edges: [...], stats: {...}, metadata: {...}}`
- Caches with `GRAPH_CACHE_TTL` (default 120s)

**Private Methods:**
- `_get_relevant_animals()` - Animals captured by user + friends
- `_build_nodes(animals)` - Create node list with metadata
- `_build_edges(animals)` - Create taxonomic relationship edges
- `_calculate_stats(animals)` - Compute graph statistics

**Node Structure:**
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

**Edge Structure:**
```json
{
  "source": "animal1_uuid",
  "target": "animal2_uuid",
  "relationship": "same_family",
  "family": "Felidae"
}
```

**Stats:** total_animals, user_captures, user_unique_species, friend_captures, friend_count, taxonomic_diversity

**Cache Invalidation:** `invalidate_cache(user_id)` - Called when new animals discovered

**API Endpoints:**
- `GET /taxonomic-tree/` - Get graph data (cached)
- `POST /invalidate-cache/` - Invalidate cache manually

---

## Infrastructure Components

### 1. Web Layer (Nginx)
- **Purpose**: Reverse proxy, SSL termination, static file serving
- **Features**:
  - Request routing to application servers
  - Load balancing across multiple Gunicorn workers
  - Static and media file serving with caching headers
  - Security headers (HSTS, CSP, X-Frame-Options)
  - Rate limiting at the edge
  - Gzip compression

### 2. Application Layer (Django + Gunicorn)
- **Purpose**: Business logic and API endpoints
- **Features**:
  - RESTful API with Django REST Framework
  - JWT authentication
  - Modular app architecture
  - Comprehensive middleware stack
  - Health check endpoints
  - Prometheus metrics integration

### 3. Database Layer (PostgreSQL)
- **Purpose**: Persistent data storage
- **Features**:
  - PostgreSQL 15 with optimized configuration
  - Connection pooling via pgBouncer
  - Read replica support (optional)
  - Automated backups
  - Performance indexes on critical queries
  - UUID primary keys for distributed systems

### 4. Caching Layer (Redis)
- **Purpose**: Cache, session storage, Celery broker
- **Features**:
  - LRU eviction policy
  - Persistence with RDB snapshots
  - Separate databases for cache/sessions/celery
  - Password authentication
  - Memory limit enforcement (256MB default)

### 5. Task Queue (Celery)
- **Purpose**: Asynchronous task processing
- **Features**:
  - Computer vision processing via OpenAI API
  - Scheduled tasks via Celery Beat
  - Task result backend in Redis
  - Worker auto-scaling
  - Task retry with exponential backoff

### 6. Monitoring Stack
- **Purpose**: Observability and alerting
- **Components**:
  - **Health Checks**: `/api/v1/health/`, `/ready/`, `/health/`
  - **Metrics**: Prometheus metrics at `/metrics/`
  - **Logging**: Structured JSON logging to files
  - **Tracing**: Request ID tracking
  - **Alerting**: Integration with monitoring services

---

## Quick Start

### Prerequisites
- Ubuntu 22.04 LTS or newer
- Docker and Docker Compose
- Python 3.12+
- 4GB RAM minimum
- 20GB disk space

### Initial Setup

1. **Clone the repository:**
```bash
git clone https://github.com/yourusername/biologidex.git
cd biologidex/server
```

2. **Run the setup script:**
```bash
sudo bash scripts/setup.sh
```

3. **Configure environment:**
```bash
cp .env.example .env
# Edit .env with your configuration
nano .env
```

4. **Start the services:**
```bash
docker-compose -f docker-compose.production.yml up -d
```

5. **Run migrations (in order):**
```bash
docker-compose -f docker-compose.production.yml exec web python manage.py makemigrations accounts animals dex social vision images taxonomy
docker-compose -f docker-compose.production.yml exec web python manage.py migrate
```

5a. **Load taxonomy fixtures:**
```bash
docker-compose -f docker-compose.production.yml exec web python manage.py loaddata taxonomy/fixtures/ranks.json
```

6. **Create superuser:**
```bash
docker-compose -f docker-compose.production.yml exec web python manage.py createsuperuser
```

7. **Verify deployment:**
```bash
curl http://localhost/api/v1/health/
```

---

## Development

### Local Development Setup

For local development without Docker:

```bash
# Install dependencies
poetry install

# Start services (just PostgreSQL and Redis)
docker-compose up -d

# Run migrations (IMPORTANT: Always in this order)
python manage.py makemigrations accounts animals dex social vision images taxonomy
python manage.py migrate

# Load taxonomy fixtures
python manage.py loaddata taxonomy/fixtures/ranks.json

# Create test data
python manage.py seed_test_users

# Start development server
python manage.py runserver

# Start Celery worker (new terminal)
celery -A biologidex worker -l info

# Start Celery beat (new terminal)
celery -A biologidex beat -l info
```

### Testing

```bash
# Run all tests
python manage.py test

# Run with coverage
coverage run --source='.' manage.py test
coverage report

# Run specific app tests
python manage.py test accounts

# Run with parallel execution
python manage.py test --parallel
```

**Test Framework:** pytest with pytest-django
- Config in pyproject.toml
- Coverage reporting
- Test paths: accounts, animals, dex, social, vision, graph

---

## API Documentation

### Base URL: `/api/v1/`

### Authentication Endpoints (`/auth/`)
- `POST /login/` - User login (returns JWT + user data)
- `POST /refresh/` - Refresh access token

### User Endpoints (`/users/`)
- `POST /` - Register (no auth required)
- `GET /me/` - Current user profile
- `GET /friend-code/` - Get your friend code
- `POST /lookup_friend_code/` - Find user by friend code

### Animal Endpoints (`/animals/`)
- `GET /` - List all animals (paginated, filterable)
- `POST /` - Create animal (IsAuthenticated)
- `GET /{id}/` - Retrieve animal details
- `GET /recent/` - Last 20 discovered animals
- `GET /popular/` - Most captured animals
- `GET /{id}/taxonomy/` - Full taxonomy tree
- `POST /lookup_or_create/` - CV pipeline endpoint

**Filtering:** conservation_status, verified, kingdom, phylum, family
**Search:** ?search= searches scientific_name, common_name, genus, species
**Ordering:** ?ordering=creation_index or -created_at

### Dex Endpoints (`/dex/entries/`)
- `POST /` - Create entry (after CV identification)
- `GET /my_entries/` - User's collection
- `GET /favorites/` - Favorite entries
- `POST /{id}/toggle_favorite/` - Toggle favorite
- `GET /sync_entries/` - Sync entries with checksums (query param: `last_sync`)

### Social Endpoints (`/social/friendships/`)
- `GET /friends/` - Friends list
- `GET /pending/` - Incoming requests
- `POST /send_request/` - Send by friend_code or user_id
- `POST /{id}/respond/` - Accept/reject/block
- `DELETE /{id}/unfriend/` - Remove friendship

### Vision Endpoints (`/vision/jobs/`)
- `POST /` - Submit image (accepts optional `transformations` JSON), triggers async processing
- `GET /{id}/` - Check job status
- `GET /completed/` - View results
- `POST /{id}/retry/` - Retry failed job (accepts optional `transformations` JSON)

### Graph Endpoints (`/graph/`)
- `GET /taxonomic-tree/` - Network graph (cached)
- `POST /invalidate-cache/` - Clear cache

### Taxonomy Endpoints (`/taxonomy/`)
- `GET /` - List taxonomy records (paginated)
- `GET /{id}/` - Retrieve taxonomy details with full hierarchy
- `GET /search/?q=query` - Search by scientific/common name
- `POST /validate/` - Validate scientific name against database
- `GET /stats/` - Database statistics
- `GET /{id}/lineage/` - Complete taxonomic lineage
- `GET /{id}/children/?direct=true` - Get child taxa
- `GET /sources/` - List data sources (COL, GBIF, etc.)

**Query Parameters:**
- search: `?q=Panthera leo` - Search term
- filters: `?rank=species&kingdom=Animalia` - Filter by rank/kingdom
- limit: `?limit=50` - Max results (default: 20, max: 100)

### API Response Patterns

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

### Interactive API Documentation

- **Swagger UI**: `http://localhost/api/docs/`
- **ReDoc**: `http://localhost/api/redoc/`

---

## Database & Models

### Database Configuration

**Type:** PostgreSQL 15 (via docker-compose)

**Connection Pooling:**
- pgBouncer for production (via docker-compose.production.yml)
- `CONN_MAX_AGE=600` - 10-minute connection pooling in Django

### Model Relationships

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

### Models Table Summary
```
accounts_user                      - Custom user with UUID pk, friend_code
accounts_userprofile               - Auto-created profile with stats
animals_animal                     - Species taxonomy with creation_index
dex_dexentry                       - User captures of animals
social_friendship                  - Bidirectional friend relationships
vision_analysisjob                 - CV identification jobs
images_processedimage              - Processed images with transformations
taxonomy_datasource                - Registry of taxonomic databases
taxonomy_importjob                 - Tracks data import jobs
taxonomy_taxonomicrank             - Reference table for ranks
taxonomy_taxonomy                  - Normalized taxonomic records (9M+)
taxonomy_commonname                - Vernacular names
taxonomy_geographicdistribution    - Distribution and conservation data
taxonomy_raw_catalogue_of_life     - Staging table for COL imports
```

**All models use:**
- UUID primary keys (except through tables)
- created_at/updated_at timestamps
- Selective indexing on search fields

---

## Key Patterns & Implementation

### Design Patterns

1. **Auto-Increment Creation Index**: Sequential Pokedex-style numbering on Animal.save()
2. **Smart Image Fallback**: dex_compatible → processed → original URL selection
3. **Bidirectional Friendship**: Single model with query helpers (not two separate edges)
4. **Signal-Based Caching**: Automatic invalidation on model updates
5. **Celery Retry with Exponential Backoff**: 60s, 120s, 240s wait times
6. **Factory Pattern**: CVServiceFactory for extensible CV providers
7. **Dual Serializers**: Lightweight list vs. detailed view serializers
8. **Rate Limiting**: Per-endpoint throttle rates (anon: 100/hr, user: 1000/hr)

### Critical Implementation Details

**Binomial Nomenclature Parsing:**
```python
pattern = r'([A-Z][a-z]+)[,\s]+([a-z]+(?:\s+[a-z]+)?)\s*(?:\(([^)]+)\))?'
# Extracts: Genus, species [subspecies] (optional common name)
# Handles markdown italics via regex cleanup
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

**Model Compatibility (Vision API):**
- GPT-4 models: `max_tokens=300`
- GPT-5+/o-series: `max_completion_tokens=300`
- Auto-detection: Check model name prefix

**Image Processing Workflow:**
1. Client rotates image 90° (pixel-level, saves as PNG)
2. Upload sends pre-rotated image in original format
3. Server creates dex-compatible PNG (standardization)
4. Server sends dex-compatible image to Vision API
5. Result stored, Animal created/linked, DexEntry created

**Authentication Flow:**
- POST /auth/login/ → JWT access + refresh tokens
- POST /auth/refresh/ → New access token
- Refresh tokens rotate automatically, old ones blacklisted
- Access token expires in 60 minutes (configurable)

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

### Signal Pattern
- UserProfile auto-created on User creation
- Cache invalidation on model updates
- Graph cache invalidation on DexEntry creation

---

## Configuration

### Environment Variables

**Required:**
- `SECRET_KEY` - Django secret (50-char random string)
- `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` - PostgreSQL
- `REDIS_PASSWORD` - Redis password
- `OPENAI_API_KEY` - OpenAI Vision API (optional, CV disabled if not set)

**Optional:**
- `DEBUG` (True/False, default False in production)
- `ALLOWED_HOSTS` (comma-separated)
- `CORS_ALLOWED_ORIGINS` (comma-separated)
- `JWT_ACCESS_TOKEN_LIFETIME_MINUTES` (default 60)
- `GRAPH_CACHE_TTL`, `ANIMAL_CACHE_TTL` (in seconds)
- `GCS_BUCKET_NAME`, `GCS_PROJECT_ID` - Google Cloud Storage
- `MAX_UPLOAD_SIZE_MB` (default 10)
- `CELERY_BROKER_URL` - Redis URL (development: redis://localhost:6379/0)
- `THROTTLE_*_RATE` - Rate limiting

### Django Settings

Settings are split into modules:
- `base.py` - Shared configuration (all environments)
- `development.py` - Local development overrides
- `production_local.py` - Docker/local production overrides
- `production.py` - Cloud production settings

**Settings Configuration:**
- Development: `biologidex.settings.development`
- Production Local: `biologidex.settings.production_local` (Docker/local server)
- Production Cloud: `biologidex.settings.production` (GCP/cloud)
- manage.py defaults to development

---

## Monitoring & Health

### Health Checks

Three health check endpoints are available:

1. **Comprehensive Health Check**: `/api/v1/health/`
   - Checks database, Redis, Celery, storage
   - Returns detailed status and response times

2. **Liveness Check**: `/health/`
   - Simple check if application is running
   - Used by Docker/Kubernetes

3. **Readiness Check**: `/ready/`
   - Checks if application is ready for traffic
   - Verifies database and cache connectivity

### Prometheus Metrics

Metrics available at `/metrics/` include:

- `django_http_requests_total` - Request counts by endpoint
- `django_http_request_duration_seconds` - Response times
- `cv_processing_total` - CV job statistics
- `celery_tasks_total` - Task execution counts
- `active_users`, `total_dex_entries` - Business metrics
- HTTP request count and duration
- API endpoint performance
- Database query metrics
- Cache hit/miss rates
- Celery task metrics
- CV processing metrics
- Active user count

### Logging

Logs are written to `/var/log/biologidex/` with rotation:
- `app.log` - Application logs
- `error.log` - Error logs
- `celery.log` - Celery worker logs
- `gunicorn-access.log` - HTTP access logs
- `gunicorn-error.log` - Gunicorn error logs

In development: `server/logs/biologidex.log`

---

## Security

### Security Features

- **Authentication**: JWT with access/refresh tokens (60-min access, 7-day refresh)
- **Authorization**: Permission-based access control
- **Rate Limiting**: Per-user and per-IP limits
- **CORS**: Configurable allowed origins
- **CSRF Protection**: Enabled for state-changing operations
- **SQL Injection Prevention**: Django ORM with parameterized queries
- **XSS Protection**: Template auto-escaping, CSP headers
- **File Upload Validation**: Type and size restrictions
- **Secrets Management**: Environment variables, no hardcoded secrets
- **HTTPS**: SSL/TLS via Nginx or Cloudflare
- **Security Headers**: HSTS, X-Frame-Options, CSP

### Security Checklist

- [ ] Change all default passwords
- [ ] Configure SSL certificates
- [ ] Set up firewall rules
- [ ] Enable fail2ban
- [ ] Configure backup encryption
- [ ] Review Django security settings
- [ ] Set up monitoring alerts
- [ ] Configure log aggregation
- [ ] Implement intrusion detection
- [ ] Regular security updates

---

## Deployment

### Production Deployment

Deploy updates using the deployment script:
```bash
./scripts/deploy.sh
```

Options:
- `--skip-backup` - Skip database backup
- `--skip-migrate` - Skip database migrations
- `--skip-static` - Skip static files collection
- `--rollback` - Rollback to previous version
- `--maintenance` - Enable maintenance mode during deployment

### Godot Web Client Export

Export and deploy Godot web client:
```bash
./scripts/export-to-prod.sh              # Full export + deploy
./scripts/export-to-prod.sh --skip-export  # Deploy existing export
```

### Docker Compose Commands

```bash
# Start all services
docker-compose -f docker-compose.production.yml up -d

# View logs
docker-compose -f docker-compose.production.yml logs -f [service]

# Stop all services
docker-compose -f docker-compose.production.yml down

# Restart a service
docker-compose -f docker-compose.production.yml restart web

# Execute command in container
docker-compose -f docker-compose.production.yml exec web python manage.py shell

# Scale services
docker-compose -f docker-compose.production.yml up -d --scale web=3

# Rebuild images after code changes
docker-compose -f docker-compose.production.yml build web celery_worker celery_beat

# Restart containers after rebuild
docker-compose -f docker-compose.production.yml up -d
```

**CRITICAL**: Production uses **built Docker images**, NOT mounted volumes. Code changes require **rebuilding images** and restarting containers.

---

## Backup & Recovery

### Automated Backups

Backups run daily at 2 AM via cron:
```bash
/opt/biologidex/server/scripts/backup.sh
```

### Manual Backup
```bash
docker-compose -f docker-compose.production.yml exec db pg_dump -U biologidex biologidex > backup.sql
```

### Restore from Backup
```bash
docker-compose -f docker-compose.production.yml exec -T db psql -U biologidex biologidex < backup.sql
```

### Full Database Reset

To completely reset the database (users, animals with creation_index, and dex entries) on the production server:

**⚠️ WARNING**: This will permanently delete all user data, animals, and dex entries. Always create a backup first!

```bash
# 1. Create a backup first (optional but recommended)
docker-compose -f docker-compose.production.yml exec db pg_dump -U biologidex biologidex > backup_$(date +%Y%m%d_%H%M%S).sql

# 2. Stop all services
docker-compose -f docker-compose.production.yml down

# 3. Remove the database volume (this deletes all data)
docker volume rm server_postgres_data

# 4. Start services (creates fresh database)
docker-compose -f docker-compose.production.yml up -d

# 5. Wait for database to be ready (10-15 seconds)
sleep 15

# 6. Run migrations in order
docker-compose -f docker-compose.production.yml exec web python manage.py makemigrations accounts animals dex social vision images taxonomy
docker-compose -f docker-compose.production.yml exec web python manage.py migrate

# 7. Load taxonomy fixtures
docker-compose -f docker-compose.production.yml exec web python manage.py loaddata taxonomy/fixtures/ranks.json

# 8. Create a new superuser
docker-compose -f docker-compose.production.yml exec web python manage.py createsuperuser

# 9. (Optional) Seed test data
docker-compose -f docker-compose.production.yml exec web python manage.py seed_test_users

# 10. Verify the reset
docker-compose -f docker-compose.production.yml exec web python manage.py shell -c "from accounts.models import User; from animals.models import Animal; from dex.models import DexEntry; print(f'Users: {User.objects.count()}, Animals: {Animal.objects.count()}, Dex Entries: {DexEntry.objects.count()}')"
```

**Notes:**
- The database volume name may vary. Check with: `docker volume ls | grep postgres`
- If the volume name is different, replace `server_postgres_data` with the actual volume name
- After reset, the Animal creation_index counter will restart from 1
- You may need to reload taxonomy data if using COL integration: `docker-compose -f docker-compose.production.yml exec web python manage.py import_col --async`
- Media files (uploaded images) are stored separately and won't be deleted by this process. To also remove media files, use: `rm -rf /var/lib/biologidex/media/*`

**Selective Reset:**

To reset only specific tables without recreating the entire database:

```bash
# Reset only users
docker-compose -f docker-compose.production.yml exec db psql -U biologidex biologidex -c "TRUNCATE accounts_user CASCADE;"

# Reset only animals (includes cascade to dex entries)
docker-compose -f docker-compose.production.yml exec db psql -U biologidex biologidex -c "TRUNCATE animals_animal CASCADE;"

# Reset only dex entries
docker-compose -f docker-compose.production.yml exec db psql -U biologidex biologidex -c "TRUNCATE dex_dexentry CASCADE;"

# Reset creation_index sequence after deleting animals
docker-compose -f docker-compose.production.yml exec db psql -U biologidex biologidex -c "SELECT setval('animals_animal_creation_index_seq', 1, false);"
```

---

## Troubleshooting

For detailed troubleshooting procedures, monitoring guides, and operational documentation, see the **[Operations Guide](operations.md)**.

### Common Issues

| Issue | Check | Fix |
|-------|-------|-----|
| 502 Bad Gateway | `docker-compose ps web` | Restart web service |
| DB Connection Errors | `docker-compose exec db pg_isready` | Check pgBouncer config |
| Celery Tasks Stuck | `celery inspect active` | Restart workers |
| High Memory | `docker stats` | Reduce Gunicorn workers |
| Slow API | Check `/metrics/` endpoint | Add caching/indexes |
| Migrations show as applied but columns missing | `\d table_name` in psql | Fake unapply then reapply: `migrate vision 0001 --fake` then `migrate vision` |

**Container won't start:**
```bash
# Check logs
docker-compose -f docker-compose.production.yml logs web

# Check container status
docker ps -a

# Verify environment variables
docker-compose -f docker-compose.production.yml config
```

**Database connection errors:**
```bash
# Test database connection
docker-compose -f docker-compose.production.yml exec web python manage.py dbshell

# Check PostgreSQL logs
docker-compose -f docker-compose.production.yml logs db
```

**Celery tasks not processing:**
```bash
# Check worker status
docker-compose -f docker-compose.production.yml exec celery_worker celery -A biologidex inspect active

# Check Redis connectivity
docker-compose -f docker-compose.production.yml exec redis redis-cli ping
```

**High memory usage:**
```bash
# Check memory usage
docker stats

# Restart services
docker-compose -f docker-compose.production.yml restart

# Clear Redis cache
docker-compose -f docker-compose.production.yml exec redis redis-cli FLUSHALL
```

### Debug Mode

To enable debug mode temporarily:
```bash
docker-compose -f docker-compose.production.yml exec web python manage.py shell
>>> from django.conf import settings
>>> settings.DEBUG = True
```

---

## Taxonomy Data Loading

### Overview

BiologiDex now includes a complete taxonomic data system integrated with the Catalogue of Life (COL). This provides authoritative validation for all CV-identified animals and enriches animal records with full taxonomic hierarchies, conservation status, and geographic distributions.

### Prerequisites

Before loading taxonomy data:

1. **Database must be running:**
   ```bash
   docker-compose -f docker-compose.production.yml up -d db redis
   ```

2. **Migrations must be applied:**
   ```bash
   # Create migrations for taxonomy and updated animals models
   poetry run python manage.py makemigrations taxonomy animals

   # Apply migrations (in order)
   poetry run python manage.py migrate
   ```

3. **Load taxonomic rank fixtures:**
   ```bash
   poetry run python manage.py loaddata taxonomy/fixtures/ranks.json
   ```

### Loading Catalogue of Life Data

#### Understanding COL Release Types

Catalogue of Life provides two types of releases:

- **Base Release** (`origin='release'`): ~5.4M curated, expert-verified records (~962 MB)
  - Higher quality, all entries reviewed by taxonomists
  - **Current default** for the importer

- **XR / eXtended Release** (`origin='xrelease'`): ~9.4M records including programmatic additions (~1.3 GB)
  - Better coverage including molecular identifiers and automated sources
  - Recommended for maximum species coverage in CV systems

The importer automatically selects the latest **base release** with an available export.

#### Option 1: Automatic Download (Recommended)

Download and import the latest COL base release automatically:

```bash
# Run in foreground (2-3 hours)
poetry run python manage.py import_col

# OR run as async Celery task (recommended for production)
poetry run python manage.py import_col --async
```

The command will:
1. Query API for latest base release (`origin='release'`)
2. Check top 5 candidates for export availability
3. Download the dataset (~1GB zip file with `extended=true` format)
4. Verify zip integrity and ColDP structure
5. Extract NameUsage.tsv (~5.4M records for base release)
6. Import to staging table (RawCatalogueOfLife)
7. Normalize to Taxonomy model with validation
8. Calculate completeness scores
9. Update caches

**Note**: The importer uses `extended=true` parameter to get the full ColDP format with `NameUsage.tsv` and all optional files, not the simplified export format.

#### Option 2: Use Local File

If you already have a COL dataset file:

```bash
# Using local zip file
poetry run python manage.py import_col --file /path/to/col_dataset.zip

# With async processing
poetry run python manage.py import_col --file /path/to/col_dataset.zip --async
```

#### Option 3: Using Existing Downloaded Data

If COL data is in `/resources/catalogue_of_life/`:

```bash
# Point to the extracted directory's zip file
poetry run python manage.py import_col --file /resources/catalogue_of_life/coldp.zip
```

### Monitoring Import Progress

#### Console Output (Foreground)

When run synchronously, you'll see:
```
=== Catalogue of Life Import ===
✓ Created data source: Catalogue of Life (col)
Created import job: 12345678-abcd-...
Running import synchronously...
⚠ This may take 2-3 hours for full COL dataset

Fetching latest COL dataset info...
Latest COL dataset: 1234 (version 2025-01)
Downloading dataset to /path/to/file.zip...
Download progress: 10.0% (100.0MB)
...
Download complete: 3200.00MB

Extracting zip file...
Parsing NameUsage.tsv...
Read 50000 records...
Read 100000 records...
...
Finished parsing: 9400000 records read

Normalizing 9400000 raw records...
Processed 10000/9400000 records...
...

✓ Import completed successfully!
  Records imported: 9400000
  Records failed: 0
  Records read: 9400000
```

#### Async Monitoring (Background)

When run with `--async`, monitor via:

1. **Django Admin:**
   - Navigate to: `http://localhost/admin/taxonomy/importjob/`
   - View status, progress, errors in real-time

2. **Log Files:**
   ```bash
   tail -f logs/biologidex.log | grep import
   ```

3. **Celery Inspector:**
   ```bash
   # Check active tasks
   celery -A biologidex inspect active

   # Check task stats
   celery -A biologidex inspect stats
   ```

### Post-Import Verification

After import completes, verify the data:

```bash
# Check taxonomy stats via API
curl http://localhost/api/v1/taxonomy/stats/

# Expected response:
{
  "total_taxa": 9400000,
  "kingdoms": 5,
  "species": 2100000,
  "genera": 450000,
  "families": 65000,
  "sources": 1
}

# Search for a species
curl "http://localhost/api/v1/taxonomy/search/?q=Panthera+leo"

# Check Django admin
# Visit: http://localhost/admin/taxonomy/taxonomy/
```

### Updating Existing Animals

After loading taxonomy data, sync existing animals with taxonomy:

```bash
# Run taxonomy sync (enriches existing animals with taxonomy data)
poetry run python manage.py shell

>>> from taxonomy.tasks import sync_taxonomy_to_animals
>>> sync_taxonomy_to_animals()
```

Or schedule it as a Celery task:
```python
# In biologidex/celery.py - add to beat_schedule:
'sync-taxonomy-daily': {
    'task': 'taxonomy.tasks.sync_taxonomy_to_animals',
    'schedule': crontab(hour=3, minute=0),
}
```

### Performance Considerations

**Import Times:**
- **Download**: 10-30 minutes (depends on connection)
- **Parsing**: 30-45 minutes (9.4M records)
- **Normalization**: 60-90 minutes (batched inserts)
- **Total**: ~2-3 hours

**Resource Usage:**
- **Disk**: 10GB temporary (5GB after cleanup)
- **Memory**: 2-4GB peak during processing
- **Database**: 8-10GB for full dataset

**Optimization Tips:**
- Run during off-peak hours
- Use `--async` flag for production
- Ensure sufficient disk space in `/tmp` or `MEDIA_ROOT`
- Monitor PostgreSQL memory (may need tuning for large imports)

### Incremental Updates

To update with latest COL data:

```bash
# Default: Blocks if import done in last 30 days
poetry run python manage.py import_col

# Force new import
poetry run python manage.py import_col --force

# Async + force
poetry run python manage.py import_col --async --force
```

### Troubleshooting

**Download fails:**
- Check internet connection
- Verify COL API is accessible: `curl https://api.checklistbank.org/dataset`
- Try using `--file` with a pre-downloaded dataset

**Import fails during processing:**
- Check disk space: `df -h`
- Check database connections: `docker-compose exec db pg_isready`
- Review error log in ImportJob via Django admin
- Check logs: `tail -f logs/biologidex.log`

**Memory errors:**
- Reduce batch sizes in `col_importer.py` (default: 5000)
- Increase Docker memory limits in `docker-compose.yml`
- Add swap space if needed

**Slow performance:**
- Disable indexes temporarily (requires code modification)
- Use faster storage (SSD)
- Increase PostgreSQL `work_mem` and `maintenance_work_mem`

### Data Source Management

View and manage taxonomy sources:

```bash
# Via Django admin
http://localhost/admin/taxonomy/datasource/

# Via API
curl http://localhost/api/v1/sources/
```

Add additional sources (GBIF, iNaturalist) by:
1. Creating a new importer class in `taxonomy/importers/`
2. Registering the source in DataSource model
3. Running import with appropriate priority

### Cleanup

Remove old import data:

```bash
# Manual cleanup (deletes processed raw records > 30 days old)
poetry run python manage.py shell

>>> from taxonomy.tasks import cleanup_old_imports
>>> cleanup_old_imports()

# Or schedule as Celery task
# Runs automatically if configured in celery.py beat_schedule
```

### Validation Testing

Test the taxonomy integration with CV pipeline:

```bash
# Via Django shell
poetry run python manage.py shell

>>> from taxonomy.services import TaxonomyService
>>> from animals.services import AnimalService

# Test taxonomy lookup
>>> taxonomy = TaxonomyService.lookup_by_scientific_name("Panthera leo")
>>> print(taxonomy.full_hierarchy)

# Test animal creation from taxonomy
>>> animal, created, message = AnimalService.lookup_or_create_from_cv(
...     "Panthera leo", "Lion", confidence=0.95
... )
>>> print(f"Animal: {animal}, Created: {created}, Message: {message}")
```

### Field Mapping Reference

**COL NameUsage → Taxonomy Model**
```
col:ID                  → source_taxon_id
col:scientificName      → scientific_name
col:authorship          → authorship
col:status              → status (mapped: accepted/provisional/synonym)
col:rank                → rank (FK to TaxonomicRank)
col:kingdom             → kingdom
col:phylum              → phylum
col:class               → class_name
col:order               → order
col:family              → family
col:subfamily           → subfamily
col:genus               → genus
col:species             → species
col:subspecies          → subspecies
col:genericName         → generic_name
col:specificEpithet     → specific_epithet
col:code                → nomenclatural_code (mapped: iczn/icn/icnp)
col:extinct             → extinct (boolean)
col:environment         → environment (array: marine/terrestrial/freshwater)
```

**Taxonomy → Animal Model**
```
taxonomy.scientific_name     → animal.scientific_name
taxonomy.kingdom             → animal.kingdom
taxonomy.phylum              → animal.phylum
taxonomy.class_name          → animal.class_name
taxonomy.order               → animal.order
taxonomy.family              → animal.family
taxonomy.subfamily           → animal.subfamily
taxonomy.genus               → animal.genus
taxonomy.specific_epithet    → animal.species
taxonomy.id                  → animal.taxonomy_id
taxonomy.source.short_code   → animal.taxonomy_source
taxonomy.source_url          → animal.taxonomy_source_url
distributions[native]        → animal.native_regions
distributions[threat_status] → animal.conservation_status
```

---

## Future Extensibility

1. **Multiple CV Providers** - CVServiceFactory ready for new implementations
2. **Additional Taxonomy Sources** - System supports GBIF, iNaturalist, WoRMS, ITIS
   - BaseImporter abstract class ready for new data sources
   - DataSource model with priority-based conflict resolution
   - Extensible importer architecture
3. **Real-time Updates** - WebSocket support can be added
4. **Machine Learning** - Custom animal identification model slot
5. **Gamification** - Badge system in User.badges (JSON)
6. **Localization** - Uses Django i18n framework
7. **Advanced Filtering** - DjangoFilterBackend supports custom filters
8. **Rate Limiting** - Per-endpoint throttle rates configurable
9. **Vernacular Names** - CommonName model ready for VernacularName.tsv import
10. **Geographic Distributions** - GeographicDistribution model ready for Distribution.tsv import

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
- `/server/social/models.py` - Friendship
- `/server/vision/models.py` - AnalysisJob CV tracking
- `/server/images/models.py` - ProcessedImage
- `/server/taxonomy/models.py` - Taxonomy, DataSource, ImportJob
- `/server/taxonomy/raw_models.py` - RawCatalogueOfLife

**Services:**
- `/server/vision/services.py` - OpenAIVisionService
- `/server/vision/tasks.py` - Celery tasks + parse_and_create_animal()
- `/server/graph/services.py` - EvolutionaryGraphService
- `/server/vision/image_processor.py` - ImageProcessor, EnhancedImageProcessor
- `/server/taxonomy/services.py` - TaxonomyService
- `/server/animals/services.py` - AnimalService with taxonomy integration

**Importers:**
- `/server/taxonomy/importers/base.py` - BaseImporter abstract class
- `/server/taxonomy/importers/col_importer.py` - CatalogueOfLifeImporter

**Views/Serializers:**
- `/server/{app}/views.py` - ViewSets for each app
- `/server/{app}/serializers.py` - DRF serializers
- `/server/{app}/urls.py` - REST routing

**Management Commands:**
- `/server/accounts/management/commands/seed_test_users.py` - Create test data
- `/server/taxonomy/management/commands/import_col.py` - Import COL data

**Fixtures:**
- `/server/taxonomy/fixtures/ranks.json` - Taxonomic rank reference data (20 ranks)

**Data:**
- `/resources/catalogue_of_life/` - 3GB+ Catalogue of Life dataset (can be imported)
- `/resources/catalogue_of_life/catalogue_of_life.md` - CoL documentation
- Taxonomy data loaded via `python manage.py import_col` command

**Configuration:**
- `/server/biologidex/settings/base.py` - All settings
- `/server/pyproject.toml` - Dependencies

---

## Performance Optimization

### Database Optimization
- Indexes on frequently queried fields
- Connection pooling via pgBouncer
- Query optimization with select_related/prefetch_related
- Database vacuuming schedule

### Caching Strategy
- Redis for session storage
- Cache frequently accessed data (1-hour TTL for Animals, 2-min for graphs)
- API response caching with proper invalidation
- Static file caching with Nginx

### Application Optimization
- Gunicorn worker tuning (workers = CPU*2+1)
- Async task processing with Celery
- Image optimization before storage
- Pagination for large datasets

---

## Maintenance

### Regular Maintenance Tasks

**Daily:**
- Check health endpoints
- Review error logs
- Monitor disk space

**Weekly:**
- Update dependencies
- Review security alerts
- Check backup integrity

**Monthly:**
- Performance analysis
- Security audit
- Update documentation

### Upgrade Procedure

1. Test upgrades in staging environment
2. Create full backup
3. Enable maintenance mode
4. Deploy updates
5. Run migrations
6. Verify functionality
7. Disable maintenance mode

---

## Support

### Resources
- [Django Documentation](https://docs.djangoproject.com/)
- [Django REST Framework](https://www.django-rest-framework.org/)
- [Docker Documentation](https://docs.docker.com/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

---

**Last Updated**: January 2025
**Version**: 1.0.0
**Status**: Production Ready
