"""
Views for images app.
"""
import hashlib
import logging
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.http import FileResponse
from django.shortcuts import get_object_or_404
from .models import ImageConversion
from .serializers import ImageConversionSerializer, ImageConversionCreateSerializer
from .processor import EnhancedImageProcessor

logger = logging.getLogger(__name__)


class ImageConversionViewSet(viewsets.GenericViewSet):
    """
    ViewSet for image conversion operations.
    Converts uploaded images to dex-compatible format.
    """
    permission_classes = [IsAuthenticated]
    serializer_class = ImageConversionSerializer

    def get_queryset(self):
        """Return conversions for the current user."""
        return ImageConversion.objects.filter(user=self.request.user)

    def create(self, request):
        """
        Convert an uploaded image to dex-compatible format.

        POST /api/v1/images/convert/
        """
        # Validate input
        input_serializer = ImageConversionCreateSerializer(data=request.data)
        if not input_serializer.is_valid():
            return Response(
                input_serializer.errors,
                status=status.HTTP_400_BAD_REQUEST
            )

        image_file = input_serializer.validated_data['image']
        transformations = input_serializer.validated_data.get('transformations', {})

        try:
            # Process the image
            processed_file, metadata = EnhancedImageProcessor.process_image_with_transformations(
                image_file,
                transformations=transformations,
                apply_exif_rotation=True
            )

            if not processed_file or metadata.get('error'):
                return Response(
                    {'error': metadata.get('error', 'Image processing failed')},
                    status=status.HTTP_500_INTERNAL_SERVER_ERROR
                )

            # Calculate checksum of processed image
            processed_file.seek(0)
            checksum = hashlib.sha256(processed_file.read()).hexdigest()
            processed_file.seek(0)

            # Create ImageConversion record
            conversion = ImageConversion(
                user=request.user,
                original_format=metadata['original_format'] or 'unknown',
                original_size=[
                    metadata['original_dimensions']['width'],
                    metadata['original_dimensions']['height']
                ],
                converted_size=[
                    metadata['processed_dimensions']['width'],
                    metadata['processed_dimensions']['height']
                ],
                transformations=metadata['transformations_applied'],
                checksum=checksum
            )

            # Save original image
            conversion.original_image.save(image_file.name, image_file, save=False)

            # Save converted image
            conversion.converted_image.save(
                f"converted_{image_file.name.rsplit('.', 1)[0]}.png",
                processed_file,
                save=False
            )

            conversion.save()

            logger.info(
                f"Image conversion created: {conversion.id} for user {request.user.username}"
            )

            # Return serialized response
            output_serializer = ImageConversionSerializer(
                conversion,
                context={'request': request}
            )
            return Response(
                output_serializer.data,
                status=status.HTTP_201_CREATED
            )

        except Exception as e:
            logger.error(f"Image conversion failed: {str(e)}", exc_info=True)
            return Response(
                {'error': f'Image conversion failed: {str(e)}'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

    @action(detail=True, methods=['get'], url_path='download')
    def download(self, request, pk=None):
        """
        Download the converted image.

        GET /api/v1/images/convert/{id}/download/
        """
        conversion = get_object_or_404(ImageConversion, id=pk, user=request.user)

        # Check if expired
        if conversion.is_expired:
            return Response(
                {'error': 'This conversion has expired'},
                status=status.HTTP_410_GONE
            )

        # Return the converted image file
        try:
            return FileResponse(
                conversion.converted_image.open('rb'),
                as_attachment=False,
                content_type='image/png'
            )
        except Exception as e:
            logger.error(f"Failed to serve converted image: {str(e)}", exc_info=True)
            return Response(
                {'error': 'Failed to retrieve converted image'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

    def retrieve(self, request, pk=None):
        """
        Get metadata about a conversion.

        GET /api/v1/images/convert/{id}/
        """
        conversion = get_object_or_404(ImageConversion, id=pk, user=request.user)
        serializer = ImageConversionSerializer(conversion, context={'request': request})
        return Response(serializer.data)
