"""
Serializers for social app.
"""
from rest_framework import serializers
from django.contrib.auth import get_user_model
from .models import Friendship

User = get_user_model()


class FriendUserSerializer(serializers.ModelSerializer):
    """Lightweight user serializer for friend lists."""
    total_catches = serializers.IntegerField(source='profile.total_catches', read_only=True)
    unique_species = serializers.IntegerField(source='profile.unique_species', read_only=True)

    class Meta:
        model = User
        fields = ['id', 'username', 'avatar', 'friend_code', 'total_catches', 'unique_species']
        read_only_fields = fields


class FriendshipSerializer(serializers.ModelSerializer):
    """Serializer for Friendship model."""
    from_user_details = FriendUserSerializer(source='from_user', read_only=True)
    to_user_details = FriendUserSerializer(source='to_user', read_only=True)

    class Meta:
        model = Friendship
        fields = [
            'id',
            'from_user',
            'from_user_details',
            'to_user',
            'to_user_details',
            'status',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'from_user', 'status', 'created_at', 'updated_at']


class FriendRequestSerializer(serializers.Serializer):
    """Serializer for creating friend requests."""
    friend_code = serializers.CharField(
        max_length=8,
        min_length=8,
        required=False,
        help_text='Friend code of user to add'
    )
    user_id = serializers.UUIDField(
        required=False,
        help_text='Direct user ID to add (alternative to friend_code)'
    )

    def validate(self, attrs):
        """Ensure either friend_code or user_id is provided."""
        if not attrs.get('friend_code') and not attrs.get('user_id'):
            raise serializers.ValidationError(
                "Either friend_code or user_id must be provided"
            )
        return attrs

    def validate_friend_code(self, value):
        """Validate that friend code exists."""
        if value:
            try:
                User.objects.get(friend_code=value)
            except User.DoesNotExist:
                raise serializers.ValidationError("No user found with this friend code")
        return value

    def validate_user_id(self, value):
        """Validate that user ID exists."""
        if value:
            try:
                User.objects.get(id=value)
            except User.DoesNotExist:
                raise serializers.ValidationError("No user found with this ID")
        return value


class FriendRequestActionSerializer(serializers.Serializer):
    """Serializer for accepting/rejecting friend requests."""
    action = serializers.ChoiceField(
        choices=['accept', 'reject', 'block'],
        help_text='Action to perform on the friend request'
    )
