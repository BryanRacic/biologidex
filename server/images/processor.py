"""
Enhanced image processing service with transformation support.
Extends the base ImageProcessor with rotation and other transformations.
"""
import logging
from io import BytesIO
from typing import Tuple, Optional
from PIL import Image
from django.core.files.base import ContentFile

logger = logging.getLogger(__name__)


class EnhancedImageProcessor:
    """Extended image processor with rotation and transformation support."""

    MAX_DIMENSION = 2560
    OUTPUT_FORMAT = 'PNG'

    @classmethod
    def apply_transformations(cls, img: Image.Image, transformations: dict) -> Image.Image:
        """
        Apply a series of transformations to an image.

        Args:
            img: PIL Image object
            transformations: Dictionary of transformations to apply
                {
                    "rotation": int (0, 90, 180, 270),
                    "crop": {"x": int, "y": int, "width": int, "height": int},
                    "brightness": float,
                    "contrast": float
                }

        Returns:
            Transformed PIL Image object
        """
        logger.info(f"Applying transformations: {transformations}")

        # Handle rotation (including EXIF auto-rotation)
        if 'rotation' in transformations:
            angle = transformations['rotation']
            if angle not in [0, 90, 180, 270]:
                logger.warning(f"Invalid rotation angle {angle}, skipping rotation")
            elif angle != 0:
                # PIL rotates counter-clockwise, negate angle for clockwise rotation
                img = img.rotate(-angle, expand=True, fillcolor='white')
                logger.info(f"Applied rotation: {angle} degrees")

        # Handle crop
        if 'crop' in transformations:
            crop = transformations['crop']
            try:
                x = crop['x']
                y = crop['y']
                width = crop['width']
                height = crop['height']

                # Validate crop boundaries
                if x < 0 or y < 0 or width <= 0 or height <= 0:
                    logger.warning(f"Invalid crop parameters: {crop}")
                elif x + width > img.width or y + height > img.height:
                    logger.warning(f"Crop exceeds image boundaries: {crop}")
                else:
                    img = img.crop((x, y, x + width, y + height))
                    logger.info(f"Applied crop: {crop}")
            except KeyError as e:
                logger.error(f"Missing crop parameter: {e}")

        # Additional transformations can be added here in the future
        # - brightness adjustment
        # - contrast adjustment
        # - filters

        return img

    @classmethod
    def auto_rotate_from_exif(cls, img: Image.Image) -> Tuple[Image.Image, int]:
        """
        Auto-rotate image based on EXIF orientation.

        Args:
            img: PIL Image object

        Returns:
            Tuple of (rotated image, rotation angle applied)
        """
        try:
            exif = img.getexif()
            if not exif:
                return img, 0

            orientation = exif.get(0x0112, 1)  # 0x0112 is the EXIF orientation tag

            # EXIF orientation to rotation angle mapping
            rotation_map = {
                3: 180,  # Rotate 180
                6: 270,  # Rotate 90 CW (PIL uses CCW, so 270)
                8: 90    # Rotate 90 CCW
            }

            if orientation in rotation_map:
                angle = rotation_map[orientation]
                img = img.rotate(-angle, expand=True)
                logger.info(f"Auto-rotated image based on EXIF orientation {orientation}: {angle} degrees")
                return img, angle
        except Exception as e:
            logger.warning(f"Failed to read EXIF orientation: {e}")

        return img, 0

    @classmethod
    def extract_exif_data(cls, img: Image.Image) -> dict:
        """
        Extract EXIF data from image.

        Args:
            img: PIL Image object

        Returns:
            Dictionary of EXIF data
        """
        exif_data = {}
        try:
            exif = img.getexif()
            if exif:
                for tag_id, value in exif.items():
                    try:
                        # Convert tag ID to human-readable name
                        from PIL.ExifTags import TAGS
                        tag = TAGS.get(tag_id, tag_id)

                        # Convert value to JSON-serializable format
                        if isinstance(value, bytes):
                            try:
                                value = value.decode('utf-8', errors='ignore')
                            except:
                                value = str(value)
                        elif not isinstance(value, (str, int, float, bool, type(None))):
                            value = str(value)

                        exif_data[tag] = value
                    except Exception as e:
                        logger.debug(f"Failed to process EXIF tag {tag_id}: {e}")
        except Exception as e:
            logger.warning(f"Failed to extract EXIF data: {e}")

        return exif_data

    @classmethod
    def process_image_with_transformations(
        cls,
        image_file,
        transformations: Optional[dict] = None,
        apply_exif_rotation: bool = True
    ) -> Tuple[Optional[ContentFile], dict]:
        """
        Process an image with transformations applied.

        Args:
            image_file: Django ImageField file object
            transformations: Optional dictionary of transformations to apply
            apply_exif_rotation: Whether to auto-rotate based on EXIF orientation

        Returns:
            Tuple of (ContentFile or None, metadata dict)
            ContentFile is None on error.
        """
        metadata = {
            'original_format': None,
            'original_dimensions': None,
            'processed_dimensions': None,
            'was_resized': False,
            'was_converted': False,
            'was_transformed': False,
            'transformations_applied': {},
            'exif_data': {},
            'error': None
        }

        try:
            # Open image with Pillow
            image_file.seek(0)
            img = Image.open(image_file)

            # Store original metadata
            metadata['original_format'] = img.format
            metadata['original_dimensions'] = {'width': img.width, 'height': img.height}

            # Extract EXIF data
            metadata['exif_data'] = cls.extract_exif_data(img)

            # Apply EXIF auto-rotation if requested
            exif_rotation = 0
            if apply_exif_rotation:
                img, exif_rotation = cls.auto_rotate_from_exif(img)
                if exif_rotation != 0:
                    metadata['transformations_applied']['exif_rotation'] = exif_rotation

            # Apply user-requested transformations
            if transformations:
                img = cls.apply_transformations(img, transformations)
                metadata['was_transformed'] = True
                metadata['transformations_applied'].update(transformations)

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
            needs_resize = max(img.size) > cls.MAX_DIMENSION
            if needs_resize:
                original_size = img.size
                img.thumbnail((cls.MAX_DIMENSION, cls.MAX_DIMENSION), Image.Resampling.LANCZOS)
                metadata['was_resized'] = True
                logger.info(f"Image resized from {original_size} to {img.size}")

            metadata['processed_dimensions'] = {'width': img.width, 'height': img.height}

            # Convert to PNG
            output = BytesIO()
            img.save(output, format=cls.OUTPUT_FORMAT, optimize=True)
            output.seek(0)

            metadata['was_converted'] = metadata['original_format'] != cls.OUTPUT_FORMAT

            # Create ContentFile for Django
            import os
            filename = f"processed_{os.path.splitext(os.path.basename(image_file.name))[0]}.png"
            content_file = ContentFile(output.read(), name=filename)

            logger.info(
                f"Image processed successfully: {metadata['original_format']} "
                f"{metadata['original_dimensions']} -> PNG {metadata['processed_dimensions']}"
            )

            return content_file, metadata

        except Exception as e:
            logger.error(f"Image processing failed: {str(e)}", exc_info=True)
            metadata['error'] = str(e)
            return None, metadata