"""
URL routing for graph app.
"""
from django.urls import path
from .views import taxonomicTreeView, InvalidateCacheView

urlpatterns = [
    path('taxonomic-tree/', taxonomicTreeView.as_view(), name='taxonomic-tree'),
    path('invalidate-cache/', InvalidateCacheView.as_view(), name='invalidate-cache'),
]
