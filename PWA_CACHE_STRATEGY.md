# PWA Cache-Busting Strategies for BiologiDex

## Overview

This document provides specific strategies and best practices for managing PWA caching issues in the BiologiDex application, with a focus on ensuring users receive updates promptly while maintaining offline functionality.

## The PWA Caching Problem

Progressive Web Apps use Service Workers to enable offline functionality, but this creates challenges:

1. **Browser Cache**: Browsers aggressively cache PWA assets for performance
2. **Service Worker Cache**: Service workers maintain their own cache storage
3. **HTTP Cache**: Standard HTTP caching headers affect resource freshness
4. **PWA Install Cache**: Installed PWAs may have additional caching layers

## Multi-Layer Caching Strategy

### Layer 1: Service Worker Version Control

```javascript
// Service worker with version-based cache management
const CACHE_VERSION = 'v1.2.3-build-4567';
const CACHE_NAME = `biologidex-${CACHE_VERSION}`;

// Critical: Different cache names for different asset types
const CACHE_NAMES = {
  static: `static-${CACHE_VERSION}`,
  dynamic: `dynamic-${CACHE_VERSION}`,
  api: 'api-v1'  // API cache doesn't change with client version
};
```

### Layer 2: Cache Strategies by Resource Type

#### HTML Files - Network First with Fallback
```javascript
// Always try network first for HTML
if (request.mode === 'navigate' || request.url.endsWith('.html')) {
  return event.respondWith(
    fetch(request)
      .then(response => {
        // Update cache with fresh version
        return caches.open(CACHE_NAMES.static)
          .then(cache => {
            cache.put(request, response.clone());
            return response;
          });
      })
      .catch(() => {
        // Fallback to cache if offline
        return caches.match(request);
      })
  );
}
```

#### Static Assets (JS/CSS) - Cache First with Background Update
```javascript
// Serve from cache, update in background
if (request.url.match(/\.(js|css|wasm|pck)$/)) {
  return event.respondWith(
    caches.match(request)
      .then(cached => {
        const fetchPromise = fetch(request)
          .then(network => {
            // Update cache in background
            caches.open(CACHE_NAMES.static)
              .then(cache => cache.put(request, network.clone()));
            return network;
          });

        // Return cached version immediately, or wait for network
        return cached || fetchPromise;
      })
  );
}
```

#### API Calls - Network Only
```javascript
// Never cache API responses in service worker
if (request.url.includes('/api/')) {
  return event.respondWith(fetch(request));
}
```

### Layer 3: Update Detection and Notification

```javascript
// Check for updates on service worker install
self.addEventListener('install', event => {
  event.waitUntil(
    // Open new cache
    caches.open(CACHE_NAME)
      .then(cache => {
        // Cache all static resources
        return cache.addAll(STATIC_CACHE_URLS);
      })
      .then(() => {
        // Skip waiting to activate immediately
        return self.skipWaiting();
      })
  );
});

// Clean old caches on activation
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(cacheNames => {
        return Promise.all(
          cacheNames
            .filter(name => name.startsWith('biologidex-') && name !== CACHE_NAME)
            .map(name => {
              console.log('Deleting old cache:', name);
              return caches.delete(name);
            })
        );
      })
      .then(() => {
        // Take control immediately
        return self.clients.claim();
      })
  );
});

// Notify clients of updates
self.addEventListener('message', event => {
  if (event.data.action === 'skipWaiting') {
    self.skipWaiting();
  }
});
```

### Layer 4: Client-Side Update Management

```javascript
// In main application code
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js')
    .then(registration => {
      // Check for updates on load
      registration.update();

      // Check for updates periodically
      setInterval(() => {
        registration.update();
      }, 60 * 60 * 1000); // Every hour

      // Listen for new service worker
      registration.addEventListener('updatefound', () => {
        const newWorker = registration.installing;

        newWorker.addEventListener('statechange', () => {
          if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
            // New version available
            showUpdatePrompt(() => {
              newWorker.postMessage({ action: 'skipWaiting' });
              window.location.reload();
            });
          }
        });
      });
    });
}
```

## HTTP Cache Headers Strategy

### Nginx Configuration

```nginx
# HTML files - no cache
location ~* \.(html)$ {
    add_header Cache-Control "no-cache, no-store, must-revalidate";
    add_header Pragma "no-cache";
    add_header Expires "0";
}

# Service Worker - minimal cache with validation
location ~ sw\.js$ {
    add_header Cache-Control "max-age=0, must-revalidate";
    add_header Service-Worker-Allowed "/";
}

# Manifest - short cache
location ~ manifest\.json$ {
    add_header Cache-Control "max-age=300, must-revalidate";
}

# Versioned assets - long cache
location ~* \.(js|css|wasm|pck)$ {
    # Check for version parameter
    if ($arg_v) {
        add_header Cache-Control "public, max-age=31536000, immutable";
    }
    # Non-versioned - shorter cache
    if (!$arg_v) {
        add_header Cache-Control "public, max-age=3600, must-revalidate";
    }
}

# Images - moderate cache
location ~* \.(png|jpg|jpeg|gif|ico|svg|webp)$ {
    add_header Cache-Control "public, max-age=86400";
}
```

## Version-Based Cache Busting

### URL Versioning
```html
<!-- Version all critical resources -->
<link rel="stylesheet" href="/styles.css?v=abc123">
<script src="/app.js?v=abc123"></script>
<link rel="manifest" href="/manifest.json?v=abc123">
```

### Build-Time Hash Injection
```javascript
// webpack.config.js or build script
module.exports = {
  output: {
    filename: '[name].[contenthash:8].js',
    chunkFilename: '[name].[contenthash:8].chunk.js'
  }
};
```

### Service Worker Registration with Version
```javascript
// Include version in SW registration
navigator.serviceWorker.register(`/sw.js?v=${BUILD_VERSION}`, {
  updateViaCache: 'none'  // Critical: bypass HTTP cache for SW
});
```

## Godot-Specific Considerations

### Export Configuration
```gdscript
# In export_presets.cfg
[preset.0.options]
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=true
html/export_icon=true
html/custom_html_shell=""
html/head_include=""
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
html/experimental_virtual_keyboard=false
progressive_web_app/enabled=true
progressive_web_app/offline_page=""
progressive_web_app/display=standalone
progressive_web_app/orientation=any
progressive_web_app/icon_144x144="res://icon_144.png"
progressive_web_app/icon_180x180="res://icon_180.png"
progressive_web_app/icon_512x512="res://icon_512.png"
progressive_web_app/background_color=Color(0, 0, 0, 1)
```

### Godot Service Worker Fix
```javascript
// Fix for Godot 4.3 service worker bug
const CACHED_FILES = [
  'index.html',
  'index.js',
  'index.wasm',
  'index.pck',
  'index.apple-touch-icon.png',
  'index.icon.png',
  'index.service.worker.js',  // Critical: SW must cache itself
  'index.manifest.json'
];
```

## Update Flow Best Practices

### 1. Soft Update Prompt
```javascript
function showUpdateBanner() {
  const banner = document.createElement('div');
  banner.className = 'update-banner';
  banner.innerHTML = `
    <p>A new version is available!</p>
    <button onclick="updateApp()">Update Now</button>
    <button onclick="dismissUpdate()">Later</button>
  `;
  document.body.appendChild(banner);
}
```

### 2. Hard Refresh Implementation
```javascript
async function forceHardRefresh() {
  // Clear all caches
  if ('caches' in window) {
    const names = await caches.keys();
    await Promise.all(names.map(name => caches.delete(name)));
  }

  // Unregister service workers
  if ('serviceWorker' in navigator) {
    const registrations = await navigator.serviceWorker.getRegistrations();
    for (let registration of registrations) {
      await registration.unregister();
    }
  }

  // Clear storage
  localStorage.clear();
  sessionStorage.clear();

  // Reload with cache bypass
  window.location.reload(true);
}
```

### 3. Graceful Degradation
```javascript
// Continue working even if update check fails
async function checkForUpdates() {
  try {
    const response = await fetch('/api/version');
    const data = await response.json();

    if (data.updateRequired) {
      showUpdatePrompt();
    }
  } catch (error) {
    console.warn('Update check failed, continuing with current version');
    // App continues to work offline
  }
}
```

## Testing Cache Behavior

### Browser DevTools Commands

```javascript
// Check service worker status
navigator.serviceWorker.getRegistrations().then(console.log);

// Check cache storage
caches.keys().then(console.log);

// View cache contents
caches.open('cache-name').then(cache =>
  cache.keys().then(requests =>
    requests.forEach(request => console.log(request.url))
  )
);

// Force service worker update
navigator.serviceWorker.getRegistration()
  .then(reg => reg.update());

// Clear all caches
caches.keys().then(names =>
  Promise.all(names.map(name => caches.delete(name)))
);
```

### Automated Testing

```javascript
// Playwright/Puppeteer test
test('PWA updates correctly', async ({ page }) => {
  // Load app
  await page.goto('https://app.example.com');

  // Wait for service worker
  await page.waitForFunction(() =>
    navigator.serviceWorker.controller !== null
  );

  // Simulate new version deployment
  await deployNewVersion();

  // Trigger update check
  await page.evaluate(() => {
    navigator.serviceWorker.getRegistration()
      .then(reg => reg.update());
  });

  // Verify update prompt appears
  await expect(page.locator('.update-prompt')).toBeVisible();

  // Accept update
  await page.click('button:has-text("Update Now")');

  // Verify new version loads
  await page.waitForLoadState('networkidle');
  const version = await page.evaluate(() =>
    window.APP_VERSION
  );
  expect(version).toBe('new-version');
});
```

## Common Issues and Solutions

### Issue 1: Service Worker Not Updating
**Problem**: Browser caches service worker despite changes
**Solution**:
- Use `updateViaCache: 'none'` in registration
- Add version query parameter to SW URL
- Set `Cache-Control: max-age=0` for SW file

### Issue 2: Old Assets Served After Update
**Problem**: Cached assets persist after deployment
**Solution**:
- Use unique cache names per version
- Clean old caches in activate event
- Implement cache.put() for updates

### Issue 3: PWA Not Showing Update
**Problem**: Installed PWA doesn't detect updates
**Solution**:
- Call registration.update() on app start
- Implement periodic update checks
- Use push notifications for critical updates

### Issue 4: Mixed Version State
**Problem**: Some assets updated, others cached
**Solution**:
- Version all assets together
- Use atomic cache updates
- Implement integrity checks

## Monitoring and Analytics

### Track Update Metrics

```javascript
// Log version info
gtag('event', 'app_version', {
  current_version: CURRENT_VERSION,
  update_available: updateAvailable,
  update_accepted: userAcceptedUpdate
});

// Track cache performance
performance.mark('cache-hit');
performance.mark('cache-miss');

// Monitor SW lifecycle
self.addEventListener('install', event => {
  analytics.track('sw_install', { version: CACHE_VERSION });
});
```

### Server-Side Tracking

```python
# Django view to track client versions
def track_client_version(request):
    client_version = request.headers.get('X-Client-Version', 'unknown')

    # Log to monitoring system
    logger.info('client_version_check', extra={
        'client_version': client_version,
        'expected_version': settings.EXPECTED_CLIENT_VERSION,
        'user_id': request.user.id if request.user.is_authenticated else None,
        'timestamp': timezone.now()
    })

    # Store in database for analytics
    ClientVersionLog.objects.create(
        version=client_version,
        user=request.user if request.user.is_authenticated else None,
        ip_address=request.META.get('REMOTE_ADDR'),
        user_agent=request.META.get('HTTP_USER_AGENT')
    )
```

## Rollback Strategy

If cache-busting causes issues:

1. **Immediate Mitigation**:
   ```javascript
   // Disable update checks
   window.DISABLE_UPDATE_CHECK = true;
   ```

2. **Service Worker Bypass**:
   ```javascript
   // Unregister all service workers
   navigator.serviceWorker.getRegistrations()
     .then(regs => regs.forEach(reg => reg.unregister()));
   ```

3. **Force Specific Version**:
   ```nginx
   # Nginx redirect to specific version
   location / {
     if ($cookie_force_version = "old") {
       return 302 /archive/v1.0.0/index.html;
     }
   }
   ```

## Conclusion

Effective PWA cache management requires a multi-layer approach combining:
- Service worker versioning
- Strategic cache policies
- HTTP header configuration
- Client-side update detection
- User-friendly update prompts

The strategies outlined here ensure BiologiDex users receive timely updates while maintaining the offline-first benefits of PWA technology.