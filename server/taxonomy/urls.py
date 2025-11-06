# taxonomy/urls.py
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import TaxonomyViewSet, DataSourceViewSet

router = DefaultRouter()
router.register(r'taxonomy', TaxonomyViewSet, basename='taxonomy')
router.register(r'sources', DataSourceViewSet, basename='datasource')

urlpatterns = [
    path('', include(router.urls)),
]
