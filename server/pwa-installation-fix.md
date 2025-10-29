# PWA Installation Fix for BiologiDex

## Current Status

✅ HTTPS enabled (via Cloudflare tunnel)
✅ Service worker file generated (`index.service.worker.js`)
✅ PWA manifest present (`index.manifest.json`)
✅ PWA icons present (144x144, 180x180, 512x512)
✅ Service worker registered in HTML
❌ **PWA install prompt not appearing**

---

## Root Cause

The Godot 4.5 PWA export has a **known bug** where the service worker file (`index.service.worker.js`) does not include itself in the `CACHED_FILES` array. This prevents the service worker from properly caching itself, which can cause issues with PWA installation and offline functionality.

**Source**: [Godot Issue #100518 - PWA does not work offline](https://github.com/godotengine/godot/issues/100518)

### Current CACHED_FILES (Line 17 of index.service.worker.js):
```javascript
const CACHED_FILES = [
    "index.html",
    "index.js",
    "index.offline.html",
    "index.icon.png",
    "index.apple-touch-icon.png",
    "index.audio.worklet.js",
    "index.audio.position.worklet.js"
];
// ❌ Missing: "index.service.worker.js"
```

---

## Additional PWA Requirements

Beyond fixing the service worker bug, there are several other requirements for browsers to show the PWA install prompt:

### 1. **HTTPS Requirement** ✅
- **Status**: WORKING (Cloudflare provides HTTPS)
- **Verification**: Visit https://biologidex.io - should show secure lock icon

### 2. **Valid Web App Manifest** ⚠️
- **Current manifest** (`index.manifest.json`):
```json
{
  "background_color": "#000000",
  "display": "standalone",
  "icons": [
    {"sizes": "144x144", "src": "index.144x144.png", "type": "image/png"},
    {"sizes": "180x180", "src": "index.180x180.png", "type": "image/png"},
    {"sizes": "512x512", "src": "index.512x512.png", "type": "image/png"}
  ],
  "name": "biologidex-client",
  "orientation": "any",
  "start_url": "./index.html"
}
```

**Issues**:
- ❌ Missing `short_name` (required for home screen)
- ❌ Missing `theme_color` (recommended)
- ❌ Missing `description` (recommended)
- ❌ Missing `scope` (recommended)
- ❌ App name is "biologidex-client" (not user-friendly)

### 3. **Service Worker Registration** ✅
- **Status**: WORKING
- Service worker is registered in `index.html` line 115
- Registration logic is present in the Godot loader

### 4. **User Engagement Requirements** ⚠️
Most browsers require:
- User has visited the site at least once
- User has spent at least 30 seconds on the site
- User has interacted with the page (clicks, scrolls)
- Site has been visited on at least 2 separate days (Chrome)

### 5. **Manifest Display Mode** ✅
- **Status**: WORKING
- `"display": "standalone"` is set correctly

### 6. **PWA Installability Criteria (Chrome/Edge)**
- ✅ Served over HTTPS
- ✅ Has a valid manifest with required fields
- ⚠️ Service worker is registered but may have caching issues
- ❌ May not meet engagement requirements yet
- ⚠️ Manifest could be improved

---

## Implementation Plan

### Phase 1: Fix Service Worker Bug (Critical)

#### Step 1: Update Service Worker File

**File to modify**: `client/biologidex-client/export/web/index.service.worker.js`

**Change line 17** from:
```javascript
const CACHED_FILES = ["index.html","index.js","index.offline.html","index.icon.png","index.apple-touch-icon.png","index.audio.worklet.js","index.audio.position.worklet.js"];
```

To:
```javascript
const CACHED_FILES = ["index.html","index.js","index.offline.html","index.icon.png","index.apple-touch-icon.png","index.audio.worklet.js","index.audio.position.worklet.js","index.service.worker.js"];
```

**Or with better formatting**:
```javascript
const CACHED_FILES = [
    "index.html",
    "index.js",
    "index.offline.html",
    "index.icon.png",
    "index.apple-touch-icon.png",
    "index.audio.worklet.js",
    "index.audio.position.worklet.js",
    "index.service.worker.js"  // ✅ Added: Cache the service worker itself
];
```

#### Step 2: Deploy Updated File

```bash
# On production server
cd /opt/biologidex/server
./scripts/export-to-prod.sh

# Or manually copy just the service worker if already exported locally:
# scp client/biologidex-client/export/web/index.service.worker.js \
#     production-server:/opt/biologidex/server/client_files/
```

#### Step 3: Clear Browser Cache & Re-register Service Worker

After deployment, users need to:
1. Open browser DevTools (F12)
2. Go to Application tab → Service Workers
3. Click "Unregister" on the old service worker
4. Refresh the page
5. Verify new service worker is registered

Or use this in browser console:
```javascript
navigator.serviceWorker.getRegistrations().then(function(registrations) {
    for(let registration of registrations) {
        registration.unregister();
    }
    location.reload();
});
```

---

### Phase 2: Improve Web App Manifest (Recommended)

#### Step 1: Enhance Manifest in Godot Project

**File**: `client/biologidex-client/project.godot`

Update the PWA settings in export presets (or via Godot Editor):

```
Export → Web → Progressive Web App Settings:
- Display: Standalone ✓ (already set)
- Name: BiologiDex
- Short Name: BiologiDex
- Description: Catch and collect real-world animals in your personal Pokedex
- Background Color: #000000 ✓ (already set)
- Theme Color: #4CAF50 (or your brand color)
- Orientation: any ✓ (already set)
- Icons: [already configured]
```

However, Godot's PWA export has limitations on what fields can be customized. For full control:

#### Step 2: Manually Edit Generated Manifest

After export, edit `client/biologidex-client/export/web/index.manifest.json`:

```json
{
  "name": "BiologiDex",
  "short_name": "BiologiDex",
  "description": "Catch and collect real-world animals in your personal Pokedex",
  "background_color": "#000000",
  "theme_color": "#4CAF50",
  "display": "standalone",
  "scope": "/",
  "start_url": "/",
  "orientation": "any",
  "icons": [
    {
      "src": "index.144x144.png",
      "sizes": "144x144",
      "type": "image/png",
      "purpose": "any"
    },
    {
      "src": "index.180x180.png",
      "sizes": "180x180",
      "type": "image/png",
      "purpose": "any"
    },
    {
      "src": "index.512x512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any maskable"
    }
  ],
  "categories": ["games", "education"],
  "screenshots": []
}
```

**Note**: This requires manual editing after each Godot export, or creating a script to automate it.

---

### Phase 3: Verify PWA Installation (Testing)

#### Browser DevTools Checks

**Chrome/Edge DevTools**:
1. Open https://biologidex.io
2. Press F12 → Application tab
3. Check sections:

**Manifest**:
- Should show all fields from manifest.json
- No warnings about missing fields
- Icons should preview correctly

**Service Workers**:
- Should show "index.service.worker.js" as activated and running
- Status: "activated"
- No errors in console

**Storage**:
- Cache Storage → Should show "biologidex-clien-sw-cache-[version]"
- Should contain all files including index.service.worker.js

#### Lighthouse PWA Audit

1. Open DevTools → Lighthouse tab
2. Select "Progressive Web App" category
3. Click "Analyze page load"
4. Review PWA checklist:
   - ✅ Installable
   - ✅ PWA Optimized
   - ✅ Offline capable

**Target Score**: 90+ for full PWA compliance

#### Manual Install Testing

**Desktop (Chrome/Edge)**:
- Look for install icon (⊕) in address bar
- Or: Menu → Install BiologiDex
- Should create desktop shortcut and app entry

**Mobile (Android Chrome)**:
- Visit site twice over 2+ days (Chrome requirement)
- Spend 30+ seconds interacting
- Look for "Add to Home Screen" banner
- Or: Menu → Install app

**Mobile (iOS Safari)**:
- Safari doesn't support PWA install prompts the same way
- User must manually: Share → Add to Home Screen
- Will use icons and manifest data

---

## Common Issues & Troubleshooting

### Issue: Install Prompt Still Not Showing

**Possible Causes**:

1. **Service Worker Not Updated**
   - Solution: Unregister old service worker, force refresh (Ctrl+Shift+R)
   - Check: DevTools → Application → Service Workers

2. **Browser Cache**
   - Solution: Clear site data (DevTools → Application → Clear storage)
   - Then refresh and wait 30+ seconds

3. **User Engagement Not Met**
   - Chrome requires 2 separate days of visits
   - Solution: Wait and revisit tomorrow, or test in different browser

4. **Manifest Errors**
   - Solution: Check DevTools → Application → Manifest for warnings
   - Fix any reported issues

5. **HTTPS/Mixed Content**
   - Solution: Ensure all resources load over HTTPS
   - Check Console for mixed content warnings

### Issue: PWA Installs But Doesn't Work Offline

**Cause**: Service worker caching issue (the original bug)

**Solution**:
1. Verify `index.service.worker.js` is in CACHED_FILES array
2. Check DevTools → Application → Cache Storage
3. Ensure all files are cached (including .wasm and .pck)

### Issue: Icons Don't Show Correctly

**Possible Causes**:
- Icon files not deployed
- Incorrect MIME types
- Manifest path issues

**Solution**:
```bash
# Verify icons are accessible
curl -I https://biologidex.io/index.144x144.png
curl -I https://biologidex.io/index.180x180.png
curl -I https://biologidex.io/index.512x512.png

# Should return 200 OK with Content-Type: image/png
```

---

## Testing Checklist

Before deploying to production:

- [ ] Service worker includes itself in CACHED_FILES
- [ ] Manifest has all required fields (name, short_name, icons, display, start_url)
- [ ] All icon files are deployed and accessible
- [ ] HTTPS is working (no mixed content)
- [ ] Service worker registers without errors
- [ ] Lighthouse PWA audit passes (90+ score)
- [ ] Test install on desktop Chrome/Edge
- [ ] Test install on Android Chrome (after meeting engagement requirements)
- [ ] Test "Add to Home Screen" on iOS Safari
- [ ] Verify offline functionality works after install

---

## Quick Commands

```bash
# Deploy Godot client with PWA files
cd /opt/biologidex/server
./scripts/export-to-prod.sh

# Verify deployed files
ls -la /opt/biologidex/server/client_files/ | grep -E "(manifest|service|worker|png)"

# Test manifest accessibility
curl https://biologidex.io/index.manifest.json

# Test service worker accessibility
curl https://biologidex.io/index.service.worker.js

# Check nginx is serving files
docker-compose -f docker-compose.production.yml logs nginx | grep -i "manifest\|worker"

# Restart nginx after file changes
docker-compose -f docker-compose.production.yml exec nginx nginx -s reload
```

---

## Expected Result After Fix

1. **Service Worker Fully Functional**
   - Caches itself properly
   - Offline mode works
   - No console errors

2. **PWA Install Prompt Appears** (after meeting engagement requirements)
   - Desktop: Install icon in address bar
   - Mobile: "Add to Home Screen" banner or menu option

3. **Installed PWA Behavior**
   - Opens in standalone window (no browser UI)
   - Has its own icon on desktop/home screen
   - Works offline after initial visit
   - Shows custom splash screen on launch

---

## References

- [Godot Issue #100518 - PWA does not work offline (bugfix found)](https://github.com/godotengine/godot/issues/100518)
- [Godot Web Progress Report #8: Progressive Web Apps](https://godotengine.org/article/godot-web-progress-report-8/)
- [MDN: Making PWAs installable](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable)
- [Chrome: PWA Install Criteria](https://web.dev/articles/install-criteria)

---

## Summary

The main issue preventing PWA installation is the service worker bug where it doesn't cache itself. This is a known Godot 4.x bug with a simple fix: add `"index.service.worker.js"` to the CACHED_FILES array.

Additionally, improving the manifest.json with proper name, description, and theme_color will enhance the PWA experience and help meet browser installation requirements.

**Total time to implement: ~15 minutes**
**Risk level: Low**
**Impact: Enables full PWA installation and offline functionality**