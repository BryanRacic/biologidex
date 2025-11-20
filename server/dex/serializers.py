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
    source_vision_job = serializers.UUIDField(required=False, allow_null=True)
    original_image = serializers.ImageField(required=False, allow_null=True)
    catch_date = serializers.DateTimeField(required=False)

    class Meta:
        model = DexEntry
        fields = [
            'animal',
            'source_vision_job',
            'original_image',
            'location_lat',
            'location_lon',
            'location_name',
            'notes',
            'catch_date',
            'visibility',
        ]

    def validate(self, attrs):
        """Validate that either source_vision_job or original_image is provided."""
        source_vision_job = attrs.get('source_vision_job')
        original_image = attrs.get('original_image')

        if not source_vision_job and not original_image:
            raise serializers.ValidationError(
                "Either source_vision_job or original_image must be provided."
            )

        return attrs

    def create(self, validated_data):
        """Set owner and handle vision job image."""
        from django.utils import timezone
        from vision.models import AnalysisJob

        validated_data['owner'] = self.context['request'].user

        # If source_vision_job provided, get the image from it
        source_vision_job_id = validated_data.pop('source_vision_job', None)
        if source_vision_job_id:
            try:
                vision_job = AnalysisJob.objects.get(id=source_vision_job_id)
                # Use the original image from the vision job
                if not validated_data.get('original_image'):
                    validated_data['original_image'] = vision_job.image
                # Link the vision job
                validated_data['source_vision_job'] = vision_job
            except AnalysisJob.DoesNotExist:
                pass

        # Set catch_date to now if not provided
        if not validated_data.get('catch_date'):
            validated_data['catch_date'] = timezone.now()

        return super().create(validated_data)


class DexEntryUpdateSerializer(serializers.ModelSerializer):
    """Serializer for updating dex entries."""

    class Meta:
        model = DexEntry
        fields = [
            'animal',
            'notes',
            'customizations',
            'visibility',
            'is_favorite',
            'location_name',
        ]

    def validate_animal(self, value):
        """Validate that the animal exists"""
        from animals.models import Animal
        if not Animal.objects.filter(id=value.id).exists():
            raise serializers.ValidationError("Animal does not exist")
        return value


class DexEntrySyncSerializer(serializers.ModelSerializer):
    """
    Serializer for syncing dex entries to client.
    Includes image metadata for comparison.
    """
    animal_id = serializers.UUIDField(source='animal.id', read_only=True)
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
            'animal_id',
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
            # AnalysisJob doesn't have updated_at, use completed_at or created_at
            return obj.source_vision_job.completed_at or obj.source_vision_job.created_at
        return obj.updated_at
