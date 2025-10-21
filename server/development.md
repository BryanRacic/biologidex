# BiologiDex Development Guide

## Local Development - Getting Started

This guide will help you set up BiologiDex on a fresh machine for local development.

### Prerequisites
- Python 3.12+ with pyenv
- Poetry for dependency management
- Docker & Docker Compose
- OpenAI API key (for CV identification)
- Google Cloud account (for media storage)

### Step-by-Step Setup

#### 1. Install Dependencies
```bash
poetry install
poetry shell
```

**Note**: This installs all dependencies including development tools like `django-debug-toolbar`, `pytest`, `black`, and `flake8`.

#### 2. Configure Environment Variables
Copy the example environment file and fill in your credentials:
```bash
cp .env.example .env
```

Edit `.env` and provide values for:
- `SECRET_KEY` - Django secret key (generate with `python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"`)
- `DB_PASSWORD` - Choose a secure password for PostgreSQL
- `OPENAI_API_KEY` - Your OpenAI API key
- `GCS_BUCKET_NAME` - Your Google Cloud Storage bucket name
- `GCS_PROJECT_ID` - Your GCP project ID
- `GOOGLE_APPLICATION_CREDENTIALS` - Path to your GCS service account JSON key file

**Note**: The `.env` file is NOT tracked in git. Each machine/developer needs their own local configuration.

#### 3. Set Up Google Cloud Storage
- Create a GCS bucket in Google Cloud Console
- Create a service account with Storage Admin role
- Download the service account key JSON file
- Add the path to this file in your `.env` as `GOOGLE_APPLICATION_CREDENTIALS`

#### 4. Start PostgreSQL and Redis
Start the Docker containers for the database and cache:
```bash
docker-compose up -d
```

This creates:
- PostgreSQL database on port 5432
- Redis cache on port 6379
- Data is stored in Docker volumes (local to this machine)

#### 5. Create Database Tables
Run Django migrations to create the database schema:
```bash
python manage.py makemigrations accounts animals dex social vision
python manage.py migrate
```

**Important**: Always create migrations in the order shown above, as `accounts.User` must exist before other apps.

#### 6. Create a Superuser (Admin Account)
Run this command to create an admin user for accessing the Django admin panel:
```bash
python manage.py createsuperuser
```

**What it does**: Creates a user account with superuser privileges (access to the admin panel and all permissions).

**What it will prompt you for:**
1. **Username** - Choose any username (e.g., "admin", "bryan", etc.)
2. **Email address** - Required by the custom User model
3. **Password** - Enter a password (twice for confirmation)
   - Django will warn if it's too simple, but you can bypass this in development by typing "y"

**After creation:**
- The superuser will have `is_staff=True` and `is_superuser=True` automatically set
- A `friend_code` will be auto-generated (8 random alphanumeric characters)
- A `UserProfile` will be auto-created via Django signals
- You can then log in at `http://localhost:8000/admin/` with your username and password

**Note**: This username/password is stored in your local database only. If you clone the repo to another machine, you'll need to create a new superuser there.

#### 7. Start Development Server
```bash
python manage.py runserver
```

The server will start at `http://localhost:8000/`

#### 8. Start Celery Worker (in another terminal)
Open a second terminal window and run:
```bash
poetry shell
celery -A biologidex worker -l info
```

This enables async processing for CV image identification.

### Verify Your Setup

Once everything is running, you can access:
- **API Documentation (Swagger)**: http://localhost:8000/api/docs/
- **API Documentation (ReDoc)**: http://localhost:8000/api/redoc/
- **Admin Panel**: http://localhost:8000/admin/
- **API Base URL**: http://localhost:8000/api/v1/

### Quick Test
Try registering a user via the API:
```bash
curl -X POST http://localhost:8000/api/v1/users/ \
  -H "Content-Type: application/json" \
  -d '{"username": "testuser", "email": "test@example.com", "password": "testpass123", "password_confirm": "testpass123"}'
```

---

## Useful Endpoints & Tools

### Django Debug Toolbar (Development Only)
**URL**: Appears as a sidebar on any page when running in development mode

**What it does**: A powerful debugging tool that provides detailed information about:
- **SQL Queries**: See all database queries executed, their execution time, and identify N+1 query problems
- **Request/Response**: View headers, session data, and request parameters
- **Templates**: See which templates were rendered and their context
- **Cache**: Monitor cache hits/misses
- **Signals**: Track Django signals being fired
- **Performance Profiling**: Identify slow code paths
- **Settings**: View current Django settings

**How to use**: Simply load any page in your browser while running the development server, and the toolbar will appear on the right side. Click on any panel to see detailed information.

**Note**: The toolbar only appears when `DEBUG=True` (development mode) and requests come from `INTERNAL_IPS` (localhost/127.0.0.1).

### Django Admin Panel
**URL**: http://localhost:8000/admin/

**Login**: Use the superuser credentials you created in Step 6

**What it does**: The Django admin panel provides a web-based interface for managing your database records directly. It's extremely useful for development, testing, and manual data management.

**Available Models**:

- **Users** (`accounts/User`) - View/edit user accounts, friend codes, badges, bios
- **User Profiles** (`accounts/UserProfile`) - View user statistics (total catches, unique species)
- **Animals** (`animals/Animal`) - Browse the canonical animal species database
  - View taxonomic information (kingdom → species)
  - See creation_index (Pokedex-style numbers)
  - Mark animals as verified
  - Edit descriptions, habitats, conservation status
- **Dex Entries** (`dex/DexEntry`) - View user collections
  - See which users have caught which animals
  - View images, locations, notes
  - Manage visibility settings (private/friends/public)
  - Check customizations
- **Friendships** (`social/Friendship`) - Manage social connections
  - View friend relationships
  - See friendship status (pending/accepted/rejected/blocked)
  - Manually create or modify friendships
- **Analysis Jobs** (`vision/AnalysisJob`) - Monitor CV identification pipeline
  - Track image analysis requests
  - View status (pending/processing/completed/failed)
  - See cost, token usage, processing time
  - Inspect raw API responses
  - Retry failed jobs
- **Groups** and **Permissions** - Django's built-in auth system for managing user permissions

**Common Admin Tasks**:
- **Seed test data**: Manually create Animals, Users, and DexEntries for testing
- **Debug CV issues**: Check AnalysisJob records to see why identifications failed
- **Verify animals**: Mark AI-identified animals as verified by an expert
- **Manage users**: View user stats, reset passwords, manage permissions
- **Test social features**: Create friendships between test users

### API Documentation (Swagger UI)
**URL**: http://localhost:8000/api/docs/

**What it does**: Interactive API documentation where you can:
- Browse all available endpoints
- See request/response schemas
- Test API calls directly from the browser
- Authenticate with JWT tokens
- View example requests and responses

**How to use**:
1. Click "Authorize" button at the top
2. Login via `/api/v1/auth/login/` to get a JWT token
3. Paste the access token in the authorization dialog
4. Test any authenticated endpoint interactively

### API Documentation (ReDoc)
**URL**: http://localhost:8000/api/redoc/

**What it does**: Alternative API documentation with a cleaner, read-only interface. Better for:
- Reading documentation
- Copying code examples
- Understanding API structure
- Sharing documentation with others

### Key API Endpoints

**Authentication**:
- `POST /api/v1/auth/login/` - Get JWT tokens
- `POST /api/v1/auth/refresh/` - Refresh access token
- `POST /api/v1/users/` - Register new user (no auth required)

**User Management**:
- `GET /api/v1/users/me/` - Get current user profile
- `GET /api/v1/users/friend-code/` - Get your friend code
- `POST /api/v1/users/lookup_friend_code/` - Find user by friend code

**Animal Identification** (the core workflow):
- `POST /api/v1/vision/jobs/` - Upload image, triggers async CV analysis
- `GET /api/v1/vision/jobs/{id}/` - Check analysis status
- `POST /api/v1/dex/entries/` - Create dex entry after successful identification

**Collections**:
- `GET /api/v1/dex/entries/my_entries/` - Your personal collection
- `GET /api/v1/animals/` - Browse all discovered animals
- `POST /api/v1/dex/entries/{id}/toggle_favorite/` - Mark favorites

**Social**:
- `POST /api/v1/social/friendships/send_request/` - Send friend request by code
- `GET /api/v1/social/friendships/friends/` - List your friends
- `POST /api/v1/social/friendships/{id}/respond/` - Accept/reject requests

**Graph**:
- `GET /api/v1/graph/evolutionary-tree/` - Get collaborative evolutionary tree data

---

## Migrating to a New Machine

When cloning this repository to a new machine, remember:
- **Database is local**: You'll have an empty database and need to run migrations + create a new superuser
- **Environment variables**: Copy `.env.example` to `.env` and fill in your credentials
- **Docker volumes**: New Docker containers will have fresh PostgreSQL/Redis instances
- **Dependencies**: Run `poetry install` to install Python packages

## Quick Start

### Prerequisites
- Python 3.12+ with pyenv
- Poetry for dependency management
- Docker & Docker Compose
- OpenAI API key

### Setup Instructions

1. **Install dependencies:**
   ```bash
   poetry install
   ```

2. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your credentials
   ```

3. **Start services:**
   ```bash
   docker-compose up -d
   ```

4. **Create migrations and database:**
   ```bash
   poetry shell
   python manage.py makemigrations accounts animals dex social vision
   python manage.py migrate
   python manage.py createsuperuser
   ```

5. **Run development server:**
   ```bash
   python manage.py runserver
   ```

6. **Start Celery worker (separate terminal):**
   ```bash
   poetry shell
   celery -A biologidex worker -l info
   ```

### Testing the API

Access the interactive API documentation at:
- **Swagger UI**: http://localhost:8000/api/docs/
- **ReDoc**: http://localhost:8000/api/redoc/
- **Admin Panel**: http://localhost:8000/admin/

Example workflow:
```bash
# 1. Register a user
curl -X POST http://localhost:8000/api/v1/users/ \
  -H "Content-Type: application/json" \
  -d '{"username": "testuser", "email": "test@example.com", "password": "testpass123", "password_confirm": "testpass123"}'

# 2. Login to get JWT token
curl -X POST http://localhost:8000/api/v1/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{"username": "testuser", "password": "testpass123"}'

# 3. Use token for authenticated requests
curl -X GET http://localhost:8000/api/v1/users/me/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

See [SETUP.md](SETUP.md) for detailed documentation.

---


## Test Users

For development and testing, BiologiDex automatically creates three test users on server startup. These users are only created in the **development environment** (when `AUTO_SEED_TEST_USERS = True` in settings).

### Default Test Users

| Username   | Email                  | Password        | Friend Code | Role         | Description                                |
|------------|------------------------|-----------------|-------------|--------------|-------------------------------------------|
| `testuser` | testuser@example.com   | `testpass123`   | TEST0001    | Basic User   | Standard user for testing user features   |
| `admin`    | admin@example.com      | `adminpass123`  | ADMIN001    | Admin        | Superuser with full admin panel access    |
| `verified` | verified@example.com   | `verifiedpass123`| VERIFY01   | Verified User| User with verified badges and privileges  |

### Usage

#### Automatic Seeding (Development Only)

Test users are automatically created when you start the Django development server:

```bash
python manage.py runserver
```

The seeding happens silently on startup if the users don't already exist.

#### Manual Seeding

You can manually seed test users using the management command:

```bash
# Create test users (skips existing users)
python manage.py seed_test_users

# Force recreation of test users (deletes and recreates)
python manage.py seed_test_users --force
```

#### API Login Example

```bash
# Login as basic test user
curl -X POST http://localhost:8000/api/v1/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "password": "testpass123"
  }'

# Login as admin
curl -X POST http://localhost:8000/api/v1/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "adminpass123"
  }'
```

### Configuration

To **disable** automatic test user seeding, edit `server/biologidex/settings/development.py`:

```python
# Set to False to disable auto-seeding
AUTO_SEED_TEST_USERS = False
```

**Note:** This setting is NOT set in production settings, so test users will never be created in production.

## Development Setup

### Prerequisites
- Python 3.12+
- PostgreSQL 15+
- Redis (for Celery)
- Docker & Docker Compose (recommended)

### Quick Start

1. **Clone the repository**
   ```bash
   git clone <repo-url>
   cd biologidex
   ```

2. **Set up Python environment**
   ```bash
   pyenv install 3.12.10
   pyenv local 3.12.10
   poetry install
   poetry shell
   ```

3. **Start services (PostgreSQL & Redis)**
   ```bash
   docker-compose up -d
   ```

4. **Configure environment**
   ```bash
   cp server/.env.example server/.env
   # Edit server/.env with your credentials
   ```

5. **Run migrations**
   ```bash
   cd server
   python manage.py makemigrations accounts animals dex social vision graph
   python manage.py migrate
   ```

6. **Start development server**
   ```bash
   python manage.py runserver
   ```

   Test users are automatically created on first startup.

7. **Access the application**
   - API: http://localhost:8000/api/v1/
   - Admin Panel: http://localhost:8000/admin/ (use `admin` / `adminpass123`)
   - API Docs: http://localhost:8000/api/docs/

### Celery Worker (for async tasks)

```bash
# In a separate terminal
cd server
celery -A biologidex worker -l info
```

## Testing API with Test Users

### Get JWT Token
```bash
TOKEN=$(curl -s -X POST http://localhost:8000/api/v1/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{"username": "testuser", "password": "testpass123"}' | jq -r '.access')
```

### Make Authenticated Request
```bash
curl -X GET http://localhost:8000/api/v1/users/me/ \
  -H "Authorization: Bearer $TOKEN"
```

### Add Friends
```bash
# Login as testuser (get TOKEN1)
# Login as verified (get TOKEN2)
# Use friend codes to add each other
curl -X POST http://localhost:8000/api/v1/social/friendships/send_request/ \
  -H "Authorization: Bearer $TOKEN1" \
  -H "Content-Type: application/json" \
  -d '{"friend_code": "VERIFY01"}'
```

## Common Commands

```bash
# Create a custom superuser
python manage.py createsuperuser

# Run tests
python manage.py test

# Check for issues
python manage.py check

# Create a new app
python manage.py startapp <app_name>

# Shell access
python manage.py shell_plus  # with django-extensions
```

## Troubleshooting

### Test users not being created?
- Check that `AUTO_SEED_TEST_USERS = True` in development settings
- Verify migrations have run: `python manage.py showmigrations`
- Manually run: `python manage.py seed_test_users --force`

### Database connection issues?
- Ensure Docker containers are running: `docker-compose ps`
- Check `.env` file has correct DB credentials
- Verify PostgreSQL is accessible: `psql -h localhost -U postgres`

### Celery tasks not running?
- Check Redis is running: `redis-cli ping`
- Start Celery worker: `celery -A biologidex worker -l info`
- In development, tasks run synchronously if `CELERY_TASK_ALWAYS_EAGER = True`
