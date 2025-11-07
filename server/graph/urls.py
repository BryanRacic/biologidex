"""
URL routing for graph app.
"""
from django.urls import path
from .views import (
    # Legacy endpoints (kept for backwards compatibility)
    taxonomicTreeView,
    InvalidateCacheView,

    # New dynamic tree endpoints
    DynamicTreeView,
    TreeChunkView,
    TreeSearchView,
    TreeInvalidateView,
    FriendTreeCombinationView,
)

urlpatterns = [
    # Legacy endpoints (deprecated but kept for backwards compatibility)
    path('taxonomic-tree/', taxonomicTreeView.as_view(), name='taxonomic-tree-legacy'),
    path('invalidate-cache/', InvalidateCacheView.as_view(), name='invalidate-cache-legacy'),

    # New dynamic tree endpoints
    path('tree/', DynamicTreeView.as_view(), name='dynamic-tree'),
    path('tree/chunk/<int:x>/<int:y>/', TreeChunkView.as_view(), name='tree-chunk'),
    path('tree/search/', TreeSearchView.as_view(), name='tree-search'),
    path('tree/invalidate/', TreeInvalidateView.as_view(), name='tree-invalidate'),
    path('tree/friends/', FriendTreeCombinationView.as_view(), name='friend-tree-combination'),
]
