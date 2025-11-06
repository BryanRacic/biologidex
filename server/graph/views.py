"""
Views for graph app.
"""
from rest_framework import permissions, status
from rest_framework.views import APIView
from rest_framework.response import Response
from .services import taxonomicGraphService


class taxonomicTreeView(APIView):
    """
    API endpoint for retrieving taxonomic/taxonomic tree data.
    Shows animals discovered by user and their friends network.
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
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        """Invalidate graph cache for the authenticated user."""
        taxonomicGraphService.invalidate_cache(request.user.id)

        return Response({
            'message': 'Graph cache invalidated successfully'
        }, status=status.HTTP_200_OK)
