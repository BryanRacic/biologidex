"""
DexEntry models for BiologiDex.
"""
import uuid
from django.db import models
from django.conf import settings
from django.utils.translation import gettext_lazy as _
from animals.models import Animal


class DexEntry(models.Model):
    """
    A user's personal record of capturing/observing an animal.
    Links a user to an animal with additional metadata and customization.
    """
    VISIBILITY_CHOICES = [
        ('private', 'Private'),
        ('friends', 'Friends Only'),
        ('public', 'Public'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    # Relationships
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='dex_entries',
        help_text=_('User who captured this animal')
    )
    animal = models.ForeignKey(
        Animal,
        on_delete=models.CASCADE,
        related_name='dex_entries',
        help_text=_('The animal species')
    )
    source_vision_job = models.ForeignKey(
        'vision.AnalysisJob',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='dex_entries',
        help_text=_('Source vision job with dex-compatible image')
    )

    # Images
    original_image = models.ImageField(
        upload_to='dex/original/%Y/%m/',
        help_text=_('Original uploaded image')
    )
    processed_image = models.ImageField(
        upload_to='dex/processed/%Y/%m/',
        null=True,
        blank=True,
        help_text=_('Processed/cropped image for card display')
    )

    # Location data (optional)
    location_lat = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        null=True,
        blank=True,
        help_text=_('Latitude of capture location')
    )
    location_lon = models.DecimalField(
        max_digits=9,
        decimal_places=6,
        null=True,
        blank=True,
        help_text=_('Longitude of capture location')
    )
    location_name = models.CharField(
        max_length=200,
        blank=True,
        help_text=_('Human-readable location name')
    )

    # User notes and customization
    notes = models.TextField(
        blank=True,
        help_text=_('User notes about this capture')
    )
    customizations = models.JSONField(
        default=dict,
        blank=True,
        help_text=_('Card styling: background, stickers, frames, etc.')
    )

    # Metadata
    catch_date = models.DateTimeField(
        help_text=_('When the animal was observed/photographed')
    )
    visibility = models.CharField(
        max_length=10,
        choices=VISIBILITY_CHOICES,
        default='friends',
        help_text=_('Who can see this entry')
    )
    is_favorite = models.BooleanField(
        default=False,
        help_text=_('User marked as favorite')
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'dex_entries'
        verbose_name = _('Dex Entry')
        verbose_name_plural = _('Dex Entries')
        ordering = ['-catch_date']
        unique_together = [['owner', 'animal', 'catch_date']]
        indexes = [
            # Original indexes
            models.Index(fields=['owner', 'animal']),
            models.Index(fields=['owner', 'catch_date']),
            models.Index(fields=['owner', 'visibility']),
            models.Index(fields=['animal', 'visibility']),
            models.Index(fields=['catch_date']),
            models.Index(fields=['is_favorite']),
            # New indexes for sync optimization (Phase 5)
            models.Index(fields=['owner', 'updated_at'], name='dex_owner_updated_idx'),
            models.Index(fields=['visibility', 'updated_at'], name='dex_visibility_updated_idx'),
            models.Index(fields=['updated_at'], name='dex_updated_at_idx'),
        ]

    def __str__(self):
        return f"{self.owner.username} - {self.animal.scientific_name} ({self.catch_date.date()})"

    @property
    def has_location(self):
        """Check if entry has valid location data."""
        return self.location_lat is not None and self.location_lon is not None

    def get_location_coords(self):
        """Return location as (lat, lon) tuple or None."""
        if self.has_location:
            return (float(self.location_lat), float(self.location_lon))
        return None

    @property
    def display_image_url(self):
        """Get URL for display image (dex-compatible or processed or original)."""
        # Prefer dex-compatible image from vision job
        if self.source_vision_job and self.source_vision_job.dex_compatible_image:
            return self.source_vision_job.dex_compatible_image.url
        # Fall back to processed image
        elif self.processed_image:
            return self.processed_image.url
        # Final fallback to original
        else:
            return self.original_image.url
