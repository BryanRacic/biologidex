"""
URL routing for graph app.
"""
from django.urls import path
from .views import EvolutionaryTreeView, InvalidateCacheView

urlpatterns = [
    path('evolutionary-tree/', EvolutionaryTreeView.as_view(), name='evolutionary-tree'),
    path('invalidate-cache/', InvalidateCacheView.as_view(), name='invalidate-cache'),
]
