# BiologiDex Architecture Documentation Index

This directory contains comprehensive documentation of the BiologiDex project architecture, including both the frontend Godot client and backend Django server.

## Documentation Files

### Core Architecture Documents

1. **DJANGO_ARCHITECTURE.md** (25 KB, 742 lines)
   - Comprehensive analysis of the Django server architecture
   - Detailed breakdown of all 7 Django apps
   - Database models and relationships
   - API endpoints and authentication
   - Services and design patterns
   - Data import planning for Catalogue of Life
   - Integration points and future extensibility
   - **Best for**: Understanding the complete system structure, developer reference

2. **SERVER_QUICK_REFERENCE.md** (9.6 KB, 249 lines)
   - Quick lookup guide for server architecture
   - System overview and component summary
   - Key design patterns and critical implementation details
   - File locations and environment variables
   - What exists vs. what's needed
   - **Best for**: Quick lookups, onboarding, implementation checklists

3. **CLAUDE.md** (32 KB)
   - Project-level memory and instructions
   - Current project status and phase completion
   - Technical architecture overview
   - Frontend (Godot) patterns and implementation details
   - Backend stack and critical learnings
   - Production infrastructure documentation
   - Development workflow and common commands
   - **Best for**: Project context and high-level decisions

4. **taxonomic_data.md** (2.5 KB)
   - Taxonomic database design specification
   - Plan for integrating Catalogue of Life
   - Data source architecture
   - Mapping from COL to Django models
   - **Best for**: Understanding data import requirements

### Supporting Documentation

5. **image-handling-updates.md** (15 KB)
   - Image transformation system details
   - Client-side rotation implementation
   - Server-side image processing pipeline
   - EXIF metadata handling
   - **Best for**: Image processing implementation details

6. **client-host.md** (9.4 KB)
   - Godot web client deployment architecture
   - Docker integration and deployment
   - CloudFlare tunnel configuration
   - **Best for**: Frontend deployment and hosting

7. **README.md** (12 KB)
   - General project overview
   - Getting started guide
   - Feature description
   - Technology stack summary
   - **Best for**: Project introduction

---

## Quick Navigation by Topic

### Understanding the System

**For Overview:**
1. Start with README.md (project intro)
2. Read CLAUDE.md "Project Overview" and "Current Status" sections
3. Scan SERVER_QUICK_REFERENCE.md "System Overview" section

**For Deep Dive:**
1. Read DJANGO_ARCHITECTURE.md completely
2. Reference CLAUDE.md for specific implementation patterns
3. Check file locations for exact code references

### Database and Models

**Understanding the data structure:**
1. DJANGO_ARCHITECTURE.md → "Django Apps Architecture" section (all 7 apps)
2. SERVER_QUICK_REFERENCE.md → "Database Model Relationships"
3. DJANGO_ARCHITECTURE.md → "Database Configuration" section
4. Check actual model files: `/server/{app}/models.py`

### API and Integration

**Building API integrations:**
1. DJANGO_ARCHITECTURE.md → "API Architecture" section
2. SERVER_QUICK_REFERENCE.md → "API Response Patterns"
3. Check actual viewsets: `/server/{app}/views.py`
4. Reference serializers: `/server/{app}/serializers.py`

### Image Processing

**For image handling:**
1. image-handling-updates.md (complete guide)
2. DJANGO_ARCHITECTURE.md → "IMAGES APP" section
3. Check services: `/server/vision/image_processor.py`
4. CLAUDE.md → "Image Transformation System" section

### Data Import and Taxonomy

**For Catalogue of Life integration:**
1. taxonomic_data.md (requirements and planning)
2. DJANGO_ARCHITECTURE.md → "Data Import & Taxonomic Data Plan"
3. /resources/catalogue_of_life/catalogue_of_life.md (data documentation)
4. SERVER_QUICK_REFERENCE.md → "Data Import (Not Yet Implemented)"

### Production Deployment

**For deployment and operations:**
1. CLAUDE.md → "Production Infrastructure" section
2. CLAUDE.md → "Godot Web Client Deployment" section
3. CLAUDE.md → "Troubleshooting Quick Reference"
4. Docker files: `/server/docker-compose.production.yml`, `/server/Dockerfile.production`

### Development and Testing

**For local development:**
1. CLAUDE.md → "Development Workflow" section
2. SERVER_QUICK_REFERENCE.md → "Testing" section
3. DJANGO_ARCHITECTURE.md → "Testing & Development" section
4. Check management commands: `/server/accounts/management/commands/`

---

## Key Architectural Components

### 7 Django Apps

| App | Purpose | Key Model | Status |
|-----|---------|-----------|--------|
| **accounts** | User management | User, UserProfile | Complete |
| **animals** | Species taxonomy | Animal | Complete |
| **dex** | User captures | DexEntry | Complete |
| **social** | Friendships | Friendship | Complete |
| **vision** | CV pipeline | AnalysisJob | Complete |
| **images** | Image processing | ProcessedImage | Complete |
| **graph** | Evolutionary trees | (Service-based) | Complete |

### Critical Services

| Service | Location | Purpose |
|---------|----------|---------|
| OpenAIVisionService | `vision/services.py` | Animal identification via GPT |
| ImageProcessor | `vision/image_processor.py` | PNG conversion and resizing |
| EnhancedImageProcessor | `vision/image_processor.py` | Transformations + EXIF |
| EvolutionaryGraphService | `graph/services.py` | Graph generation |
| CVServiceFactory | `vision/services.py` | Service instantiation pattern |

### Celery Tasks

| Task | Location | Purpose |
|------|----------|---------|
| `process_analysis_job` | `vision/tasks.py` | Async CV processing |
| `parse_and_create_animal` | `vision/tasks.py` | Parse CV output + create Animal |
| `cleanup_old_analysis_jobs` | `vision/tasks.py` | Periodic cleanup |

---

## Implementation Status

### Completed
- All Django app models with proper relationships
- Complete REST API with JWT authentication
- CV identification pipeline (OpenAI Vision)
- Image processing with rotation and transformations
- Social friendship system with bidirectional support
- Evolutionary graph generation with caching
- Production Docker setup with monitoring
- Admin interface for all models
- Rate limiting and throttling
- Comprehensive logging and health checks

### In Progress
- Data import framework (Catalogue of Life integration)

### Not Yet Started
- Automated tests (pytest infrastructure ready)
- WebSocket real-time updates
- Advanced search and filtering UI
- Mobile app (beyond web export)
- Machine learning custom models

---

## How to Use This Documentation

**I'm new to the project:**
1. Read README.md for overview
2. Skim CLAUDE.md "Project Overview" section
3. Read SERVER_QUICK_REFERENCE.md completely
4. Then dive into DJANGO_ARCHITECTURE.md

**I need to add a feature:**
1. Check SERVER_QUICK_REFERENCE.md "Key Design Patterns"
2. Find similar feature in DJANGO_ARCHITECTURE.md
3. Look at actual code files
4. Reference CLAUDE.md for specific patterns in your app

**I need to fix a bug:**
1. Check SERVER_QUICK_REFERENCE.md for architecture
2. Find relevant app section in DJANGO_ARCHITECTURE.md
3. Check actual code in `/server/{app}/`
4. Use CLAUDE.md "Critical Implementation Details" if needed

**I need to deploy:**
1. Read CLAUDE.md "Production Infrastructure" section
2. Check deployment scripts: `/server/scripts/`
3. Review docker-compose.production.yml
4. Reference CLAUDE.md "Troubleshooting Quick Reference"

**I need to understand data flow:**
1. Check DJANGO_ARCHITECTURE.md "Database Model Relationships"
2. Review specific app sections in DJANGO_ARCHITECTURE.md
3. Check "Integration Points" section
4. Look at actual models and serializers in code

---

## File Tree Reference

```
biologidex/
├── ARCHITECTURE_INDEX.md          # This file
├── DJANGO_ARCHITECTURE.md         # Comprehensive analysis
├── SERVER_QUICK_REFERENCE.md      # Quick lookup guide
├── CLAUDE.md                      # Project memory
├── taxonomic_data.md              # Data import planning
├── image-handling-updates.md      # Image system docs
├── client-host.md                 # Frontend deployment
├── README.md                      # Project intro
│
├── server/                        # Django backend
│   ├── accounts/                  # User management
│   ├── animals/                   # Species database
│   ├── dex/                       # User captures
│   ├── social/                    # Friendships
│   ├── vision/                    # CV pipeline
│   ├── images/                    # Image processing
│   ├── graph/                     # Evolutionary trees
│   ├── biologidex/                # Project config
│   │   └── settings/
│   │       ├── base.py            # All environments
│   │       ├── development.py
│   │       ├── production_local.py
│   │       └── production.py
│   └── scripts/                   # Deployment
│
├── client/                        # Godot frontend
│   └── biologidex-client/
│       ├── camera.tscn
│       ├── dex.tscn
│       ├── home.tscn
│       ├── login.tscn
│       └── ...
│
└── resources/
    └── catalogue_of_life/         # 3.2GB dataset
        ├── NameUsage.tsv          # 9.4M species records
        ├── VernacularName.tsv     # Common names
        ├── Distribution.tsv       # Geographic data
        └── catalogue_of_life.md   # Documentation
```

---

## Getting Help

**To find information about...**

| Topic | Document | Section |
|-------|----------|---------|
| User authentication | DJANGO_ARCHITECTURE.md | ACCOUNTS APP |
| Animal taxonomy | DJANGO_ARCHITECTURE.md | ANIMALS APP |
| Image uploads | image-handling-updates.md | Complete |
| CV identification | DJANGO_ARCHITECTURE.md | VISION APP |
| Friendships | DJANGO_ARCHITECTURE.md | SOCIAL APP |
| Deployment | CLAUDE.md | Production Infrastructure |
| Development | CLAUDE.md | Development Workflow |
| Troubleshooting | CLAUDE.md | Troubleshooting Quick Reference |
| Architecture patterns | SERVER_QUICK_REFERENCE.md | Key Design Patterns |

---

## Version Information

- **Last Updated**: 2025-11-06
- **Django Version**: 4.2+
- **Python Version**: 3.12+
- **Database**: PostgreSQL 15
- **Frontend**: Godot 4.5

---

## Related Resources

**Project Code:**
- Frontend: `/home/bryan/Development/Github/biologidex/client/`
- Backend: `/home/bryan/Development/Github/biologidex/server/`

**Data Sources:**
- Catalogue of Life: `/home/bryan/Development/Github/biologidex/resources/catalogue_of_life/`

**External References:**
- Catalogue of Life: https://www.catalogueoflife.org
- Django REST Framework: https://www.django-rest-framework.org
- Godot Engine: https://godotengine.org

