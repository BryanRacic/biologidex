"""
Views for dex app.
"""
from rest_framework import viewsets, filters, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from django_filters.rest_framework import DjangoFilterBackend
from django.db.models import Q
from .models import DexEntry
from .serializers import (
    DexEntrySerializer,
    DexEntryListSerializer,
    DexEntryCreateSerializer,
    DexEntryUpdateSerializer,
)


class IsOwnerOrReadOnly(permissions.BasePermission):
    """
    Custom permission to only allow owners of an entry to edit it.
    """
    def has_object_permission(self, request, view, obj):
        # Read permissions are allowed based on visibility
        if request.method in permissions.SAFE_METHODS:
            if obj.visibility == 'public':
                return True
            elif obj.visibility == 'friends':
                # Check if requester is friends with owner
                from social.models import Friendship
                return (
                    request.user == obj.owner or
                    Friendship.are_friends(request.user, obj.owner)
                )
            else:  # private
                return request.user == obj.owner

        # Write permissions are only for the owner
        return obj.owner == request.user


class DexEntryViewSet(viewsets.ModelViewSet):
    """
    ViewSet for DexEntry operations.
    Users can manage their own entries and view others' based on visibility.
    """
    queryset = DexEntry.objects.select_related('owner', 'animal').all()
    serializer_class = DexEntrySerializer
    permission_classes = [permissions.IsAuthenticated, IsOwnerOrReadOnly]
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    filterset_fields = ['animal', 'visibility', 'is_favorite']
    search_fields = ['animal__scientific_name', 'animal__common_name', 'notes']
    ordering_fields = ['catch_date', 'created_at']
    ordering = ['-catch_date']

    def get_queryset(self):
        """
        Filter queryset based on user permissions and visibility.
        """
        user = self.request.user
        if not user.is_authenticated:
            return DexEntry.objects.none()

        # Get friend IDs
        from social.models import Friendship
        friend_ids = Friendship.get_friend_ids(user)

        # Build query:
        # - Own entries (all)
        # - Friends' entries (friends/public visibility)
        # - Others' entries (public only)
        return self.queryset.filter(
            Q(owner=user) |  # Own entries
            Q(owner__id__in=friend_ids, visibility__in=['friends', 'public']) |  # Friends
            Q(visibility='public')  # Public entries
        ).distinct()

    def get_serializer_class(self):
        """Return appropriate serializer based on action."""
        if self.action == 'list':
            return DexEntryListSerializer
        elif self.action == 'create':
            return DexEntryCreateSerializer
        elif self.action in ['update', 'partial_update']:
            return DexEntryUpdateSerializer
        return DexEntrySerializer

    @action(detail=False, methods=['get'])
    def my_entries(self, request):
        """Get current user's dex entries."""
        entries = self.queryset.filter(owner=request.user)
        page = self.paginate_queryset(entries)
        if page is not None:
            serializer = DexEntryListSerializer(page, many=True)
            return self.get_paginated_response(serializer.data)

        serializer = DexEntryListSerializer(entries, many=True)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def favorites(self, request):
        """Get user's favorite entries."""
        entries = self.queryset.filter(owner=request.user, is_favorite=True)
        serializer = DexEntryListSerializer(entries, many=True)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def recent(self, request):
        """Get recently captured entries from user and friends."""
        from social.models import Friendship

        user = request.user
        friend_ids = Friendship.get_friend_ids(user)

        entries = self.queryset.filter(
            Q(owner=user) |
            Q(owner__id__in=friend_ids, visibility__in=['friends', 'public'])
        ).order_by('-catch_date')[:20]

        serializer = DexEntryListSerializer(entries, many=True)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def by_animal(self, request):
        """Get all entries for a specific animal (respecting visibility)."""
        animal_id = request.query_params.get('animal_id')
        if not animal_id:
            return Response(
                {'error': 'animal_id parameter required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        entries = self.get_queryset().filter(animal_id=animal_id)
        serializer = DexEntryListSerializer(entries, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['post'])
    def toggle_favorite(self, request, pk=None):
        """Toggle favorite status of an entry."""
        entry = self.get_object()
        entry.is_favorite = not entry.is_favorite
        entry.save(update_fields=['is_favorite'])
        serializer = self.get_serializer(entry)
        return Response(serializer.data)
