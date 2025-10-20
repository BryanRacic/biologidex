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

        # Graph/Evolutionary Tree
        path('graph/', include('graph.urls')),
    ])),
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
