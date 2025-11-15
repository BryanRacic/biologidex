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
from .layout import ReingoldTilfordLayout, ChunkManager

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
        nodes = self._build_nodes(animals, hierarchy, positions)

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

    def _build_nodes(self, animals, hierarchy, positions):
        """
        Build node list with full metadata.
        Includes capture info specific to current scope and virtual taxonomy nodes.
        """
        nodes = []
        processed_taxonomy_nodes = set()

        # Build lookup for friend relationships
        if self.scoped_user_ids:
            friend_ids = set(Friendship.get_friend_ids(self.user))
        else:
            friend_ids = set()

        # First, add all virtual taxonomy nodes from hierarchy
        def add_taxonomy_nodes(node, parent_path=""):
            """Recursively add taxonomy nodes from hierarchy."""
            node_id = node['id']
            node_path = f"{parent_path}/{node['name']}" if parent_path else node['name']

            # Skip if already processed or if this is the root node
            if node_path in processed_taxonomy_nodes or node_id == 'root':
                return

            processed_taxonomy_nodes.add(node_path)

            # Skip if this node has animals (we'll add them as animal nodes below)
            if node.get('animals'):
                # Process children first (taxonomy nodes above the species level)
                for child in node.get('children', {}).values():
                    add_taxonomy_nodes(child, node_path)
                return

            # Create taxonomy node
            taxonomy_node = {
                'id': node_id,
                'type': 'taxonomic',
                'node_type': 'taxonomic',  # For client compatibility
                'rank': node['rank'],
                'name': node['name'],
                'scientific_name': node['name'],  # For consistency with animal nodes
                'position': positions.get(node_id, [0, 0]),
                'captured_by_user': False,  # Taxonomy nodes aren't captured
                'captured_by_friends': [],
                'capture_count': 0,
                'children_count': len(node.get('children', {})) + len(node.get('animals', [])),
                'animal_count': node.get('animal_count', 0)
            }
            nodes.append(taxonomy_node)

            # Recursively add children
            for child in node.get('children', {}).values():
                add_taxonomy_nodes(child, node_path)

        # Add taxonomy nodes starting from root's children
        for child in hierarchy.get('children', {}).values():
            add_taxonomy_nodes(child)

        # Then add animal nodes (existing code)
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

            # Build animal node
            node = {
                'id': str(animal.id),
                'type': 'animal',
                'node_type': 'animal',  # For client compatibility
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

        logger.info(f"Built {len(nodes)} total nodes ({len([n for n in nodes if n['type'] == 'taxonomic'])} taxonomic, {len([n for n in nodes if n['type'] == 'animal'])} animal)")

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
