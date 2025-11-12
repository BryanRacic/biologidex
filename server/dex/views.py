"""
Views for dex app.
"""
from rest_framework import viewsets, filters, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from django_filters.rest_framework import DjangoFilterBackend
from django.db.models import Q
from django.core.cache import cache
from django.utils import timezone
from .models import DexEntry
from .serializers import (
    DexEntrySerializer,
    DexEntryListSerializer,
    DexEntryCreateSerializer,
    DexEntryUpdateSerializer,
    DexEntrySyncSerializer,
)


## Cache helper functions

def get_user_dex_cache_key(user_id, last_sync=None):
    """Generate cache key for user dex sync"""
    if last_sync:
        return f"dex:user:{user_id}:since:{last_sync}"
    return f"dex:user:{user_id}:all"


def get_friends_overview_cache_key(user_id):
    """Generate cache key for friends overview"""
    return f"dex:friends_overview:{user_id}"


def invalidate_user_dex_cache(user_id):
    """Invalidate all cache entries for a user's dex"""
    # Clear all possible cache keys for this user
    cache.delete_pattern(f"dex:user:{user_id}:*")
    print(f"[DexCache] Invalidated cache for user {user_id}")


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

    @action(detail=False, methods=['get'])
    def sync_entries(self, request):
        """
        Sync endpoint for client to check for updated dex entries.
        Returns entries with their image metadata for comparison.

        Caching: 5 minute TTL for full syncs, no caching for incremental syncs

        Query params:
            last_sync: ISO 8601 datetime string - only return entries updated after this time
        """
        from django.utils import timezone
        from django.utils.dateparse import parse_datetime

        last_sync = request.query_params.get('last_sync')

        # Try cache for full syncs (no last_sync parameter)
        if not last_sync:
            cache_key = get_user_dex_cache_key(str(request.user.id))
            cached_response = cache.get(cache_key)
            if cached_response:
                print(f"[DexCache] Hit for user {request.user.id}")
                return Response(cached_response)

        # Get user's entries ordered by creation_index
        entries = self.queryset.filter(owner=request.user).order_by('animal__creation_index')

        # Filter by last_sync timestamp if provided
        if last_sync:
            try:
                # URL decode the + sign if present (+ becomes space in URL decode)
                last_sync = last_sync.replace(' ', '+')
                last_sync_dt = parse_datetime(last_sync)
                if last_sync_dt is None:
                    return Response(
                        {'error': 'Invalid last_sync format. Use ISO 8601 datetime.'},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                entries = entries.filter(updated_at__gt=last_sync_dt)
            except Exception as e:
                return Response(
                    {'error': f'Failed to parse last_sync: {str(e)}'},
                    status=status.HTTP_400_BAD_REQUEST
                )

        # Serialize entries with image metadata
        serializer = DexEntrySyncSerializer(
            entries,
            many=True,
            context={'request': request}
        )

        response_data = {
            'entries': serializer.data,
            'server_time': timezone.now().isoformat(),
            'count': entries.count()
        }

        # Cache full syncs for 5 minutes
        if not last_sync:
            cache_key = get_user_dex_cache_key(str(request.user.id))
            cache.set(cache_key, response_data, 300)  # 5 minutes
            print(f"[DexCache] Set for user {request.user.id}")

        return Response(response_data)

    @action(detail=False, methods=['get'], url_path='user/(?P<user_id>[^/.]+)/entries')
    def user_entries(self, request, user_id=None):
        """
        Get dex entries for a specific user (respecting permissions).

        Permission rules:
        - Own entries: All entries visible
        - Friend's entries: Friends and public entries visible
        - Stranger's entries: Public entries only

        Query params:
            last_sync: ISO 8601 datetime string - incremental sync support
        """
        from django.utils import timezone
        from django.utils.dateparse import parse_datetime
        from accounts.models import User
        from social.models import Friendship

        # Get target user
        try:
            target_user = User.objects.get(id=user_id)
        except User.DoesNotExist:
            return Response(
                {'error': 'User not found'},
                status=status.HTTP_404_NOT_FOUND
            )

        # Determine visibility filter based on relationship
        if target_user == request.user:
            # Own entries - see everything
            visibility_filter = Q()
        elif Friendship.are_friends(request.user, target_user):
            # Friend's entries - see friends and public
            visibility_filter = Q(visibility__in=['friends', 'public'])
        else:
            # Stranger's entries - see public only
            visibility_filter = Q(visibility='public')

        # Get entries
        entries = self.queryset.filter(
            owner=target_user
        ).filter(visibility_filter).order_by('animal__creation_index')

        # Support incremental sync
        last_sync = request.query_params.get('last_sync')
        if last_sync:
            try:
                # URL decode the + sign if present (+ becomes space in URL decode)
                last_sync = last_sync.replace(' ', '+')
                last_sync_dt = parse_datetime(last_sync)
                if last_sync_dt is None:
                    return Response(
                        {'error': 'Invalid last_sync format. Use ISO 8601 datetime.'},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                entries = entries.filter(updated_at__gt=last_sync_dt)
            except Exception as e:
                return Response(
                    {'error': f'Failed to parse last_sync: {str(e)}'},
                    status=status.HTTP_400_BAD_REQUEST
                )

        # Serialize with image metadata
        serializer = DexEntrySyncSerializer(
            entries,
            many=True,
            context={'request': request}
        )

        return Response({
            'entries': serializer.data,
            'server_time': timezone.now().isoformat(),
            'user_id': str(target_user.id),
            'total_count': entries.count()
        })

    @action(detail=False, methods=['get'])
    def friends_overview(self, request):
        """
        Get summary of all friends' dex collections for discovery.
        Returns user info and entry counts for each friend.

        Caching: 2 minute TTL
        """
        from social.models import Friendship

        # Try cache first
        cache_key = get_friends_overview_cache_key(str(request.user.id))
        cached_response = cache.get(cache_key)
        if cached_response:
            print(f"[DexCache] Friends overview hit for user {request.user.id}")
            return Response(cached_response)

        friends = Friendship.get_friends(request.user)
        overview = []

        for friend in friends:
            # Count entries visible to current user
            entry_count = self.queryset.filter(
                owner=friend,
                visibility__in=['friends', 'public']
            ).count()

            # Get latest entry
            latest_entry = self.queryset.filter(
                owner=friend,
                visibility__in=['friends', 'public']
            ).order_by('-updated_at').first()

            overview.append({
                'user_id': str(friend.id),
                'username': friend.username,
                'friend_code': friend.friend_code,
                'total_entries': entry_count,
                'latest_update': latest_entry.updated_at.isoformat() if latest_entry else None
            })

        response_data = {'friends': overview}

        # Cache for 2 minutes
        cache.set(cache_key, response_data, 120)
        print(f"[DexCache] Friends overview set for user {request.user.id}")

        return Response(response_data)

    @action(detail=False, methods=['post'])
    def batch_sync(self, request):
        """
        Sync multiple users' dex collections in a single request.
        Optimizes network requests for syncing own dex + multiple friends.

        Request body:
        {
            "sync_requests": [
                {"user_id": "self", "last_sync": "2024-01-01T00:00:00Z"},
                {"user_id": "<uuid>", "last_sync": "2024-01-01T00:00:00Z"}
            ]
        }

        Response:
        {
            "results": {
                "self": {"entries": [...], "count": 5},
                "<uuid>": {"entries": [...], "count": 3}
            },
            "server_time": "2024-01-02T00:00:00Z"
        }
        """
        from django.utils import timezone
        from django.utils.dateparse import parse_datetime
        from accounts.models import User
        from social.models import Friendship

        sync_requests = request.data.get('sync_requests', [])
        results = {}

        for sync_req in sync_requests:
            user_id = sync_req.get('user_id', 'self')
            last_sync = sync_req.get('last_sync')

            # Determine target user
            if user_id == 'self':
                target_user = request.user
            else:
                try:
                    target_user = User.objects.get(id=user_id)
                    # Check permissions
                    if not Friendship.are_friends(request.user, target_user):
                        results[user_id] = {'error': 'Not friends with this user'}
                        continue
                except User.DoesNotExist:
                    results[user_id] = {'error': 'User not found'}
                    continue

            # Get entries
            try:
                entries = self._get_sync_entries(
                    target_user,
                    request.user,
                    last_sync
                )

                serializer = DexEntrySyncSerializer(
                    entries,
                    many=True,
                    context={'request': request}
                )

                results[user_id] = {
                    'entries': serializer.data,
                    'count': entries.count()
                }
            except Exception as e:
                results[user_id] = {'error': str(e)}

        return Response({
            'results': results,
            'server_time': timezone.now().isoformat()
        })

    def _get_sync_entries(self, target_user, requesting_user, last_sync=None):
        """
        Helper method to get entries for sync with proper filtering.
        """
        from django.utils.dateparse import parse_datetime

        # Determine visibility
        if target_user == requesting_user:
            visibility_filter = Q()
        elif hasattr(self, '_are_friends_cached'):
            # Use cached friendship check if available
            visibility_filter = Q(visibility__in=['friends', 'public'])
        else:
            from social.models import Friendship
            if Friendship.are_friends(requesting_user, target_user):
                visibility_filter = Q(visibility__in=['friends', 'public'])
            else:
                visibility_filter = Q(visibility='public')

        entries = self.queryset.filter(
            owner=target_user
        ).filter(visibility_filter).order_by('animal__creation_index')

        # Filter by last_sync if provided
        if last_sync:
            last_sync_dt = parse_datetime(last_sync)
            if last_sync_dt:
                entries = entries.filter(updated_at__gt=last_sync_dt)

        return entries
