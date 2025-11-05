"""
Image models for BiologiDex.
Centralized repository for processed images with transformation tracking.
"""
import uuid
import hashlib
from django.db import models
from django.conf import settings
from django.utils.translation import gettext_lazy as _


class ProcessedImage(models.Model):
    """
    Central repository for all processed images in the system.
    Tracks transformations and provides versioning capability.
    """
    SOURCE_TYPE_CHOICES = [
        ('vision_job', 'Vision Analysis Job'),
        ('user_upload', 'Direct User Upload'),
        ('dex_edit', 'Dex Entry Edit'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    # Source tracking
    source_type = models.CharField(
        max_length=20,
        choices=SOURCE_TYPE_CHOICES,
        help_text=_('Type of source that created this image')
    )
    source_id = models.UUIDField(
        null=True,
        blank=True,
        help_text=_('UUID of the source object (generic foreign key)')
    )

    # Files
    original_file = models.ImageField(
        upload_to='images/original/%Y/%m/',
        help_text=_('Original uploaded image file')
    )
    processed_file = models.ImageField(
        upload_to='images/processed/%Y/%m/',
        help_text=_('Processed image with transformations applied')
    )
    thumbnail = models.ImageField(
        upload_to='images/thumbnails/%Y/%m/',
        null=True,
        blank=True,
        help_text=_('Optional thumbnail for list views')
    )

    # Metadata
    original_format = models.CharField(
        max_length=10,
        help_text=_('Original file format (JPEG, PNG, etc.)')
    )
    original_dimensions = models.JSONField(
        help_text=_('Original dimensions as {"width": int, "height": int}')
    )
    processed_dimensions = models.JSONField(
        help_text=_('Processed dimensions as {"width": int, "height": int}')
    )
    file_size_bytes = models.IntegerField(
        help_text=_('File size in bytes')
    )

    # Transformations applied
    transformations = models.JSONField(
        default=dict,
        blank=True,
        help_text=_(
            'Applied transformations: '
            '{"rotation": 90, "crop": {...}, "brightness": 1.1, etc.}'
        )
    )

    # Processing details
    processing_warnings = models.JSONField(
        default=list,
        blank=True,
        help_text=_('List of warning messages during processing')
    )
    processing_errors = models.JSONField(
        default=list,
        blank=True,
        help_text=_('List of error messages during processing')
    )
    exif_data = models.JSONField(
        default=dict,
        blank=True,
        help_text=_('Extracted EXIF metadata')
    )

    # Versioning
    version = models.IntegerField(
        default=1,
        help_text=_('Version number of this image')
    )
    parent_image = models.ForeignKey(
        'self',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='versions',
        help_text=_('Parent image if this is a derived version')
    )

    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    # Checksums for deduplication
    original_checksum = models.CharField(
        max_length=64,
        db_index=True,
        help_text=_('SHA256 checksum of original file')
    )
    processed_checksum = models.CharField(
        max_length=64,
        db_index=True,
        help_text=_('SHA256 checksum of processed file')
    )

    class Meta:
        db_table = 'processed_images'
        verbose_name = _('Processed Image')
        verbose_name_plural = _('Processed Images')
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['source_type', 'source_id']),
            models.Index(fields=['original_checksum']),
            models.Index(fields=['processed_checksum']),
            models.Index(fields=['created_at']),
        ]

    def __str__(self):
        return f"ProcessedImage {self.id} - {self.source_type} (v{self.version})"

    @staticmethod
    def calculate_checksum(file_field):
        """Calculate SHA256 checksum for a file."""
        sha256 = hashlib.sha256()
        file_field.seek(0)
        for chunk in file_field.chunks():
            sha256.update(chunk)
        file_field.seek(0)
        return sha256.hexdigest()

    def save(self, *args, **kwargs):
        """Override save to calculate checksums if not set."""
        if not self.original_checksum and self.original_file:
            self.original_checksum = self.calculate_checksum(self.original_file)
        if not self.processed_checksum and self.processed_file:
            self.processed_checksum = self.calculate_checksum(self.processed_file)
        super().save(*args, **kwargs)