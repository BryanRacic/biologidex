# PWA Automation in Export Script

## Overview

The `export-to-prod.sh` script now automatically fixes Godot PWA export issues during the build process. You no longer need to manually edit files after each export.

## What Gets Automated

### 1. Service Worker Fix
**Issue**: Godot 4.x doesn't include the service worker file in its own cache list ([GitHub Issue #100518](https://github.com/godotengine/godot/issues/100518))

**Automated Fix**: The script patches `index.service.worker.js` to add itself to the `CACHED_FILES` array:
```javascript
// Before (Godot export):
const CACHED_FILES = ["index.html","index.js",...,"index.audio.position.worklet.js"];

// After (automated patch):
const CACHED_FILES = ["index.html","index.js",...,"index.audio.position.worklet.js","index.service.worker.js"];
```

### 2. Manifest Enhancement
**Issue**: Godot generates a minimal manifest missing fields required for "Rich Install UI" and proper PWA behavior

**Automated Fix**: The script replaces the manifest with an enhanced version including:
- `name`: "BiologiDex" (user-friendly)
- `short_name`: "BiologiDex"
- `description`: Full app description
- `theme_color`: Brand color for system UI
- `scope`: Defines PWA navigation scope
- `screenshots`: Both wide (desktop) and narrow (mobile) for install UI
- `categories`: For app store classification
- `purpose`: Proper icon purposes including "maskable"

## How It Works

The `post_process_export()` function runs automatically after Godot export:

1. **Export**: Godot generates files to `client/biologidex-client/export/web/`
2. **Post-Process**: Script patches service worker and manifest
3. **Deploy**: Patched files are copied to `server/client_files/`
4. **Optimize**: Files are compressed (gzip/brotli)
5. **Deploy**: Nginx serves the fixed files

## Usage

Just run the export script as normal:

```bash
cd server
./scripts/export-to-prod.sh
```

The PWA fixes are applied automatically - no manual editing needed!

## Customization

To change PWA settings (colors, description, etc.), edit the `post_process_export()` function in `export-to-prod.sh`:

### Change Theme Color
```bash
# Line 166 in export-to-prod.sh
"theme_color": "#4CAF50",  # Change to your brand color
```

### Change App Name
```bash
# Lines 158-159
"name": "BiologiDex",
"short_name": "BiologiDex",
```

### Change Description
```bash
# Line 160
"description": "Catch and collect real-world animals in your personal Pokedex",
```

### Add Real Screenshots

When you have actual screenshots:

1. Export your app screenshots (recommended sizes):
   - Desktop: 1920x1080 (16:9 landscape)
   - Mobile: 750x1334 (9:16 portrait)

2. Place them in `client/biologidex-client/export/web/` as:
   - `screenshot-desktop.png`
   - `screenshot-mobile.png`

3. Update the manifest in `export-to-prod.sh` lines 187-201:
```json
"screenshots": [
  {
    "src": "screenshot-desktop.png",
    "sizes": "1920x1080",
    "type": "image/png",
    "form_factor": "wide",
    "label": "BiologiDex desktop view"
  },
  {
    "src": "screenshot-mobile.png",
    "sizes": "750x1334",
    "type": "image/png",
    "form_factor": "narrow",
    "label": "BiologiDex mobile view"
  }
]
```

## Verification

After deployment, verify the fixes were applied:

### Check Service Worker
```bash
curl https://biologidex.io/index.service.worker.js | grep '"index.service.worker.js"'
# Should find the file in CACHED_FILES
```

### Check Manifest
```bash
curl https://biologidex.io/index.manifest.json | jq .
# Should show enhanced manifest with all fields
```

### Check in Browser DevTools
1. Open https://biologidex.io
2. F12 → Application tab
3. Manifest section: Should show no warnings
4. Service Workers section: Should show active service worker

### Run Lighthouse PWA Audit
1. F12 → Lighthouse tab
2. Select "Progressive Web App"
3. Run audit
4. Should score 90+ with no critical issues

## Troubleshooting

### Issue: Script fails with "sed: command not found"
**Solution**: Install sed (should be available on all Unix systems)
```bash
# macOS (if missing)
brew install gnu-sed

# Linux
sudo apt-get install sed  # Debian/Ubuntu
sudo yum install sed      # RHEL/CentOS
```

### Issue: Manifest changes aren't applied
**Check**: Verify post_process_export is in the main flow
```bash
grep -A 5 "export_godot_project" server/scripts/export-to-prod.sh | grep post_process
# Should show: post_process_export
```

### Issue: Old manifest still cached in browser
**Solution**: Clear browser cache or hard refresh (Ctrl+Shift+R)

### Issue: Want to skip post-processing
**Temporary disable**: Comment out line in main():
```bash
# post_process_export  # Disabled for testing
```

## Benefits

✅ **No manual editing** after each Godot export
✅ **Consistent PWA configuration** across deployments
✅ **Version controlled** PWA settings in the script
✅ **Automatic bug fixes** for known Godot PWA issues
✅ **Easy customization** by editing the script
✅ **Rollback support** via backup system

## Related Files

- `export-to-prod.sh` (lines 130-215): Post-processing function
- `pwa-installation-fix.md`: Detailed PWA issue documentation
- `https-implementation-plan.md`: HTTPS setup guide
- `client-host.md`: Godot web client hosting architecture

## Future Improvements

Potential enhancements to consider:

1. **Screenshot Generation**: Auto-capture screenshots using headless browser
2. **Icon Generation**: Generate all icon sizes from a single source image
3. **Manifest Validation**: JSON schema validation before deployment
4. **Service Worker Templates**: Support for custom service worker features
5. **PWA Score Tracking**: Automated Lighthouse audits in CI/CD

## References

- [Godot Issue #100518](https://github.com/godotengine/godot/issues/100518) - Service worker cache bug
- [MDN PWA Manifest](https://developer.mozilla.org/en-US/docs/Web/Manifest)
- [Chrome Install Criteria](https://web.dev/articles/install-criteria)
- [Godot Web Export Docs](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)