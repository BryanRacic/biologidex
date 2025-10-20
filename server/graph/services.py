"""
Services for generating evolutionary/taxonomic graphs.
"""
import logging
from typing import Dict, List, Set
from django.core.cache import cache
from django.conf import settings
from django.db.models import Count, Q
from animals.models import Animal
from dex.models import DexEntry
from social.models import Friendship

logger = logging.getLogger(__name__)


class EvolutionaryGraphService:
    """
    Service for generating evolutionary tree data structure.
    Shows animals discovered by user and their friends.
    """

    def __init__(self, user):
        """
        Initialize service for a specific user.

        Args:
            user: User instance for whom to generate the graph
        """
        self.user = user

    def get_graph_data(self, use_cache: bool = True) -> Dict:
        """
        Generate graph data showing animals discovered by user and friends.

        Returns:
            Dict with structure:
            {
                'nodes': [list of animal nodes],
                'edges': [list of taxonomic relationships],
                'stats': {summary statistics},
                'metadata': {graph metadata}
            }
        """
        cache_key = f'evolution_graph_{self.user.id}'

        if use_cache:
            cached_data = cache.get(cache_key)
            if cached_data:
                logger.info(f"Returning cached graph for user {self.user.id}")
                return cached_data

        logger.info(f"Generating graph for user {self.user.id}")

        # Get all relevant animals
        animals = self._get_relevant_animals()

        # Build nodes
        nodes = self._build_nodes(animals)

        # Build edges (taxonomic relationships)
        edges = self._build_edges(animals)

        # Calculate stats
        stats = self._calculate_stats(animals)

        # Build metadata
        metadata = {
            'user_id': str(self.user.id),
            'username': self.user.username,
            'total_nodes': len(nodes),
            'total_edges': len(edges),
        }

        graph_data = {
            'nodes': nodes,
            'edges': edges,
            'stats': stats,
            'metadata': metadata,
        }

        # Cache the result
        cache.set(cache_key, graph_data, settings.GRAPH_CACHE_TTL)

        return graph_data

    def _get_relevant_animals(self) -> List[Animal]:
        """Get animals discovered by user and their friends."""
        # Get friend IDs
        friend_ids = Friendship.get_friend_ids(self.user)
        user_and_friend_ids = [self.user.id] + friend_ids

        # Get animals that have been captured by user or friends
        animal_ids = DexEntry.objects.filter(
            owner__id__in=user_and_friend_ids
        ).values_list('animal_id', distinct=True)

        # Fetch animals with capture counts
        animals = Animal.objects.filter(
            id__in=animal_ids
        ).annotate(
            capture_count=Count('dex_entries', filter=Q(
                dex_entries__owner__id__in=user_and_friend_ids
            ))
        ).order_by('kingdom', 'phylum', 'family', 'genus')

        return list(animals)

    def _build_nodes(self, animals: List[Animal]) -> List[Dict]:
        """
        Build node list from animals.

        Each node represents an animal with its taxonomic information.
        """
        nodes = []

        for animal in animals:
            # Check if user has captured this animal
            user_captured = DexEntry.objects.filter(
                owner=self.user,
                animal=animal
            ).exists()

            # Get discoverer info
            discoverer = None
            if animal.created_by:
                is_friend = Friendship.are_friends(self.user, animal.created_by)
                discoverer = {
                    'user_id': str(animal.created_by.id),
                    'username': animal.created_by.username,
                    'is_friend': is_friend,
                    'is_self': animal.created_by == self.user,
                }

            node = {
                'id': str(animal.id),
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
                'conservation_status': animal.conservation_status,
                'verified': animal.verified,
                'captured_by_user': user_captured,
                'capture_count': getattr(animal, 'capture_count', 0),
                'discoverer': discoverer,
            }

            nodes.append(node)

        return nodes

    def _build_edges(self, animals: List[Animal]) -> List[Dict]:
        """
        Build edges representing taxonomic relationships.

        Edges connect animals that share taxonomic classifications.
        """
        edges = []
        edge_set = set()  # To avoid duplicates

        # Group animals by family
        family_groups = {}
        for animal in animals:
            if animal.family:
                if animal.family not in family_groups:
                    family_groups[animal.family] = []
                family_groups[animal.family].append(animal)

        # Create edges between animals in same family
        for family, family_animals in family_groups.items():
            for i, animal1 in enumerate(family_animals):
                for animal2 in family_animals[i+1:]:
                    # Create edge
                    edge_id = tuple(sorted([str(animal1.id), str(animal2.id)]))
                    if edge_id not in edge_set:
                        edge_set.add(edge_id)
                        edges.append({
                            'source': str(animal1.id),
                            'target': str(animal2.id),
                            'relationship': 'same_family',
                            'family': family,
                        })

        return edges

    def _calculate_stats(self, animals: List[Animal]) -> Dict:
        """Calculate statistics about the graph."""
        # Get friend IDs
        friend_ids = Friendship.get_friend_ids(self.user)

        # User's captures
        user_captures = DexEntry.objects.filter(owner=self.user).count()
        user_unique_species = DexEntry.objects.filter(
            owner=self.user
        ).values('animal').distinct().count()

        # Friend captures
        friend_captures = DexEntry.objects.filter(
            owner__id__in=friend_ids
        ).count()

        # Taxonomic diversity
        kingdoms = set(a.kingdom for a in animals if a.kingdom)
        phylums = set(a.phylum for a in animals if a.phylum)
        families = set(a.family for a in animals if a.family)

        return {
            'total_animals': len(animals),
            'user_captures': user_captures,
            'user_unique_species': user_unique_species,
            'friend_captures': friend_captures,
            'friend_count': len(friend_ids),
            'taxonomic_diversity': {
                'kingdoms': len(kingdoms),
                'phylums': len(phylums),
                'families': len(families),
            },
        }

    @staticmethod
    def invalidate_cache(user_id):
        """Invalidate cached graph for a user."""
        cache_key = f'evolution_graph_{user_id}'
        cache.delete(cache_key)
        logger.info(f"Invalidated graph cache for user {user_id}")
