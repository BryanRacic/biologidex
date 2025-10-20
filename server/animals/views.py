"""
Views for animals app.
"""
from rest_framework import viewsets, filters, permissions
from rest_framework.decorators import action
from rest_framework.response import Response
from django_filters.rest_framework import DjangoFilterBackend
from .models import Animal
from .serializers import (
    AnimalSerializer,
    AnimalListSerializer,
    AnimalCreateSerializer,
)


class AnimalViewSet(viewsets.ModelViewSet):
    """
    ViewSet for Animal operations.
    Provides list, retrieve, create, update, and delete operations.
    """
    queryset = Animal.objects.all()
    serializer_class = AnimalSerializer
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    filterset_fields = ['conservation_status', 'verified', 'kingdom', 'phylum', 'family']
    search_fields = ['scientific_name', 'common_name', 'genus', 'species']
    ordering_fields = ['creation_index', 'created_at', 'scientific_name']
    ordering = ['creation_index']

    def get_permissions(self):
        """
        Anyone can view animals, but only authenticated users can create.
        Only staff can update/delete.
        """
        if self.action in ['list', 'retrieve']:
            return [permissions.AllowAny()]
        elif self.action == 'create':
            return [permissions.IsAuthenticated()]
        return [permissions.IsAdminUser()]

    def get_serializer_class(self):
        """Return appropriate serializer based on action."""
        if self.action == 'list':
            return AnimalListSerializer
        elif self.action == 'create':
            return AnimalCreateSerializer
        return AnimalSerializer

    def get_serializer_context(self):
        """Add user to serializer context."""
        context = super().get_serializer_context()
        context['user'] = self.request.user
        return context

    @action(detail=False, methods=['get'])
    def recent(self, request):
        """Get recently discovered animals."""
        animals = self.queryset.order_by('-created_at')[:20]
        serializer = AnimalListSerializer(animals, many=True)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def popular(self, request):
        """Get most captured animals."""
        from dex.models import DexEntry
        from django.db.models import Count

        animals = self.queryset.annotate(
            capture_count=Count('dexentry')
        ).order_by('-capture_count')[:20]

        serializer = AnimalListSerializer(animals, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['get'])
    def taxonomy(self, request, pk=None):
        """Get full taxonomic information for an animal."""
        animal = self.get_object()
        return Response(animal.get_taxonomic_tree())

    @action(detail=False, methods=['post'])
    def lookup_or_create(self, request):
        """
        Look up an animal by scientific name, or create if doesn't exist.
        Used by the CV identification pipeline.
        """
        scientific_name = request.data.get('scientific_name')

        if not scientific_name:
            return Response(
                {'error': 'scientific_name is required'},
                status=400
            )

        # Try to find existing animal
        try:
            animal = Animal.objects.get(scientific_name__iexact=scientific_name)
            serializer = self.get_serializer(animal)
            return Response({
                'created': False,
                'animal': serializer.data
            })
        except Animal.DoesNotExist:
            # Create new animal
            serializer = AnimalCreateSerializer(
                data=request.data,
                context=self.get_serializer_context()
            )
            serializer.is_valid(raise_exception=True)
            animal = serializer.save()

            full_serializer = AnimalSerializer(animal)
            return Response({
                'created': True,
                'animal': full_serializer.data
            }, status=201)
