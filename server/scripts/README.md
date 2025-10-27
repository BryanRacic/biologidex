# BiologiDex Server Scripts

This directory contains operational scripts for managing the BiologiDex server infrastructure.

## Available Scripts

### Setup & Deployment

#### `setup.sh`
**Purpose**: Initial server setup and configuration
**Usage**: `./scripts/setup.sh`
**Description**: Prepares a fresh Ubuntu server with all required dependencies, Docker, and initial configuration for running BiologiDex in production.

**When to use:**
- Setting up a new server from scratch
- Initial installation on a clean Ubuntu system

---

#### `deploy.sh`
**Purpose**: Zero-downtime production deployment
**Usage**: `./scripts/deploy.sh [environment]`
**Description**: Performs production deployment with health checks, rollback capability, and zero downtime.

**Features:**
- Pull latest code from git
- Rebuild Docker images
- Rolling restart with health monitoring
- Automatic rollback on failure

**When to use:**
- Deploying code updates to production
- After making configuration changes

---

### Operations & Maintenance

#### `restart.sh` ⭐ (Most Common)
**Purpose**: Restart all services with comprehensive health checks
**Usage**: `./scripts/restart.sh`
**Description**: The main operational script for restarting BiologiDex services. Handles all third-party service configurations gracefully, checks database connectivity, and provides detailed health status.

**Features:**
- Validates `.env` configuration
- Detects and handles database password mismatches
- Disables unconfigured services (Sentry, OpenAI, GCS, Email)
- Rebuilds Docker images with updated configuration
- Comprehensive health checks for all services
- Detailed service status reporting

**When to use:**
- After updating `.env` configuration
- When services need to be restarted
- After code or configuration changes
- When troubleshooting service issues

**Configuration checked:**
- Database credentials
- Sentry DSN
- OpenAI API key
- Email SMTP settings
- Google Cloud Storage settings

---

#### `reset_database.sh`
**Purpose**: Reset database when password is incorrect
**Usage**: `./scripts/reset_database.sh`
**Description**: Standalone utility for completely resetting the PostgreSQL database. Useful when database password mismatches occur.

**Warning:** This will DELETE all database data!

**When to use:**
- Database password mismatch errors
- Need to start with a fresh database
- After changing `DB_PASSWORD` in `.env`

**Process:**
1. Stops all services
2. Removes database volumes
3. Recreates database with new password from `.env`
4. Verifies connection

---

### Monitoring & Diagnostics

#### `monitor.sh`
**Purpose**: Real-time system monitoring dashboard
**Usage**: `./scripts/monitor.sh`
**Description**: Displays real-time metrics for CPU, memory, disk, network, and Docker container status.

**When to use:**
- Monitoring system performance
- Checking resource usage
- Identifying bottlenecks

---

#### `diagnose.sh`
**Purpose**: Comprehensive system diagnostics
**Usage**: `./scripts/diagnose.sh`
**Description**: Runs a complete diagnostic check of the entire system including Docker, services, logs, and configuration.

**When to use:**
- Troubleshooting issues
- Pre-deployment health check
- After service failures

---

### Backup & Recovery

#### `backup.sh`
**Purpose**: Automated database and media file backups
**Usage**: `./scripts/backup.sh`
**Description**: Creates backups of PostgreSQL database and media files with optional cloud upload.

**Features:**
- Database dumps with compression
- Media file archiving
- Backup rotation
- Cloud storage upload (optional)

**When to use:**
- Regular backup schedules (via cron)
- Before major updates
- Manual backup needs

---

### Networking

#### `setup-cloudflare-tunnel.sh`
**Purpose**: Configure Cloudflare Tunnel for secure external access
**Usage**: `./scripts/setup-cloudflare-tunnel.sh`
**Description**: Sets up and configures a Cloudflare Tunnel to expose the local BiologiDex server to the internet securely.

**When to use:**
- Exposing local server externally
- Setting up secure HTTPS access
- Initial Cloudflare integration

---

## Quick Reference

### Common Tasks

**First-time setup:**
```bash
./scripts/setup.sh
```

**Restart after configuration changes:**
```bash
./scripts/restart.sh
```

**Deploy code updates:**
```bash
./scripts/deploy.sh production
```

**Check system health:**
```bash
./scripts/diagnose.sh
```

**Monitor system:**
```bash
./scripts/monitor.sh
```

**Backup database:**
```bash
./scripts/backup.sh
```

**Reset database (WARNING: deletes data):**
```bash
./scripts/reset_database.sh
```

---

## Environment Configuration

Most scripts require a properly configured `.env` file in the server root directory. See `.env.example` for a template.

**Required variables:**
- `DB_NAME`, `DB_USER`, `DB_PASSWORD` - Database credentials
- `REDIS_PASSWORD` - Redis authentication
- `SECRET_KEY` - Django secret key

**Optional variables (gracefully handled):**
- `SENTRY_DSN` - Error tracking (disabled if not configured)
- `OPENAI_API_KEY` - CV identification (disabled if not configured)
- `GCS_BUCKET_NAME` - Cloud storage (uses local storage if not configured)
- `EMAIL_HOST`, `EMAIL_HOST_USER` - Email (uses console backend if not configured)

---

## Script Maintenance

All scripts follow these conventions:
- Executable permission: `chmod +x scripts/*.sh`
- Shebang: `#!/bin/bash`
- Comments explaining purpose and usage
- Error handling with clear messages
- Non-destructive by default (confirmation prompts for destructive operations)

---

## Troubleshooting

### Services won't start
1. Run `./scripts/diagnose.sh` for detailed diagnostics
2. Check `.env` configuration
3. Run `./scripts/restart.sh` and review output
4. Check logs: `docker-compose -f docker-compose.production.yml logs`

### Database connection errors
1. Verify `DB_PASSWORD` in `.env` matches database
2. Run `./scripts/reset_database.sh` if password mismatch (WARNING: deletes data)
3. Check database container: `docker-compose -f docker-compose.production.yml logs db`

### Service-specific issues
- **Sentry errors**: Comment out `SENTRY_DSN` in `.env` (handled gracefully)
- **OpenAI errors**: Set valid `OPENAI_API_KEY` or leave blank to disable CV
- **Email errors**: Configure SMTP or leave blank for console backend
- **Storage errors**: Configure GCS or use default local storage

---

## Additional Resources

- Main documentation: `/home/bryan/Development/Git/biologidex/CLAUDE.md`
- Docker Compose config: `docker-compose.production.yml`
- Environment template: `.env.example`
- Application settings: `biologidex/settings/production_local.py`