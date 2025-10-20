"""
URL routing for dex app.
"""
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import DexEntryViewSet

router = DefaultRouter()
router.register(r'entries', DexEntryViewSet, basename='dexentry')

urlpatterns = [
    path('', include(router.urls)),
]
