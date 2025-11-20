"""
Serializers for images app.
"""
from rest_framework import serializers
from .models import ImageConversion


class ImageConversionSerializer(serializers.ModelSerializer):
    """Serializer for ImageConversion model."""
    download_url = serializers.SerializerMethodField()
    metadata = serializers.SerializerMethodField()

    class Meta:
        model = ImageConversion
        fields = [
            'id',
            'download_url',
            'metadata',
            'created_at',
            'expires_at',
        ]
        read_only_fields = ['id', 'created_at', 'expires_at']

    def get_download_url(self, obj):
        """Get the URL to download the converted image."""
        request = self.context.get('request')
        if request and obj.converted_image:
            return request.build_absolute_uri(obj.converted_image.url)
        return None

    def get_metadata(self, obj):
        """Get metadata about the conversion."""
        return {
            'original_format': obj.original_format,
            'original_size': obj.original_size,
            'converted_size': obj.converted_size,
            'transformations_applied': obj.transformations,
            'checksum': obj.checksum,
        }


class ImageConversionCreateSerializer(serializers.Serializer):
    """Serializer for creating an image conversion."""
    image = serializers.ImageField(
        required=True,
        help_text='Image file to convert'
    )
    transformations = serializers.JSONField(
        required=False,
        default=dict,
        help_text='Optional transformations to apply (rotation, crop, etc.)'
    )

    def validate_image(self, value):
        """Validate the uploaded image."""
        # Check file size (max 20MB)
        max_size = 20 * 1024 * 1024  # 20MB
        if value.size > max_size:
            raise serializers.ValidationError(
                f'Image file too large. Maximum size is {max_size / (1024 * 1024)}MB.'
            )

        # Check file format
        allowed_formats = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/heic']
        content_type = value.content_type.lower()
        if content_type not in allowed_formats:
            raise serializers.ValidationError(
                f'Unsupported image format: {content_type}. '
                f'Allowed formats: JPEG, PNG, WebP, HEIC.'
            )

        return value

    def validate_transformations(self, value):
        """Validate transformations JSON."""
        if not isinstance(value, dict):
            raise serializers.ValidationError('Transformations must be a JSON object.')

        # Validate rotation if present
        if 'rotation' in value:
            rotation = value['rotation']
            if not isinstance(rotation, int) or rotation not in [0, 90, 180, 270]:
                raise serializers.ValidationError(
                    'Rotation must be one of: 0, 90, 180, 270.'
                )

        # Validate crop if present
        if 'crop' in value:
            crop = value['crop']
            if not isinstance(crop, dict):
                raise serializers.ValidationError('Crop must be a JSON object.')
            required_keys = ['x', 'y', 'width', 'height']
            if not all(k in crop for k in required_keys):
                raise serializers.ValidationError(
                    f'Crop must contain: {", ".join(required_keys)}.'
                )

        return value
