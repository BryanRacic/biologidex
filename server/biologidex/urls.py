"""
BiologiDex URL Configuration
"""
from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from drf_spectacular.views import (
    SpectacularAPIView,
    SpectacularRedocView,
    SpectacularSwaggerView,
)

# Customize admin site
admin.site.site_header = "BiologiDex Administration"
admin.site.site_title = "BiologiDex Admin"
admin.site.index_title = "Welcome to BiologiDex Administration"

urlpatterns = [
    # Admin
    path('admin/', admin.site.urls),

    # API Documentation
    path('api/schema/', SpectacularAPIView.as_view(), name='schema'),
    path('api/docs/', SpectacularSwaggerView.as_view(url_name='schema'), name='swagger-ui'),
    path('api/redoc/', SpectacularRedocView.as_view(url_name='schema'), name='redoc'),

    # API v1 endpoints
    path('api/v1/', include([
        # Accounts & Authentication
        path('', include('accounts.urls')),

        # Animals
        path('', include('animals.urls')),

        # Dex Entries
        path('dex/', include('dex.urls')),

        # Social/Friends
        path('social/', include('social.urls')),

        # Vision/Analysis
        path('vision/', include('vision.urls')),

        # Graph/taxonomic Tree
        path('graph/', include('graph.urls')),

        # Taxonomy
        path('', include('taxonomy.urls')),
    ])),
]

# Health check endpoints (always available, even in production)
from biologidex.health import health_check, liveness_check, readiness_check

urlpatterns += [
    path('api/v1/health/', health_check, name='health-check'),
    path('health/', liveness_check, name='liveness-check'),
    path('ready/', readiness_check, name='readiness-check'),
]

# Prometheus metrics endpoint (production monitoring)
from biologidex.monitoring import metrics_view

urlpatterns += [
    path('metrics/', metrics_view, name='prometheus-metrics'),
]

# Media files (development only)
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)

    # Django Debug Toolbar
    try:
        import debug_toolbar
        urlpatterns = [
            path('__debug__/', include(debug_toolbar.urls)),
        ] + urlpatterns
    except ImportError:
        pass
