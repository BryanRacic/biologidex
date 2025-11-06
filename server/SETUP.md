# BiologiDex Server Setup Guide

This guide covers setup instructions for both development and production environments.

## Table of Contents

1. [Development Setup](#development-setup)
2. [Production Setup](#production-setup)
3. [Operations Guide](#operations-guide)
4. [API Documentation](#api-documentation)
5. [Troubleshooting](#troubleshooting)

---

## Development Setup

### Prerequisites

- Python 3.12+ (managed with pyenv)
- Poetry (Python dependency management)
- Docker & Docker Compose (for PostgreSQL and Redis)
- Google Cloud account (optional, for media storage)
- OpenAI API key

### Quick Start for Development

#### 1. Install Python with pyenv

```bash
# Install pyenv if not already installed
curl https://pyenv.run | bash

# Install Python 3.12.10
pyenv install 3.12.10
pyenv local 3.12.10
```

#### 2. Install Poetry

```bash
# Ubuntu/Debian
sudo apt install python3-poetry

# Or via official installer
curl -sSL https://install.python-poetry.org | python3 -
```

#### 3. Install Dependencies

```bash
# From the server/ directory
poetry install
```

#### 4. Set Up Environment Variables

```bash
# Copy the example environment file
cp .env.example .env

# Edit .env with your actual credentials
nano .env
```

Required environment variables:
- `SECRET_KEY`: Django secret key
- `DB_PASSWORD`: PostgreSQL password
- `OPENAI_API_KEY`: Your OpenAI API key

#### 5. Start Development Services

```bash
# Start PostgreSQL and Redis containers
docker-compose up -d

# Verify they're running
docker-compose ps
```

#### 6. Initialize Database

```bash
# Activate poetry shell
poetry shell

# Run migrations
python manage.py migrate

# Create a superuser for admin access
python manage.py createsuperuser
```

#### 7. Start Development Server

```bash
# Terminal 1: Django development server
python manage.py runserver

# Terminal 2: Celery worker for async tasks
poetry shell
celery -A biologidex worker -l info

# Terminal 3 (optional): Celery beat for scheduled tasks
poetry shell
celery -A biologidex beat -l info
```

### Development Access Points

- **API**: http://localhost:8000/api/v1/
- **Admin Panel**: http://localhost:8000/admin/
- **API Documentation (Swagger)**: http://localhost:8000/api/docs/
- **API Documentation (ReDoc)**: http://localhost:8000/api/redoc/
- **Django Debug Toolbar**: Appears as sidebar in development mode

---

## Production Setup

### Prerequisites

- Ubuntu 22.04 LTS or newer
- Docker and Docker Compose
- Root or sudo access
- Domain name (optional, for Cloudflare tunnel)
- Minimum 4GB RAM, 20GB disk space

### Option 1: Automated Setup (Recommended)

#### 1. Clone Repository

```bash
git clone https://github.com/yourusername/biologidex.git
cd biologidex/server
```

#### 2. Run Automated Setup Script

```bash
# This script installs all dependencies and configures the system
sudo bash scripts/setup.sh
```

The setup script will:
- Install Docker and Docker Compose
- Install Python and Poetry
- Configure firewall (UFW)
- Set up fail2ban
- Create necessary directories
- Install monitoring tools
- Configure log rotation
- Set up systemd service

#### 3. Configure Production Environment

```bash
# Copy and edit production environment file
cp .env.example .env
nano .env
```

Required variables:
```env
# Security
SECRET_KEY=your-very-secret-key-here
DEBUG=False
ALLOWED_HOSTS=localhost,your-domain.com

# Database
DB_PASSWORD=strong-database-password
DB_USER=biologidex
DB_NAME=biologidex
DB_HOST=db
DB_PORT=5432

# Redis
REDIS_PASSWORD=strong-redis-password
REDIS_HOST=redis
REDIS_PORT=6379

# OpenAI
OPENAI_API_KEY=sk-your-openai-api-key

# Optional: Google Cloud Storage
GCS_BUCKET_NAME=your-bucket
GCS_PROJECT_ID=your-project
GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json
```

#### 4. Start Production Services

```bash
# Start all services with Docker Compose
docker-compose -f docker-compose.production.yml up -d

# Check service status
docker-compose -f docker-compose.production.yml ps

# View logs
docker-compose -f docker-compose.production.yml logs -f
```

#### 5. Initialize Production Database

```bash
# Run migrations
docker-compose -f docker-compose.production.yml exec web python manage.py migrate

# Create superuser
docker-compose -f docker-compose.production.yml exec web python manage.py createsuperuser

# Collect static files
docker-compose -f docker-compose.production.yml exec web python manage.py collectstatic --noinput
```

### Option 2: Manual Production Setup

If you prefer manual setup or need custom configuration:

```bash
# 1. Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# 2. Install Docker Compose
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# 3. Create directories
mkdir -p /opt/biologidex
mkdir -p /var/log/biologidex
mkdir -p /var/lib/biologidex/{media,static,backups}

# 4. Clone repository
cd /opt
git clone https://github.com/yourusername/biologidex.git

# 5. Configure environment
cd biologidex/server
cp .env.example .env
nano .env

# 6. Start services
docker-compose -f docker-compose.production.yml up -d
```

### Production Services

The production stack includes:

| Service | Purpose | Port | Health Check |
|---------|---------|------|--------------|
| **Nginx** | Reverse proxy, static files | 80, 443 | `/` |
| **Django/Gunicorn** | Application server | 8000 | `/api/v1/health/` |
| **PostgreSQL** | Primary database | 5432 | `pg_isready` |
| **pgBouncer** | Connection pooling | 6432 | `SHOW POOLS` |
| **Redis** | Cache & Celery broker | 6379 | `ping` |
| **Celery Worker** | Async task processing | - | `celery inspect ping` |
| **Celery Beat** | Scheduled tasks | - | - |

### Production Access Points

- **API**: http://your-domain.com/api/v1/
- **Admin Panel**: http://your-domain.com/admin/
- **Health Check**: http://your-domain.com/api/v1/health/
- **Metrics**: http://your-domain.com/metrics/
- **API Documentation**: http://your-domain.com/api/docs/

### Deployment & Updates

Deploy updates with zero downtime:

```bash
# Pull latest code and deploy
./scripts/deploy.sh

# Options:
./scripts/deploy.sh --skip-backup    # Skip database backup
./scripts/deploy.sh --skip-migrate   # Skip migrations
./scripts/deploy.sh --rollback       # Rollback to previous version
./scripts/deploy.sh --maintenance    # Enable maintenance mode
```

### Monitoring

#### Real-time Monitoring Dashboard

```bash
# Launch monitoring dashboard
./scripts/monitor.sh
```

Shows:
- System health status
- Container status
- Resource usage
- Recent errors
- Key metrics

#### System Diagnostics

```bash
# Run diagnostics
./scripts/diagnose.sh

# Full diagnostics with details
./scripts/diagnose.sh --full
```

#### Health Endpoints

- **Comprehensive Health**: `/api/v1/health/`
  ```bash
  curl http://localhost/api/v1/health/ | jq .
  ```

- **Liveness Check**: `/health/`
  ```bash
  curl http://localhost/health/
  ```

- **Readiness Check**: `/ready/`
  ```bash
  curl http://localhost/ready/
  ```

### Backup & Recovery

#### Automated Backups

Backups run daily at 2 AM via cron:

```bash
# Manual backup
./scripts/backup.sh

# Restore from backup
docker-compose -f docker-compose.production.yml exec -T db psql -U biologidex biologidex < backup.sql
```

### Cloudflare Tunnel Setup (Optional)

Expose your local server to the internet securely:

```bash
# Install cloudflared
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb

# Authenticate
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create biologidex

# Configure tunnel (edit /etc/cloudflared/config.yml)
tunnel: biologidex
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: api.biologidex.example.com
    service: http://localhost:80
  - service: http_status:404

# Start tunnel
cloudflared tunnel run biologidex
```

---

## Operations Guide

For detailed operational procedures, see **[OPERATIONS.md](OPERATIONS.md)**, which covers:

- Nginx operations and troubleshooting
- Gunicorn worker management
- Prometheus metrics and Grafana setup
- Database operations and optimization
- Redis cache management
- Celery task monitoring
- Log analysis and aggregation
- Performance tuning
- Security hardening
- Emergency procedures

---

## API Documentation

### Interactive Documentation

- **Swagger UI**: `/api/docs/` - Interactive API explorer
- **ReDoc**: `/api/redoc/` - Alternative documentation format
- **OpenAPI Schema**: `/api/schema/` - Machine-readable API specification

### Key API Endpoints

#### Authentication
- `POST /api/v1/auth/login/` - User login
- `POST /api/v1/auth/refresh/` - Refresh JWT token

#### Users
- `POST /api/v1/users/` - Register new user
- `GET /api/v1/users/me/` - Current user profile
- `GET /api/v1/users/friend-code/` - Get friend code

#### Animals
- `GET /api/v1/animals/` - List all animals
- `POST /api/v1/animals/lookup_or_create/` - Find or create animal

#### Dex Entries
- `GET /api/v1/dex/entries/` - List dex entries
- `POST /api/v1/dex/entries/` - Create new entry
- `GET /api/v1/dex/entries/my_entries/` - User's entries

#### Social
- `GET /api/v1/social/friendships/friends/` - Friends list
- `POST /api/v1/social/friendships/send_request/` - Send friend request

#### Vision
- `POST /api/v1/vision/jobs/` - Submit image for analysis
- `GET /api/v1/vision/jobs/{id}/` - Check job status

#### Monitoring
- `GET /api/v1/health/` - Comprehensive health check
- `GET /metrics/` - Prometheus metrics

---

## Troubleshooting

### Common Development Issues

#### ModuleNotFoundError

```bash
# Ensure you're in poetry shell
poetry shell
```

#### Database Connection Errors

```bash
# Check Docker containers
docker-compose ps
docker-compose up -d

# Test database connection
docker-compose exec db psql -U biologidex
```

#### OpenAI API Errors

```bash
# Verify API key
echo $OPENAI_API_KEY

# Test API key
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"
```

### Common Production Issues

#### Container Won't Start

```bash
# Check logs
docker-compose -f docker-compose.production.yml logs web

# Verify environment variables
docker-compose -f docker-compose.production.yml config
```

#### High Memory Usage

```bash
# Check memory usage
docker stats

# Restart services
docker-compose -f docker-compose.production.yml restart

# Clear Redis cache
docker-compose -f docker-compose.production.yml exec redis redis-cli FLUSHALL
```

#### 502 Bad Gateway

```bash
# Check if Django is running
docker-compose -f docker-compose.production.yml ps web

# Check Gunicorn logs
tail -f /var/log/biologidex/gunicorn-error.log

# Restart application
docker-compose -f docker-compose.production.yml restart web
```

#### Database Issues

```bash
# Check connections
docker-compose -f docker-compose.production.yml exec db psql -U biologidex -c "SELECT count(*) FROM pg_stat_activity;"

# Check pgBouncer
docker-compose -f docker-compose.production.yml exec pgbouncer psql -h localhost -p 6432 -U biologidex pgbouncer -c "SHOW POOLS;"
```

### Emergency Procedures

#### Complete System Restart

```bash
docker-compose -f docker-compose.production.yml down
docker-compose -f docker-compose.production.yml up -d
```

#### Rollback Deployment

```bash
./scripts/deploy.sh --rollback
```

#### Emergency Backup

```bash
docker-compose -f docker-compose.production.yml exec db pg_dump -U biologidex biologidex | gzip > emergency_backup_$(date +%Y%m%d_%H%M%S).sql.gz
```

---

## Project Structure

```
server/
├── biologidex/              # Main Django configuration
│   ├── settings/           # Environment-specific settings
│   │   ├── base.py        # Common settings
│   │   ├── development.py # Development settings
│   │   ├── production_local.py # Local production
│   │   └── production.py  # Cloud production
│   ├── health.py          # Health check endpoints
│   ├── monitoring.py      # Prometheus metrics
│   └── urls.py            # URL configuration
├── accounts/              # User authentication
├── animals/               # Animal species database
├── dex/                   # User collections
├── social/                # Social features
├── vision/                # CV/AI pipeline
├── graph/                 # taxonomic tree
├── scripts/               # Operational scripts
│   ├── setup.sh          # Server setup
│   ├── deploy.sh         # Deployment
│   ├── backup.sh         # Backup
│   ├── monitor.sh        # Monitoring
│   └── diagnose.sh       # Diagnostics
├── nginx/                 # Nginx configuration
├── logs/                  # Application logs
├── media/                 # Uploaded files
├── static/                # Static files
├── docker-compose.yml     # Development stack
├── docker-compose.production.yml # Production stack
├── Dockerfile.production  # Production image
├── gunicorn.conf.py      # Gunicorn config
├── redis.conf            # Redis config
├── init.sql              # PostgreSQL init
├── .env.example          # Development env template
├── .env.example # Production env template
└── pyproject.toml        # Python dependencies
```

---

## Support & Resources

- **Operations Guide**: [OPERATIONS.md](OPERATIONS.md) - Detailed operational procedures
- **Migration Audit**: [migration-audit.md](migration-audit.md) - Architecture decisions
- **README**: [README.md](README.md) - High-level project overview
- **API Docs**: `/api/docs/` - Interactive API documentation
- **GitHub Issues**: Report bugs and request features

---

**Last Updated**: October 2025
**Version**: 2.0.0 (Production Ready)