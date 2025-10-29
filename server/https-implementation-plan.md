# HTTPS Implementation Plan for BiologiDex

## Executive Summary

The current 502 Bad Gateway error when accessing biologidex.io via HTTPS is caused by a **critical misconfiguration** in the Cloudflare tunnel routing. The tunnel is pointing directly to Django (port 8000) instead of nginx (port 80), bypassing the reverse proxy entirely. This document provides a step-by-step plan to fix the issue and properly enable HTTPS.

**Time to Resolution: ~30 minutes**

---

## Root Cause Analysis

### Primary Issue
The Cloudflare tunnel configuration at `/etc/cloudflared/config.yml` (or in the Cloudflare dashboard) routes traffic to:
- **Current (INCORRECT)**: `http://localhost:8000` (Django directly)
- **Required (CORRECT)**: `http://localhost:80` (nginx reverse proxy)

### Why This Causes 502 Bad Gateway
1. Cloudflare tunnel delivers HTTP traffic expecting port 80
2. Configuration points to port 8000 (Django)
3. Django expects to be behind nginx proxy with proper headers
4. Missing proxy headers cause request handling errors
5. Result: 502 Bad Gateway

---

## Architecture Overview

### How HTTPS Should Work with Cloudflare Tunnel

```
Internet Users
    ↓
biologidex.io (HTTPS - Cloudflare handles SSL)
    ↓
Cloudflare Tunnel (encrypted tunnel to your server)
    ↓
localhost:80 (nginx - receives HTTP inside tunnel)
    ↓
├── / → Godot web client files
├── /api/ → Proxy to Django (port 8000)
├── /admin/ → Proxy to Django (port 8000)
└── /static/ → Django static files
```

**Key Point**: Cloudflare handles all SSL/TLS encryption. Your server only needs HTTP internally.

---

## Implementation Steps

### Phase 1: Fix Critical Configuration (Immediate - 5 minutes)

#### Step 1.1: Update Cloudflare Tunnel Configuration

**Option A: Via Cloudflare Dashboard (Recommended)**
1. Log into Cloudflare Dashboard
2. Navigate to Zero Trust → Networks → Tunnels
3. Find your `biologidex` tunnel
4. Click Configure → Public Hostname
5. Edit the hostname for `biologidex.io`
6. Change Service URL from `http://localhost:8000` to `http://localhost:80`
7. Save changes

**Option B: Via Local Config File**
```bash
# If using config file at /etc/cloudflared/config.yml
sudo nano /etc/cloudflared/config.yml
```

Change:
```yaml
ingress:
  - hostname: biologidex.io
    service: http://localhost:8000  # WRONG
```

To:
```yaml
ingress:
  - hostname: biologidex.io
    service: http://localhost:80     # CORRECT
```

Then restart the tunnel:
```bash
sudo systemctl restart cloudflared
```

#### Step 1.2: Verify Services Are Running
```bash
cd /home/bryan/Development/Git/biologidex/server
docker-compose -f docker-compose.production.yml ps

# Should show:
# biologidex-nginx-1    running    0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
# biologidex-web-1      running    127.0.0.1:8000->8000/tcp
```

#### Step 1.3: Test the Fix
```bash
# Test locally
curl -I http://localhost:80
# Should return 200 OK

# Test via tunnel (wait 30 seconds for changes to propagate)
curl -I https://biologidex.io
# Should return 200 OK
```

---

### Phase 2: Fix Environment Configuration (10 minutes)

#### Step 2.1: Update .env File

Edit `/home/bryan/Development/Git/biologidex/server/.env`:

```bash
# PRODUCTION SETTINGS
DEBUG=False
DJANGO_SETTINGS_MODULE=biologidex.settings.production_local

# Docker service names (not localhost)
DB_HOST=db
REDIS_HOST=redis

# Keep these as-is
ALLOWED_HOSTS=localhost,127.0.0.1,biologidex.io
SECRET_KEY=[your-secret-key]
DB_PASSWORD=[your-db-password]
OPENAI_API_KEY=[your-api-key]

# Enable HTTPS redirect (optional, see note below)
SECURE_SSL_REDIRECT=False  # Keep False for Cloudflare tunnel
```

**Note on SECURE_SSL_REDIRECT**: Keep this `False` when using Cloudflare tunnel. The tunnel already enforces HTTPS at the edge, and enabling this could cause redirect loops.

#### Step 2.2: Restart Services with New Configuration
```bash
cd /home/bryan/Development/Git/biologidex/server

# Restart to apply new environment variables
docker-compose -f docker-compose.production.yml down
docker-compose -f docker-compose.production.yml up -d

# Check logs for any errors
docker-compose -f docker-compose.production.yml logs -f --tail=50
```

---

### Phase 3: Validate and Monitor (5 minutes)

#### Step 3.1: Health Check Endpoints
```bash
# Check nginx is responding
curl http://localhost:80/health/
# Expected: {"status": "ok"}

# Check Django API health
curl http://localhost:80/api/v1/health/
# Expected: JSON with service statuses

# Check via HTTPS domain
curl https://biologidex.io/health/
curl https://biologidex.io/api/v1/health/
```

#### Step 3.2: Verify Client Access
1. Open browser to https://biologidex.io
2. Should load Godot web client
3. Check browser console for any errors (F12 → Console)
4. Test API endpoint: https://biologidex.io/api/v1/

#### Step 3.3: Monitor Logs
```bash
# Watch for errors
docker-compose -f docker-compose.production.yml logs -f nginx
docker-compose -f docker-compose.production.yml logs -f web
```

---

### Phase 4: Optional Enhancements (Future)

#### Option A: Clean Up Nginx Configuration
Since you're using Cloudflare tunnel, you can remove the commented HTTPS block from nginx.conf to reduce confusion:

1. Edit `/home/bryan/Development/Git/biologidex/server/nginx/nginx.conf`
2. Delete lines 159-273 (entire commented HTTPS server block)
3. Remove port 443 exposure from docker-compose.production.yml (line 126)
4. Restart nginx: `docker-compose -f docker-compose.production.yml restart nginx`

#### Option B: Add Security Headers (Recommended)
Add these to nginx.conf HTTP server block (after line 71):
```nginx
# Security headers for Cloudflare tunnel setup
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "DENY" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
```

#### Option C: Enable Cloudflare Security Features
In Cloudflare dashboard for biologidex.io:
1. SSL/TLS → Overview → Set to "Full (strict)"
2. SSL/TLS → Edge Certificates → Enable "Always Use HTTPS"
3. SSL/TLS → Edge Certificates → Enable "Automatic HTTPS Rewrites"
4. Security → Settings → Set Security Level to "Medium"
5. Speed → Optimization → Enable Auto Minify for JS/CSS/HTML

---

## Troubleshooting Guide

### Issue: Still Getting 502 Bad Gateway

**Check 1: Verify tunnel configuration**
```bash
# Check if tunnel is pointing to correct port
sudo cloudflared tunnel info biologidex
```

**Check 2: Ensure nginx is running**
```bash
docker-compose -f docker-compose.production.yml ps nginx
# Should show "Up" status
```

**Check 3: Test local routing**
```bash
# From host machine
curl -v http://localhost:80
curl -v http://localhost:80/api/v1/
```

### Issue: Redirect Loops

**Cause**: `SECURE_SSL_REDIRECT=True` in Django
**Fix**: Set `SECURE_SSL_REDIRECT=False` in .env file

### Issue: Mixed Content Warnings

**Cause**: Resources loading over HTTP
**Fix**: Ensure all API calls use relative URLs (`/api/`) not absolute (`http://...`)

### Issue: Cannot Connect to Database

**Cause**: Using `localhost` instead of Docker service names
**Fix**: Ensure .env has `DB_HOST=db` and `REDIS_HOST=redis`

---

## Verification Checklist

- [ ] Cloudflare tunnel points to `http://localhost:80` (not 8000)
- [ ] Docker services are running (`docker-compose ps`)
- [ ] nginx responds on port 80 (`curl http://localhost:80`)
- [ ] HTTPS works: `https://biologidex.io` loads without errors
- [ ] API accessible: `https://biologidex.io/api/v1/` returns API response
- [ ] Godot client loads at root path
- [ ] No 502 errors in browser or logs
- [ ] .env file uses production settings
- [ ] `DB_HOST=db` and `REDIS_HOST=redis` in .env

---

## Quick Commands Reference

```bash
# Restart everything
cd /home/bryan/Development/Git/biologidex/server
docker-compose -f docker-compose.production.yml down
docker-compose -f docker-compose.production.yml up -d

# Check status
docker-compose -f docker-compose.production.yml ps
docker-compose -f docker-compose.production.yml logs --tail=100

# Test endpoints
curl -I https://biologidex.io
curl https://biologidex.io/api/v1/health/

# Monitor in real-time
./scripts/monitor.sh

# Full diagnostics
./scripts/diagnose.sh
```

---

## Summary

The HTTPS implementation is actually already handled by Cloudflare. The only required fix is updating the tunnel configuration to point to nginx (port 80) instead of Django (port 8000). This is a simple configuration change that should resolve the 502 Bad Gateway error immediately.

No SSL certificates, Let's Encrypt setup, or nginx HTTPS configuration is needed when using Cloudflare tunnel - it handles all the SSL/TLS complexity at the edge.

**Total time to implement: ~30 minutes**
**Risk level: Low**
**Downtime: < 1 minute during service restart**