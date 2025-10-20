"""
URL routing for vision app.
"""
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import AnalysisJobViewSet

router = DefaultRouter()
router.register(r'jobs', AnalysisJobViewSet, basename='analysisjob')

urlpatterns = [
    path('', include(router.urls)),
]
