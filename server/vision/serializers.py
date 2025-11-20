"""
Serializers for vision app.
"""
from rest_framework import serializers
from .models import AnalysisJob
from animals.serializers import AnimalListSerializer


class AnalysisJobSerializer(serializers.ModelSerializer):
    """Full serializer for AnalysisJob model with multiple animals support."""
    animal_details = AnimalListSerializer(source='identified_animal', read_only=True)
    duration = serializers.ReadOnlyField()
    dex_compatible_url = serializers.SerializerMethodField()
    conversion_id = serializers.UUIDField(source='source_conversion.id', read_only=True)

    class Meta:
        model = AnalysisJob
        fields = [
            'id',
            'source_conversion',
            'conversion_id',
            'image',  # Deprecated legacy field
            'dex_compatible_url',
            'image_conversion_status',
            'post_conversion_transformations',
            'user',
            'status',
            'cv_method',
            'model_name',
            'detail_level',
            'parsed_prediction',
            'identified_animal',  # Deprecated - first animal only
            'animal_details',
            'confidence_score',
            'detected_animals',  # NEW: List of all detected animals
            'selected_animal_index',  # NEW: Which animal user selected
            'cost_usd',
            'processing_time',
            'input_tokens',
            'output_tokens',
            'error_message',
            'retry_count',
            'created_at',
            'started_at',
            'completed_at',
            'duration',
        ]
        read_only_fields = [
            'id',
            'user',
            'status',
            'dex_compatible_url',
            'conversion_id',
            'image_conversion_status',
            'parsed_prediction',
            'identified_animal',
            'confidence_score',
            'detected_animals',
            'cost_usd',
            'processing_time',
            'input_tokens',
            'output_tokens',
            'error_message',
            'retry_count',
            'created_at',
            'started_at',
            'completed_at',
        ]

    def get_dex_compatible_url(self, obj):
        """Return URL for dex-compatible image."""
        # Prefer source_conversion image over legacy image field
        if obj.source_conversion and obj.source_conversion.converted_image:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.source_conversion.converted_image.url)
            return obj.source_conversion.converted_image.url
        elif obj.dex_compatible_image:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.dex_compatible_image.url)
            return obj.dex_compatible_image.url
        return None


class AnalysisJobCreateSerializer(serializers.ModelSerializer):
    """
    Serializer for creating analysis jobs.
    Supports both new conversion_id workflow and legacy image upload.
    """
    conversion_id = serializers.UUIDField(
        required=False,
        write_only=True,
        help_text='ID of pre-converted image (new workflow)'
    )

    class Meta:
        model = AnalysisJob
        fields = [
            'conversion_id',  # NEW: Preferred method
            'image',  # DEPRECATED: Legacy direct upload
            'post_conversion_transformations',  # NEW: Additional client-side transforms
            'cv_method',
            'model_name',
            'detail_level',
        ]

    def validate(self, attrs):
        """Ensure either conversion_id or image is provided."""
        conversion_id = attrs.get('conversion_id')
        image = attrs.get('image')

        if not conversion_id and not image:
            raise serializers.ValidationError(
                'Either conversion_id or image must be provided'
            )

        # If conversion_id provided, fetch and validate the conversion
        if conversion_id:
            from images.models import ImageConversion
            try:
                conversion = ImageConversion.objects.get(
                    id=conversion_id,
                    user=self.context['request'].user
                )

                if conversion.is_expired:
                    raise serializers.ValidationError(
                        'Image conversion has expired. Please upload again.'
                    )

                # Store conversion object for create method
                attrs['_conversion'] = conversion

            except ImageConversion.DoesNotExist:
                raise serializers.ValidationError(
                    'Invalid conversion_id or conversion not found'
                )

        return attrs

    def create(self, validated_data):
        """
        Create analysis job from conversion or direct image upload.
        """
        user = self.context['request'].user
        validated_data['user'] = user

        # Extract conversion if present
        conversion = validated_data.pop('_conversion', None)
        validated_data.pop('conversion_id', None)

        if conversion:
            # New workflow: Use converted image
            validated_data['source_conversion'] = conversion

            # Mark conversion as used
            conversion.used_in_job = True
            conversion.save(update_fields=['used_in_job'])

            # Use converted image as dex_compatible_image
            validated_data['dex_compatible_image'] = conversion.converted_image
            validated_data['image_conversion_status'] = 'completed'

        return super().create(validated_data)


class AnalysisJobListSerializer(serializers.ModelSerializer):
    """Lightweight serializer for job lists."""

    class Meta:
        model = AnalysisJob
        fields = [
            'id',
            'status',
            'parsed_prediction',
            'identified_animal',
            'cost_usd',
            'created_at',
            'completed_at',
        ]
