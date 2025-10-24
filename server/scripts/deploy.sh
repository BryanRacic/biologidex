#!/bin/bash
# BiologiDex Production Deployment Script
# Usage: ./scripts/deploy.sh [environment]

set -euo pipefail

# Configuration
ENVIRONMENT="${1:-production}"
DOCKER_COMPOSE_FILE="docker-compose.${ENVIRONMENT}.yml"
ENV_FILE=".env.${ENVIRONMENT}"
BACKUP_DIR="/var/backups/biologidex"
LOG_FILE="/var/log/biologidex/deploy.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Pre-deployment checks
pre_deployment_checks() {
    log "Running pre-deployment checks..."

    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        error "Docker is not running"
    fi

    # Check if environment file exists
    if [ ! -f "$ENV_FILE" ]; then
        error "Environment file $ENV_FILE not found"
    fi

    # Check if docker-compose file exists
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        error "Docker compose file $DOCKER_COMPOSE_FILE not found"
    fi

    # Check disk space
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE" -lt 1000000 ]; then
        warning "Low disk space: ${AVAILABLE_SPACE}KB available"
    fi

    log "Pre-deployment checks completed successfully"
}

# Backup database
backup_database() {
    log "Creating database backup..."

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="${BACKUP_DIR}/db_backup_${TIMESTAMP}.sql"

    mkdir -p "$BACKUP_DIR"

    # Create backup using Docker
    docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T db pg_dump -U biologidex biologidex > "$BACKUP_FILE"

    if [ $? -eq 0 ]; then
        log "Database backed up to $BACKUP_FILE"
        # Keep only last 7 backups
        find "$BACKUP_DIR" -name "db_backup_*.sql" -mtime +7 -delete
    else
        error "Database backup failed"
    fi
}

# Build and update images
build_images() {
    log "Building Docker images..."

    docker-compose -f "$DOCKER_COMPOSE_FILE" build --no-cache web celery_worker celery_beat

    if [ $? -eq 0 ]; then
        log "Docker images built successfully"
    else
        error "Docker image build failed"
    fi
}

# Run database migrations
run_migrations() {
    log "Running database migrations..."

    docker-compose -f "$DOCKER_COMPOSE_FILE" run --rm web python manage.py migrate --noinput

    if [ $? -eq 0 ]; then
        log "Database migrations completed"
    else
        error "Database migrations failed"
    fi
}

# Collect static files
collect_static() {
    log "Collecting static files..."

    docker-compose -f "$DOCKER_COMPOSE_FILE" run --rm web python manage.py collectstatic --noinput

    if [ $? -eq 0 ]; then
        log "Static files collected"
    else
        error "Static file collection failed"
    fi
}

# Deploy application
deploy() {
    log "Starting deployment..."

    # Stop existing services
    log "Stopping existing services..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" down

    # Start services
    log "Starting services..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d

    # Wait for services to be healthy
    log "Waiting for services to be healthy..."
    sleep 10

    # Check health
    for service in db redis web celery_worker; do
        if docker-compose -f "$DOCKER_COMPOSE_FILE" ps | grep -q "${service}.*Up"; then
            log "Service $service is running"
        else
            error "Service $service failed to start"
        fi
    done

    log "Deployment completed successfully"
}

# Health check
health_check() {
    log "Running health check..."

    # Wait for services to be ready
    sleep 5

    # Check API health endpoint
    HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/api/v1/health/)

    if [ "$HEALTH_STATUS" = "200" ]; then
        log "Health check passed"
    else
        error "Health check failed with status $HEALTH_STATUS"
    fi
}

# Rollback function
rollback() {
    warning "Rolling back deployment..."

    # Stop current deployment
    docker-compose -f "$DOCKER_COMPOSE_FILE" down

    # Restore previous images
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d --no-build

    # Restore database if needed
    if [ -f "$BACKUP_FILE" ]; then
        log "Restoring database from backup..."
        docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T db psql -U biologidex biologidex < "$BACKUP_FILE"
    fi

    warning "Rollback completed. Please check the system."
}

# Cleanup old resources
cleanup() {
    log "Cleaning up old resources..."

    # Remove unused Docker images
    docker image prune -f

    # Remove unused volumes
    docker volume prune -f

    # Clean old logs
    find /var/log/biologidex -name "*.log" -mtime +30 -delete

    log "Cleanup completed"
}

# Main deployment flow
main() {
    log "=== Starting BiologiDex Deployment ==="
    log "Environment: $ENVIRONMENT"

    # Set trap for rollback on error
    trap rollback ERR

    # Run deployment steps
    pre_deployment_checks
    backup_database
    build_images
    run_migrations
    collect_static
    deploy
    health_check
    cleanup

    # Remove trap after successful deployment
    trap - ERR

    log "=== Deployment Completed Successfully ==="

    # Show service status
    echo ""
    log "Service Status:"
    docker-compose -f "$DOCKER_COMPOSE_FILE" ps

    # Show logs location
    echo ""
    log "Logs available at:"
    echo "  - Application: /var/log/biologidex/app.log"
    echo "  - Deployment: $LOG_FILE"
    echo "  - Docker: docker-compose -f $DOCKER_COMPOSE_FILE logs -f [service]"
}

# Run main function
main "$@"