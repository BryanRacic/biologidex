# BiologiDex Server

A production-ready Django REST API for the BiologiDex application - a Pokedex-style social network for sharing real-world zoological observations.

## Architecture Overview

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

### Component Architecture

| Component | Purpose | Technology | Configuration |
|-----------|---------|------------|---------------|
| **Web Server** | Reverse proxy, static files | Nginx | nginx/nginx.conf |
| **Application Server** | Django application | Gunicorn + Django 4.2 | gunicorn.conf.py |
| **Database** | Primary data storage | PostgreSQL 15 | init.sql, pgBouncer for pooling |
| **Cache** | Session storage, task queue | Redis 7 | redis.conf |
| **Task Queue** | Async processing | Celery | celery_worker, celery_beat |
| **Storage** | Media files | Local filesystem / GCS | /var/lib/biologidex/media |
| **Monitoring** | Metrics and health checks | Prometheus + Grafana | monitoring.py |

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

## Documentation

- **[Operations Guide](operations.md)** - Complete guide for operating, monitoring, and troubleshooting
- **[Migration Audit](migration-audit.md)** - Detailed migration planning and architecture decisions
- **[API Documentation](#api-documentation)** - Interactive API docs and endpoint reference

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

5. **Run migrations:**
```bash
docker-compose -f docker-compose.production.yml exec web python manage.py migrate
```

6. **Create superuser:**
```bash
docker-compose -f docker-compose.production.yml exec web python manage.py createsuperuser
```

7. **Verify deployment:**
```bash
curl http://localhost/api/v1/health/
```

## Deployment

### Production Deployment

Deploy updates using the deployment script:
```bash
./scripts/deploy.sh
```

Options:
- `--skip-backup`: Skip database backup
- `--skip-migrate`: Skip database migrations
- `--skip-static`: Skip static files collection
- `--rollback`: Rollback to previous version
- `--maintenance`: Enable maintenance mode during deployment

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
```

## Development

### Local Development Setup

For local development without Docker:

```bash
# Install dependencies
poetry install

# Start services
docker-compose up -d  # Just PostgreSQL and Redis

# Run migrations
python manage.py migrate

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

## API Documentation

### Available Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/auth/login/` | POST | User login |
| `/api/v1/auth/refresh/` | POST | Refresh JWT token |
| `/api/v1/users/` | POST | Register new user |
| `/api/v1/users/me/` | GET | Current user profile |
| `/api/v1/animals/` | GET | List all animals |
| `/api/v1/dex/entries/` | GET/POST | User's dex entries |
| `/api/v1/vision/jobs/` | POST | Submit image for analysis |
| `/api/v1/social/friendships/` | GET/POST | Manage friendships |
| `/api/v1/graph/evolutionary-tree/` | GET | Get evolutionary tree data |

### Interactive API Documentation

- Swagger UI: `http://localhost/api/docs/`
- ReDoc: `http://localhost/api/redoc/`

## Configuration

### Environment Variables

Key environment variables (see `.env.example` for full list):

| Variable | Description | Example |
|----------|-------------|---------|
| `SECRET_KEY` | Django secret key | Random 50-char string |
| `DB_PASSWORD` | PostgreSQL password | Strong password |
| `REDIS_PASSWORD` | Redis password | Strong password |
| `OPENAI_API_KEY` | OpenAI API key | sk-... |
| `ALLOWED_HOSTS` | Allowed hostnames | localhost,api.example.com |
| `CORS_ALLOWED_ORIGINS` | CORS origins | https://app.example.com |

### Django Settings

Settings are split into modules:
- `base.py`: Common settings
- `development.py`: Development settings
- `production_local.py`: Local production settings
- `production.py`: Cloud production settings

## Monitoring

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

- HTTP request count and duration
- API endpoint performance
- Database query metrics
- Cache hit/miss rates
- Celery task metrics
- CV processing metrics
- Active user count

### Logging

Logs are written to `/var/log/biologidex/` with rotation:
- `app.log`: Application logs
- `error.log`: Error logs
- `celery.log`: Celery worker logs
- `gunicorn-access.log`: HTTP access logs
- `gunicorn-error.log`: Gunicorn error logs

## Security

### Security Features

- **Authentication**: JWT with access/refresh tokens
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

## Backup and Recovery

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

## Troubleshooting

For detailed troubleshooting procedures, monitoring guides, and operational documentation, see the **[Operations Guide](operations.md)**.

### Common Issues

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

## Performance Optimization

### Database Optimization
- Indexes on frequently queried fields
- Connection pooling via pgBouncer
- Query optimization with select_related/prefetch_related
- Database vacuuming schedule

### Caching Strategy
- Redis for session storage
- Cache frequently accessed data
- API response caching with proper invalidation
- Static file caching with Nginx

### Application Optimization
- Gunicorn worker tuning
- Async task processing with Celery
- Image optimization before storage
- Pagination for large datasets

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

## Support

### Resources
- [Django Documentation](https://docs.djangoproject.com/)
- [Django REST Framework](https://www.django-rest-framework.org/)
- [Docker Documentation](https://docs.docker.com/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

### Getting Help
- GitHub Issues: [Report bugs and feature requests]
- Email: support@biologidex.example.com
- Slack: #biologidex-support

---

**Last Updated**: October 2024
**Version**: 1.0.0
**Status**: Production Ready