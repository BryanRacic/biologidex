"""
Views for accounts app.
"""
from rest_framework import viewsets, status, permissions
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework_simplejwt.views import TokenObtainPairView
from django.contrib.auth import get_user_model
from .models import UserProfile
from .serializers import (
    UserSerializer,
    UserRegistrationSerializer,
    UserUpdateSerializer,
    FriendCodeSerializer,
)

User = get_user_model()


class UserViewSet(viewsets.ModelViewSet):
    """
    ViewSet for User operations.
    Handles user registration, profile viewing, and updates.
    """
    queryset = User.objects.all()
    serializer_class = UserSerializer

    def get_permissions(self):
        """Set permissions based on action."""
        if self.action == 'create':
            # Allow anyone to register
            return [permissions.AllowAny()]
        return [permissions.IsAuthenticated()]

    def get_serializer_class(self):
        """Return appropriate serializer based on action."""
        if self.action == 'create':
            return UserRegistrationSerializer
        elif self.action in ['update', 'partial_update']:
            return UserUpdateSerializer
        return UserSerializer

    def get_object(self):
        """
        Override to allow 'me' as a special case to get current user.
        """
        pk = self.kwargs.get('pk')
        if pk == 'me':
            return self.request.user
        return super().get_object()

    def create(self, request, *args, **kwargs):
        """Register a new user."""
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()

        # Return user data with tokens
        user_serializer = UserSerializer(user)
        return Response(
            user_serializer.data,
            status=status.HTTP_201_CREATED
        )

    @action(detail=False, methods=['get'])
    def me(self, request):
        """Get current user's profile."""
        serializer = self.get_serializer(request.user)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def friend_code(self, request):
        """Get current user's friend code."""
        return Response({
            'friend_code': request.user.friend_code,
            'username': request.user.username
        })

    @action(detail=False, methods=['post'])
    def lookup_friend_code(self, request):
        """
        Look up a user by friend code.
        Used before sending friend request.
        """
        serializer = FriendCodeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        friend_code = serializer.validated_data['friend_code']

        try:
            user = User.objects.get(friend_code=friend_code)
            return Response({
                'id': user.id,
                'username': user.username,
                'avatar': user.avatar.url if user.avatar else None,
            })
        except User.DoesNotExist:
            return Response(
                {'error': 'No user found with this friend code'},
                status=status.HTTP_404_NOT_FOUND
            )

    @action(detail=True, methods=['post'])
    def update_stats(self, request, pk=None):
        """
        Manually trigger profile stats update.
        Usually done automatically via signals.
        """
        user = self.get_object()
        user.profile.update_stats()
        serializer = self.get_serializer(user)
        return Response(serializer.data)


class CustomTokenObtainPairView(TokenObtainPairView):
    """
    Custom token view that includes user data in response.
    """
    def post(self, request, *args, **kwargs):
        response = super().post(request, *args, **kwargs)

        # Add user data to response
        if response.status_code == 200:
            username = request.data.get('username')
            try:
                user = User.objects.get(username=username)
                user_serializer = UserSerializer(user)
                response.data['user'] = user_serializer.data
            except User.DoesNotExist:
                pass

        return response
