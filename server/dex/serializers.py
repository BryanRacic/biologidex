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


class DexEntrySyncSerializer(serializers.ModelSerializer):
    """
    Serializer for syncing dex entries to client.
    Includes image metadata for comparison.
    """
    scientific_name = serializers.CharField(source='animal.scientific_name', read_only=True)
    common_name = serializers.CharField(source='animal.common_name', read_only=True)
    creation_index = serializers.IntegerField(source='animal.creation_index', read_only=True)

    # Image URLs for client to download
    dex_compatible_url = serializers.SerializerMethodField()
    image_checksum = serializers.SerializerMethodField()
    image_updated_at = serializers.SerializerMethodField()

    class Meta:
        model = DexEntry
        fields = [
            'id',
            'creation_index',
            'scientific_name',
            'common_name',
            'dex_compatible_url',
            'image_checksum',
            'image_updated_at',
            'catch_date',
            'is_favorite',
            'updated_at',
        ]

    def get_dex_compatible_url(self, obj):
        """Get the dex-compatible image URL."""
        request = self.context.get('request')
        if obj.source_vision_job and obj.source_vision_job.dex_compatible_image:
            if request:
                return request.build_absolute_uri(obj.source_vision_job.dex_compatible_image.url)
            return obj.source_vision_job.dex_compatible_image.url
        elif obj.processed_image:
            if request:
                return request.build_absolute_uri(obj.processed_image.url)
            return obj.processed_image.url
        elif obj.original_image:
            if request:
                return request.build_absolute_uri(obj.original_image.url)
            return obj.original_image.url
        return None

    def get_image_checksum(self, obj):
        """Get checksum for the dex-compatible image."""
        import hashlib
        try:
            # Use dex-compatible image if available
            if obj.source_vision_job and obj.source_vision_job.dex_compatible_image:
                image_file = obj.source_vision_job.dex_compatible_image
            elif obj.processed_image:
                image_file = obj.processed_image
            elif obj.original_image:
                image_file = obj.original_image
            else:
                return None

            # Calculate checksum
            sha256 = hashlib.sha256()
            image_file.seek(0)
            for chunk in image_file.chunks():
                sha256.update(chunk)
            image_file.seek(0)
            return sha256.hexdigest()
        except Exception:
            return None

    def get_image_updated_at(self, obj):
        """Get the last update time for the image."""
        if obj.source_vision_job:
            return obj.source_vision_job.updated_at
        return obj.updated_at
