"""
Production settings for local server deployment with Cloudflare tunneling
Inherits from base settings and overrides for production environment
"""
import os
from .base import *

# Environment identifier
ENVIRONMENT = 'production_local'
VERSION = os.getenv('APP_VERSION', '1.0.0')

# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY = os.getenv('SECRET_KEY')
if not SECRET_KEY:
    raise ValueError("SECRET_KEY environment variable must be set in production")

# SECURITY WARNING: don't run with debug turned on in production!
DEBUG = False

# Allowed hosts
ALLOWED_HOSTS = os.getenv('ALLOWED_HOSTS', 'localhost,127.0.0.1').split(',')

# Database configuration with connection pooling
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.getenv('DB_NAME', 'biologidex'),
        'USER': os.getenv('DB_USER', 'biologidex'),
        'PASSWORD': os.getenv('DB_PASSWORD'),
        'HOST': os.getenv('DB_HOST', 'localhost'),
        'PORT': os.getenv('DB_PORT', '5432'),
        'CONN_MAX_AGE': 600,  # Connection pooling
        'OPTIONS': {
            'connect_timeout': 10,
            'options': '-c statement_timeout=30000',  # 30 second statement timeout
        },
        'ATOMIC_REQUESTS': True,  # Wrap each request in a transaction
    }
}

# Redis Cache configuration
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.redis.RedisCache',
        'LOCATION': f"redis://:{os.getenv('REDIS_PASSWORD', '')}@{os.getenv('REDIS_HOST', 'localhost')}:{os.getenv('REDIS_PORT', '6379')}/1",
        'OPTIONS': {
            'CLIENT_CLASS': 'django_redis.client.DefaultClient',
            'CONNECTION_POOL_KWARGS': {
                'max_connections': 50,
                'retry_on_timeout': True,
            },
            'SOCKET_CONNECT_TIMEOUT': 5,
            'SOCKET_TIMEOUT': 5,
            'COMPRESSOR': 'django_redis.compressors.zlib.ZlibCompressor',
            'PARSER_CLASS': 'redis.connection.HiredisParser',
        },
        'KEY_PREFIX': 'biologidex',
        'VERSION': 1,
    }
}

# Security settings
SECURE_SSL_REDIRECT = os.getenv('SECURE_SSL_REDIRECT', 'False') == 'True'
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = 'DENY'
SECURE_HSTS_SECONDS = 31536000  # 1 year
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True

# Session configuration
SESSION_ENGINE = 'django.contrib.sessions.backends.cache'
SESSION_CACHE_ALIAS = 'default'
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = 'Strict'
SESSION_COOKIE_AGE = 86400  # 24 hours

# CORS configuration
CORS_ALLOWED_ORIGINS = os.getenv('CORS_ALLOWED_ORIGINS', '').split(',') if os.getenv('CORS_ALLOWED_ORIGINS') else []
CORS_ALLOW_CREDENTIALS = True

# REST Framework settings
REST_FRAMEWORK['DEFAULT_RENDERER_CLASSES'] = [
    'rest_framework.renderers.JSONRenderer',  # Remove BrowsableAPIRenderer in production
]

# Enhanced throttling for production
REST_FRAMEWORK['DEFAULT_THROTTLE_RATES'] = {
    'anon': os.getenv('THROTTLE_ANON_RATE', '100/hour'),
    'user': os.getenv('THROTTLE_USER_RATE', '1000/hour'),
    'upload': os.getenv('THROTTLE_UPLOAD_RATE', '20/hour'),
}

# Celery configuration for production
CELERY_TASK_ALWAYS_EAGER = False  # Run tasks asynchronously
CELERY_TASK_EAGER_PROPAGATES = False
CELERY_WORKER_POOL = 'prefork'  # Use prefork pool for better stability
CELERY_WORKER_PREFETCH_MULTIPLIER = 4
CELERY_TASK_SOFT_TIME_LIMIT = 1800  # 30 minutes soft limit
CELERY_TASK_TIME_LIMIT = 2100  # 35 minutes hard limit

# Static files configuration
STATIC_ROOT = os.path.join(BASE_DIR, 'static')
STATICFILES_STORAGE = 'django.contrib.staticfiles.storage.ManifestStaticFilesStorage'

# Media files configuration
MEDIA_ROOT = os.path.join(BASE_DIR, 'media')
MEDIA_URL = '/media/'

# Google Cloud Storage (optional, for media files)
if os.getenv('GCS_BUCKET_NAME'):
    DEFAULT_FILE_STORAGE = 'storages.backends.gcloud.GoogleCloudStorage'
    GS_BUCKET_NAME = os.getenv('GCS_BUCKET_NAME')
    GS_PROJECT_ID = os.getenv('GCS_PROJECT_ID')
    GS_DEFAULT_ACL = 'publicRead'
    GS_FILE_OVERWRITE = False
    GS_MAX_MEMORY_SIZE = 5 * 1024 * 1024  # 5MB
    GS_BLOB_CHUNK_SIZE = 1024 * 1024  # 1MB chunks
    GS_CREDENTIALS = service_account.Credentials.from_service_account_file(
        os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
    ) if os.getenv('GOOGLE_APPLICATION_CREDENTIALS') else None

# Email configuration
EMAIL_BACKEND = 'django.core.mail.backends.smtp.EmailBackend'
EMAIL_HOST = os.getenv('EMAIL_HOST', 'smtp.gmail.com')
EMAIL_PORT = int(os.getenv('EMAIL_PORT', '587'))
EMAIL_USE_TLS = os.getenv('EMAIL_USE_TLS', 'True') == 'True'
EMAIL_HOST_USER = os.getenv('EMAIL_HOST_USER', '')
EMAIL_HOST_PASSWORD = os.getenv('EMAIL_HOST_PASSWORD', '')
DEFAULT_FROM_EMAIL = os.getenv('DEFAULT_FROM_EMAIL', 'noreply@biologidex.com')
SERVER_EMAIL = DEFAULT_FROM_EMAIL

# Logging configuration for production
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'verbose': {
            'format': '{levelname} {asctime} {module} {process:d} {thread:d} {message}',
            'style': '{',
            'datefmt': '%Y-%m-%d %H:%M:%S'
        },
        'json': {
            '()': 'pythonjsonlogger.jsonlogger.JsonFormatter',
            'format': '%(asctime)s %(name)s %(levelname)s %(message)s'
        },
    },
    'filters': {
        'require_debug_false': {
            '()': 'django.utils.log.RequireDebugFalse',
        },
    },
    'handlers': {
        'file': {
            'level': 'INFO',
            'class': 'logging.handlers.RotatingFileHandler',
            'filename': os.getenv('LOG_FILE', '/app/logs/biologidex.log'),
            'maxBytes': 10485760,  # 10MB
            'backupCount': 10,
            'formatter': 'json',
        },
        'error_file': {
            'level': 'ERROR',
            'class': 'logging.handlers.RotatingFileHandler',
            'filename': '/app/logs/error.log',
            'maxBytes': 10485760,  # 10MB
            'backupCount': 10,
            'formatter': 'json',
        },
        'mail_admins': {
            'level': 'ERROR',
            'filters': ['require_debug_false'],
            'class': 'django.utils.log.AdminEmailHandler',
            'formatter': 'verbose',
        },
        'console': {
            'level': 'INFO',
            'class': 'logging.StreamHandler',
            'formatter': 'verbose'
        },
    },
    'loggers': {
        'django': {
            'handlers': ['file', 'error_file', 'console'],
            'level': 'INFO',
            'propagate': False,
        },
        'django.request': {
            'handlers': ['file', 'error_file', 'mail_admins'],
            'level': 'ERROR',
            'propagate': False,
        },
        'biologidex': {
            'handlers': ['file', 'error_file', 'console'],
            'level': os.getenv('LOG_LEVEL', 'INFO'),
            'propagate': False,
        },
        'vision': {
            'handlers': ['file', 'console'],
            'level': 'INFO',
            'propagate': False,
        },
        'celery': {
            'handlers': ['file', 'error_file', 'console'],
            'level': 'INFO',
            'propagate': False,
        },
    },
    'root': {
        'handlers': ['file', 'console'],
        'level': 'WARNING',
    },
}

# Sentry error tracking (optional)
if os.getenv('SENTRY_DSN'):
    import sentry_sdk
    from sentry_sdk.integrations.django import DjangoIntegration
    from sentry_sdk.integrations.celery import CeleryIntegration
    from sentry_sdk.integrations.redis import RedisIntegration

    sentry_sdk.init(
        dsn=os.getenv('SENTRY_DSN'),
        integrations=[
            DjangoIntegration(),
            CeleryIntegration(),
            RedisIntegration(),
        ],
        traces_sample_rate=0.1,  # 10% of transactions for performance monitoring
        send_default_pii=False,
        environment=ENVIRONMENT,
        release=VERSION,
    )

# Admin URL (security through obscurity)
ADMIN_URL = os.getenv('ADMIN_URL', 'admin/')

# Feature flags
AUTO_SEED_TEST_USERS = False
ENABLE_DEBUG_TOOLBAR = False
ENABLE_SILK_PROFILING = False

# File upload settings
MAX_UPLOAD_SIZE = int(os.getenv('MAX_UPLOAD_SIZE_MB', '10')) * 1024 * 1024
FILE_UPLOAD_MAX_MEMORY_SIZE = MAX_UPLOAD_SIZE
DATA_UPLOAD_MAX_MEMORY_SIZE = MAX_UPLOAD_SIZE

# Cache TTL settings
GRAPH_CACHE_TTL = int(os.getenv('GRAPH_CACHE_TTL', '120'))
ANIMAL_CACHE_TTL = int(os.getenv('ANIMAL_CACHE_TTL', '3600'))

# JWT settings
from datetime import timedelta

SIMPLE_JWT['ACCESS_TOKEN_LIFETIME'] = timedelta(
    minutes=int(os.getenv('JWT_ACCESS_TOKEN_LIFETIME_MINUTES', '60'))
)
SIMPLE_JWT['REFRESH_TOKEN_LIFETIME'] = timedelta(
    days=int(os.getenv('JWT_REFRESH_TOKEN_LIFETIME_DAYS', '7'))
)

# OpenAI settings
OPENAI_MODEL = os.getenv('OPENAI_MODEL', 'gpt-4o')

# Monitoring
PROMETHEUS_METRICS_ENABLED = os.getenv('PROMETHEUS_METRICS_ENABLED', 'True') == 'True'
HEALTH_CHECK_ENABLED = os.getenv('HEALTH_CHECK_ENABLED', 'True') == 'True'

# Add Prometheus middleware if metrics are enabled
if PROMETHEUS_METRICS_ENABLED:
    MIDDLEWARE.insert(0, 'biologidex.monitoring.PrometheusMiddleware')