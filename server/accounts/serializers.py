"""
Serializers for accounts app.
"""
from rest_framework import serializers
from django.contrib.auth.password_validation import validate_password
from .models import User, UserProfile


class UserProfileSerializer(serializers.ModelSerializer):
    """Serializer for UserProfile model."""

    class Meta:
        model = UserProfile
        fields = [
            'total_catches',
            'unique_species',
            'preferred_card_style',
            'join_date',
            'last_catch_date',
        ]
        read_only_fields = ['total_catches', 'unique_species', 'join_date', 'last_catch_date']


class UserSerializer(serializers.ModelSerializer):
    """Serializer for User model."""
    profile = UserProfileSerializer(read_only=True)

    class Meta:
        model = User
        fields = [
            'id',
            'username',
            'email',
            'friend_code',
            'bio',
            'avatar',
            'badges',
            'created_at',
            'updated_at',
            'profile',
        ]
        read_only_fields = ['id', 'friend_code', 'badges', 'created_at', 'updated_at']
        extra_kwargs = {
            'email': {'required': True},
        }


class UserRegistrationSerializer(serializers.ModelSerializer):
    """Serializer for user registration."""
    password = serializers.CharField(
        write_only=True,
        required=True,
        validators=[validate_password],
        style={'input_type': 'password'}
    )
    password_confirm = serializers.CharField(
        write_only=True,
        required=True,
        style={'input_type': 'password'}
    )

    class Meta:
        model = User
        fields = ['username', 'email', 'password', 'password_confirm']

    def validate(self, attrs):
        """Validate that passwords match."""
        if attrs['password'] != attrs['password_confirm']:
            raise serializers.ValidationError(
                {"password": "Password fields didn't match."}
            )
        return attrs

    def create(self, validated_data):
        """Create and return a new user."""
        validated_data.pop('password_confirm')
        user = User.objects.create_user(
            username=validated_data['username'],
            email=validated_data['email'],
            password=validated_data['password']
        )
        return user


class UserUpdateSerializer(serializers.ModelSerializer):
    """Serializer for updating user profile."""
    preferred_card_style = serializers.JSONField(
        source='profile.preferred_card_style',
        required=False
    )

    class Meta:
        model = User
        fields = ['bio', 'avatar', 'preferred_card_style']

    def update(self, instance, validated_data):
        """Update user and profile data."""
        profile_data = validated_data.pop('profile', {})

        # Update user fields
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        instance.save()

        # Update profile fields
        if profile_data:
            profile = instance.profile
            for attr, value in profile_data.items():
                setattr(profile, attr, value)
            profile.save()

        return instance


class FriendCodeSerializer(serializers.Serializer):
    """Serializer for friend code lookup."""
    friend_code = serializers.CharField(max_length=8, min_length=8)
