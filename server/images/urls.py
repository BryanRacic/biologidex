"""
URL configuration for images app.
"""
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import ImageConversionViewSet

router = DefaultRouter()
router.register(r'convert', ImageConversionViewSet, basename='image-conversion')

urlpatterns = [
    path('', include(router.urls)),
]
