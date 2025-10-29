# BiologiDex - Godot Web Client Hosting Plan

## Overview
This document outlines the strategy for hosting the BiologiDex Godot 4.5 web client through the existing Django/Nginx production infrastructure.

## Current Architecture Assessment

### Existing Infrastructure
- **Web Server**: Nginx (reverse proxy)
- **Application Server**: Django with Gunicorn
- **Container Stack**: Docker Compose production setup
- **API Endpoints**: `/api/v1/*`
- **Static Files**: `/static/*` (Django static)
- **Media Files**: `/media/*` (user uploads)

### Godot Client Export
- **Engine**: Godot 4.5 with GL Compatibility renderer
- **Export Path**: `client/biologidex-client/export/web/`
- **Key Files**:
  - `index.html` - Main entry point
  - `index.wasm` - WebAssembly binary (~36MB)
  - `index.pck` - Game data package
  - `index.js` - JavaScript loader
  - PWA assets (manifest.json, service worker)

## Hosting Strategy

### URL Structure
```
https://biologidex.example.com/          # Godot web client (main app)
https://biologidex.example.com/api/      # Django REST API
https://biologidex.example.com/admin/    # Django admin panel
https://biologidex.example.com/static/   # Django static files
https://biologidex.example.com/media/    # User uploaded media
```

### Implementation Approach

#### 1. Dedicated Client Directory
Create a new volume in Docker for serving Godot client files:
- Mount point: `/var/www/biologidex/client/`
- Files served directly by Nginx (no proxy)
- Proper caching headers for performance
- CORS headers for SharedArrayBuffer support

#### 2. Nginx Configuration Updates

##### Required MIME Types
```nginx
types {
    application/wasm wasm;
    application/octet-stream pck;
}
```

##### CORS Headers for SharedArrayBuffer (Multi-threaded)
```nginx
location / {
    # Cross-Origin Isolation headers
    add_header 'Cross-Origin-Opener-Policy' 'same-origin' always;
    add_header 'Cross-Origin-Embedder-Policy' 'require-corp' always;
}
```

##### Single-Threaded Alternative (Better Compatibility)
For maximum compatibility (itch.io, third-party hosting), export with single-threading:
- No special headers required
- Works on all browsers including Safari/iOS
- Slightly reduced performance

#### 3. Directory Structure
```
server/
├── client_files/           # New: Godot web export destination
│   ├── index.html
│   ├── index.wasm
│   ├── index.pck
│   ├── index.js
│   └── [other web export files]
├── static/                 # Django static files
├── media/                  # User uploads
└── nginx/
    └── nginx.conf         # Updated configuration
```

## Nginx Configuration Changes

### Updated nginx.conf Sections

```nginx
http {
    # Add MIME types for Godot
    types {
        application/wasm wasm;
        application/octet-stream pck;
    }

    server {
        listen 80;
        server_name _;

        # Godot Web Client (root path)
        location / {
            alias /var/www/biologidex/client/;
            try_files $uri $uri/ /index.html;

            # CORS headers for SharedArrayBuffer
            add_header 'Cross-Origin-Opener-Policy' 'same-origin' always;
            add_header 'Cross-Origin-Embedder-Policy' 'require-corp' always;

            # Cache control for game assets
            location ~* \.(wasm|pck)$ {
                expires 7d;
                add_header Cache-Control "public, immutable";
                add_header 'Cross-Origin-Opener-Policy' 'same-origin' always;
                add_header 'Cross-Origin-Embedder-Policy' 'require-corp' always;
            }

            # PWA files
            location ~* \.(manifest\.json|service\.worker\.js)$ {
                expires -1;
                add_header Cache-Control "no-cache, must-revalidate";
                add_header 'Cross-Origin-Opener-Policy' 'same-origin' always;
                add_header 'Cross-Origin-Embedder-Policy' 'require-corp' always;
            }
        }

        # Django API endpoints
        location /api/ {
            proxy_pass http://biologidex_backend;
            # ... existing proxy settings ...
        }

        # Django Admin
        location /admin/ {
            proxy_pass http://biologidex_backend;
            # ... existing proxy settings ...
        }

        # Django static files
        location /static/ {
            alias /var/www/biologidex/static/;
            # ... existing settings ...
        }

        # User uploaded media
        location /media/ {
            alias /var/www/biologidex/media/;
            # ... existing settings ...
        }
    }
}
```

## Docker Compose Updates

### docker-compose.production.yml Modifications

```yaml
services:
  nginx:
    image: nginx:alpine
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./client_files:/var/www/biologidex/client:ro  # NEW: Godot client files
      - static_files:/var/www/biologidex/static:ro
      - media_files:/var/www/biologidex/media:ro
    depends_on:
      - web
    networks:
      - biologidex-network
```

## Export Script (`export-to-prod`)

The export script will:
1. Export from Godot using headless mode
2. Optimize assets (compression, minification)
3. Deploy to production server
4. Handle rollback on failure

Script location: `scripts/export-to-prod.sh`

### Key Features:
- Automated Godot CLI export
- Asset optimization (gzip, brotli)
- Zero-downtime deployment
- Version tracking and rollback
- Health check verification

## Progressive Web App (PWA) Configuration

The Godot export includes PWA support:
- **Manifest**: Defines app metadata, icons, display mode
- **Service Worker**: Enables offline functionality
- **Icons**: Multiple sizes for different devices
- **Cross-Origin Isolation**: Handled via service worker if server headers unavailable

## Performance Optimizations

### 1. Compression
- Enable gzip/brotli for all text assets
- Pre-compress .wasm files if possible
- Use CDN for large static assets

### 2. Caching Strategy
- Immutable cache for versioned assets (.wasm, .pck)
- Short TTL for HTML entry point
- Service worker for offline caching

### 3. Loading Optimizations
- Show loading progress bar
- Lazy load non-critical assets
- Use WebP for images where supported

## Security Considerations

### 1. Content Security Policy
Update CSP headers for WebAssembly:
```nginx
add_header Content-Security-Policy "
    default-src 'self';
    script-src 'self' 'wasm-unsafe-eval';
    worker-src 'self' blob:;
    style-src 'self' 'unsafe-inline';
" always;
```

### 2. API Authentication
- JWT tokens stored in memory (not localStorage)
- Secure cookie options for refresh tokens
- CORS properly configured for API endpoints

## Deployment Workflow

### Initial Setup
1. Create `server/client_files/` directory
2. Update nginx.conf with new location blocks
3. Update docker-compose.production.yml
4. Run export-to-prod script
5. Restart nginx container

### Regular Updates
1. Make changes in Godot project
2. Run `./scripts/export-to-prod.sh`
3. Script handles export, optimization, and deployment
4. Automatic rollback on failure

## Monitoring & Health Checks

### Client-Specific Metrics
- Page load time
- WebAssembly initialization time
- API response times from client perspective
- Client-side error tracking

### Health Check Endpoint
Add client health check:
```javascript
// In Godot client
func check_api_health():
    var response = await api_manager.health_check()
    return response.status == "healthy"
```

## Browser Compatibility

### Minimum Requirements
- **Chrome**: 91+
- **Firefox**: 89+
- **Safari**: 15.2+
- **Edge**: 91+

### Feature Detection
- WebAssembly support
- WebGL 2.0
- SharedArrayBuffer (optional with fallback)

## Troubleshooting Guide

### Common Issues

1. **"SharedArrayBuffer not defined"**
   - Solution: Ensure COOP/COEP headers are set
   - Alternative: Use single-threaded export

2. **Slow initial load**
   - Solution: Enable compression, use CDN
   - Check network tab for large assets

3. **CORS errors**
   - Solution: Verify nginx headers
   - Check API endpoint configuration

4. **PWA not installing**
   - Solution: Verify HTTPS, manifest.json served correctly
   - Check service worker registration

## Migration Timeline

### Phase 1: Development Testing
- Set up local nginx with client hosting
- Test CORS headers and WebAssembly loading
- Verify API integration

### Phase 2: Staging Deployment
- Deploy to staging server
- Test with real SSL certificates
- Performance benchmarking

### Phase 3: Production Rollout
- Deploy during low-traffic period
- Monitor error rates and performance
- Have rollback plan ready

## Future Enhancements

### Planned Improvements
1. CDN integration for static assets
2. WebSocket support for real-time features
3. A/B testing framework
4. Client-side analytics integration
5. Automated performance testing

### Optimization Opportunities
1. Asset bundling and tree-shaking
2. Texture atlas optimization
3. Audio sprite sheets
4. Lazy loading for game scenes

## Conclusion

This hosting strategy leverages the existing Django/Nginx infrastructure while properly serving the Godot web client. The approach ensures optimal performance, security, and maintainability while supporting progressive enhancement through PWA features.

Key benefits:
- Single domain for entire application
- Unified SSL/TLS management
- Simplified CORS configuration
- Integrated monitoring and logging
- Zero-downtime deployments