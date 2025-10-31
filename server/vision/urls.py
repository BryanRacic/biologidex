"""
URL routing for vision app.
"""
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import AnalysisJobViewSet, DexCompatibleImageView

router = DefaultRouter()
router.register(r'jobs', AnalysisJobViewSet, basename='analysisjob')

urlpatterns = [
    path('', include(router.urls)),
    path('jobs/<uuid:job_id>/dex-image/', DexCompatibleImageView.as_view(), name='dex-compatible-image'),
]
