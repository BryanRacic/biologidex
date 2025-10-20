# BiologiDex Server Setup Guide

This guide will help you set up the BiologiDex Django API server for development.

## Prerequisites

- Python 3.12+ (managed with pyenv)
- Poetry (Python dependency management)
- Docker & Docker Compose (for PostgreSQL and Redis)
- Google Cloud account (for media storage)
- OpenAI API key

## Quick Start

### 1. Install Python with pyenv

```bash
# Install pyenv if not already installed
curl https://pyenv.run | bash

# Install Python 3.12.10
pyenv install 3.12.10
pyenv local 3.12.10
```

### 2. Install Poetry

```bash
curl -sSL https://install.python-poetry.org | python3 -
```

### 3. Install Dependencies

```bash
# From the server/ directory
poetry install
```

This installs:
- **Core dependencies**: Django, DRF, PostgreSQL drivers, Celery, Redis, OpenAI SDK
- **Development tools**: `django-debug-toolbar`, `pytest`, `black`, `flake8`, `ipython`

### 4. Set Up Environment Variables

```bash
# Copy the example environment file
cp .env.example .env

# Edit .env with your actual credentials
nano .env
```

Required environment variables:
- `SECRET_KEY`: Django secret key (generate with `python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"`)
- `DB_PASSWORD`: PostgreSQL password
- `OPENAI_API_KEY`: Your OpenAI API key
- `GCS_BUCKET_NAME`, `GCS_PROJECT_ID`, `GOOGLE_APPLICATION_CREDENTIALS`: Google Cloud Storage credentials

### 5. Start Database and Redis

```bash
# Start PostgreSQL and Redis containers
docker-compose up -d

# Verify they're running
docker-compose ps
```

### 6. Run Migrations

```bash
# Activate poetry shell
poetry shell

# Run migrations to create database tables
python manage.py migrate

# Create a superuser for admin access
python manage.py createsuperuser
```

### 7. Start Development Server

```bash
# Start Django development server
python manage.py runserver

# In another terminal, start Celery worker for async tasks
poetry shell
celery -A biologidex worker -l info
```

## Accessing the Application

- **API**: http://localhost:8000/api/v1/
- **Admin Panel**: http://localhost:8000/admin/
- **Django Debug Toolbar**: Appears as a sidebar in development mode (enabled by default)
- **API Documentation (Swagger)**: http://localhost:8000/api/docs/
- **API Documentation (ReDoc)**: http://localhost:8000/api/redoc/
- **API Schema**: http://localhost:8000/api/schema/

### Development Tools

**Django Debug Toolbar**:
- Automatically enabled in development mode
- Provides detailed debugging information including SQL queries, request/response data, cache hits, and performance profiling
- Appears as a collapsible sidebar on the right side of any page
- Only visible when accessing from localhost/127.0.0.1

## API Endpoints Overview

### Authentication
- `POST /api/v1/auth/login/` - Login with username/password
- `POST /api/v1/auth/refresh/` - Refresh JWT token
- `POST /api/v1/users/` - Register new user

### Users
- `GET /api/v1/users/me/` - Get current user profile
- `PATCH /api/v1/users/me/` - Update profile
- `GET /api/v1/users/friend-code/` - Get your friend code
- `POST /api/v1/users/lookup_friend_code/` - Look up user by friend code

### Animals
- `GET /api/v1/animals/` - List all animals
- `GET /api/v1/animals/{id}/` - Get animal details
- `POST /api/v1/animals/lookup_or_create/` - Find or create animal record

### Dex Entries
- `GET /api/v1/dex/entries/` - List dex entries
- `POST /api/v1/dex/entries/` - Create new dex entry
- `GET /api/v1/dex/entries/my_entries/` - Get your entries
- `GET /api/v1/dex/entries/favorites/` - Get favorite entries

### Social/Friends
- `GET /api/v1/social/friendships/friends/` - Get friends list
- `GET /api/v1/social/friendships/pending/` - Get pending friend requests
- `POST /api/v1/social/friendships/send_request/` - Send friend request
- `POST /api/v1/social/friendships/{id}/respond/` - Accept/reject friend request

### Vision/Analysis
- `POST /api/v1/vision/jobs/` - Submit image for analysis
- `GET /api/v1/vision/jobs/{id}/` - Check analysis job status
- `GET /api/v1/vision/jobs/completed/` - Get completed jobs

### Graph
- `GET /api/v1/graph/evolutionary-tree/` - Get evolutionary tree data

## Project Structure

```
server/
├── biologidex/              # Main project configuration
│   ├── settings/           # Split settings (base, dev, prod)
│   ├── celery.py          # Celery configuration
│   └── urls.py            # Root URL configuration
├── accounts/              # User authentication & profiles
├── animals/               # Animal species database
├── dex/                   # User's animal collections
├── social/                # Friendships & social features
├── vision/                # CV/AI identification pipeline
├── graph/                 # Evolutionary tree generation
├── logs/                  # Application logs
├── media/                 # Uploaded media files
├── staticfiles/           # Static files (CSS, JS)
├── docker-compose.yml     # Docker services configuration
├── pyproject.toml         # Poetry dependencies
└── manage.py              # Django management script
```

## Development Workflow

### Running Tests

```bash
pytest
```

### Code Formatting

```bash
# Format code with Black
black .

# Check code style with Flake8
flake8 .
```

### Database Management

```bash
# Create new migration
python manage.py makemigrations

# Apply migrations
python manage.py migrate

# Reset database (WARNING: destroys all data)
python manage.py flush
```

### Celery Tasks

```bash
# Start Celery worker
celery -A biologidex worker -l info

# Start Celery beat (for periodic tasks)
celery -A biologidex beat -l info

# Run both worker and beat together
celery -A biologidex worker -B -l info
```

## Common Issues

### ModuleNotFoundError: No module named 'django'

Make sure you're in the poetry shell:
```bash
poetry shell
```

### Database connection errors

Ensure Docker containers are running:
```bash
docker-compose ps
docker-compose up -d
```

### OpenAI API errors

Verify your API key is set in `.env`:
```bash
echo $OPENAI_API_KEY
```

### Google Cloud Storage errors

1. Create a GCS bucket in Google Cloud Console
2. Create a service account with Storage Admin role
3. Download service account key JSON
4. Set `GOOGLE_APPLICATION_CREDENTIALS` in `.env` to point to the JSON file

## Production Deployment

### Settings

Change `DJANGO_SETTINGS_MODULE` to use production settings:
```bash
export DJANGO_SETTINGS_MODULE=biologidex.settings.production
```

### Required Changes

1. Set `DEBUG=False` in production
2. Configure proper `ALLOWED_HOSTS`
3. Use managed PostgreSQL (e.g., Cloud SQL)
4. Use managed Redis (e.g., Cloud Memorystore)
5. Set up proper secrets management
6. Configure HTTPS/SSL
7. Set up proper logging and monitoring
8. Use Gunicorn or uWSGI as WSGI server
9. Set up Nginx for static files and reverse proxy
10. Configure Cloud Storage for media files

### Example Production Start

```bash
# Collect static files
python manage.py collectstatic --no-input

# Run with Gunicorn
gunicorn biologidex.wsgi:application --bind 0.0.0.0:8000 --workers 4
```

## Support

For issues or questions, please refer to the main project README or open an issue on GitHub.
