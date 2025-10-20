"""
Production settings for BiologiDex project.
"""
from .base import *
from google.oauth2 import service_account

# SECURITY WARNING: don't run with debug turned on in production!
DEBUG = False

# Security Settings
SECURE_SSL_REDIRECT = True
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = 'DENY'
SECURE_HSTS_SECONDS = 31536000  # 1 year
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True

# Google Cloud Storage for media files
if GCS_BUCKET_NAME and GOOGLE_APPLICATION_CREDENTIALS:
    GS_CREDENTIALS = service_account.Credentials.from_service_account_file(
        GOOGLE_APPLICATION_CREDENTIALS
    )
    DEFAULT_FILE_STORAGE = 'storages.backends.gcloud.GoogleCloudStorage'
    GS_DEFAULT_ACL = 'publicRead'
    GS_FILE_OVERWRITE = False
    GS_MAX_MEMORY_SIZE = 5242880  # 5MB
    MEDIA_URL = f'https://storage.googleapis.com/{GCS_BUCKET_NAME}/'
else:
    raise ValueError(
        "GCS_BUCKET_NAME and GOOGLE_APPLICATION_CREDENTIALS must be set in production"
    )

# Email backend for production (configure with your email service)
EMAIL_BACKEND = 'django.core.mail.backends.smtp.EmailBackend'
EMAIL_HOST = os.getenv('EMAIL_HOST', 'smtp.gmail.com')
EMAIL_PORT = int(os.getenv('EMAIL_PORT', '587'))
EMAIL_USE_TLS = os.getenv('EMAIL_USE_TLS', 'True') == 'True'
EMAIL_HOST_USER = os.getenv('EMAIL_HOST_USER')
EMAIL_HOST_PASSWORD = os.getenv('EMAIL_HOST_PASSWORD')
DEFAULT_FROM_EMAIL = os.getenv('DEFAULT_FROM_EMAIL', 'noreply@biologidex.com')

# Celery - async tasks in production
CELERY_TASK_ALWAYS_EAGER = False

# Stricter CORS in production
CORS_ALLOW_ALL_ORIGINS = False
CORS_ALLOWED_ORIGINS = os.getenv('CORS_ALLOWED_ORIGINS', '').split(',')

# Logging - less verbose in production
LOGGING['loggers']['django']['level'] = 'WARNING'
LOGGING['loggers']['biologidex']['level'] = 'INFO'
LOGGING['loggers']['vision']['level'] = 'INFO'

# Add production-specific logging handlers if needed
LOGGING['handlers']['sentry'] = {
    'class': 'logging.Handler',  # Replace with actual Sentry handler if using Sentry
}

# Database connection pooling (if using external connection pooler)
# DATABASES['default']['CONN_MAX_AGE'] = None  # Use persistent connections with pgBouncer

# Static files - use WhiteNoise or CDN in production
STATICFILES_STORAGE = 'django.contrib.staticfiles.storage.ManifestStaticFilesStorage'

# Admin site security
ADMIN_URL = os.getenv('ADMIN_URL', 'admin/')  # Can use custom admin URL for security