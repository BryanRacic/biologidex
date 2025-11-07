# Dynamic User-Specific Taxonomic Tree - Updated Implementation Plan

## Overview

This document updates the original taxonomic tree implementation to support dynamic, user-specific trees based on dex entries. Each user sees a different tree based on the animals they and their friends have discovered. This creates a growing, evolving visualization unique to each user's journey.

## Key Requirements

1. **User-Specific Trees**: Each user's tree contains only animals in their dex + friends' dex
2. **Admin Global View**: Admins can view a tree compiled from ALL users' dex entries
3. **Friend Combinations**: Users can view trees combining their dex with selected friends
4. **Performance**: Must maintain 60 FPS with 100k+ nodes
5. **Caching**: User-specific caching with proper invalidation

## Server Architecture Updates

### 1. Enhanced Service Layer (`server/graph/services.py`)

```python
"""
Enhanced services for dynamic user-specific taxonomic trees.
"""
import logging
from typing import Dict, List, Set, Optional
from django.core.cache import cache
from django.conf import settings
from django.db.models import Count, Q, Prefetch
from django.contrib.auth import get_user_model
from animals.models import Animal
from dex.models import DexEntry
from social.models import Friendship

User = get_user_model()
logger = logging.getLogger(__name__)


class DynamicTaxonomicTreeService:
    """
    Service for generating dynamic, user-specific taxonomic trees.
    Supports multiple view modes: personal, friends, admin global.
    """

    # View modes
    MODE_PERSONAL = 'personal'  # User's dex only
    MODE_FRIENDS = 'friends'    # User + all friends
    MODE_SELECTED = 'selected'  # User + specific friends
    MODE_GLOBAL = 'global'      # All users (admin only)

    def __init__(self, user, mode=MODE_FRIENDS, selected_friend_ids=None):
        """
        Initialize service for dynamic tree generation.

        Args:
            user: Primary user viewing the tree
            mode: View mode (personal, friends, selected, global)
            selected_friend_ids: List of friend IDs for MODE_SELECTED
        """
        self.user = user
        self.mode = mode
        self.selected_friend_ids = selected_friend_ids or []

        # Precompute user scope
        self._compute_user_scope()

        # Initialize layout and chunking managers
        self.layout_engine = ReingoldTilfordLayout()
        self.chunk_manager = ChunkManager(chunk_size=2048)

    def _compute_user_scope(self):
        """Determine which users' dex entries to include."""
        if self.mode == self.MODE_PERSONAL:
            self.scoped_user_ids = [self.user.id]

        elif self.mode == self.MODE_FRIENDS:
            friend_ids = Friendship.get_friend_ids(self.user)
            self.scoped_user_ids = [self.user.id] + friend_ids

        elif self.mode == self.MODE_SELECTED:
            # Validate selected friends
            friend_ids = Friendship.get_friend_ids(self.user)
            valid_friend_ids = [
                fid for fid in self.selected_friend_ids
                if fid in friend_ids
            ]
            self.scoped_user_ids = [self.user.id] + valid_friend_ids

        elif self.mode == self.MODE_GLOBAL:
            # Admin only - include all users
            if not self.user.is_staff:
                raise PermissionError("Global view requires admin privileges")
            self.scoped_user_ids = None  # None means all users

        else:
            raise ValueError(f"Invalid mode: {self.mode}")

    def get_cache_key(self, suffix=''):
        """Generate cache key based on user scope."""
        if self.mode == self.MODE_GLOBAL:
            base_key = 'taxonomic_tree_global'
        elif self.mode == self.MODE_SELECTED:
            # Sort IDs for consistent cache keys
            id_hash = '_'.join(sorted(map(str, self.scoped_user_ids)))
            base_key = f'taxonomic_tree_selected_{id_hash}'
        else:
            base_key = f'taxonomic_tree_{self.mode}_{self.user.id}'

        return f'{base_key}{suffix}' if suffix else base_key

    def get_tree_data(self, use_cache=True):
        """
        Generate complete tree data with layout for current scope.

        Returns:
            Dict containing nodes, edges, layout, stats, and metadata
        """
        cache_key = self.get_cache_key()

        if use_cache:
            cached_data = cache.get(cache_key)
            if cached_data:
                logger.info(f"Returning cached tree for key {cache_key}")
                return cached_data

        logger.info(f"Generating tree for {self.mode} mode, user {self.user.id}")

        # Get animals in scope with optimized queries
        animals = self._get_scoped_animals()

        # Build hierarchical structure
        hierarchy = self._build_hierarchy(animals)

        # Generate layout positions
        positions = self.layout_engine.calculate_layout(hierarchy)

        # Build nodes with metadata
        nodes = self._build_nodes(animals, positions)

        # Build parent-child edges (true tree structure)
        edges = self._build_tree_edges(hierarchy)

        # Generate spatial chunks for progressive loading
        chunks = self.chunk_manager.generate_chunks(nodes, edges, positions)

        # Calculate statistics
        stats = self._calculate_stats(animals, nodes, edges)

        # Build response
        tree_data = {
            'nodes': nodes,
            'edges': edges,
            'layout': {
                'positions': positions,
                'world_bounds': self.chunk_manager.get_world_bounds(),
                'chunk_metadata': chunks,
                'chunk_size': {'width': 2048, 'height': 2048}
            },
            'stats': stats,
            'metadata': {
                'mode': self.mode,
                'user_id': str(self.user.id),
                'username': self.user.username,
                'scoped_users': len(self.scoped_user_ids) if self.scoped_user_ids else 'all',
                'total_nodes': len(nodes),
                'total_edges': len(edges),
                'cache_key': cache_key
            }
        }

        # Cache with appropriate TTL
        ttl = settings.GRAPH_CACHE_TTL if self.mode != self.MODE_GLOBAL else 300
        cache.set(cache_key, tree_data, ttl)

        return tree_data

    def _get_scoped_animals(self):
        """
        Get animals discovered by users in current scope.
        Highly optimized with prefetch and select_related.
        """
        # Build base query
        dex_query = DexEntry.objects.all()

        if self.scoped_user_ids is not None:
            dex_query = dex_query.filter(owner_id__in=self.scoped_user_ids)

        # Get unique animal IDs
        animal_ids = dex_query.values_list('animal_id', flat=True).distinct()

        # Fetch animals with optimized queries
        animals = Animal.objects.filter(
            id__in=animal_ids
        ).select_related(
            'created_by'  # Prefetch discoverer info
        ).prefetch_related(
            Prefetch(
                'dex_entries',
                queryset=DexEntry.objects.filter(
                    owner_id__in=self.scoped_user_ids
                ) if self.scoped_user_ids else DexEntry.objects.all(),
                to_attr='scoped_captures'
            )
        ).annotate(
            scoped_capture_count=Count(
                'dex_entries',
                filter=Q(dex_entries__owner_id__in=self.scoped_user_ids)
                if self.scoped_user_ids else Q()
            )
        )

        return list(animals)

    def _build_hierarchy(self, animals):
        """
        Build true taxonomic hierarchy from animals.
        Creates virtual nodes for missing taxonomic ranks.
        """
        hierarchy = {
            'id': 'root',
            'name': 'Life',
            'rank': 'root',
            'children': {},
            'animal_count': 0
        }

        ranks = ['kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species']

        for animal in animals:
            current_node = hierarchy
            path = []

            # Traverse/create path through taxonomy
            for rank in ranks:
                value = getattr(animal, rank if rank != 'class' else 'class_name', None)

                if value:
                    path.append(value)

                    if value not in current_node['children']:
                        # Create virtual node for taxonomic rank
                        current_node['children'][value] = {
                            'id': f"{rank}_{value}".replace(' ', '_'),
                            'name': value,
                            'rank': rank,
                            'path': '/'.join(path),
                            'children': {},
                            'animal_count': 0,
                            'animals': []
                        }

                    current_node = current_node['children'][value]
                    current_node['animal_count'] += 1

            # Add animal as leaf node
            current_node['animals'].append(animal)

        return hierarchy

    def _build_tree_edges(self, hierarchy):
        """
        Build parent-child edges from hierarchy.
        Creates true tree structure, not same_family groupings.
        """
        edges = []

        def traverse(node, parent_id=None):
            node_id = node['id']

            if parent_id:
                edges.append({
                    'source': parent_id,
                    'target': node_id,
                    'relationship': 'parent_child',
                    'rank_transition': f"{parent_id.split('_')[0]}_to_{node['rank']}"
                })

            # Process children
            for child in node.get('children', {}).values():
                traverse(child, node_id)

            # Process animal leaves
            for animal in node.get('animals', []):
                edges.append({
                    'source': node_id,
                    'target': str(animal.id),
                    'relationship': 'parent_child',
                    'rank_transition': f"{node['rank']}_to_species"
                })

        traverse(hierarchy)
        return edges

    def _build_nodes(self, animals, positions):
        """
        Build node list with full metadata.
        Includes capture info specific to current scope.
        """
        nodes = []

        # Build lookup for friend relationships
        if self.scoped_user_ids:
            friend_ids = set(Friendship.get_friend_ids(self.user))
        else:
            friend_ids = set()

        for animal in animals:
            # Get scoped capture info
            scoped_captures = getattr(animal, 'scoped_captures', [])
            captured_by_user = any(c.owner_id == self.user.id for c in scoped_captures)
            captured_by_friends = [
                {
                    'user_id': str(c.owner_id),
                    'username': c.owner.username,
                    'captured_at': c.created_at.isoformat()
                }
                for c in scoped_captures
                if c.owner_id != self.user.id and c.owner_id in friend_ids
            ]

            # Build node
            node = {
                'id': str(animal.id),
                'type': 'animal',  # Distinguish from virtual taxonomy nodes
                'scientific_name': animal.scientific_name,
                'common_name': animal.common_name,
                'creation_index': animal.creation_index,
                'taxonomy': {
                    'kingdom': animal.kingdom,
                    'phylum': animal.phylum,
                    'class': animal.class_name,
                    'order': animal.order,
                    'family': animal.family,
                    'genus': animal.genus,
                    'species': animal.species,
                },
                'position': positions.get(str(animal.id), [0, 0]),
                'captured_by_user': captured_by_user,
                'captured_by_friends': captured_by_friends,
                'capture_count': animal.scoped_capture_count,
                'conservation_status': animal.conservation_status,
                'verified': animal.verified,
                'discoverer': {
                    'user_id': str(animal.created_by.id),
                    'username': animal.created_by.username,
                    'is_self': animal.created_by.id == self.user.id,
                    'is_friend': animal.created_by.id in friend_ids
                } if animal.created_by else None
            }
            nodes.append(node)

        # Add virtual taxonomy nodes
        # These are created from the hierarchy for complete tree visualization
        # Implementation depends on UI requirements

        return nodes

    def _calculate_stats(self, animals, nodes, edges):
        """Calculate comprehensive statistics."""
        stats = {
            'total_animals': len(animals),
            'total_nodes': len(nodes),
            'total_edges': len(edges),
            'mode': self.mode,
            'scope': {
                'users_included': len(self.scoped_user_ids) if self.scoped_user_ids else 'all',
                'is_admin_view': self.mode == self.MODE_GLOBAL
            }
        }

        if self.scoped_user_ids:
            # User-specific stats
            user_captures = DexEntry.objects.filter(
                owner_id=self.user.id,
                animal__in=animals
            ).count()

            friend_captures = DexEntry.objects.filter(
                owner_id__in=self.scoped_user_ids,
                animal__in=animals
            ).exclude(owner_id=self.user.id).count()

            stats.update({
                'user_captures': user_captures,
                'friend_captures': friend_captures,
                'unique_to_user': sum(
                    1 for n in nodes
                    if n.get('captured_by_user') and not n.get('captured_by_friends')
                ),
                'shared_with_friends': sum(
                    1 for n in nodes
                    if n.get('captured_by_user') and n.get('captured_by_friends')
                )
            })

        # Taxonomic diversity
        taxonomic_ranks = ['kingdom', 'phylum', 'class', 'order', 'family', 'genus']
        for rank in taxonomic_ranks:
            unique_values = set(
                n['taxonomy'].get(rank)
                for n in nodes
                if n.get('type') == 'animal' and n['taxonomy'].get(rank)
            )
            stats[f'unique_{rank}'] = len(unique_values)

        return stats

    def get_chunk(self, chunk_x, chunk_y):
        """Get specific chunk with caching."""
        chunk_cache_key = self.get_cache_key(f'_chunk_{chunk_x}_{chunk_y}')

        cached_chunk = cache.get(chunk_cache_key)
        if cached_chunk:
            return cached_chunk

        # Get full tree data (uses main cache if available)
        tree_data = self.get_tree_data()

        # Extract chunk
        chunk = self.chunk_manager.get_chunk(chunk_x, chunk_y, tree_data)

        # Cache chunk separately
        cache.set(chunk_cache_key, chunk, settings.GRAPH_CACHE_TTL)

        return chunk

    def search_tree(self, query, limit=50):
        """
        Search within current tree scope.
        Returns only animals visible in current mode.
        """
        # Get scoped animals
        animals = self._get_scoped_animals()
        animal_ids = [a.id for a in animals]

        # Search within scope
        from django.db.models import Q
        results = Animal.objects.filter(
            id__in=animal_ids
        ).filter(
            Q(scientific_name__icontains=query) |
            Q(common_name__icontains=query) |
            Q(genus__icontains=query) |
            Q(species__icontains=query)
        )[:limit]

        # Get position from current layout
        tree_data = self.get_tree_data()
        positions = tree_data['layout']['positions']

        return [
            {
                'id': str(animal.id),
                'scientific_name': animal.scientific_name,
                'common_name': animal.common_name,
                'position': positions.get(str(animal.id), [0, 0]),
                'taxonomy_path': '/'.join([
                    getattr(animal, rank, '')
                    for rank in ['kingdom', 'phylum', 'class_name', 'order', 'family', 'genus', 'species']
                    if getattr(animal, rank, '')
                ])
            }
            for animal in results
        ]

    @classmethod
    def invalidate_user_caches(cls, user_id):
        """
        Invalidate all tree caches for a user.
        Called when user's dex changes.
        """
        # Clear personal tree
        cache.delete(f'taxonomic_tree_personal_{user_id}')
        cache.delete(f'taxonomic_tree_friends_{user_id}')

        # Clear any selected combinations including this user
        # This requires tracking which combinations exist
        # Could use cache.delete_pattern if available or maintain a registry

        # Clear global cache if exists
        cache.delete('taxonomic_tree_global')

        logger.info(f"Invalidated tree caches for user {user_id}")

    @classmethod
    def invalidate_global_cache(cls):
        """Invalidate global admin cache."""
        cache.delete('taxonomic_tree_global')
        logger.info("Invalidated global tree cache")
```

### 2. Updated API Endpoints (`server/graph/views.py`)

```python
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated, IsAdminUser
from django.contrib.auth import get_user_model
from .services import DynamicTaxonomicTreeService

User = get_user_model()


class DynamicTreeView(APIView):
    """
    Dynamic user-specific taxonomic tree endpoint.
    Supports multiple modes via query parameters.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        """
        GET /api/v1/graph/tree/

        Query params:
            - mode: personal|friends|selected|global (default: friends)
            - friend_ids: comma-separated friend IDs for selected mode
            - use_cache: true|false (default: true)
        """
        mode = request.query_params.get('mode', DynamicTaxonomicTreeService.MODE_FRIENDS)
        use_cache = request.query_params.get('use_cache', 'true').lower() == 'true'

        # Parse friend IDs for selected mode
        friend_ids = []
        if mode == DynamicTaxonomicTreeService.MODE_SELECTED:
            friend_ids_param = request.query_params.get('friend_ids', '')
            if friend_ids_param:
                try:
                    friend_ids = [int(id_str) for id_str in friend_ids_param.split(',')]
                except ValueError:
                    return Response(
                        {'error': 'Invalid friend_ids format'},
                        status=status.HTTP_400_BAD_REQUEST
                    )

        # Check permissions for global mode
        if mode == DynamicTaxonomicTreeService.MODE_GLOBAL and not request.user.is_staff:
            return Response(
                {'error': 'Admin privileges required for global view'},
                status=status.HTTP_403_FORBIDDEN
            )

        try:
            service = DynamicTaxonomicTreeService(
                user=request.user,
                mode=mode,
                selected_friend_ids=friend_ids
            )

            tree_data = service.get_tree_data(use_cache=use_cache)

            return Response(tree_data, status=status.HTTP_200_OK)

        except PermissionError as e:
            return Response(
                {'error': str(e)},
                status=status.HTTP_403_FORBIDDEN
            )
        except Exception as e:
            logger.error(f"Error generating tree: {str(e)}", exc_info=True)
            return Response(
                {'error': 'Failed to generate tree'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class TreeChunkView(APIView):
    """
    Get specific chunk of tree data for progressive loading.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, x, y):
        """
        GET /api/v1/graph/tree/chunk/<x>/<y>/

        Query params:
            - mode: personal|friends|selected|global
            - friend_ids: for selected mode
        """
        mode = request.query_params.get('mode', DynamicTaxonomicTreeService.MODE_FRIENDS)

        # Parse friend IDs
        friend_ids = []
        if mode == DynamicTaxonomicTreeService.MODE_SELECTED:
            friend_ids_param = request.query_params.get('friend_ids', '')
            if friend_ids_param:
                friend_ids = [int(id_str) for id_str in friend_ids_param.split(',')]

        # Check permissions
        if mode == DynamicTaxonomicTreeService.MODE_GLOBAL and not request.user.is_staff:
            return Response(
                {'error': 'Admin privileges required'},
                status=status.HTTP_403_FORBIDDEN
            )

        try:
            service = DynamicTaxonomicTreeService(
                user=request.user,
                mode=mode,
                selected_friend_ids=friend_ids
            )

            chunk_data = service.get_chunk(int(x), int(y))

            if chunk_data:
                return Response(chunk_data, status=status.HTTP_200_OK)
            else:
                return Response(
                    {'error': 'Chunk not found'},
                    status=status.HTTP_404_NOT_FOUND
                )

        except Exception as e:
            logger.error(f"Error fetching chunk: {str(e)}", exc_info=True)
            return Response(
                {'error': 'Failed to fetch chunk'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class TreeSearchView(APIView):
    """
    Search within user's current tree scope.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        """
        GET /api/v1/graph/tree/search/

        Query params:
            - q: search query (required)
            - mode: tree mode
            - friend_ids: for selected mode
            - limit: max results (default: 50)
        """
        query = request.query_params.get('q', '')
        if not query:
            return Response(
                {'error': 'Query parameter required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        mode = request.query_params.get('mode', DynamicTaxonomicTreeService.MODE_FRIENDS)
        limit = int(request.query_params.get('limit', 50))

        # Parse friend IDs
        friend_ids = []
        if mode == DynamicTaxonomicTreeService.MODE_SELECTED:
            friend_ids_param = request.query_params.get('friend_ids', '')
            if friend_ids_param:
                friend_ids = [int(id_str) for id_str in friend_ids_param.split(',')]

        try:
            service = DynamicTaxonomicTreeService(
                user=request.user,
                mode=mode,
                selected_friend_ids=friend_ids
            )

            results = service.search_tree(query, limit)

            return Response({
                'query': query,
                'mode': mode,
                'count': len(results),
                'results': results
            }, status=status.HTTP_200_OK)

        except Exception as e:
            logger.error(f"Error searching tree: {str(e)}", exc_info=True)
            return Response(
                {'error': 'Search failed'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


class TreeInvalidateView(APIView):
    """
    Invalidate tree caches when data changes.
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        """
        POST /api/v1/graph/tree/invalidate/

        Body:
            - scope: user|global (default: user)
        """
        scope = request.data.get('scope', 'user')

        if scope == 'global':
            if not request.user.is_staff:
                return Response(
                    {'error': 'Admin privileges required'},
                    status=status.HTTP_403_FORBIDDEN
                )
            DynamicTaxonomicTreeService.invalidate_global_cache()
            message = "Global tree cache invalidated"
        else:
            DynamicTaxonomicTreeService.invalidate_user_caches(request.user.id)
            message = f"Tree caches invalidated for user {request.user.username}"

        return Response({'message': message}, status=status.HTTP_200_OK)


class FriendTreeCombinationView(APIView):
    """
    Special endpoint for viewing combined friend trees.
    Provides UI for selecting which friends to include.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        """
        GET /api/v1/graph/tree/friends/

        Returns available friends and their stats.
        """
        from social.models import Friendship
        from dex.models import DexEntry

        friends = Friendship.get_friends(request.user)

        friend_data = []
        for friend in friends:
            unique_animals = DexEntry.objects.filter(
                owner=friend
            ).values('animal').distinct().count()

            friend_data.append({
                'id': friend.id,
                'username': friend.username,
                'unique_species': unique_animals,
                'friend_code': friend.friend_code
            })

        return Response({
            'friends': friend_data,
            'total_friends': len(friend_data)
        }, status=status.HTTP_200_OK)
```

### 3. URL Configuration (`server/graph/urls.py`)

```python
from django.urls import path
from .views import (
    # Legacy endpoints (keep for backwards compatibility)
    TaxonomicTreeView,
    InvalidateCacheView,

    # New dynamic tree endpoints
    DynamicTreeView,
    TreeChunkView,
    TreeSearchView,
    TreeInvalidateView,
    FriendTreeCombinationView,
)

urlpatterns = [
    # Legacy endpoints (deprecated)
    path('taxonomic-tree/', TaxonomicTreeView.as_view(), name='taxonomic-tree-legacy'),
    path('invalidate-cache/', InvalidateCacheView.as_view(), name='invalidate-cache-legacy'),

    # New dynamic tree endpoints
    path('tree/', DynamicTreeView.as_view(), name='dynamic-tree'),
    path('tree/chunk/<int:x>/<int:y>/', TreeChunkView.as_view(), name='tree-chunk'),
    path('tree/search/', TreeSearchView.as_view(), name='tree-search'),
    path('tree/invalidate/', TreeInvalidateView.as_view(), name='tree-invalidate'),
    path('tree/friends/', FriendTreeCombinationView.as_view(), name='friend-tree-combination'),
]
```

### 4. Cache Invalidation Strategy

```python
# In dex/models.py - Update signals

from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver
from graph.services import DynamicTaxonomicTreeService

@receiver(post_save, sender=DexEntry)
def invalidate_tree_on_dex_change(sender, instance, created, **kwargs):
    """Invalidate tree caches when dex entry changes."""
    if created or instance.tracker.has_changed('animal_id'):
        # Invalidate user's tree caches
        DynamicTaxonomicTreeService.invalidate_user_caches(instance.owner_id)

        # Also invalidate friends' caches since they include this user's data
        from social.models import Friendship
        friend_ids = Friendship.get_friend_ids(instance.owner)
        for friend_id in friend_ids:
            DynamicTaxonomicTreeService.invalidate_user_caches(friend_id)

        # Invalidate global cache if it exists
        DynamicTaxonomicTreeService.invalidate_global_cache()

@receiver(post_delete, sender=DexEntry)
def invalidate_tree_on_dex_delete(sender, instance, **kwargs):
    """Invalidate tree caches when dex entry deleted."""
    DynamicTaxonomicTreeService.invalidate_user_caches(instance.owner_id)

    from social.models import Friendship
    friend_ids = Friendship.get_friend_ids(instance.owner)
    for friend_id in friend_ids:
        DynamicTaxonomicTreeService.invalidate_user_caches(friend_id)

    DynamicTaxonomicTreeService.invalidate_global_cache()
```

### 5. Performance Optimizations

#### Database Indexes
```python
# In animals/models.py
class Animal(models.Model):
    # ... existing fields ...

    class Meta:
        indexes = [
            models.Index(fields=['kingdom', 'phylum', 'class_name']),
            models.Index(fields=['family', 'genus', 'species']),
            models.Index(fields=['creation_index']),
            models.Index(fields=['created_by']),
        ]
```

#### Query Optimization Patterns
```python
# Batch fetch pattern for avoiding N+1
def batch_fetch_user_info(user_ids):
    """Fetch user info in single query."""
    users = User.objects.filter(id__in=user_ids).values(
        'id', 'username', 'friend_code'
    )
    return {u['id']: u for u in users}

# Prefetch pattern for related data
animals = Animal.objects.prefetch_related(
    Prefetch(
        'dex_entries',
        queryset=DexEntry.objects.select_related('owner'),
        to_attr='all_captures'
    )
)
```

### 6. Admin Interface

```python
# In graph/admin.py
from django.contrib import admin
from django.urls import reverse
from django.utils.html import format_html

@admin.register(TreeCacheStatus)
class TreeCacheStatusAdmin(admin.ModelAdmin):
    """Admin interface for monitoring tree cache status."""

    list_display = ['user', 'mode', 'cached_at', 'node_count', 'invalidate_action']
    list_filter = ['mode', 'cached_at']
    search_fields = ['user__username']

    def invalidate_action(self, obj):
        """Action button to invalidate cache."""
        url = reverse('admin:invalidate_tree_cache', args=[obj.pk])
        return format_html(
            '<a href="{}" class="button">Invalidate</a>',
            url
        )
    invalidate_action.short_description = 'Actions'
```

## Client Updates Required

### 1. API Integration Changes

Update `tree_controller.gd` to handle dynamic modes:

```gdscript
extends Node
class_name TreeController

enum TreeMode {
    PERSONAL,    # User's dex only
    FRIENDS,     # User + all friends (default)
    SELECTED,    # User + selected friends
    GLOBAL       # Admin view of all users
}

var current_mode: TreeMode = TreeMode.FRIENDS
var selected_friend_ids: Array = []

func load_tree_data(mode: TreeMode = TreeMode.FRIENDS, friend_ids: Array = []):
    current_mode = mode
    selected_friend_ids = friend_ids

    var params = {
        "mode": _mode_to_string(mode),
        "use_cache": "true"
    }

    if mode == TreeMode.SELECTED and friend_ids.size() > 0:
        params["friend_ids"] = ",".join(friend_ids.map(func(id): return str(id)))

    api_manager.get_tree_data(params, _on_tree_data_loaded)

func _mode_to_string(mode: TreeMode) -> String:
    match mode:
        TreeMode.PERSONAL: return "personal"
        TreeMode.FRIENDS: return "friends"
        TreeMode.SELECTED: return "selected"
        TreeMode.GLOBAL: return "global"
    return "friends"
```

### 2. UI for Mode Selection

Add mode selector to `tree.tscn`:

```gdscript
# In tree UI
var mode_selector: OptionButton
var friend_selector: ItemList

func _ready():
    mode_selector.add_item("My Discoveries", TreeMode.PERSONAL)
    mode_selector.add_item("Friends & Me", TreeMode.FRIENDS)
    mode_selector.add_item("Select Friends", TreeMode.SELECTED)

    if api_manager.current_user.is_admin:
        mode_selector.add_item("All Users (Admin)", TreeMode.GLOBAL)

func _on_mode_changed(index: int):
    var mode = mode_selector.get_item_metadata(index)

    if mode == TreeMode.SELECTED:
        friend_selector.visible = true
        _load_friend_list()
    else:
        friend_selector.visible = false
        tree_controller.load_tree_data(mode)
```

## Migration Path

1. **Phase 1**: Deploy new service alongside existing one
2. **Phase 2**: Update clients to use new endpoints
3. **Phase 3**: Migrate existing caches
4. **Phase 4**: Deprecate old endpoints
5. **Phase 5**: Remove legacy code

## Performance Considerations

### Caching Strategy
- **Personal trees**: 5 minute TTL (changes frequently)
- **Friend trees**: 2 minute TTL (moderate change rate)
- **Selected combinations**: 1 minute TTL (highly dynamic)
- **Global admin tree**: 5 minute TTL (expensive to compute)
- **Chunks**: Same TTL as parent tree

### Memory Management
- Limit cache size: `CACHES['default']['OPTIONS']['MAX_ENTRIES'] = 10000`
- Use Redis with LRU eviction policy
- Monitor memory usage via Prometheus

### Query Optimization Checklist
- ✅ Use select_related for ForeignKeys
- ✅ Use prefetch_related for ManyToMany
- ✅ Batch queries where possible
- ✅ Add database indexes on filter fields
- ✅ Use values/values_list for read-only data
- ✅ Implement query result caching

## Testing Strategy

### Unit Tests
```python
# tests/test_dynamic_tree_service.py
class DynamicTreeServiceTests(TestCase):
    def test_personal_mode_shows_only_user_animals(self):
        # Test that personal mode filters correctly

    def test_friend_mode_includes_all_friends(self):
        # Test friend inclusion

    def test_selected_mode_filters_friends(self):
        # Test friend selection

    def test_admin_global_mode_requires_permission(self):
        # Test permission check

    def test_cache_invalidation_cascades(self):
        # Test cache invalidation
```

### Performance Tests
```python
def test_large_tree_performance(self):
    # Create 10,000 animals across 100 users
    # Assert response time < 2 seconds
    # Assert memory usage < 500MB
```

## Deployment Notes

1. **Database migrations**: Run after deploying new code
2. **Cache warming**: Pre-generate admin global tree
3. **Monitoring**: Watch for cache hit rates
4. **Rollback plan**: Keep legacy endpoints during transition

## Summary of Changes

### What's New
1. **Dynamic tree generation** based on user's dex entries
2. **Multiple view modes** (personal, friends, selected, global)
3. **Friend combination selector** for custom views
4. **Admin global view** of all users' discoveries
5. **Improved caching** with user-specific keys
6. **True tree structure** with parent-child relationships

### What's Improved
1. **Query optimization** with prefetch/select_related
2. **Cache invalidation** cascades to affected users
3. **Hierarchical edges** instead of same_family groupings
4. **Scoped statistics** based on current view mode
5. **Permission system** for admin features

### Breaking Changes
1. API endpoints moved from `/graph/taxonomic-tree/` to `/graph/tree/`
2. Response structure includes `mode` in metadata
3. Cache keys changed to include mode/scope
4. Edge relationships changed from `same_family` to `parent_child`

This implementation provides a robust, scalable solution for dynamic user-specific taxonomic trees while maintaining the performance targets of the original design.