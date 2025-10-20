"""
Serializers for dex app.
"""
from rest_framework import serializers
from .models import DexEntry
from animals.serializers import AnimalListSerializer


class DexEntrySerializer(serializers.ModelSerializer):
    """Full serializer for DexEntry model."""
    animal_details = AnimalListSerializer(source='animal', read_only=True)
    owner_username = serializers.CharField(source='owner.username', read_only=True)
    location_coords = serializers.ReadOnlyField(source='get_location_coords')

    class Meta:
        model = DexEntry
        fields = [
            'id',
            'owner',
            'owner_username',
            'animal',
            'animal_details',
            'original_image',
            'processed_image',
            'location_lat',
            'location_lon',
            'location_name',
            'location_coords',
            'notes',
            'customizations',
            'catch_date',
            'visibility',
            'is_favorite',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'owner', 'processed_image', 'created_at', 'updated_at']


class DexEntryListSerializer(serializers.ModelSerializer):
    """Lightweight serializer for dex entry lists."""
    animal_name = serializers.CharField(source='animal.common_name', read_only=True)
    owner_username = serializers.CharField(source='owner.username', read_only=True)

    class Meta:
        model = DexEntry
        fields = [
            'id',
            'owner_username',
            'animal',
            'animal_name',
            'original_image',
            'catch_date',
            'visibility',
            'is_favorite',
        ]


class DexEntryCreateSerializer(serializers.ModelSerializer):
    """Serializer for creating dex entries."""

    class Meta:
        model = DexEntry
        fields = [
            'animal',
            'original_image',
            'location_lat',
            'location_lon',
            'location_name',
            'notes',
            'catch_date',
            'visibility',
        ]

    def create(self, validated_data):
        """Set owner from request context."""
        validated_data['owner'] = self.context['request'].user
        return super().create(validated_data)


class DexEntryUpdateSerializer(serializers.ModelSerializer):
    """Serializer for updating dex entries."""

    class Meta:
        model = DexEntry
        fields = [
            'notes',
            'customizations',
            'visibility',
            'is_favorite',
            'location_name',
        ]
