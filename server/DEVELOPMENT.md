# BiologiDex Development Guide

Comprehensive guide for developing and testing BiologiDex components in a development environment.

## Table of Contents

1. [Development Environment](#development-environment)
2. [Django Development Server](#django-development-server)
3. [Component Testing](#component-testing)
4. [Database Development](#database-development)
5. [API Development & Testing](#api-development--testing)
6. [Celery Task Development](#celery-task-development)
7. [Frontend Integration Testing](#frontend-integration-testing)
8. [Debugging Techniques](#debugging-techniques)
9. [Testing Strategies](#testing-strategies)
10. [Development Best Practices](#development-best-practices)

---

## Development Environment

### Initial Setup

```bash
# 1. Set Python version
pyenv local 3.12.10

# 2. Install dependencies
poetry install

# 3. Activate virtual environment
poetry shell

# 4. Configure environment
cp .env.example .env
# Edit .env with development settings
```

### Environment Variables for Development

Create a `.env` file with minimal configuration:

```env
# Django
SECRET_KEY=dev-secret-key-for-local-development-only
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1,0.0.0.0

# Database (using Docker)
DB_NAME=biologidex
DB_USER=biologidex
DB_PASSWORD=development
DB_HOST=localhost
DB_PORT=5432

# Redis (using Docker)
REDIS_HOST=localhost
REDIS_PORT=6379

# OpenAI (for CV testing)
OPENAI_API_KEY=sk-your-api-key

# Optional: Disable in development
EMAIL_BACKEND=django.core.mail.backends.console.EmailBackend
CELERY_TASK_ALWAYS_EAGER=False  # Set to True to run Celery tasks synchronously
```

### Docker Services for Development

Start only the services you need:

```bash
# Start all development services
docker-compose up -d

# Or start specific services
docker-compose up -d db        # Just PostgreSQL
docker-compose up -d redis     # Just Redis
docker-compose up -d db redis  # Both

# Check status
docker-compose ps

# View logs
docker-compose logs -f db
docker-compose logs -f redis
```

---

## Django Development Server

### Basic Server Commands

```bash
# Standard development server
python manage.py runserver

# Specific port/interface
python manage.py runserver 0.0.0.0:8000  # Accept connections from any interface
python manage.py runserver 8080          # Different port

# With verbose output
python manage.py runserver --verbosity 2

# Auto-reload disabled (for debugging)
python manage.py runserver --noreload
```

### Django Debug Toolbar

The Debug Toolbar is automatically enabled in development:

```python
# Access from browser at http://127.0.0.1:8000
# Toolbar appears on the right side
# Shows: SQL queries, templates, cache, signals, logging
```

Features:
- **SQL Panel**: View all queries with execution time
- **Templates**: See template hierarchy and context
- **Cache**: Monitor cache hits/misses
- **Profiling**: CPU and memory profiling
- **Signals**: Track Django signals

### Development URLs

```
http://localhost:8000/              # Root (redirects to API)
http://localhost:8000/api/v1/       # API root
http://localhost:8000/admin/        # Django admin
http://localhost:8000/api/docs/     # Swagger UI
http://localhost:8000/api/redoc/    # ReDoc
http://localhost:8000/api/schema/   # OpenAPI schema
http://localhost:8000/__debug__/    # Debug toolbar URLs
```

---

## Component Testing

### Testing Individual Django Apps

#### 1. Accounts App

```bash
# Run only accounts tests
python manage.py test accounts

# Test specific functionality
python manage.py test accounts.tests.test_models
python manage.py test accounts.tests.test_views
python manage.py test accounts.tests.test_api

# Test user registration flow
python manage.py test accounts.tests.test_registration
```

Manual testing:
```python
# Django shell
python manage.py shell

# Test user creation
from accounts.models import User
user = User.objects.create_user(
    username="testuser",
    email="test@example.com",
    password="testpass123"
)
print(user.friend_code)

# Test profile creation
from accounts.models import UserProfile
profile = user.profile
profile.bio = "Test bio"
profile.save()
```

#### 2. Animals App

```bash
# Test animal models and lookups
python manage.py test animals

# Test specific animal lookup
python manage.py test animals.tests.test_lookup_or_create
```

Manual testing:
```python
# Django shell
python manage.py shell

from animals.models import Animal

# Create test animal
animal = Animal.objects.create(
    scientific_name="Canis lupus",
    common_name="Gray Wolf",
    kingdom="Animalia",
    phylum="Chordata",
    animal_class="Mammalia",
    order="Carnivora",
    family="Canidae",
    genus="Canis",
    species="lupus"
)

# Test lookup
from animals.models import Animal
animal = Animal.lookup_or_create("Felis catus")
print(animal.common_name)
```

#### 3. Dex App

```bash
# Test dex entries
python manage.py test dex

# Test visibility permissions
python manage.py test dex.tests.test_permissions
```

Manual testing:
```python
# Create dex entry
from dex.models import DexEntry
from accounts.models import User
from animals.models import Animal

user = User.objects.first()
animal = Animal.objects.first()

entry = DexEntry.objects.create(
    owner=user,
    animal=animal,
    location="Test Location",
    notes="Spotted in the wild",
    visibility="friends"
)
```

#### 4. Vision App (CV Processing)

```bash
# Test vision processing
python manage.py test vision

# Test OpenAI integration (requires API key)
python manage.py test vision.tests.test_openai_service
```

Manual CV testing:
```python
# Test image analysis
from vision.models import AnalysisJob
from accounts.models import User
from django.core.files.uploadedfile import SimpleUploadedFile

user = User.objects.first()

# Create test job
job = AnalysisJob.objects.create(
    user=user,
    status='pending'
)

# Process manually (normally done by Celery)
from vision.tasks import process_analysis_job
process_analysis_job(job.id)

# Check result
job.refresh_from_db()
print(job.status)
print(job.result)
```

#### 5. Social App

```bash
# Test friendship functionality
python manage.py test social

# Test friend requests
python manage.py test social.tests.test_friend_requests
```

Manual testing:
```python
from social.models import Friendship
from accounts.models import User

user1 = User.objects.get(username="user1")
user2 = User.objects.get(username="user2")

# Send friend request
friendship = Friendship.objects.create(
    user1=user1,
    user2=user2,
    status='pending'
)

# Accept request
friendship.accept()

# Check if friends
print(Friendship.are_friends(user1, user2))
```

---

## Database Development

### Database Management Commands

```bash
# Create migrations for changes
python manage.py makemigrations

# View migration SQL
python manage.py sqlmigrate accounts 0001

# Apply migrations
python manage.py migrate

# Rollback migrations
python manage.py migrate accounts 0002  # Go to specific migration

# Reset database (WARNING: loses all data)
python manage.py flush

# Database shell
python manage.py dbshell
```

### Database Debugging

```sql
-- Connect to database directly
docker-compose exec db psql -U biologidex

-- Useful queries for debugging

-- Check table sizes
SELECT schemaname,tablename,pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename))
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Active queries
SELECT pid, now() - query_start as duration, query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY duration DESC;

-- Lock information
SELECT * FROM pg_locks WHERE NOT granted;

-- Index usage
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
ORDER BY idx_scan;
```

### Creating Test Data

```bash
# Load fixtures
python manage.py loaddata test_users.json
python manage.py loaddata test_animals.json

# Create test data script
python manage.py shell < scripts/create_test_data.py
```

Example test data script:
```python
# scripts/create_test_data.py
from accounts.models import User
from animals.models import Animal
from dex.models import DexEntry
from social.models import Friendship

# Create test users
users = []
for i in range(5):
    user = User.objects.create_user(
        username=f"testuser{i}",
        email=f"user{i}@test.com",
        password="testpass123"
    )
    users.append(user)

# Create test animals
animals = [
    Animal.objects.create(scientific_name="Canis lupus", common_name="Gray Wolf"),
    Animal.objects.create(scientific_name="Felis catus", common_name="House Cat"),
    Animal.objects.create(scientific_name="Ursus arctos", common_name="Brown Bear"),
]

# Create dex entries
for user in users[:3]:
    for animal in animals:
        DexEntry.objects.create(
            owner=user,
            animal=animal,
            notes=f"Test entry for {animal.common_name}"
        )

# Create friendships
Friendship.objects.create(user1=users[0], user2=users[1], status='accepted')
Friendship.objects.create(user1=users[0], user2=users[2], status='pending')

print("Test data created successfully!")
```

---

## API Development & Testing

### Testing with Django REST Framework Test Client

```python
# test_api.py
from rest_framework.test import APITestCase
from rest_framework import status
from accounts.models import User

class AnimalAPITest(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username='testuser',
            password='testpass123'
        )

    def test_list_animals(self):
        # Authenticate
        self.client.login(username='testuser', password='testpass123')

        # Make request
        response = self.client.get('/api/v1/animals/')

        # Assert
        self.assertEqual(response.status_code, status.HTTP_200_OK)
```

### Manual API Testing with HTTPie

```bash
# Install HTTPie
pip install httpie

# Test endpoints
# Login
http POST localhost:8000/api/v1/auth/login/ \
    username=testuser \
    password=testpass123

# Use token
export TOKEN="your-jwt-token"

# Get animals
http GET localhost:8000/api/v1/animals/ \
    "Authorization: Bearer $TOKEN"

# Create dex entry
http POST localhost:8000/api/v1/dex/entries/ \
    "Authorization: Bearer $TOKEN" \
    animal_id=1 \
    notes="Spotted in backyard"
```

### Testing with cURL

```bash
# Login and get token
TOKEN=$(curl -s -X POST http://localhost:8000/api/v1/auth/login/ \
    -H "Content-Type: application/json" \
    -d '{"username":"testuser","password":"testpass123"}' \
    | jq -r .access)

# Test authenticated endpoint
curl -H "Authorization: Bearer $TOKEN" \
    http://localhost:8000/api/v1/dex/entries/my_entries/
```

### Testing with Swagger UI

1. Navigate to http://localhost:8000/api/docs/
2. Click "Authorize" button
3. Enter credentials or JWT token
4. Try out endpoints interactively
5. View request/response examples

### Custom Management Commands for Testing

Create custom commands for testing:

```python
# management/commands/test_cv.py
from django.core.management.base import BaseCommand
from vision.services import OpenAIVisionService

class Command(BaseCommand):
    help = 'Test CV processing with a sample image'

    def add_arguments(self, parser):
        parser.add_argument('image_path', type=str)

    def handle(self, *args, **options):
        service = OpenAIVisionService()
        with open(options['image_path'], 'rb') as f:
            result = service.identify_animal(f.read())
        self.stdout.write(f"Result: {result}")
```

Usage:
```bash
python manage.py test_cv /path/to/image.jpg
```

---

## Celery Task Development

### Running Celery for Development

```bash
# Run worker with verbose logging
celery -A biologidex worker -l DEBUG

# Run with specific queues
celery -A biologidex worker -Q default,cv_processing -l INFO

# Run beat scheduler
celery -A biologidex beat -l INFO

# Run flower (web UI for monitoring)
pip install flower
celery -A biologidex flower
# Access at http://localhost:5555
```

### Testing Celery Tasks Synchronously

```python
# In settings/development.py
CELERY_TASK_ALWAYS_EAGER = True  # Tasks run synchronously
CELERY_TASK_EAGER_PROPAGATES = True  # Propagate exceptions

# Test in shell
from vision.tasks import process_analysis_job

# Will run immediately instead of queuing
result = process_analysis_job.delay(job_id=1)
print(result.get())  # Get result immediately
```

### Debugging Celery Tasks

```python
# Add debugging to tasks
from celery import shared_task
import logging

logger = logging.getLogger(__name__)

@shared_task(bind=True)
def debug_task(self, param):
    logger.info(f"Task ID: {self.request.id}")
    logger.info(f"Params: {param}")

    # Add breakpoint (requires celery to run with --pool=solo)
    import pdb; pdb.set_trace()

    # Or use ipdb
    import ipdb; ipdb.set_trace()

    return "result"
```

Run Celery for debugging:
```bash
# Run with single thread for debugging
celery -A biologidex worker --pool=solo -l DEBUG

# Or use gevent for better debugging
pip install gevent
celery -A biologidex worker --pool=gevent -l DEBUG
```

---

## Frontend Integration Testing

### Testing API with Mock Frontend

Create a simple HTML file for testing:

```html
<!-- test_frontend.html -->
<!DOCTYPE html>
<html>
<head>
    <title>BiologiDex API Test</title>
</head>
<body>
    <h1>API Test Interface</h1>

    <div>
        <h2>Login</h2>
        <input type="text" id="username" placeholder="Username">
        <input type="password" id="password" placeholder="Password">
        <button onclick="login()">Login</button>
    </div>

    <div>
        <h2>Test Endpoints</h2>
        <button onclick="getAnimals()">Get Animals</button>
        <button onclick="getMyDex()">Get My Dex</button>
        <div id="result"></div>
    </div>

    <script>
        let token = null;
        const API_BASE = 'http://localhost:8000/api/v1';

        async function login() {
            const response = await fetch(`${API_BASE}/auth/login/`, {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({
                    username: document.getElementById('username').value,
                    password: document.getElementById('password').value
                })
            });
            const data = await response.json();
            token = data.access;
            console.log('Logged in!', data);
        }

        async function getAnimals() {
            const response = await fetch(`${API_BASE}/animals/`, {
                headers: {'Authorization': `Bearer ${token}`}
            });
            const data = await response.json();
            document.getElementById('result').innerText = JSON.stringify(data, null, 2);
        }

        async function getMyDex() {
            const response = await fetch(`${API_BASE}/dex/entries/my_entries/`, {
                headers: {'Authorization': `Bearer ${token}`}
            });
            const data = await response.json();
            document.getElementById('result').innerText = JSON.stringify(data, null, 2);
        }
    </script>
</body>
</html>
```

Serve it:
```bash
# Python simple server
python -m http.server 3000

# Access at http://localhost:3000/test_frontend.html
```

### CORS Testing

Test CORS configuration:

```bash
# Test CORS headers
curl -I -X OPTIONS http://localhost:8000/api/v1/animals/ \
    -H "Origin: http://localhost:3000" \
    -H "Access-Control-Request-Method: GET" \
    -H "Access-Control-Request-Headers: Authorization"
```

---

## Debugging Techniques

### Django Shell Plus

```bash
# Install django-extensions
pip install django-extensions ipython

# Add to INSTALLED_APPS
INSTALLED_APPS += ['django_extensions']

# Use shell_plus (auto-imports all models)
python manage.py shell_plus

# With IPython
python manage.py shell_plus --ipython

# Print SQL queries
python manage.py shell_plus --print-sql
```

### Debugging Views

```python
# Add debugging in views
import logging
import pdb

logger = logging.getLogger(__name__)

class AnimalViewSet(viewsets.ModelViewSet):
    def list(self, request):
        # Add logging
        logger.debug(f"User: {request.user}")
        logger.debug(f"Query params: {request.query_params}")

        # Add breakpoint
        pdb.set_trace()

        # Or use IPython debugger
        from IPython import embed
        embed()  # Drops into IPython shell

        return super().list(request)
```

### SQL Query Debugging

```python
# Show SQL queries in shell
from django.db import connection
from django.conf import settings

# Enable query logging
settings.DEBUG = True

# Run queries
from animals.models import Animal
animals = Animal.objects.filter(verified=True)
print(animals.query)  # Show SQL

# Show all queries
for query in connection.queries:
    print(query['sql'])
    print(f"Time: {query['time']}")
```

### Profiling

```python
# Use Django Debug Toolbar profiling panel
# Or use line_profiler

pip install line_profiler

# Decorate function
@profile
def slow_function():
    # code to profile
    pass

# Run with profiler
kernprof -l -v manage.py runserver
```

### Memory Debugging

```python
# Install memory_profiler
pip install memory_profiler

# Decorate function
from memory_profiler import profile

@profile
def memory_intensive_function():
    # code to profile
    pass

# Run
python -m memory_profiler manage.py runserver
```

---

## Testing Strategies

### Unit Testing Structure

```
tests/
├── test_models.py      # Model logic
├── test_views.py       # View logic
├── test_serializers.py # Serialization
├── test_permissions.py # Permissions
├── test_tasks.py       # Celery tasks
└── test_integration.py # End-to-end
```

### Test Coverage

```bash
# Install coverage
pip install coverage

# Run with coverage
coverage run --source='.' manage.py test
coverage report
coverage html  # Generate HTML report

# Open htmlcov/index.html in browser
```

### Continuous Testing

```bash
# Install pytest-watch
pip install pytest-watch

# Auto-run tests on file changes
ptw -- --testmon

# Or use Django's test runner
python manage.py test --parallel --keepdb
```

### Testing Best Practices

```python
# Use factories for test data
pip install factory-boy

# factories.py
import factory
from accounts.models import User

class UserFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = User

    username = factory.Sequence(lambda n: f"user{n}")
    email = factory.LazyAttribute(lambda obj: f"{obj.username}@example.com")
    first_name = factory.Faker("first_name")
    last_name = factory.Faker("last_name")

# In tests
user = UserFactory()
users = UserFactory.create_batch(5)
```

### Performance Testing

```python
# Use Django's test utilities
from django.test import TestCase, TransactionTestCase
from django.test.utils import override_settings
from django.core.cache import cache

class PerformanceTest(TransactionTestCase):
    def test_api_performance(self):
        from django.test import Client
        import time

        client = Client()
        start = time.time()

        for _ in range(100):
            response = client.get('/api/v1/animals/')

        duration = time.time() - start
        self.assertLess(duration, 5.0)  # Should complete in 5 seconds
```

---

## Development Best Practices

### Code Organization

```python
# Keep views thin
class AnimalViewSet(viewsets.ModelViewSet):
    def perform_create(self, serializer):
        # Delegate to service
        AnimalService.create_animal(serializer.validated_data)

# Use services for business logic
# services.py
class AnimalService:
    @staticmethod
    def create_animal(data):
        # Complex business logic here
        pass
```

### Git Workflow

```bash
# Feature branch workflow
git checkout -b feature/animal-search

# Make atomic commits
git add -p  # Stage chunks interactively
git commit -m "Add animal search by scientific name"

# Keep commits clean
git rebase -i main  # Squash/reorder before PR

# Run tests before pushing
python manage.py test && git push origin feature/animal-search
```

### Pre-commit Hooks

```bash
# Install pre-commit
pip install pre-commit

# Create .pre-commit-config.yaml
cat > .pre-commit-config.yaml << EOF
repos:
  - repo: https://github.com/psf/black
    rev: 23.1.0
    hooks:
      - id: black
        language_version: python3.12

  - repo: https://github.com/PyCQA/flake8
    rev: 6.0.0
    hooks:
      - id: flake8
        args: ['--max-line-length=88']

  - repo: https://github.com/pycqa/isort
    rev: 5.12.0
    hooks:
      - id: isort
        args: ['--profile', 'black']
EOF

# Install hooks
pre-commit install

# Run manually
pre-commit run --all-files
```

### Environment Management

```bash
# Use direnv for automatic environment activation
brew install direnv  # or apt install direnv

# Create .envrc
echo "layout poetry" > .envrc
direnv allow

# Auto-activates when entering directory
cd server/  # Environment activated automatically
```

### Documentation

```python
# Write good docstrings
def process_animal_image(image: bytes, user: User) -> Animal:
    """
    Process an uploaded image to identify the animal.

    Args:
        image: Image file contents as bytes
        user: User who uploaded the image

    Returns:
        Animal: The identified animal instance

    Raises:
        ValidationError: If image is invalid
        OpenAIError: If CV processing fails

    Example:
        >>> with open('cat.jpg', 'rb') as f:
        ...     animal = process_animal_image(f.read(), user)
        >>> print(animal.scientific_name)
        'Felis catus'
    """
    pass
```

### Logging

```python
# Use structured logging
import logging
import json

logger = logging.getLogger(__name__)

# Log with context
logger.info("Processing image", extra={
    'user_id': user.id,
    'image_size': len(image),
    'timestamp': datetime.now().isoformat()
})

# Configure for development
LOGGING = {
    'version': 1,
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'verbose'
        },
    },
    'formatters': {
        'verbose': {
            'format': '[{levelname}] {asctime} {module} {message}',
            'style': '{',
        },
    },
    'loggers': {
        'biologidex': {
            'handlers': ['console'],
            'level': 'DEBUG',
        },
    },
}
```

---

## Quick Reference

### Common Commands

```bash
# Development server
python manage.py runserver

# Database
python manage.py makemigrations
python manage.py migrate
python manage.py dbshell

# Testing
python manage.py test
python manage.py test --parallel
python manage.py test --keepdb

# Shell
python manage.py shell
python manage.py shell_plus

# Static files
python manage.py collectstatic

# Cache
python manage.py clear_cache

# Users
python manage.py createsuperuser
python manage.py changepassword username
```

### Useful Shortcuts

```python
# Quick model testing in shell
from django.contrib.auth import get_user_model
User = get_user_model()

# Get or create
animal, created = Animal.objects.get_or_create(
    scientific_name="Canis lupus",
    defaults={'common_name': 'Gray Wolf'}
)

# Bulk operations
Animal.objects.bulk_create([
    Animal(scientific_name="Felis catus"),
    Animal(scientific_name="Canis lupus"),
])

# Raw SQL when needed
from django.db import connection
with connection.cursor() as cursor:
    cursor.execute("SELECT * FROM animals_animal WHERE verified = %s", [True])
    results = cursor.fetchall()
```

### Environment Variables

```bash
# Quick environment check
python -c "from django.conf import settings; print(settings.DEBUG)"
python -c "import os; print(os.environ.get('OPENAI_API_KEY', 'Not set'))"

# Django settings module
export DJANGO_SETTINGS_MODULE=biologidex.settings.development
```

---

## Troubleshooting Development Issues

### Common Problems and Solutions

| Problem | Solution |
|---------|----------|
| Import errors | Check `poetry.lock`, run `poetry install` |
| Migration conflicts | `python manage.py migrate --merge` |
| Database locks | Restart PostgreSQL: `docker-compose restart db` |
| Redis connection refused | Start Redis: `docker-compose up -d redis` |
| Celery not processing | Check worker is running: `celery -A biologidex worker` |
| Static files 404 | Run `python manage.py collectstatic` |
| CORS errors | Check `CORS_ALLOWED_ORIGINS` in settings |
| JWT expired | Get new token from `/api/v1/auth/refresh/` |

---

## Resources

- [Django Documentation](https://docs.djangoproject.com/)
- [Django REST Framework](https://www.django-rest-framework.org/)
- [Celery Documentation](https://docs.celeryq.dev/)
- [pytest-django](https://pytest-django.readthedocs.io/)
- [Django Debug Toolbar](https://django-debug-toolbar.readthedocs.io/)

---

**Last Updated**: October 2025
**Version**: 1.0.0