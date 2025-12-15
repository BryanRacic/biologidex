# BiologiDex Server Security & Code Audit Report

**Audit Date:** December 15, 2025
**Auditor:** Claude (AI Code Auditor)
**Scope:** `/server/` directory - Django REST Framework backend
**Target Environment:** Pre-beta, transitioning from private server to cloud hosting

---

## Executive Summary

This audit identified **4 critical**, **8 high**, **12 medium**, and **6 low** severity issues across security, performance, and code quality domains. The codebase demonstrates solid foundational architecture with proper use of Django REST Framework, JWT authentication, and Celery async processing. However, several security vulnerabilities require immediate attention before beta release, particularly around authorization bypass, exposed endpoints, and inadequate input validation.

### Risk Summary

| Severity | Count | Immediate Action Required |
|----------|-------|---------------------------|
| Critical | 4 | Yes - Block deployment |
| High | 8 | Yes - Fix before beta |
| Medium | 12 | Recommended before beta |
| Low | 6 | Address during beta |

---

## Critical Security Vulnerabilities

### CRIT-001: Authorization Bypass in DexCompatibleImageView

**File:** `vision/views.py:243-271`
**Severity:** Critical
**OWASP Category:** A01:2021 - Broken Access Control

**Description:**
The `DexCompatibleImageView` explicitly contains a TODO comment stating permission checks are needed but currently serves images to ANY user who knows the job UUID. This allows unauthorized access to potentially private user images.

```python
class DexCompatibleImageView(View):
    """
    TODO: Add proper IAM/permission checks:
    - Verify user owns the image OR
    - Image is from a public dex entry OR
    - User has friend access to the owner
    """

    def get(self, request, job_id):
        # No authentication check
        # No authorization check
        job = AnalysisJob.objects.get(id=job_id)
        # ... serves image directly
```

**Impact:**
- Any user can access any other user's uploaded images by guessing/enumerating UUIDs
- Privacy breach for all user-uploaded content
- Potential legal liability for PII exposure

**Remediation:**
1. Add `@login_required` decorator or convert to DRF ViewSet
2. Implement ownership/friend/visibility check before serving
3. Consider signed URLs with expiration for image access

---

### CRIT-002: Metrics Endpoint Exposed Without Authentication

**File:** `biologidex/urls.py:68-70`
**Severity:** Critical
**OWASP Category:** A01:2021 - Broken Access Control

**Description:**
The `/metrics/` Prometheus endpoint exposes sensitive system information including active users count, database statistics, request timing, and Celery task information without any authentication.

```python
urlpatterns += [
    path('metrics/', metrics_view, name='prometheus-metrics'),
]
```

**Impact:**
- Reconnaissance information for attackers (user counts, system load patterns)
- Internal application metrics exposed publicly
- Database query patterns revealed

**Remediation:**
1. Add authentication requirement or IP whitelist
2. Move metrics to internal-only port (not exposed via nginx)
3. Use bearer token authentication for metrics scraping

---

### CRIT-003: Health Endpoints Leak System State

**Files:** `biologidex/health.py`, `biologidex/urls.py:59-63`
**Severity:** Critical
**OWASP Category:** A01:2021 - Broken Access Control

**Description:**
The `/api/v1/health/` endpoint returns detailed system state including database health, Redis status, Celery worker count, GCS bucket name, and debug mode status without authentication.

```python
health_status['metadata'] = {
    'environment': settings.ENVIRONMENT,
    'version': settings.VERSION,
    'debug': settings.DEBUG,  # Sensitive
}
# Also exposes: GCS bucket name, worker counts, response times
```

**Impact:**
- Infrastructure enumeration
- Exposes cloud resource identifiers (GCS bucket)
- Debug mode leakage aids attack planning

**Remediation:**
1. Create separate internal and external health endpoints
2. External: Only return `{"status": "ok"}`
3. Internal: Full details, IP-restricted or authenticated

---

### CRIT-004: Default Redis Password in Production Configuration

**File:** `docker-compose.production.yml:32`
**Severity:** Critical
**OWASP Category:** A07:2021 - Identification and Authentication Failures

**Description:**
Redis is configured with a weak default password that may be used if environment variable not set:

```yaml
command: redis-server --requirepass "${REDIS_PASSWORD:-defaultpass123}"
```

**Impact:**
- If `.env` file missing or REDIS_PASSWORD not set, default password used
- Redis contains session data, cached credentials, and task queue
- Attacker can inject malicious tasks, steal session data

**Remediation:**
1. Remove default password - require explicit configuration
2. Add startup validation that required secrets are set
3. Use secrets management (Vault, AWS Secrets Manager) for cloud migration

---

## High Severity Issues

### HIGH-001: CORS Allows All Private Network IPs in Production

**File:** `biologidex/settings/base.py:191-198`
**Severity:** High
**OWASP Category:** A05:2021 - Security Misconfiguration

**Description:**
CORS regex patterns allowing all LAN IP ranges are defined in `base.py` and inherited by production settings:

```python
CORS_ALLOWED_ORIGIN_REGEXES = [
    r"^https?://192\.168\.\d{1,3}\.\d{1,3}(:\d+)?$",
    r"^https?://10\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?$",
    r"^https?://172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}(:\d+)?$",
]
```

**Impact:**
- In cloud environments, other tenants' VMs may be on same private network
- Cross-origin requests from any private IP accepted
- DNS rebinding attacks possible

**Remediation:**
1. Remove LAN patterns from production settings
2. Only allow specific production domains
3. Override `CORS_ALLOWED_ORIGIN_REGEXES = []` in production.py

---

### HIGH-002: API Documentation Exposed in Production

**File:** `biologidex/urls.py:24-26`
**Severity:** High
**OWASP Category:** A05:2021 - Security Misconfiguration

**Description:**
Swagger UI and ReDoc are available without authentication:

```python
path('api/docs/', SpectacularSwaggerView.as_view(url_name='schema')),
path('api/redoc/', SpectacularRedocView.as_view(url_name='redoc')),
path('api/schema/', SpectacularAPIView.as_view(), name='schema'),
```

**Impact:**
- Full API schema exposed to attackers
- Endpoint enumeration trivial
- Request/response formats revealed for fuzzing

**Remediation:**
1. Disable in production or require authentication
2. Add IP whitelist for internal documentation access
3. Set `SERVE_INCLUDE_SCHEMA = False` for production

---

### HIGH-003: Insufficient Authorization in Batch Sync Endpoint

**File:** `dex/views.py:450-523`
**Severity:** High
**OWASP Category:** A01:2021 - Broken Access Control

**Description:**
The `batch_sync` endpoint allows requesting dex entries for any user ID. While it checks friendship status, rejection only returns an error in the results rather than preventing access:

```python
if not Friendship.are_friends(request.user, target_user):
    results[user_id] = {'error': 'Not friends with this user'}
    continue  # Still processes other requests
```

**Impact:**
- User enumeration via timing attacks (friend check vs. not found)
- Potential data leakage in error handling paths
- No rate limiting on batch requests

**Remediation:**
1. Validate all user_ids upfront before processing
2. Return 403 Forbidden for unauthorized access attempts
3. Add rate limiting to batch endpoints

---

### HIGH-004: User Registration Lacks Rate Limiting

**File:** `accounts/views.py:30-63`
**Severity:** High
**OWASP Category:** A07:2021 - Identification and Authentication Failures

**Description:**
User registration endpoint allows unlimited attempts:

```python
def get_permissions(self):
    if self.action == 'create':
        return [permissions.AllowAny()]  # No throttling applied
```

**Impact:**
- Bot account creation
- Username enumeration
- Resource exhaustion (database, storage)

**Remediation:**
1. Apply stricter rate limiting (e.g., 5/hour per IP)
2. Add CAPTCHA verification
3. Implement email verification before activation

---

### HIGH-005: JWT Signing Key Same as Django SECRET_KEY

**File:** `biologidex/settings/base.py:179-180`
**Severity:** High
**OWASP Category:** A02:2021 - Cryptographic Failures

**Description:**
JWT tokens are signed using the Django SECRET_KEY:

```python
SIMPLE_JWT = {
    'SIGNING_KEY': SECRET_KEY,
}
```

**Impact:**
- If SECRET_KEY is compromised, both session and JWT auth compromised
- SECRET_KEY may be logged or exposed more easily than JWT-specific key
- No rotation capability without invalidating all sessions

**Remediation:**
1. Use separate `JWT_SIGNING_KEY` environment variable
2. Implement key rotation strategy
3. Consider asymmetric keys (RS256) for microservices architecture

---

### HIGH-006: Admin Panel Not IP-Restricted

**File:** `nginx/nginx.conf:102-109`
**Severity:** High
**OWASP Category:** A01:2021 - Broken Access Control

**Description:**
Admin panel is publicly accessible:

```nginx
location /admin/ {
    # No IP restriction
    proxy_pass http://biologidex_backend;
}
```

**Impact:**
- Brute force attacks on admin credentials
- Credential stuffing attacks
- Admin interface vulnerabilities exposed

**Remediation:**
1. Add IP whitelist for admin access
2. Implement 2FA for admin accounts
3. Consider separate admin domain with VPN requirement

---

### HIGH-007: File Upload Validation Insufficient

**File:** `images/views.py:31-114`
**Severity:** High
**OWASP Category:** A04:2021 - Insecure Design

**Description:**
Image uploads have minimal validation:

```python
def create(self, request):
    input_serializer = ImageConversionCreateSerializer(data=request.data)
    # Only validates via serializer
    image_file = input_serializer.validated_data['image']
    # No virus scanning
    # No magic byte validation
    # No malicious image detection
```

**Impact:**
- Malformed images could exploit PIL vulnerabilities
- Image bombs (decompression attacks)
- Polyglot files (image + executable)

**Remediation:**
1. Validate file magic bytes match claimed type
2. Implement file size limits per dimension (not just file size)
3. Consider virus scanning for uploaded content
4. Use isolated image processing environment

---

### HIGH-008: Celery Running as Root

**File:** `docker-compose.production.yml:89`
**Severity:** High
**OWASP Category:** A05:2021 - Security Misconfiguration

**Description:**
Celery worker configured to run as root:

```yaml
C_FORCE_ROOT: "1"  # Allow celery to run as root in container
```

**Impact:**
- Container escape more impactful
- File system access unrestricted
- Principle of least privilege violated

**Remediation:**
1. Create non-root user in Dockerfile
2. Remove `C_FORCE_ROOT` setting
3. Run all containers with `user:` directive

---

## Medium Severity Issues

### MED-001: Request Logging May Contain Sensitive Data

**File:** `biologidex/middleware/request_logging.py`
**Severity:** Medium

While passwords are redacted, other sensitive data may be logged:
- Full request/response bodies
- User-generated content (notes, etc.)
- Query parameters

**Remediation:** Implement field-level redaction list, reduce logging verbosity in production.

---

### MED-002: N+1 Query Pattern in Friends Overview

**File:** `dex/views.py:418-447`
**Severity:** Medium

```python
for friend in friends:
    entry_count = self.queryset.filter(owner=friend, ...)  # Query per friend
    latest_entry = self.queryset.filter(owner=friend, ...)  # Another query per friend
```

**Impact:** Performance degrades linearly with friend count.

**Remediation:** Use aggregation and subqueries to batch queries.

---

### MED-003: Checksum Calculation in Serializer

**File:** `dex/serializers.py:354-376`
**Severity:** Medium

```python
def get_image_checksum(self, obj):
    sha256 = hashlib.sha256()
    for chunk in image_file.chunks():
        sha256.update(chunk)
```

**Impact:** Blocks request for large images, I/O intensive.

**Remediation:** Pre-calculate and store checksums on upload.

---

### MED-004: Print Statements in Production Code

**Files:** Multiple (dex/views.py, vision/tasks.py, etc.)
**Severity:** Medium

```python
print(f"[DexCache] Invalidated cache for user {user_id}")
```

**Impact:** Logs scattered, inconsistent formatting, potential data leakage.

**Remediation:** Replace all `print()` with proper `logger` calls.

---

### MED-005: Missing Content Security Policy

**File:** `nginx/nginx.conf`
**Severity:** Medium

No CSP headers configured in active HTTP section.

**Remediation:** Add CSP headers restricting script/style sources.

---

### MED-006: HTTPS Section Commented Out

**File:** `nginx/nginx.conf:165-280`
**Severity:** Medium

Full HTTPS configuration exists but is commented out, relying on Cloudflare Tunnel.

**Impact:** No defense in depth, single point of failure.

**Remediation:** Enable HTTPS locally, use Cloudflare as CDN layer.

---

### MED-007: No Rate Limiting on Friend Requests

**File:** `social/views.py:74-110`
**Severity:** Medium

Friend request endpoint has no throttling, enabling harassment/spam.

**Remediation:** Add rate limiting (e.g., 20 requests/day).

---

### MED-008: Visibility Timeout Not Configured for Long Tasks

**File:** `biologidex/settings/base.py:200-222`
**Severity:** Medium

No `visibility_timeout` configured for Redis broker. Tasks with long processing times may be redelivered.

**Remediation:** Set `CELERY_BROKER_TRANSPORT_OPTIONS = {'visibility_timeout': 3600}`.

---

### MED-009: No Database Connection Pooling in Production

**File:** `biologidex/settings/production.py:62-63`
**Severity:** Medium

```python
# DATABASES['default']['CONN_MAX_AGE'] = None  # Commented out
```

**Impact:** Each request creates new database connection.

**Remediation:** Enable pgBouncer connection or set `CONN_MAX_AGE`.

---

### MED-010: Circular Import Workarounds

**Files:** Multiple (dex/signals.py, animals/services.py, etc.)
**Severity:** Medium

```python
# Import here to avoid circular dependency
from graph.services_dynamic import DynamicTaxonomicTreeService
```

**Impact:** Code maintainability, startup order issues.

**Remediation:** Refactor to use dependency injection or signals properly.

---

### MED-011: Legacy API Support Increases Attack Surface

**Files:** `vision/views.py`, `vision/serializers.py`, `vision/models.py`
**Severity:** Medium

Both legacy `image` upload and new `conversion_id` workflows supported:

```python
# DEPRECATED: Legacy direct upload
image = models.ImageField(...)
```

**Impact:** Doubled attack surface, maintenance burden.

**Remediation:** Set deprecation timeline, remove legacy endpoints before GA.

---

### MED-012: Error Messages May Leak Information

**File:** Multiple views
**Severity:** Medium

Detailed error messages returned to client:

```python
return Response({'error': f'Failed to parse last_sync: {str(e)}'})
```

**Impact:** Stack traces or internal details may leak.

**Remediation:** Use generic error messages, log details server-side.

---

## Low Severity Issues

### LOW-001: Default Pagination Size May Be Too High

**File:** `biologidex/settings/base.py:149`

`PAGE_SIZE = 50` may return excessive data for mobile clients.

---

### LOW-002: Session Cookie Settings Not Hardened

Missing `SESSION_COOKIE_HTTPONLY`, `SESSION_COOKIE_SAMESITE` explicit settings.

---

### LOW-003: No Explicit Content-Type Validation

Upload endpoints don't validate `Content-Type` header matches actual content.

---

### LOW-004: Gunicorn Worker Count Not Environment-Aware

**File:** `gunicorn.conf.py:13`

```python
workers = multiprocessing.cpu_count() * 2 + 1
```

May be excessive in containerized environment with CPU limits.

---

### LOW-005: No Request ID Tracing

No correlation IDs for request tracing across services.

---

### LOW-006: Test Users Auto-Seeded in Development

**File:** `biologidex/settings/development.py:75`

```python
AUTO_SEED_TEST_USERS = True
```

Ensure this cannot be accidentally enabled in production.

---

## Performance Optimization Recommendations

### PERF-001: Add Database Indexes

Missing indexes that would improve query performance:

```python
# social/models.py - Add composite index
models.Index(fields=['from_user', 'to_user', 'status']),

# dex/models.py - Already has good indexes
```

### PERF-002: Implement Query Optimization

```python
# Instead of:
for friend in friends:
    count = DexEntry.objects.filter(owner=friend).count()

# Use:
counts = DexEntry.objects.filter(
    owner__in=friend_ids
).values('owner').annotate(count=Count('id'))
```

### PERF-003: Async Image Processing

Move image processing to dedicated Celery queue with concurrency limits.

### PERF-004: Implement Response Caching

Add ETags and Last-Modified headers for cacheable endpoints.

---

## Cloud Migration Recommendations

### Infrastructure Security

1. **Secrets Management**: Migrate from `.env` files to cloud secrets manager (AWS Secrets Manager, GCP Secret Manager)

2. **Network Security**:
   - Place database in private subnet
   - Use VPC service endpoints for GCS
   - Implement WAF for API gateway

3. **Container Security**:
   - Use distroless or minimal base images
   - Scan images for vulnerabilities (Trivy, Snyk)
   - Implement pod security policies

4. **Monitoring**:
   - Centralized logging (CloudWatch, Stackdriver)
   - APM integration (Datadog, New Relic)
   - Security event alerting

### Compliance Preparation

1. Enable audit logging for all data access
2. Implement data retention policies
3. Add user consent tracking for GDPR
4. Document data processing activities

---

## Remediation Priority

### Before Beta Release (Critical)

1. [ ] Fix CRIT-001: Add authorization to DexCompatibleImageView
2. [ ] Fix CRIT-002: Secure metrics endpoint
3. [ ] Fix CRIT-003: Reduce health endpoint information leakage
4. [ ] Fix CRIT-004: Remove default Redis password
5. [ ] Fix HIGH-001: Remove LAN CORS patterns from production
6. [ ] Fix HIGH-002: Restrict API documentation access
7. [ ] Fix HIGH-006: IP-restrict admin panel
8. [ ] Fix HIGH-008: Run Celery as non-root

### During Beta (High/Medium)

1. [ ] Fix HIGH-003: Improve batch_sync authorization
2. [ ] Fix HIGH-004: Add registration rate limiting
3. [ ] Fix HIGH-005: Separate JWT signing key
4. [ ] Fix HIGH-007: Enhance file upload validation
5. [ ] Fix MED-001 through MED-012

### Before GA (Low/Optimization)

1. [ ] Address LOW-001 through LOW-006
2. [ ] Implement PERF-001 through PERF-004
3. [ ] Complete cloud migration security hardening

---

## References

- [OWASP Django Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Django_Security_Cheat_Sheet.html)
- [OWASP Django REST Framework Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Django_REST_Framework_Cheat_Sheet.html)
- [Django Security Documentation](https://docs.djangoproject.com/en/5.2/topics/security/)
- [Celery Security Best Practices](https://docs.celeryq.dev/en/stable/userguide/security.html)
- [Django Best Practices: Security](https://learndjango.com/tutorials/django-best-practices-security)

---

*This audit was performed by automated code analysis and may not capture all vulnerabilities. A penetration test is recommended before production deployment.*
