"""
Views for social app.
"""
from rest_framework import viewsets, status, permissions
from rest_framework.decorators import action
from rest_framework.response import Response
from django.contrib.auth import get_user_model
from django.db.models import Q
from .models import Friendship
from .serializers import (
    FriendshipSerializer,
    FriendRequestSerializer,
    FriendRequestActionSerializer,
    FriendUserSerializer,
)

User = get_user_model()


class FriendshipViewSet(viewsets.ReadOnlyModelViewSet):
    """
    ViewSet for managing friendships and friend requests.
    Provides endpoints for:
    - Viewing friends list
    - Sending friend requests
    - Accepting/rejecting requests
    - Unfriending users
    """
    serializer_class = FriendshipSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        """
        Return friendships involving the current user.
        """
        user = self.request.user
        return Friendship.objects.filter(
            Q(from_user=user) | Q(to_user=user)
        ).select_related('from_user', 'to_user')

    @action(detail=False, methods=['get'])
    def friends(self, request):
        """Get list of accepted friends."""
        friends = Friendship.get_friends(request.user)
        serializer = FriendUserSerializer(friends, many=True)
        return Response({
            'count': friends.count(),
            'friends': serializer.data
        })

    @action(detail=False, methods=['get'])
    def pending(self, request):
        """Get pending friend requests (received by user)."""
        requests = Friendship.get_pending_requests(request.user)
        serializer = FriendshipSerializer(requests, many=True)
        return Response({
            'count': requests.count(),
            'requests': serializer.data
        })

    @action(detail=False, methods=['get'])
    def sent(self, request):
        """Get friend requests sent by user."""
        sent_requests = Friendship.objects.filter(
            from_user=request.user,
            status='pending'
        ).select_related('to_user')
        serializer = FriendshipSerializer(sent_requests, many=True)
        return Response({
            'count': sent_requests.count(),
            'requests': serializer.data
        })

    @action(detail=False, methods=['post'])
    def send_request(self, request):
        """
        Send a friend request using friend code or user ID.
        """
        serializer = FriendRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        # Get target user
        if serializer.validated_data.get('friend_code'):
            to_user = User.objects.get(
                friend_code=serializer.validated_data['friend_code']
            )
        else:
            to_user = User.objects.get(
                id=serializer.validated_data['user_id']
            )

        # Check if trying to add self
        if to_user == request.user:
            return Response(
                {'error': 'Cannot send friend request to yourself'},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            friendship = Friendship.create_request(request.user, to_user)
            response_serializer = FriendshipSerializer(friendship)
            return Response(
                response_serializer.data,
                status=status.HTTP_201_CREATED
            )
        except ValueError as e:
            return Response(
                {'error': str(e)},
                status=status.HTTP_400_BAD_REQUEST
            )

    @action(detail=True, methods=['post'])
    def respond(self, request, pk=None):
        """
        Accept, reject, or block a friend request.
        Only the recipient can respond.
        """
        friendship = self.get_object()

        # Verify user is the recipient
        if friendship.to_user != request.user:
            return Response(
                {'error': 'Only the recipient can respond to this request'},
                status=status.HTTP_403_FORBIDDEN
            )

        serializer = FriendRequestActionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        action_type = serializer.validated_data['action']

        try:
            if action_type == 'accept':
                friendship.accept()
            elif action_type == 'reject':
                friendship.reject()
            elif action_type == 'block':
                friendship.block()

            response_serializer = FriendshipSerializer(friendship)
            return Response(response_serializer.data)
        except ValueError as e:
            return Response(
                {'error': str(e)},
                status=status.HTTP_400_BAD_REQUEST
            )

    @action(detail=True, methods=['delete'])
    def unfriend(self, request, pk=None):
        """
        Remove a friendship (unfriend a user).
        Either user in the friendship can unfriend.
        """
        friendship = self.get_object()

        # Verify user is part of this friendship
        if request.user not in [friendship.from_user, friendship.to_user]:
            return Response(
                {'error': 'You are not part of this friendship'},
                status=status.HTTP_403_FORBIDDEN
            )

        friendship.unfriend()
        return Response(
            {'message': 'Friendship removed successfully'},
            status=status.HTTP_204_NO_CONTENT
        )

    @action(detail=False, methods=['get'])
    def check(self, request):
        """
        Check friendship status with another user.
        Query param: user_id
        """
        user_id = request.query_params.get('user_id')
        if not user_id:
            return Response(
                {'error': 'user_id parameter required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            other_user = User.objects.get(id=user_id)
        except User.DoesNotExist:
            return Response(
                {'error': 'User not found'},
                status=status.HTTP_404_NOT_FOUND
            )

        # Check friendship status
        is_friends = Friendship.are_friends(request.user, other_user)

        # Check if there's a pending request
        pending_request = Friendship.objects.filter(
            Q(from_user=request.user, to_user=other_user) |
            Q(from_user=other_user, to_user=request.user),
            status='pending'
        ).first()

        return Response({
            'user_id': str(other_user.id),
            'username': other_user.username,
            'is_friends': is_friends,
            'pending_request': FriendshipSerializer(pending_request).data if pending_request else None
        })
