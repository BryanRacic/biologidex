# BiologiDex Client Version Check Implementation Plan

## Executive Summary

This document outlines a comprehensive implementation strategy for client version checking in the BiologiDex Progressive Web Application (PWA). The solution addresses the critical issue of browser-cached clients not properly updating, which can lead to API incompatibility and degraded user experience.

## Problem Statement

- **Primary Issue**: PWA clients are aggressively cached by browsers and don't reliably check for updates
- **Impact**: Users may run outdated clients against updated server APIs, causing failures
- **Current State**: No mechanism exists to detect or notify users of version mismatches
- **Challenge**: Must work without requiring Docker rebuild when client is updated

## Solution Architecture

### High-Level Overview

1. **Version Tracking**: Track client version using git commit hash at build time
2. **Version Storage**: Store expected client version in a file accessible to Django without rebuild
3. **Version Endpoint**: Expose version info via existing health API endpoint
4. **Client Check**: Check version on app startup and periodically during runtime
5. **User Notification**: Display clear update prompt when version mismatch detected
6. **Cache Busting**: Implement service worker strategies to force updates when needed

### Technical Components

```
┌─────────────────────┐
│   Build Process     │
│  (export-to-prod.sh)│
├─────────────────────┤
│ - Get git commit    │
│ - Generate manifest │
│ - Update version    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Version Storage    │
├─────────────────────┤
│ /server/            │
│  client_version.json│
│ (outside container) │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   Django Server     │
├─────────────────────┤
│ /api/v1/version/    │
│ Returns expected    │
│ client version      │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   Godot Client      │
├─────────────────────┤
│ - Check on startup  │
│ - Periodic checks   │
│ - Show update popup │
└─────────────────────┘
```

## Detailed Implementation Plan

### Phase 1: Version Tracking Infrastructure

#### 1.1 Server-Side Version Storage

Create a version file that Django can read without requiring container rebuild:

**File: `/server/client_version.json`**
```json
{
  "version": "git-commit-hash",
  "build_timestamp": "2025-11-21T10:30:00Z",
  "build_number": 1234,
  "git_commit": "305d923",
  "git_message": "Claude client refactor (untested)",
  "git_branch": "main",
  "godot_version": "4.5",
  "minimum_api_version": "1.0.0",
  "features": {
    "multi_animal_detection": true,
    "two_step_upload": true,
    "taxonomic_tree": true
  }
}
```

**Key Design Decisions:**
- Store as JSON file outside Docker container for easy updates
- Mount as volume in docker-compose for container access
- Include feature flags for capability detection
- Track both client and API versions for compatibility

#### 1.2 Django Version Endpoint

Create a dedicated version endpoint that doesn't require authentication:

**File: `/server/biologidex/version.py`**
```python
"""
Client version management for BiologiDex
Handles version checking and compatibility
"""
import json
import os
from pathlib import Path
from django.http import JsonResponse
from django.views.decorators.http import require_http_methods
from django.views.decorators.cache import cache_page
from django.conf import settings


@cache_page(60)  # Cache for 1 minute
@require_http_methods(["GET"])
def client_version_check(request):
    """
    Returns expected client version information
    Used by clients to detect when updates are required
    """
    version_file = Path(settings.BASE_DIR).parent / 'client_version.json'

    # Default version info if file doesn't exist
    version_info = {
        'client_version': 'unknown',
        'build_timestamp': None,
        'git_commit': 'unknown',
        'minimum_api_version': '1.0.0',
        'update_required': False,
        'update_message': None
    }

    try:
        if version_file.exists():
            with open(version_file, 'r') as f:
                stored_version = json.load(f)
                version_info.update(stored_version)

        # Check if client provided their version
        client_version = request.headers.get('X-Client-Version', 'unknown')

        if client_version != 'unknown' and client_version != version_info['git_commit']:
            version_info['update_required'] = True
            version_info['update_message'] = (
                f"Your client is out of date and may not work as expected! "
                f"Please clear your cache and reload the application. "
                f"Current version: {client_version}, "
                f"Expected version: {version_info['git_commit']}"
            )

    except Exception as e:
        version_info['error'] = str(e)

    return JsonResponse(version_info)
```

**URL Configuration Update:**
```python
# In /server/biologidex/urls.py
from biologidex.version import client_version_check

urlpatterns += [
    path('api/v1/version/', client_version_check, name='client-version'),
]
```

### Phase 2: Build Process Integration

#### 2.1 Enhanced Export Script

Update `/server/scripts/export-to-prod.sh` to capture version information:

```bash
# Add to export-to-prod.sh after line 50

# Capture version information
capture_version_info() {
    log "Capturing version information..."

    # Get git information
    GIT_COMMIT=$(git rev-parse --short HEAD)
    GIT_COMMIT_FULL=$(git rev-parse HEAD)
    GIT_MESSAGE=$(git log -1 --pretty=%B | head -n 1)
    GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    GIT_TIMESTAMP=$(git log -1 --format=%cd --date=iso)
    BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    BUILD_NUMBER=$(date +%s)

    # Get Godot version from earlier check
    GODOT_VERSION_SHORT=$(echo "$GODOT_VERSION" | grep -oE '[0-9]+\.[0-9]+' | head -1)

    # Create version file
    cat > "$SERVER_DIR/client_version.json" << EOF
{
  "version": "$GIT_COMMIT",
  "build_timestamp": "$BUILD_TIMESTAMP",
  "build_number": $BUILD_NUMBER,
  "git_commit": "$GIT_COMMIT",
  "git_commit_full": "$GIT_COMMIT_FULL",
  "git_message": "$(echo "$GIT_MESSAGE" | sed 's/"/\\"/g')",
  "git_branch": "$GIT_BRANCH",
  "git_timestamp": "$GIT_TIMESTAMP",
  "godot_version": "$GODOT_VERSION_SHORT",
  "minimum_api_version": "1.0.0",
  "features": {
    "multi_animal_detection": true,
    "two_step_upload": true,
    "taxonomic_tree": true,
    "dex_sync_v2": true
  }
}
EOF

    log "Version info captured: $GIT_COMMIT"

    # Also embed version in the exported files
    echo "$GIT_COMMIT" > "$EXPORT_DIR/version.txt"

    # Update service worker with version for cache busting
    if [ -f "$EXPORT_DIR/index.service.worker.js" ]; then
        sed -i "1s/^/\/\/ Version: $GIT_COMMIT\\n\/\/ Build: $BUILD_TIMESTAMP\\n\\n/" \
            "$EXPORT_DIR/index.service.worker.js"

        # Update cache name with version
        sed -i "s/const CACHE_NAME = .*/const CACHE_NAME = 'biologidex-v-$GIT_COMMIT';/" \
            "$EXPORT_DIR/index.service.worker.js"
    fi
}

# Call this function after export_godot_project in main()
# Add after line 402:
capture_version_info
```

#### 2.2 Docker Volume Configuration

Update `docker-compose.production.yml` to mount the version file:

```yaml
services:
  web:
    volumes:
      - ./client_version.json:/app/client_version.json:ro
      # ... existing volumes

  celery_worker:
    volumes:
      - ./client_version.json:/app/client_version.json:ro
      # ... existing volumes
```

### Phase 3: Client-Side Implementation

#### 3.1 Version Manager Singleton

Create a new Godot singleton for version management that **only runs in exported builds**:

**File: `/client/biologidex-client/features/version/version_manager.gd`**

**Important Runtime Detection:**
- Version checking is **disabled** when running in the Godot editor
- Only activates in exported builds (currently web exports only)
- Prevents development/testing interference
- Uses multiple detection methods:
  - `OS.has_feature("editor")` - detects Godot editor
  - `OS.has_feature("debug")` - detects debug builds
  - `OS.has_feature("web")` - ensures web export
  - Checks for `version.txt` file presence
  - JavaScript validation for web context

```gdscript
extends Node

# Version Manager - Handles client version checking and update prompts
# Autoloaded singleton - ONLY ACTIVE IN EXPORTED BUILDS

signal version_check_completed(is_current: bool)
signal update_required(current_version: String, expected_version: String)

const VERSION_CHECK_ENDPOINT = "/api/v1/version/"
const VERSION_FILE_PATH = "res://version.txt"
const CHECK_INTERVAL = 300.0  # Check every 5 minutes
const VERSION_KEY = "client_version"

var current_version: String = "unknown"
var expected_version: String = "unknown"
var last_check_time: float = 0
var check_timer: Timer
var is_checking: bool = false

# Services
var api_manager

func _ready() -> void:
	print("[VersionManager] Initializing...")

	# Load current version from embedded file
	_load_current_version()

	# Get API manager
	api_manager = get_node_or_null("/root/APIManager")
	if not api_manager:
		push_error("[VersionManager] APIManager not found")
		return

	# Setup periodic check timer
	check_timer = Timer.new()
	check_timer.wait_time = CHECK_INTERVAL
	check_timer.timeout.connect(_on_check_timer_timeout)
	check_timer.autostart = false
	add_child(check_timer)

	print("[VersionManager] Ready. Current version: ", current_version)

func _load_current_version() -> void:
	"""Load the current client version from embedded file"""
	if FileAccess.file_exists(VERSION_FILE_PATH):
		var file = FileAccess.open(VERSION_FILE_PATH, FileAccess.READ)
		if file:
			current_version = file.get_line().strip_edges()
			file.close()
	else:
		# Fallback: try to get from exported HTML metadata
		if OS.has_feature("web"):
			var version_meta = JavaScriptBridge.eval("""
				(() => {
					const meta = document.querySelector('meta[name="client-version"]');
					return meta ? meta.content : 'unknown';
				})()
			""")
			if version_meta and version_meta != "unknown":
				current_version = version_meta

func check_version(force: bool = false) -> void:
	"""Check if client version matches server expectation"""
	if is_checking:
		return

	# Skip if recently checked (unless forced)
	var current_time = Time.get_ticks_msec() / 1000.0
	if not force and current_time - last_check_time < 60.0:  # Min 1 minute between checks
		return

	is_checking = true
	last_check_time = current_time

	print("[VersionManager] Checking version...")

	# Make version check request
	var headers = {
		"X-Client-Version": current_version
	}

	api_manager.make_request(
		VERSION_CHECK_ENDPOINT,
		HTTPClient.METHOD_GET,
		{},
		headers,
		func(response: Dictionary, code: int):
			_handle_version_response(response, code)
	)

func _handle_version_response(response: Dictionary, code: int) -> void:
	"""Handle version check response"""
	is_checking = false

	if code != 200:
		print("[VersionManager] Version check failed: ", code)
		version_check_completed.emit(true)  # Assume OK on failure
		return

	expected_version = response.get("git_commit", "unknown")
	var update_required = response.get("update_required", false)
	var update_message = response.get("update_message", "")

	print("[VersionManager] Version check: current=", current_version,
		  " expected=", expected_version, " update_required=", update_required)

	if update_required or (current_version != expected_version and
						  current_version != "unknown" and
						  expected_version != "unknown"):
		# Version mismatch detected
		print("[VersionManager] Version mismatch detected!")
		version_check_completed.emit(false)
		self.update_required.emit(current_version, expected_version)

		# Show update dialog
		_show_update_dialog(update_message)

		# Stop periodic checks during update
		check_timer.stop()
	else:
		# Version is current
		version_check_completed.emit(true)

		# Start periodic checks
		if not check_timer.is_stopped():
			check_timer.start()

func _show_update_dialog(message: String = "") -> void:
	"""Show update required dialog to user"""
	var dialog_message = message
	if dialog_message.is_empty():
		dialog_message = """Your client is out of date and may not work as expected!

Please refresh the page to load the latest version.
If the issue persists:
1. Clear your browser cache (Ctrl+Shift+R or Cmd+Shift+R)
2. For installed PWAs: Uninstall and reinstall the app
3. For mobile: Clear app data in settings

Current version: %s
Expected version: %s""" % [current_version, expected_version]

	# Use the error dialog system if available
	var error_handler = get_node_or_null("/root/ErrorHandler")
	if error_handler and error_handler.has_method("show_error"):
		error_handler.show_error(
			"Update Required",
			dialog_message,
			{"actions": ["Refresh Now", "Continue Anyway"]}
		)
	else:
		# Fallback to JavaScript alert on web
		if OS.has_feature("web"):
			JavaScriptBridge.eval("""
				if (confirm('%s\\n\\nRefresh now?')) {
					window.location.reload(true);
				}
			""" % dialog_message.replace("\n", "\\n"))

func _on_check_timer_timeout() -> void:
	"""Periodic version check"""
	check_version(false)

func start_periodic_checks() -> void:
	"""Start periodic version checking"""
	if check_timer and check_timer.is_stopped():
		check_timer.start()

func stop_periodic_checks() -> void:
	"""Stop periodic version checking"""
	if check_timer:
		check_timer.stop()

func force_refresh() -> void:
	"""Force a hard refresh of the application"""
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.reload(true);")

func clear_cache_and_refresh() -> void:
	"""Attempt to clear cache and refresh (web only)"""
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""
			(async () => {
				// Clear all caches
				if ('caches' in window) {
					const names = await caches.keys();
					await Promise.all(names.map(name => caches.delete(name)));
				}

				// Unregister service worker
				if ('serviceWorker' in navigator) {
					const registrations = await navigator.serviceWorker.getRegistrations();
					for(let registration of registrations) {
						await registration.unregister();
					}
				}

				// Force reload
				window.location.reload(true);
			})();
		""")
```

#### 3.2 Login Scene Integration

Update `/client/biologidex-client/scenes/login/login.gd` to check version on startup:

```gdscript
# Add to _ready() function after line 25:
	# Check client version
	var version_manager = get_node_or_null("/root/VersionManager")
	if version_manager:
		version_manager.check_version(true)
		version_manager.version_check_completed.connect(_on_version_check_completed)

# Add new function:
func _on_version_check_completed(is_current: bool) -> void:
	"""Handle version check completion"""
	if not is_current:
		# Disable login until user updates
		login_button.disabled = true
		create_acct_button.disabled = true
		status_label.text = "Update required - please refresh the page"
		status_label.add_theme_color_override("font_color", Color.RED)
```

#### 3.3 Service Worker Enhancement

Update service worker template to handle version-based cache busting:

**File: `/client/biologidex-client/export_templates/index.service.worker.js`** (create if doesn't exist)
```javascript
// BiologiDex Service Worker with Version Management
// Version: {{VERSION}}
// Build: {{BUILD_TIMESTAMP}}

const CACHE_NAME = 'biologidex-v-{{VERSION}}';
const CACHE_VERSION = '{{VERSION}}';

// Files to cache (will be populated by Godot export)
const CACHED_FILES = [
  // ... existing files
];

// Install event - cache all files
self.addEventListener('install', (event) => {
  console.log('[ServiceWorker] Install version:', CACHE_VERSION);

  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(CACHED_FILES);
    }).then(() => {
      // Skip waiting to activate immediately
      return self.skipWaiting();
    })
  );
});

// Activate event - clean old caches
self.addEventListener('activate', (event) => {
  console.log('[ServiceWorker] Activate version:', CACHE_VERSION);

  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          // Delete old version caches
          if (cacheName.startsWith('biologidex-v-') && cacheName !== CACHE_NAME) {
            console.log('[ServiceWorker] Deleting old cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    }).then(() => {
      // Take control of all clients immediately
      return self.clients.claim();
    })
  );
});

// Fetch event - serve from cache with network fallback
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Skip version check endpoint - always fetch from network
  if (url.pathname.includes('/api/v1/version/')) {
    event.respondWith(fetch(event.request));
    return;
  }

  // Skip API calls - always fetch from network
  if (url.pathname.startsWith('/api/')) {
    event.respondWith(fetch(event.request));
    return;
  }

  // Cache-first strategy for static assets
  event.respondWith(
    caches.match(event.request).then((response) => {
      if (response) {
        // Check if we should validate the cache
        if (shouldValidateCache(event.request)) {
          // Fetch in background and update cache
          fetch(event.request).then((networkResponse) => {
            if (networkResponse && networkResponse.status === 200) {
              caches.open(CACHE_NAME).then((cache) => {
                cache.put(event.request, networkResponse.clone());
              });
            }
          });
        }
        return response;
      }

      // Not in cache, fetch from network
      return fetch(event.request).then((response) => {
        // Cache successful responses
        if (response && response.status === 200 && shouldCache(event.request)) {
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, response.clone());
          });
        }
        return response;
      });
    })
  );
});

// Message handler for forced updates
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    console.log('[ServiceWorker] Received skip waiting message');
    self.skipWaiting();
  }

  if (event.data && event.data.type === 'CHECK_VERSION') {
    event.ports[0].postMessage({
      version: CACHE_VERSION,
      cacheName: CACHE_NAME
    });
  }
});

// Helper functions
function shouldCache(request) {
  const url = new URL(request.url);
  // Cache static assets
  return url.pathname.match(/\.(js|css|wasm|pck|png|jpg|jpeg|gif|svg|ico|webp)$/);
}

function shouldValidateCache(request) {
  const url = new URL(request.url);
  // Always validate HTML files
  return url.pathname.endsWith('.html') || url.pathname === '/';
}
```

### Phase 4: PWA Manifest and Cache Management

#### 4.1 Enhanced PWA Manifest

Update the manifest generation in export script to include version:

```json
{
  "name": "BiologiDex",
  "short_name": "BiologiDex",
  "version": "{{VERSION}}",
  "version_name": "{{GIT_MESSAGE}}",
  "description": "Catch and collect real-world animals in your personal Pokedex",
  "start_url": "./index.html?v={{VERSION}}",
  "id": "biologidex-{{VERSION}}",
  "scope": "/",
  "display": "standalone",
  "orientation": "any",
  "background_color": "#000000",
  "theme_color": "#4CAF50",
  "prefer_related_applications": false,
  "related_applications": [],
  "categories": ["games", "education", "social"],
  "screenshots": [...],
  "icons": [...],
  "shortcuts": [
    {
      "name": "Camera",
      "short_name": "Capture",
      "description": "Capture a new animal",
      "url": "/index.html#camera",
      "icons": [{"src": "index.144x144.png", "sizes": "144x144"}]
    },
    {
      "name": "My Dex",
      "short_name": "Dex",
      "description": "View your collection",
      "url": "/index.html#dex",
      "icons": [{"src": "index.144x144.png", "sizes": "144x144"}]
    }
  ]
}
```

#### 4.2 HTML Meta Tags

Update the exported HTML to include version metadata:

```html
<!-- Add to index.html template -->
<meta name="client-version" content="{{VERSION}}">
<meta name="build-timestamp" content="{{BUILD_TIMESTAMP}}">
<link rel="manifest" href="index.manifest.json?v={{VERSION}}">

<!-- Force service worker update check -->
<script>
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('./index.service.worker.js?v={{VERSION}}', {
    updateViaCache: 'none'
  }).then((registration) => {
    // Check for updates every page load
    registration.update();

    // Listen for update found
    registration.addEventListener('updatefound', () => {
      const newWorker = registration.installing;
      newWorker.addEventListener('statechange', () => {
        if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
          // New service worker available
          if (confirm('New version available! Reload to update?')) {
            newWorker.postMessage({ type: 'SKIP_WAITING' });
            window.location.reload();
          }
        }
      });
    });
  });
}
</script>
```

### Phase 5: Nginx Configuration

#### 5.1 Cache Headers

Update nginx configuration to prevent aggressive caching:

```nginx
# In /server/nginx/nginx.conf

location / {
    root /var/www/biologidex/client;
    try_files $uri $uri/ /index.html;

    # HTML files - no cache
    location ~* \.(html)$ {
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma "no-cache";
        add_header Expires "0";
        add_header X-Client-Version "$client_version";
    }

    # Service worker - short cache
    location ~ service\.worker\.js$ {
        add_header Cache-Control "max-age=300, must-revalidate";
        add_header Service-Worker-Allowed "/";
    }

    # Manifest - short cache
    location ~ manifest\.json$ {
        add_header Cache-Control "max-age=300, must-revalidate";
    }

    # WASM/PCK files - versioned, can cache longer
    location ~* \.(wasm|pck)$ {
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    # Other static assets - moderate cache
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp)$ {
        add_header Cache-Control "public, max-age=3600, must-revalidate";
    }
}

# Version endpoint - pass to Django
location /api/v1/version/ {
    proxy_pass http://web:8000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    add_header Cache-Control "no-cache, must-revalidate";
}
```

## Implementation Timeline

### Week 1: Foundation
- [ ] Day 1-2: Implement server-side version endpoint and storage
- [ ] Day 3-4: Update export script to capture and store version info
- [ ] Day 5: Test version file generation and Docker volume mounting

### Week 2: Client Integration
- [ ] Day 1-2: Create VersionManager singleton for Godot
- [ ] Day 3-4: Integrate version checking into login flow
- [ ] Day 5: Implement update notification UI

### Week 3: PWA Enhancement
- [ ] Day 1-2: Update service worker with version-based caching
- [ ] Day 3: Enhance PWA manifest with version info
- [ ] Day 4: Configure nginx cache headers
- [ ] Day 5: End-to-end testing and refinement

## Testing Strategy

### Test Scenarios

1. **Fresh Install**
   - User visits site for first time
   - Verify correct version is loaded
   - Confirm service worker installs successfully

2. **Version Mismatch**
   - Deploy new server version
   - Access with old cached client
   - Verify update prompt appears
   - Confirm refresh loads new version

3. **Forced Update**
   - User dismisses update prompt
   - Verify periodic checks continue
   - Test forced refresh functionality

4. **Offline Behavior**
   - Client goes offline
   - Verify app remains functional
   - Version check fails gracefully

5. **PWA Update**
   - Installed PWA receives update
   - Service worker updates correctly
   - Old cache is cleared

### Testing Commands

```bash
# Test version endpoint
curl https://biologidex.example.com/api/v1/version/

# Check service worker registration
# In browser console:
navigator.serviceWorker.getRegistrations().then(console.log)

# Force service worker update
navigator.serviceWorker.getRegistration().then(r => r.update())

# Clear all caches
caches.keys().then(names => names.forEach(name => caches.delete(name)))
```

## Rollback Plan

If issues arise with version checking:

1. **Quick Disable**
   - Set `VERSION_CHECK_ENABLED=false` in settings
   - Version endpoint returns `update_required: false`
   - Client skips version validation

2. **Full Rollback**
   - Restore previous export script
   - Remove version checking code from client
   - Revert nginx cache headers
   - Clear CDN cache if applicable

## Security Considerations

1. **Version Information Disclosure**
   - Version endpoint is public (no auth required)
   - Only expose necessary information
   - Don't include sensitive build paths or credentials

2. **Cache Poisoning**
   - Validate version format on server
   - Sanitize version strings in responses
   - Use CSP headers to prevent script injection

3. **Update Mechanism**
   - Updates are suggested, not forced
   - Users can continue with old version at own risk
   - No automatic code execution during updates

## Performance Impact

### Expected Impact
- **Version Check**: ~50ms additional on startup
- **Periodic Checks**: Negligible (every 5 minutes)
- **Cache Management**: Improved with proper headers
- **Service Worker**: Better update detection

### Optimization Options
- Cache version endpoint for 1 minute
- Batch version checks with other API calls
- Use ETags for efficient cache validation
- Implement exponential backoff for failed checks

## Monitoring and Metrics

### Key Metrics to Track

1. **Version Distribution**
   ```sql
   SELECT
     client_version,
     COUNT(*) as user_count,
     MAX(last_seen) as last_seen
   FROM user_sessions
   GROUP BY client_version
   ORDER BY user_count DESC;
   ```

2. **Update Success Rate**
   - Track version check requests
   - Monitor update prompt interactions
   - Measure time to update after prompt

3. **Cache Performance**
   - Service worker install/update events
   - Cache hit/miss ratios
   - Resource loading times

### Alerts to Configure

- Alert if >20% of users on outdated version
- Alert if version check endpoint fails
- Alert if service worker registration drops

## Best Practices Applied

Based on 2024-2025 PWA best practices research:

1. **Cache-First with Validation**: Service worker uses cache-first strategy with background revalidation for HTML
2. **Version-Based Cache Names**: Each version gets unique cache name for clean updates
3. **Immediate Activation**: Service worker skips waiting and claims clients immediately
4. **Update on Navigate**: Check for updates when user navigates to app
5. **Short Cache TTL**: Critical files (HTML, service worker, manifest) have short cache times
6. **User Control**: Users decide when to update, preventing data loss
7. **Feature Detection**: Version info includes feature flags for capability checking
8. **Progressive Enhancement**: Version check fails gracefully, app remains functional

## Additional Considerations

### Browser Compatibility
- Service Worker API: Chrome 40+, Firefox 44+, Safari 12.1+
- Cache API: Chrome 43+, Firefox 41+, Safari 11.1+
- Web App Manifest: Chrome 39+, Firefox (partial), Safari (partial)

### PWA Store Listings
- Google Play Store: May cache app bundle, consider store listing updates
- Microsoft Store: PWAs update automatically with manifest changes
- Apple App Store: Not applicable (PWAs not in App Store)

### CDN Considerations
- Cloudflare: Configure page rules for version endpoint
- Set "Browser Cache TTL" to respect origin headers
- Use "Cache Level: Bypass" for `/api/v1/version/`

## Conclusion

This implementation plan provides a robust solution for client version management in the BiologiDex PWA. By combining git-based version tracking, service worker cache management, and clear user communication, we can ensure users always have access to a compatible client version while maintaining a smooth user experience.

The solution is designed to be:
- **Non-intrusive**: Doesn't require Docker rebuilds for client updates
- **User-friendly**: Clear messaging and update prompts
- **Performant**: Minimal impact on load time and runtime
- **Reliable**: Fails gracefully, maintains functionality
- **Maintainable**: Clear separation of concerns, documented thoroughly

## Appendix: Quick Implementation Checklist

- [ ] Create `/server/client_version.json` structure
- [ ] Implement Django version endpoint
- [ ] Update Docker Compose with version file volume
- [ ] Modify export-to-prod.sh to generate version info
- [ ] Create Godot VersionManager singleton
- [ ] Integrate version check into login scene
- [ ] Update service worker template with versioning
- [ ] Configure nginx cache headers
- [ ] Test end-to-end version checking flow
- [ ] Document version check disable procedure
- [ ] Set up monitoring for version metrics
- [ ] Create runbook for version mismatch incidents