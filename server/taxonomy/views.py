# taxonomy/views.py
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import AllowAny
from django.db.models import Q
from .models import Taxonomy, DataSource
from .serializers import (
    TaxonomySerializer, TaxonomyMinimalSerializer,
    DataSourceSerializer, TaxonomyValidationSerializer
)
from .services import TaxonomyService


class TaxonomyViewSet(viewsets.ReadOnlyModelViewSet):
    """API endpoints for taxonomy data"""
    queryset = Taxonomy.objects.filter(status='accepted').select_related('source', 'rank')
    permission_classes = [AllowAny]

    def get_serializer_class(self):
        if self.action == 'list' or self.action == 'search':
            return TaxonomyMinimalSerializer
        return TaxonomySerializer

    @action(detail=False, methods=['get'])
    def search(self, request):
        """
        Search taxonomy database

        Query params:
        - q: General search term (optional) - searches across all fields
        - genus: Search by genus (optional)
        - species: Search by species epithet (optional)
        - common_name: Search by common name (optional)
        - rank: Filter by rank (optional)
        - kingdom: Filter by kingdom (optional)
        - limit: Maximum results (default: 20, max: 100)

        Note: At least one search parameter (q, genus, species, or common_name) is required
        """
        query = request.query_params.get('q', '').strip()
        genus = request.query_params.get('genus', '').strip()
        species = request.query_params.get('species', '').strip()
        common_name = request.query_params.get('common_name', '').strip()
        rank = request.query_params.get('rank')
        kingdom = request.query_params.get('kingdom')
        limit = min(int(request.query_params.get('limit', 20)), 100)

        # Require at least one search parameter
        if not any([query, genus, species, common_name]):
            return Response(
                {'error': 'At least one search parameter is required (q, genus, species, or common_name)'},
                status=status.HTTP_400_BAD_REQUEST
            )

        results = TaxonomyService.search_taxonomy(
            query=query,
            genus=genus,
            species=species,
            common_name=common_name,
            rank=rank,
            kingdom=kingdom,
            limit=limit
        )

        serializer = self.get_serializer(results, many=True)
        return Response({
            'count': len(results),
            'results': serializer.data
        })

    @action(detail=False, methods=['post'])
    def validate(self, request):
        """
        Validate scientific name against taxonomy database

        Request body:
        {
            "scientific_name": "Genus species",
            "common_name": "Common name" (optional),
            "confidence": 0.95 (optional, CV confidence)
        }

        Response:
        {
            "valid": true/false,
            "created": true/false,
            "message": "...",
            "taxonomy": {...} (if valid)
        }
        """
        serializer = TaxonomyValidationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        scientific_name = serializer.validated_data['scientific_name']
        common_name = serializer.validated_data.get('common_name')
        confidence = serializer.validated_data.get('confidence', 0.0)

        taxonomy, created, message = TaxonomyService.lookup_or_create_from_cv(
            scientific_name=scientific_name,
            common_name=common_name,
            confidence=confidence
        )

        if taxonomy:
            return Response({
                'valid': True,
                'created': created,
                'message': message,
                'taxonomy': TaxonomySerializer(taxonomy).data
            })
        else:
            return Response({
                'valid': False,
                'created': False,
                'message': message
            })

    @action(detail=False, methods=['get'])
    def stats(self, request):
        """
        Get taxonomy database statistics

        Response:
        {
            "total_taxa": 123456,
            "kingdoms": 5,
            "species": 100000,
            "genera": 20000,
            "families": 5000,
            "sources": 1
        }
        """
        stats = TaxonomyService.get_hierarchy_stats()
        return Response(stats)

    @action(detail=True, methods=['get'])
    def lineage(self, request, pk=None):
        """
        Get complete taxonomic lineage for a taxon

        Returns list of taxonomy objects from kingdom to current taxon
        """
        taxonomy = self.get_object()
        lineage = TaxonomyService.get_taxonomic_lineage(taxonomy)
        serializer = TaxonomyMinimalSerializer(lineage, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['get'])
    def children(self, request, pk=None):
        """
        Get child taxa

        Query params:
        - direct: true/false (default: true, only direct children)
        """
        taxonomy = self.get_object()
        direct_only = request.query_params.get('direct', 'true').lower() == 'true'

        children = TaxonomyService.get_children(taxonomy, direct_only=direct_only)
        serializer = TaxonomyMinimalSerializer(children, many=True)
        return Response({
            'count': len(children),
            'direct_only': direct_only,
            'results': serializer.data
        })


class DataSourceViewSet(viewsets.ReadOnlyModelViewSet):
    """API endpoints for data sources"""
    queryset = DataSource.objects.filter(is_active=True)
    serializer_class = DataSourceSerializer
    permission_classes = [AllowAny]
