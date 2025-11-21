#!/bin/bash
# BiologiDex Client Version Tracking Add-on
# This file contains functions to add to export-to-prod.sh for version tracking
# Copy these functions into the main export-to-prod.sh script

# ============================================================================
# ADD THESE FUNCTIONS TO export-to-prod.sh
# ============================================================================

# Function to capture version information
# Call this after export_godot_project() in the main flow
capture_version_info() {
    log "Capturing version information..."

    # Ensure we're in the git repository
    cd "$PROJECT_ROOT"

    # Check if git is available
    if ! command -v git &> /dev/null; then
        warning "Git not found, using fallback version info"
        GIT_COMMIT="unknown"
        GIT_COMMIT_FULL="unknown"
        GIT_MESSAGE="Git not available"
        GIT_BRANCH="unknown"
        GIT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    else
        # Get git information
        GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        GIT_COMMIT_FULL=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        GIT_MESSAGE=$(git log -1 --pretty=%B 2>/dev/null | head -n 1 | sed 's/"/\\"/g' || echo "No commit message")
        GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        GIT_TIMESTAMP=$(git log -1 --format=%cd --date=iso 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
        GIT_AUTHOR=$(git log -1 --pretty=%an 2>/dev/null || echo "unknown")
    fi

    # Build information
    BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    BUILD_NUMBER=$(date +%s)
    BUILD_HOST=$(hostname)

    # Get Godot version from earlier check (if available)
    if [ -z "$GODOT_VERSION" ]; then
        GODOT_VERSION=$($GODOT_CMD --version 2>&1 | head -n 1 || echo "unknown")
    fi
    GODOT_VERSION_SHORT=$(echo "$GODOT_VERSION" | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "4.5")

    # Create version file for Django
    VERSION_FILE="$SERVER_DIR/client_version.json"
    log "Creating version file: $VERSION_FILE"

    cat > "$VERSION_FILE" << EOF
{
  "version": "$GIT_COMMIT",
  "build_timestamp": "$BUILD_TIMESTAMP",
  "build_number": $BUILD_NUMBER,
  "build_host": "$BUILD_HOST",
  "git_commit": "$GIT_COMMIT",
  "git_commit_full": "$GIT_COMMIT_FULL",
  "git_message": "$GIT_MESSAGE",
  "git_branch": "$GIT_BRANCH",
  "git_timestamp": "$GIT_TIMESTAMP",
  "git_author": "$GIT_AUTHOR",
  "godot_version": "$GODOT_VERSION_SHORT",
  "minimum_api_version": "1.0.0",
  "features": {
    "multi_animal_detection": true,
    "two_step_upload": true,
    "taxonomic_tree": true,
    "dex_sync_v2": true,
    "version_checking": true
  },
  "deployment": {
    "environment": "production",
    "deployed_by": "$(whoami)",
    "deployed_at": "$BUILD_TIMESTAMP"
  }
}
EOF

    log "Version info captured: $GIT_COMMIT ($GIT_BRANCH)"

    # Embed version in exported files
    embed_version_in_client
}

# Function to embed version information in client files
embed_version_in_client() {
    log "Embedding version in client files..."

    cd "$EXPORT_DIR"

    # 1. Create version.txt for Godot to read
    echo "$GIT_COMMIT" > version.txt
    log "Created version.txt with commit: $GIT_COMMIT"

    # 2. Update service worker with version
    if [ -f "index.service.worker.js" ]; then
        log "Updating service worker with version..."

        # Create temporary file with version header
        cat > index.service.worker.tmp << EOF
// BiologiDex Service Worker
// Version: $GIT_COMMIT
// Build: $BUILD_TIMESTAMP
// Branch: $GIT_BRANCH
// Message: $GIT_MESSAGE

EOF
        # Append original service worker content
        cat index.service.worker.js >> index.service.worker.tmp

        # Replace cache name with versioned name
        sed -i "s/const CACHE_NAME = .*/const CACHE_NAME = 'biologidex-v$GIT_COMMIT';/" index.service.worker.tmp

        # Add version constant if not present
        if ! grep -q "const CACHE_VERSION" index.service.worker.tmp; then
            sed -i "/const CACHE_NAME/a const CACHE_VERSION = '$GIT_COMMIT';" index.service.worker.tmp
        else
            sed -i "s/const CACHE_VERSION = .*/const CACHE_VERSION = '$GIT_COMMIT';/" index.service.worker.tmp
        fi

        # Move temp file to replace original
        mv index.service.worker.tmp index.service.worker.js
        log "Service worker updated with version $GIT_COMMIT"
    else
        warning "Service worker not found, skipping version injection"
    fi

    # 3. Update HTML with version metadata
    if [ -f "index.html" ]; then
        log "Adding version metadata to HTML..."

        # Add meta tags before </head>
        sed -i "/<\/head>/i\\
<meta name=\"client-version\" content=\"$GIT_COMMIT\">\\
<meta name=\"build-timestamp\" content=\"$BUILD_TIMESTAMP\">\\
<meta name=\"git-branch\" content=\"$GIT_BRANCH\">" index.html

        # Update manifest link to include version parameter
        sed -i "s/index\.manifest\.json/index.manifest.json?v=$GIT_COMMIT/" index.html

        # Update service worker registration to include version
        sed -i "s/index\.service\.worker\.js/index.service.worker.js?v=$GIT_COMMIT/" index.html

        log "HTML updated with version metadata"
    fi

    # 4. Update PWA manifest with version
    if [ -f "index.manifest.json" ]; then
        log "Updating PWA manifest with version..."

        # Use jq if available, otherwise use sed
        if command -v jq &> /dev/null; then
            jq --arg v "$GIT_COMMIT" \
               --arg msg "$GIT_MESSAGE" \
               --arg ts "$BUILD_TIMESTAMP" \
               '. + {version: $v, version_name: $msg, build_timestamp: $ts}' \
               index.manifest.json > index.manifest.tmp && \
               mv index.manifest.tmp index.manifest.json
        else
            # Fallback: Add version after opening brace
            sed -i "s/{/{\\n  \"version\": \"$GIT_COMMIT\",\\n  \"version_name\": \"$GIT_MESSAGE\",\\n  \"build_timestamp\": \"$BUILD_TIMESTAMP\",/" index.manifest.json
        fi

        # Update start_url with version parameter
        sed -i "s/\"start_url\": \"[^\"]*\"/\"start_url\": \".\/index.html?v=$GIT_COMMIT\"/" index.manifest.json

        log "PWA manifest updated with version"
    fi

    log "Version embedding completed"
}

# Function to validate version embedding
validate_version_embedding() {
    log "Validating version embedding..."

    local validation_passed=true
    cd "$EXPORT_DIR"

    # Check version.txt exists and contains commit hash
    if [ -f "version.txt" ]; then
        local embedded_version=$(cat version.txt)
        if [ "$embedded_version" = "$GIT_COMMIT" ]; then
            log "✓ version.txt contains correct commit: $GIT_COMMIT"
        else
            error "✗ version.txt has wrong version: $embedded_version (expected: $GIT_COMMIT)"
            validation_passed=false
        fi
    else
        error "✗ version.txt not found"
        validation_passed=false
    fi

    # Check service worker has version
    if [ -f "index.service.worker.js" ]; then
        if grep -q "Version: $GIT_COMMIT" index.service.worker.js; then
            log "✓ Service worker contains version header"
        else
            warning "✗ Service worker missing version header"
            validation_passed=false
        fi

        if grep -q "biologidex-v$GIT_COMMIT" index.service.worker.js; then
            log "✓ Service worker cache name is versioned"
        else
            warning "✗ Service worker cache name not versioned"
            validation_passed=false
        fi
    fi

    # Check HTML has version metadata
    if [ -f "index.html" ]; then
        if grep -q "client-version.*$GIT_COMMIT" index.html; then
            log "✓ HTML contains version metadata"
        else
            warning "✗ HTML missing version metadata"
            validation_passed=false
        fi
    fi

    # Check server version file
    if [ -f "$SERVER_DIR/client_version.json" ]; then
        if grep -q "\"git_commit\": \"$GIT_COMMIT\"" "$SERVER_DIR/client_version.json"; then
            log "✓ Server version file contains correct commit"
        else
            error "✗ Server version file has wrong commit"
            validation_passed=false
        fi
    else
        error "✗ Server version file not found"
        validation_passed=false
    fi

    if [ "$validation_passed" = true ]; then
        log "Version embedding validation PASSED"
        return 0
    else
        error "Version embedding validation FAILED"
        return 1
    fi
}

# Function to show version deployment info
show_version_deployment_info() {
    echo ""
    log "=== Version Deployment Information ==="
    echo ""
    echo "Git Commit: $GIT_COMMIT"
    echo "Git Branch: $GIT_BRANCH"
    echo "Git Message: $GIT_MESSAGE"
    echo "Build Time: $BUILD_TIMESTAMP"
    echo "Build Number: $BUILD_NUMBER"
    echo ""
    echo "Version File: $SERVER_DIR/client_version.json"
    echo "Client Version: $EXPORT_DIR/version.txt"
    echo ""
    echo "Version Check Endpoint:"
    echo "  curl -H 'X-Client-Version: $GIT_COMMIT' \\"
    echo "       https://your-domain.com/api/v1/version/"
    echo ""
}

# ============================================================================
# INTEGRATION INSTRUCTIONS
# ============================================================================
#
# To integrate these functions into export-to-prod.sh:
#
# 1. Copy all the functions above into export-to-prod.sh
#
# 2. In the main() function, add after export_godot_project:
#    capture_version_info
#
# 3. Add after verify_deployment:
#    validate_version_embedding
#
# 4. In show_deployment_info, add:
#    show_version_deployment_info
#
# 5. Make sure GODOT_CMD and GODOT_VERSION are available (they should be from pre_export_checks)
#
# Example main() function modification:
#
# main() {
#     log "=== Starting BiologiDex Client Export to Production ==="
#
#     if [ -d "$CLIENT_FILES_DIR" ]; then
#         trap rollback ERR
#     fi
#
#     pre_export_checks
#     export_godot_project
#     capture_version_info        # <-- ADD THIS
#     post_process_export
#     backup_current_deployment
#     deploy_client_files
#     optimize_assets
#     verify_deployment
#     validate_version_embedding  # <-- ADD THIS
#     reload_nginx
#
#     trap - ERR
#
#     log "=== Export to Production Completed Successfully ==="
#
#     show_deployment_info
#     show_version_deployment_info  # <-- ADD THIS
# }
#
# ============================================================================