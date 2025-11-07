"""
Views for graph app.
"""
import logging
from rest_framework import permissions, status
from rest_framework.views import APIView
from rest_framework.response import Response
from .services import taxonomicGraphService
from .services_dynamic import DynamicTaxonomicTreeService

logger = logging.getLogger(__name__)


# =============================================================================
# Legacy Views (kept for backwards compatibility)
# =============================================================================

class taxonomicTreeView(APIView):
    """
    API endpoint for retrieving taxonomic/taxonomic tree data.
    Shows animals discovered by user and their friends network.

    DEPRECATED: Use DynamicTreeView instead.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        """
        Get taxonomic tree data for the authenticated user.

        Query params:
            - use_cache: bool (default: True) - whether to use cached data
        """
        use_cache = request.query_params.get('use_cache', 'true').lower() == 'true'

        service = taxonomicGraphService(request.user)
        graph_data = service.get_graph_data(use_cache=use_cache)

        return Response(graph_data)


class InvalidateCacheView(APIView):
    """
    API endpoint to manually invalidate graph cache.
    Useful after making changes that affect the graph.

    DEPRECATED: Use TreeInvalidateView instead.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        """Invalidate graph cache for the authenticated user."""
        taxonomicGraphService.invalidate_cache(request.user.id)

        return Response({
            'message': 'Graph cache invalidated successfully'
        }, status=status.HTTP_200_OK)


# =============================================================================
# New Dynamic Tree Views
# =============================================================================

class DynamicTreeView(APIView):
    """
    Dynamic user-specific taxonomic tree endpoint.
    Supports multiple modes via query parameters.
    """
    permission_classes = [permissions.IsAuthenticated]

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
    permission_classes = [permissions.IsAuthenticated]

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
    permission_classes = [permissions.IsAuthenticated]

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
    permission_classes = [permissions.IsAuthenticated]

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
    permission_classes = [permissions.IsAuthenticated]

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
