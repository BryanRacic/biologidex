#!/bin/bash
# BiologiDex Automated Backup Script
# Handles database and media file backups with cloud upload

set -euo pipefail

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/var/backups/biologidex}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_NAME="${DB_NAME:-biologidex}"
DB_USER="${DB_USER:-biologidex}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
MEDIA_DIR="${MEDIA_DIR:-/var/www/biologidex/media}"
GCS_BACKUP_BUCKET="${GCS_BACKUP_BUCKET:-biologidex-backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
LOG_FILE="/var/log/biologidex/backup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# Create backup directories
setup_directories() {
    log "Setting up backup directories..."
    mkdir -p "$BACKUP_DIR"/{postgres,redis,media}
    mkdir -p "$(dirname "$LOG_FILE")"
}

# Backup PostgreSQL database
backup_postgres() {
    log "Starting PostgreSQL backup..."

    local backup_file="$BACKUP_DIR/postgres/biologidex_${TIMESTAMP}.sql.gz"

    # Use .pgpass for authentication
    export PGPASSFILE="$HOME/.pgpass"

    # Perform backup with compression
    if pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
               --no-password --verbose --no-owner --no-acl \
               --format=custom --compress=9 \
               --file="$backup_file" 2>> "$LOG_FILE"; then
        log "PostgreSQL backup completed: $backup_file"

        # Upload to GCS if configured
        if command -v gsutil &> /dev/null && [ -n "$GCS_BACKUP_BUCKET" ]; then
            log "Uploading PostgreSQL backup to GCS..."
            if gsutil -m cp "$backup_file" "gs://$GCS_BACKUP_BUCKET/postgres/"; then
                log "PostgreSQL backup uploaded to GCS"
            else
                warning "Failed to upload PostgreSQL backup to GCS"
            fi
        fi

        # Clean up old local backups
        find "$BACKUP_DIR/postgres" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete
        log "Cleaned up PostgreSQL backups older than $RETENTION_DAYS days"
    else
        error "PostgreSQL backup failed"
    fi
}

# Backup Redis data
backup_redis() {
    log "Starting Redis backup..."

    local backup_file="$BACKUP_DIR/redis/redis_${TIMESTAMP}.rdb"

    # Trigger Redis background save
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" BGSAVE

    # Wait for background save to complete
    log "Waiting for Redis background save..."
    while [ "$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" LASTSAVE)" = "$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" LASTSAVE)" ]; do
        sleep 1
    done

    # Copy the dump file
    if [ -f "/var/lib/redis/dump.rdb" ]; then
        cp "/var/lib/redis/dump.rdb" "$backup_file"
        log "Redis backup completed: $backup_file"

        # Compress the backup
        gzip "$backup_file"
        backup_file="${backup_file}.gz"

        # Upload to GCS if configured
        if command -v gsutil &> /dev/null && [ -n "$GCS_BACKUP_BUCKET" ]; then
            log "Uploading Redis backup to GCS..."
            if gsutil -m cp "$backup_file" "gs://$GCS_BACKUP_BUCKET/redis/"; then
                log "Redis backup uploaded to GCS"
            else
                warning "Failed to upload Redis backup to GCS"
            fi
        fi

        # Clean up old local backups
        find "$BACKUP_DIR/redis" -name "*.rdb.gz" -mtime +$RETENTION_DAYS -delete
        log "Cleaned up Redis backups older than $RETENTION_DAYS days"
    else
        warning "Redis dump file not found"
    fi
}

# Backup media files
backup_media() {
    log "Starting media files backup..."

    if [ -d "$MEDIA_DIR" ]; then
        local backup_file="$BACKUP_DIR/media/media_${TIMESTAMP}.tar.gz"

        # Create compressed archive
        tar -czf "$backup_file" -C "$(dirname "$MEDIA_DIR")" "$(basename "$MEDIA_DIR")" 2>> "$LOG_FILE"

        if [ $? -eq 0 ]; then
            log "Media backup completed: $backup_file"

            # Upload to GCS if configured
            if command -v gsutil &> /dev/null && [ -n "$GCS_BACKUP_BUCKET" ]; then
                log "Syncing media files to GCS..."
                # Use rsync for incremental backup
                if gsutil -m rsync -r -d "$MEDIA_DIR" "gs://$GCS_BACKUP_BUCKET/media/current/"; then
                    log "Media files synced to GCS"

                    # Also upload the archive for point-in-time recovery
                    gsutil -m cp "$backup_file" "gs://$GCS_BACKUP_BUCKET/media/archives/"
                else
                    warning "Failed to sync media files to GCS"
                fi
            fi

            # Clean up old local backups
            find "$BACKUP_DIR/media" -name "*.tar.gz" -mtime +7 -delete
            log "Cleaned up media backups older than 7 days"
        else
            warning "Media backup failed"
        fi
    else
        warning "Media directory not found: $MEDIA_DIR"
    fi
}

# Verify backups
verify_backups() {
    log "Verifying backups..."

    local today_backups=$(find "$BACKUP_DIR" -name "*${TIMESTAMP:0:8}*" -type f)

    if [ -z "$today_backups" ]; then
        error "No backups found for today"
    else
        log "Today's backups:"
        echo "$today_backups" | while read -r backup; do
            local size=$(du -h "$backup" | cut -f1)
            log "  - $backup ($size)"
        done
    fi
}

# Send notification (optional)
send_notification() {
    local status=$1
    local message=$2

    # Email notification if configured
    if [ -n "${EMAIL_TO:-}" ] && command -v mail &> /dev/null; then
        echo "$message" | mail -s "BiologiDex Backup $status - $(hostname)" "$EMAIL_TO"
    fi

    # Slack notification if configured
    if [ -n "${SLACK_WEBHOOK:-}" ]; then
        curl -X POST -H 'Content-type: application/json' \
             --data "{\"text\":\"BiologiDex Backup $status on $(hostname): $message\"}" \
             "$SLACK_WEBHOOK"
    fi
}

# Main backup process
main() {
    log "=== Starting BiologiDex Backup ==="
    log "Timestamp: $TIMESTAMP"

    # Setup
    setup_directories

    # Track backup status
    local backup_status="SUCCESS"
    local error_message=""

    # Run backups
    {
        backup_postgres
        backup_redis
        backup_media
        verify_backups
    } || {
        backup_status="FAILED"
        error_message="Backup process failed. Check logs at $LOG_FILE"
    }

    # Report results
    if [ "$backup_status" = "SUCCESS" ]; then
        log "=== Backup Completed Successfully ==="
        send_notification "SUCCESS" "All backups completed successfully at $TIMESTAMP"
    else
        error "=== Backup Failed ==="
        send_notification "FAILED" "$error_message"
    fi

    # Show disk usage
    log "Backup directory disk usage:"
    du -sh "$BACKUP_DIR"/* | tee -a "$LOG_FILE"
}

# Run with lock to prevent concurrent executions
LOCK_FILE="/var/run/biologidex-backup.lock"
exec 200>"$LOCK_FILE"

if ! flock -n 200; then
    warning "Another backup is already running"
    exit 1
fi

# Run main function
main "$@"