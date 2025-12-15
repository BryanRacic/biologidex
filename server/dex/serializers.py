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
    """
    Serializer for creating dex entries.

    Supports three image source modes:
    1. source_vision_job - From CV analysis (standard flow)
    2. source_conversion - From ImageConversion (manual entry without CV)
    3. original_image - Direct file upload (legacy/fallback)

    At least one of these must be provided.
    """
    source_vision_job = serializers.UUIDField(required=False, allow_null=True)
    source_conversion = serializers.UUIDField(
        required=False,
        allow_null=True,
        help_text="UUID of ImageConversion for manual entry creation"
    )
    original_image = serializers.ImageField(required=False, allow_null=True)
    catch_date = serializers.DateTimeField(required=False)

    class Meta:
        model = DexEntry
        fields = [
            'id',
            'animal',
            'source_vision_job',
            'source_conversion',
            'original_image',
            'location_lat',
            'location_lon',
            'location_name',
            'notes',
            'catch_date',
            'visibility',
        ]
        read_only_fields = ['id']

    def validate_source_conversion(self, value):
        """Validate that the image conversion exists and belongs to the user"""
        if value is None:
            return None

        from images.models import ImageConversion
        request = self.context.get('request')

        try:
            conversion = ImageConversion.objects.get(id=value)
            if conversion.user != request.user:
                raise serializers.ValidationError(
                    "Image conversion does not belong to current user"
                )
            if conversion.is_expired:
                raise serializers.ValidationError(
                    "Image conversion has expired"
                )
            return value
        except ImageConversion.DoesNotExist:
            raise serializers.ValidationError("Image conversion not found")

    def validate(self, attrs):
        """Validate that at least one image source is provided."""
        source_vision_job = attrs.get('source_vision_job')
        source_conversion = attrs.get('source_conversion')
        original_image = attrs.get('original_image')

        if not source_vision_job and not source_conversion and not original_image:
            raise serializers.ValidationError(
                "One of source_vision_job, source_conversion, or original_image must be provided."
            )

        return attrs

    def create(self, validated_data):
        """Set owner and handle image source."""
        from django.utils import timezone
        from vision.models import AnalysisJob
        from images.models import ImageConversion

        validated_data['owner'] = self.context['request'].user

        source_vision_job_id = validated_data.pop('source_vision_job', None)
        source_conversion_id = validated_data.pop('source_conversion', None)

        # Priority 1: source_vision_job - standard CV analysis flow
        if source_vision_job_id:
            try:
                vision_job = AnalysisJob.objects.get(id=source_vision_job_id)
                # Use the dex-compatible image from the vision job (preferred)
                # Fall back to deprecated image field for legacy support
                if not validated_data.get('original_image'):
                    if vision_job.dex_compatible_image:
                        validated_data['original_image'] = vision_job.dex_compatible_image
                    elif vision_job.image:
                        validated_data['original_image'] = vision_job.image
                # Link the vision job
                validated_data['source_vision_job'] = vision_job
            except AnalysisJob.DoesNotExist:
                pass

        # Priority 2: source_conversion - manual entry without CV
        elif source_conversion_id:
            try:
                conversion = ImageConversion.objects.get(id=source_conversion_id)
                # Use converted image as the original_image
                validated_data['original_image'] = conversion.converted_image
                # Mark conversion as used
                conversion.used_in_job = True
                conversion.save(update_fields=['used_in_job'])
            except ImageConversion.DoesNotExist:
                pass

        # Priority 3: original_image provided directly (legacy fallback)
        # No additional handling needed

        # Set catch_date to now if not provided
        if not validated_data.get('catch_date'):
            validated_data['catch_date'] = timezone.now()

        return super().create(validated_data)


class DexEntryUpdateSerializer(serializers.ModelSerializer):
    """
    Serializer for updating dex entries.

    Supports:
    - Changing the animal (re-identification)
    - Updating notes, visibility, customizations
    - Replacing the image via source_conversion (from ImageConversion)
    - Replacing the image via source_vision_job (from new CV analysis)
    """
    # Optional image replacement fields (write-only)
    source_vision_job = serializers.UUIDField(
        required=False,
        allow_null=True,
        write_only=True,
        help_text="UUID of AnalysisJob to use for image replacement"
    )
    source_conversion = serializers.UUIDField(
        required=False,
        allow_null=True,
        write_only=True,
        help_text="UUID of ImageConversion to use for image replacement"
    )

    class Meta:
        model = DexEntry
        fields = [
            'animal',
            'notes',
            'customizations',
            'visibility',
            'is_favorite',
            'location_name',
            'source_vision_job',
            'source_conversion',
        ]

    def validate_animal(self, value):
        """Validate that the animal exists"""
        from animals.models import Animal
        if not Animal.objects.filter(id=value.id).exists():
            raise serializers.ValidationError("Animal does not exist")
        return value

    def validate_source_vision_job(self, value):
        """Validate that the vision job exists and belongs to the user"""
        if value is None:
            return None

        from vision.models import AnalysisJob
        request = self.context.get('request')

        try:
            job = AnalysisJob.objects.get(id=value)
            if job.user != request.user:
                raise serializers.ValidationError(
                    "Vision job does not belong to current user"
                )
            if not job.dex_compatible_image and not job.image:
                raise serializers.ValidationError(
                    "Vision job has no associated image"
                )
            return value
        except AnalysisJob.DoesNotExist:
            raise serializers.ValidationError("Vision job not found")

    def validate_source_conversion(self, value):
        """Validate that the image conversion exists and belongs to the user"""
        if value is None:
            return None

        from images.models import ImageConversion
        request = self.context.get('request')

        try:
            conversion = ImageConversion.objects.get(id=value)
            if conversion.user != request.user:
                raise serializers.ValidationError(
                    "Image conversion does not belong to current user"
                )
            if conversion.is_expired:
                raise serializers.ValidationError(
                    "Image conversion has expired"
                )
            return value
        except ImageConversion.DoesNotExist:
            raise serializers.ValidationError("Image conversion not found")

    def update(self, instance, validated_data):
        """
        Update dex entry with optional image replacement.

        Image replacement priority:
        1. source_vision_job - Use image from a new CV analysis job
        2. source_conversion - Use image from ImageConversion (manual upload)
        """
        from vision.models import AnalysisJob
        from images.models import ImageConversion

        source_vision_job_id = validated_data.pop('source_vision_job', None)
        source_conversion_id = validated_data.pop('source_conversion', None)

        # Handle image replacement from vision job
        if source_vision_job_id:
            job = AnalysisJob.objects.get(id=source_vision_job_id)
            instance.source_vision_job = job
            # Clear direct image fields since we're now using vision job
            instance.original_image = None
            instance.processed_image = None

        # Handle image replacement from image conversion
        elif source_conversion_id:
            conversion = ImageConversion.objects.get(id=source_conversion_id)
            # Copy converted image to entry's original_image field
            instance.original_image = conversion.converted_image
            instance.processed_image = None
            instance.source_vision_job = None
            # Mark conversion as used
            conversion.used_in_job = True
            conversion.save(update_fields=['used_in_job'])

        return super().update(instance, validated_data)


class DexEntrySyncSerializer(serializers.ModelSerializer):
    """
    Serializer for syncing dex entries to client.
    Includes image metadata for comparison.
    """
    animal_id = serializers.UUIDField(source='animal.id', read_only=True)
    scientific_name = serializers.CharField(source='animal.scientific_name', read_only=True)
    common_name = serializers.CharField(source='animal.common_name', read_only=True)
    creation_index = serializers.IntegerField(source='animal.creation_index', read_only=True)
    owner_username = serializers.CharField(source='owner.username', read_only=True)

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
            'owner_username',
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
