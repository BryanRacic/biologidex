"""
Image processing service for BiologiDex.
Handles image format conversion and resizing for standardized display.
"""
import os
from PIL import Image
from io import BytesIO
from django.core.files.base import ContentFile
from typing import Tuple, Optional
import logging

logger = logging.getLogger(__name__)


class ImageProcessor:
    """Handles image format conversion and resizing for BiologiDex."""

    MAX_DIMENSION = 2560
    OUTPUT_FORMAT = 'PNG'
    JPEG_QUALITY = 95  # For future JPEG support

    @classmethod
    def process_image(cls, image_file) -> Tuple[Optional[ContentFile], dict]:
        """
        Process an image to create a dex-compatible version.

        Args:
            image_file: Django ImageField file object

        Returns:
            Tuple of (ContentFile or None, metadata dict)
            ContentFile is None if original already meets criteria or on error.
        """
        metadata = {
            'original_format': None,
            'original_dimensions': None,
            'processed_dimensions': None,
            'was_resized': False,
            'was_converted': False,
            'error': None
        }

        try:
            # Open image with Pillow
            image_file.seek(0)
            img = Image.open(image_file)

            # Store original metadata
            metadata['original_format'] = img.format
            metadata['original_dimensions'] = img.size

            # Check if processing needed
            needs_resize = max(img.size) > cls.MAX_DIMENSION
            needs_conversion = img.format != cls.OUTPUT_FORMAT

            if not needs_resize and not needs_conversion:
                # Original already meets criteria
                logger.info(f"Image already dex-compatible: {img.format} {img.size}")
                return None, metadata

            # Convert RGBA to RGB if necessary (for PNG with transparency)
            if img.mode in ('RGBA', 'LA', 'P'):
                # Create white background
                background = Image.new('RGB', img.size, (255, 255, 255))
                if img.mode == 'P':
                    img = img.convert('RGBA')
                background.paste(img, mask=img.split()[-1] if img.mode == 'RGBA' else None)
                img = background
            elif img.mode != 'RGB':
                img = img.convert('RGB')

            # Resize if needed (maintain aspect ratio)
            if needs_resize:
                original_size = img.size
                img.thumbnail((cls.MAX_DIMENSION, cls.MAX_DIMENSION), Image.Resampling.LANCZOS)
                metadata['was_resized'] = True
                metadata['processed_dimensions'] = img.size
                logger.info(f"Image resized from {original_size} to {img.size}")
            else:
                metadata['processed_dimensions'] = metadata['original_dimensions']

            # Convert to PNG
            output = BytesIO()
            img.save(output, format=cls.OUTPUT_FORMAT, optimize=True)
            output.seek(0)

            metadata['was_converted'] = needs_conversion
            logger.info(f"Image converted to {cls.OUTPUT_FORMAT}, size: {output.tell()} bytes")

            # Create ContentFile for Django
            filename = f"dex_compatible_{os.path.splitext(os.path.basename(image_file.name))[0]}.png"
            return ContentFile(output.read(), name=filename), metadata

        except Exception as e:
            logger.error(f"Image processing failed: {str(e)}", exc_info=True)
            metadata['error'] = str(e)
            return None, metadata

    @classmethod
    def extract_image_metadata(cls, image_file) -> dict:
        """Extract useful metadata from image."""
        try:
            image_file.seek(0)
            img = Image.open(image_file)

            # Extract EXIF if available
            exif = img.getexif() if hasattr(img, 'getexif') else {}

            return {
                'format': img.format,
                'mode': img.mode,
                'size': img.size,
                'width': img.width,
                'height': img.height,
                'has_transparency': img.mode in ('RGBA', 'LA', 'P'),
                'exif_orientation': exif.get(0x0112, 1) if exif else 1,  # EXIF Orientation tag
            }
        except Exception as e:
            logger.error(f"Metadata extraction failed: {str(e)}")
            return {}
