#!/bin/bash
# BiologiDex Godot Client Export to Production Script
# Usage: ./scripts/export-to-prod.sh [--skip-export]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLIENT_DIR="$PROJECT_ROOT/client/biologidex-client"
EXPORT_DIR="$CLIENT_DIR/export/web"
SERVER_DIR="$PROJECT_ROOT/server"
CLIENT_FILES_DIR="$SERVER_DIR/client_files"
BACKUP_DIR="$SERVER_DIR/client_files_backup"
LOG_FILE="${SERVER_DIR}/logs/export.log"

# Parse arguments
SKIP_EXPORT=false
if [[ "${1:-}" == "--skip-export" ]]; then
    SKIP_EXPORT=true
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

# Pre-export checks
pre_export_checks() {
    log "Running pre-export checks..."

    # Check if client directory exists
    if [ ! -d "$CLIENT_DIR" ]; then
        error "Client directory not found: $CLIENT_DIR"
    fi

    # Check if Godot is installed
    if ! command -v godot &> /dev/null && ! command -v godot4 &> /dev/null; then
        error "Godot not found in PATH. Please install Godot 4.5+"
    fi

    # Determine Godot command
    if command -v godot4 &> /dev/null; then
        GODOT_CMD="godot4"
    else
        GODOT_CMD="godot"
    fi

    # Check Godot version
    GODOT_VERSION=$($GODOT_CMD --version 2>&1 | head -n 1)
    log "Using Godot: $GODOT_VERSION"

    # Check if export preset exists
    if [ ! -f "$CLIENT_DIR/export_presets.cfg" ]; then
        error "Export presets not found. Please configure export settings in Godot editor first."
    fi

    # Check disk space
    AVAILABLE_SPACE=$(df "$SERVER_DIR" | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE" -lt 100000 ]; then
        warning "Low disk space: ${AVAILABLE_SPACE}KB available"
    fi

    log "Pre-export checks completed successfully"
}

# Export Godot project
export_godot_project() {
    if [ "$SKIP_EXPORT" = true ]; then
        warning "Skipping Godot export (--skip-export flag set)"
        return
    fi

    log "Exporting Godot project..."

    # Clean previous export
    if [ -d "$EXPORT_DIR" ]; then
        log "Cleaning previous export directory..."
        rm -rf "$EXPORT_DIR"
    fi

    # Create export directory
    mkdir -p "$EXPORT_DIR"

    # Export using Godot headless
    cd "$CLIENT_DIR"

    info "Running Godot export (this may take a minute)..."
    if $GODOT_CMD --headless --export-release "Web" "$EXPORT_DIR/index.html" 2>&1 | tee -a "$LOG_FILE"; then
        log "Godot export completed successfully"
    else
        error "Godot export failed. Check the log for details."
    fi

    # Verify export files exist
    if [ ! -f "$EXPORT_DIR/index.html" ]; then
        error "Export failed: index.html not found"
    fi

    if [ ! -f "$EXPORT_DIR/index.wasm" ]; then
        error "Export failed: index.wasm not found"
    fi

    log "Export verification passed"
}

# Backup current deployment
backup_current_deployment() {
    if [ -d "$CLIENT_FILES_DIR" ]; then
        log "Backing up current deployment..."

        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

        mkdir -p "$BACKUP_PATH"
        cp -r "$CLIENT_FILES_DIR"/* "$BACKUP_PATH/"

        log "Current deployment backed up to $BACKUP_PATH"

        # Keep only last 5 backups
        BACKUP_COUNT=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)
        if [ "$BACKUP_COUNT" -gt 5 ]; then
            log "Cleaning old backups (keeping last 5)..."
            ls -1t "$BACKUP_DIR" | tail -n +6 | xargs -I {} rm -rf "$BACKUP_DIR/{}"
        fi
    else
        info "No existing deployment to backup"
    fi
}

# Deploy client files
deploy_client_files() {
    log "Deploying client files..."

    # Create client_files directory
    mkdir -p "$CLIENT_FILES_DIR"

    # Check if export directory has files
    if [ ! "$(ls -A "$EXPORT_DIR")" ]; then
        error "Export directory is empty: $EXPORT_DIR"
    fi

    # Copy all files from export directory
    log "Copying files to $CLIENT_FILES_DIR..."
    cp -r "$EXPORT_DIR"/* "$CLIENT_FILES_DIR/"

    # Set proper permissions
    chmod -R 755 "$CLIENT_FILES_DIR"

    # Get file sizes
    TOTAL_SIZE=$(du -sh "$CLIENT_FILES_DIR" | cut -f1)
    WASM_SIZE=$(du -h "$CLIENT_FILES_DIR/index.wasm" | cut -f1)

    log "Deployment completed"
    info "Total size: $TOTAL_SIZE (WASM: $WASM_SIZE)"

    # List deployed files
    log "Deployed files:"
    ls -lh "$CLIENT_FILES_DIR" | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}'
}

# Optimize assets
optimize_assets() {
    log "Optimizing assets..."

    cd "$CLIENT_FILES_DIR"

    # Check if gzip is available
    if command -v gzip &> /dev/null; then
        # Pre-compress large files for nginx gzip_static
        for file in *.wasm *.js *.html; do
            if [ -f "$file" ]; then
                log "Compressing $file..."
                gzip -k -f -9 "$file"
            fi
        done
        log "Pre-compression completed"
    else
        warning "gzip not available, skipping pre-compression"
    fi

    # Check if brotli is available
    if command -v brotli &> /dev/null; then
        for file in *.wasm *.js *.html; do
            if [ -f "$file" ]; then
                log "Brotli compressing $file..."
                brotli -k -f -q 11 "$file"
            fi
        done
        log "Brotli compression completed"
    else
        info "brotli not available, skipping brotli compression"
    fi
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."

    # Check if all required files exist
    REQUIRED_FILES=("index.html" "index.wasm" "index.js" "index.pck")

    for file in "${REQUIRED_FILES[@]}"; do
        if [ ! -f "$CLIENT_FILES_DIR/$file" ]; then
            error "Required file missing: $file"
        fi
    done

    # Check file sizes are reasonable
    WASM_SIZE=$(stat -f%z "$CLIENT_FILES_DIR/index.wasm" 2>/dev/null || stat -c%s "$CLIENT_FILES_DIR/index.wasm")
    if [ "$WASM_SIZE" -lt 1000000 ]; then
        warning "WASM file seems too small (${WASM_SIZE} bytes). Deployment may be incomplete."
    fi

    log "Deployment verification passed"
}

# Reload nginx
reload_nginx() {
    log "Checking if nginx reload is needed..."

    # Check if running in Docker
    if docker ps | grep -q "biologidex.*nginx"; then
        log "Reloading nginx in Docker..."
        docker-compose -f "$SERVER_DIR/docker-compose.production.yml" exec -T nginx nginx -s reload

        if [ $? -eq 0 ]; then
            log "Nginx reloaded successfully"
        else
            warning "Failed to reload nginx, you may need to restart the container"
        fi
    else
        info "Nginx not running in Docker, skipping reload"
    fi
}

# Rollback function
rollback() {
    warning "Rolling back deployment..."

    # Find latest backup
    LATEST_BACKUP=$(ls -1t "$BACKUP_DIR" 2>/dev/null | head -n 1)

    if [ -z "$LATEST_BACKUP" ]; then
        error "No backup found for rollback"
    fi

    log "Restoring from backup: $LATEST_BACKUP"

    # Remove current deployment
    rm -rf "$CLIENT_FILES_DIR"

    # Restore from backup
    mkdir -p "$CLIENT_FILES_DIR"
    cp -r "$BACKUP_DIR/$LATEST_BACKUP"/* "$CLIENT_FILES_DIR/"

    log "Rollback completed"
}

# Show deployment info
show_deployment_info() {
    echo ""
    log "=== Deployment Information ==="
    echo ""
    echo "Client files location: $CLIENT_FILES_DIR"
    echo "Backup location: $BACKUP_DIR"
    echo "Log file: $LOG_FILE"
    echo ""
    echo "To test locally:"
    echo "  cd $CLIENT_FILES_DIR && python3 -m http.server 8080"
    echo ""
    echo "Production URL (once nginx is configured):"
    echo "  http://localhost/ (or your domain)"
    echo ""
    echo "Nginx configuration:"
    echo "  Update server/nginx/nginx.conf to serve from $CLIENT_FILES_DIR"
    echo "  See client-host.md for detailed instructions"
    echo ""
}

# Main export flow
main() {
    log "=== Starting BiologiDex Client Export to Production ==="

    # Set trap for rollback on error (only if not first deployment)
    if [ -d "$CLIENT_FILES_DIR" ]; then
        trap rollback ERR
    fi

    # Run export steps
    pre_export_checks
    export_godot_project
    backup_current_deployment
    deploy_client_files
    optimize_assets
    verify_deployment
    reload_nginx

    # Remove trap after successful deployment
    trap - ERR

    log "=== Export to Production Completed Successfully ==="

    show_deployment_info
}

# Run main function
main "$@"
