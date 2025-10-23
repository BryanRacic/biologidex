# Local Development / Getting Started
see server/development.md

# Usage
### Step-by-Step Setup

Start python env
```bash
poetry shell
```

Start PostgreSQL and Redis
```bash
docker-compose up -d
```

Run migrations (if necissary)
```bash
python manage.py migrate
```

Start Development Server
```bash
python manage.py runserver
```
The server will start at `http://localhost:8000/`

Start Celery Worker (in another terminal)
Open a second terminal window and run:
```bash
poetry shell
celery -A biologidex worker -l info
```

# Outline
User
- Account creation
- Login
- View Profile
- Update Profile
- Get friendslist
- Get friend code
- Add friend by code

Create Dex Entry
- Analyze image
- Get animal Record
  - Create animal record if doesn't exist
- Create dex entry

Modify dex entry
- modify dex entry 

Get Dex Entries (all nodes: user's & friend's)
- Get known dex entries
- Get dex entry
- Download dex image

## Layout
High-level app breakdown:
- accounts/ – user auth, profiles, friend codes, settings
- social/ – friendships & friend lists
- animals/ – canonical “Animal” records (taxonomy, metadata)
- dex/ – user “DexEntry” (links user ↔ animal + image + status)
- vision/ – CV pipeline (image ingestion, analysis jobs, adapters to providers)
- graph/ – graph APIs (seen network across user + friends)

Each app owns its models, serializers, viewsets, urls, tasks, and admin.

Minimal project layout
pokedex/
  manage.py
  pokedex/settings.py
  pokedex/urls.py
  accounts/
    models.py, serializers.py, views.py, urls.py, services.py, admin.py, signals.py, permissions.py
  social/
    models.py, serializers.py, views.py, urls.py, admin.py
  animals/
    models.py, serializers.py, views.py, urls.py, admin.py
  dex/
    models.py, serializers.py, views.py, urls.py, admin.py
  vision/
    models.py, tasks.py, adapters/..., services.py, urls.py
  graph/
    views.py, urls.py, services.py


# Implementation
## Best Practice Notes
- Auth: Use JWT (e.g., djangorestframework-simplejwt). Require auth on all mutating endpoints.
- Storage: Google Cloud Storage via django-storages; store original + a standardized dex image (create on upload with a signal/task).
- Database: PostgreSQL for both development and production for consistency and feature parity.
- Throttling/Rate limits: DRF throttles for image upload & friend-adds; per-IP + per-user.
- Validation: Server-side file type/size; optionally run an async safety check (e.g., NSFW) before public display.
- Indexing: Add composite indexes on DexEntry(owner, status, created_at) and DexEntry(owner, animal).
- Caching: Cache Graph results per user for a short TTL (e.g., 60–120s); cache Animal lookups.
- Idempotency: For CV callbacks or retries, use AnalysisJob as the idempotency key.
- Observability: Log AnalysisJob transitions; add Prometheus metrics (jobs queued/succeeded/failed, latency).
- OpenAPI: Generate swagger with drf-spectacular; document upload schema & graph schema.
- Migrations at scale: Prefer additive (nullable → backfill → not null), avoid column renames during traffic.

## Quick Start Recommended Settings
- AUTH_USER_MODEL = "accounts.User"
- Installed apps: django.contrib.*, rest_framework, django_filters, storages, your apps.
- DRF defaults (auth, throttle, pagination).
- Celery config + Redis; CELERY_TASK_ALWAYS_EAGER=False in prod.

## Post MVP TODO
- Admin for Animals/DexEntry/Profile.
- Override control: allow trusted users to correct misidentified animals (with audit trail).
- “Seen” logic tweaks: mark seen_source = "self" | "friend" | "suggested" on edges/nodes for the UI.
- Search: add trigram or full-text index on common_name/scientific_name.

---

# Implementation Plan

## Project Overview
Transform the existing default Django template into a fully functional MVP for BiologiDex - a Pokedex-style social network for sharing zoological observations with collaborative evolutionary tree building.

### Current State Assessment
- **Status**: ✅ **PHASE 1 COMPLETE** - All core infrastructure and apps implemented
- **Architecture**: Fully implemented with 6 Django apps
- **CV Integration**: OpenAI Vision API integrated with Celery async processing
- **Database**: PostgreSQL with Redis caching

---

## Phase 1: Foundation & Infrastructure ✅ COMPLETE

### 1.1 Project Setup & Dependencies ✅
**Status**: Complete
- Poetry-based dependency management with pyproject.toml
- All dependencies configured with latest compatible versions
- Python 3.12.10 environment with pyenv

### 1.2 Settings Configuration ✅
**Status**: Complete
- Split settings architecture (base/development/production)
- Environment variables via python-dotenv
- JWT authentication configured
- Google Cloud Storage for media files
- Celery + Redis for async tasks
- Comprehensive logging with rotating file handlers

### 1.3 Database Setup ✅
**Status**: Complete
- PostgreSQL 15 via Docker Compose
- Connection pooling configured (CONN_MAX_AGE=600)
- Redis for caching and Celery backend
- Proper indexing on all models for query performance

**PostgreSQL Configuration:**
```python
# settings.py
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.getenv('DB_NAME', 'biologidex'),
        'USER': os.getenv('DB_USER', 'postgres'),
        'PASSWORD': os.getenv('DB_PASSWORD'),
        'HOST': os.getenv('DB_HOST', 'localhost'),
        'PORT': os.getenv('DB_PORT', '5432'),
        'CONN_MAX_AGE': 600,  # Connection pooling
    }
}
```

**Docker Compose for Local Development:**
```yaml
# docker-compose.yml
version: '3.8'
services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: biologidex
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

volumes:
  postgres_data:
```

### 1.4 Google Cloud Storage Setup
**Storage Configuration:**
```python
# settings.py
from google.oauth2 import service_account

# Google Cloud Storage settings
GS_BUCKET_NAME = os.getenv('GCS_BUCKET_NAME')
GS_PROJECT_ID = os.getenv('GCS_PROJECT_ID')
GS_CREDENTIALS = service_account.Credentials.from_service_account_file(
    os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
)

# Media files
DEFAULT_FILE_STORAGE = 'storages.backends.gcloud.GoogleCloudStorage'
GS_DEFAULT_ACL = 'publicRead'  # Or 'private' for authenticated access
GS_FILE_OVERWRITE = False
GS_MAX_MEMORY_SIZE = 5242880  # 5MB

# Static files (optional - can use GCS or local/CDN)
STATIC_URL = '/static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

# Media URL from GCS
MEDIA_URL = f'https://storage.googleapis.com/{GS_BUCKET_NAME}/'
```

**Environment Variables (.env):**
```bash
# Database
DB_NAME=biologidex
DB_USER=postgres
DB_PASSWORD=your_secure_password
DB_HOST=localhost
DB_PORT=5432

# Google Cloud Storage
GCS_BUCKET_NAME=biologidex-media
GCS_PROJECT_ID=your-project-id
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json

# Django
SECRET_KEY=your_secret_key_here
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1

# OpenAI
OPENAI_API_KEY=your_openai_key

# Celery
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0
```

---

## Phase 2: Core Django Apps Creation

### 2.1 Accounts App
**Models:**
```python
# accounts/models.py
- User (extends AbstractUser)
  - friend_code (unique, auto-generated)
  - bio, avatar, created_at, updated_at
  - badges (JSONField for achievements)

- UserProfile (OneToOne with User)
  - total_catches, unique_species, join_date
  - preferred_card_style (JSONField)
```

**Key Features:**
- JWT authentication endpoints
- User registration/login/logout
- Profile CRUD operations
- Friend code generation system
- Password reset flow

### 2.2 Animals App
**Models:**
```python
# animals/models.py
- Animal
  - scientific_name (genus + species, unique)
  - common_name
  - kingdom, phylum, class, order, family
  - conservation_status
  - description, habitat, diet
  - creation_index (auto-increment, like Pokedex #)
  - created_by (ForeignKey to User)
  - verified (boolean)
```

**Key Features:**
- Animal database with taxonomic information
- Auto-lookup from external APIs
- Fallback to LLM for missing data
- Admin interface for verification

### 2.3 Dex App
**Models:**
```python
# dex/models.py
- DexEntry
  - owner (ForeignKey to User)
  - animal (ForeignKey to Animal)
  - original_image (ImageField)
  - processed_image (ImageField, auto-generated)
  - location (optional GPS)
  - notes (TextField)
  - catch_date, created_at
  - visibility (private/friends/public)
  - customizations (JSONField for card styling)
```

**Key Features:**
- User's personal collection management
- Image upload and processing
- Card customization options
- Privacy controls

### 2.4 Social App
**Models:**
```python
# social/models.py
- Friendship
  - user_from, user_to (ForeignKeys to User)
  - status (pending/accepted/blocked)
  - created_at

- SharedTree
  - Cached representation of friend network's catches
```

**Key Features:**
- Friend request system using friend codes
- Friends list management
- Shared evolutionary tree generation

### 2.5 Vision App
**Models:**
```python
# vision/models.py
- AnalysisJob
  - image (ImageField)
  - status (pending/processing/completed/failed)
  - cv_method (openai/fallback)
  - raw_response (JSONField)
  - identified_animal (ForeignKey to Animal, nullable)
  - confidence_score
  - cost_usd, processing_time
```

**Services:**
- Integrate existing `animal_id_benchmark.py` code
- OpenAI Vision API adapter
- Fallback CV service adapters
- Async processing with Celery

---

## Phase 3: API Implementation

### 3.1 RESTful API Structure
```
/api/v1/
├── auth/
│   ├── register/
│   ├── login/
│   ├── refresh/
│   └── logout/
├── users/
│   ├── profile/
│   ├── {id}/
│   └── friend-code/
├── social/
│   ├── friends/
│   ├── friend-requests/
│   └── add-friend/
├── animals/
│   ├── list/
│   ├── {id}/
│   └── search/
├── dex/
│   ├── entries/
│   ├── {id}/
│   ├── upload/
│   └── analyze/
├── vision/
│   ├── identify/
│   └── job/{id}/
└── graph/
    └── evolutionary-tree/
```

### 3.2 Serializers & ViewSets
- Implement ModelSerializers for all models
- Create nested serializers for related data
- Add validation and permissions
- Implement pagination and filtering

### 3.3 Business Logic Services
- Create service layers for complex operations
- Implement the animal identification workflow
- Friend network calculations
- Evolutionary tree generation algorithm

---

## Phase 4: Core Workflows

### 4.1 Animal Identification Workflow
```python
# Workflow steps:
1. User uploads image → Create AnalysisJob
2. Async task: Send to OpenAI Vision API
3. Parse response using ANIMAL_ID_PROMPT format
4. Lookup or create Animal record
5. Create DexEntry for user
6. Send notification on completion
```

### 4.2 Social Features
- Friend code generation and sharing
- Friend request acceptance flow
- Shared collection visibility
- Collaborative tree building

### 4.3 Data Enrichment Pipeline
- External API integration for animal facts
- LLM fallback for missing information
- Image processing and thumbnail generation
- Card style generation

---

## Phase 5: Testing & Documentation

### 5.1 Testing Suite
```python
# Test coverage targets:
- Unit tests for models and serializers
- Integration tests for workflows
- API endpoint tests
- CV integration tests (using benchmark framework)
```

### 5.2 API Documentation
- Auto-generate OpenAPI schema with drf-spectacular
- Document all endpoints
- Provide example requests/responses
- Authentication flow documentation

---

## Phase 6: Production Readiness

### 6.1 Security & Performance
- Implement rate limiting
- Add request throttling
- Set up caching (Redis)
- Database query optimization
- Add proper indexes

### 6.2 Deployment Configuration
- Docker containerization
- Environment-specific settings
- Gunicorn/uWSGI configuration
- Nginx setup for static files
- Database migrations strategy

---

## Implementation Order & Priority

### Week 1 Focus (MVP Core)
1. **Day 1-2**: Setup & infrastructure
2. **Day 3-4**: Accounts & Animals apps
3. **Day 5-6**: Vision app & CV integration
4. **Day 7**: Dex app & core workflow

### Week 2 Focus (Social & Polish)
5. **Day 8-9**: Social features & friend system
6. **Day 10-11**: Evolutionary tree & graph APIs
7. **Day 12**: Testing & documentation
8. **Day 13-14**: Production readiness

---

## Best Practices Implementation

### Code Organization
```python
# Each app follows this structure:
app_name/
├── models.py       # Django models
├── serializers.py  # DRF serializers
├── views.py        # ViewSets and APIViews
├── urls.py         # URL routing
├── services.py     # Business logic
├── tasks.py        # Celery async tasks
├── signals.py      # Django signals
├── permissions.py  # Custom permissions
├── admin.py        # Admin interface
└── tests/          # Test directory
    ├── test_models.py
    ├── test_views.py
    └── test_services.py
```

### Security Checklist
- [x] JWT authentication on all endpoints
- [x] CORS properly configured
- [x] File upload validation
- [x] SQL injection prevention (ORM)
- [x] Rate limiting on expensive operations
- [x] Secure secret management (.env)
- [x] HTTPS enforcement in production

### Performance Optimizations
- Database indexes on frequently queried fields
- Celery for async image processing
- Redis caching for evolutionary tree
- Pagination on list endpoints
- Select_related/prefetch_related optimization
- Image compression and thumbnails

---

## Next Steps & Essential Improvements

### Immediate Next Steps (Post-MVP)

TODO: Figure out email stuff? 
  - Sending out email verification
  - Reset password

1. **Frontend Development**
   - React/Vue.js application
   - Mobile-responsive design
   - Real-time updates (WebSocket)

2. **Enhanced CV Pipeline**
   - Multiple CV service integration
   - Confidence scoring improvements
   - Species verification system

3. **Gamification Features**
   - Achievement system
   - Leaderboards
   - Rare species alerts
   - Collection completion tracking

### Essential Improvements
1. **Scalability**
   - Microservice architecture consideration
   - GraphQL API option
   - CDN for media files (Cloud CDN with GCS backend)
   - Database sharding strategy (PostgreSQL partitioning)
   - Cloud SQL for managed PostgreSQL in production

2. **ML/AI Enhancements**
   - Custom trained animal recognition model
   - Species suggestion algorithm
   - Habitat-based recommendations

3. **Social Features**
   - Group collections
   - Trading card mechanics
   - Community challenges
   - Expert verification system

4. **Data Quality**
   - Crowdsourced verification
   - Expert review panel
   - Automated quality checks
   - Report/flag system

---

## Risk Mitigation

### Technical Risks
- **CV API Costs**: Implement caching, batch processing
- **Data Quality**: Manual verification, community moderation
- **Scalability**: Start with vertical scaling, plan for horizontal
- **Privacy**: Implement robust permission system

### Operational Risks
- **Image Storage Costs**: Compress images, implement quotas, use GCS lifecycle policies
- **API Rate Limits**: Queue system, multiple API keys
- **Database Growth**: Archival strategy, data retention policies, PostgreSQL partitioning

---

## Success Metrics

### MVP Success Criteria
- ✓ Users can register and authenticate
- ✓ Image upload triggers animal identification
- ✓ Successful creation of dex entries
- ✓ Friend system functional
- ✓ Basic evolutionary tree visible
- ✓ API response time < 2s for standard operations
- ✓ CV identification accuracy > 70%

### Performance Targets
- API response time: < 200ms (cached), < 2s (uncached)
- Image processing: < 10s end-to-end
- Concurrent users: Support 100+ active users
- Database queries: < 50ms for common operations 