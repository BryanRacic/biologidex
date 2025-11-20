"""
Vision models for BiologiDex CV pipeline.
"""
import uuid
from django.db import models
from django.conf import settings
from django.utils.translation import gettext_lazy as _
from animals.models import Animal


class AnalysisJob(models.Model):
    """
    Tracks CV/AI analysis jobs for animal identification.
    Provides idempotency and audit trail for identification requests.
    """
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('processing', 'Processing'),
        ('completed', 'Completed'),
        ('failed', 'Failed'),
    ]

    CV_METHOD_CHOICES = [
        ('openai', 'OpenAI Vision'),
        ('fallback', 'Fallback CV Service'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    # Input - New conversion-based approach
    source_conversion = models.ForeignKey(
        'images.ImageConversion',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='analysis_jobs',
        help_text=_('Source image conversion (new workflow)')
    )

    # Input - Legacy direct upload (deprecated, will be removed)
    image = models.ImageField(
        upload_to='vision/analysis/original/%Y/%m/',
        null=True,
        blank=True,
        help_text=_('DEPRECATED: Original uploaded image (legacy workflow)')
    )
    dex_compatible_image = models.ImageField(
        upload_to='vision/analysis/dex_compatible/%Y/%m/',
        null=True,
        blank=True,
        help_text=_('Standardized PNG image for display (max 2560x2560)')
    )
    image_conversion_status = models.CharField(
        max_length=20,
        choices=[
            ('pending', 'Pending'),
            ('processing', 'Processing'),
            ('completed', 'Completed'),
            ('failed', 'Failed'),
            ('unnecessary', 'Unnecessary'),  # Original already meets criteria
        ],
        default='pending',
        help_text=_('Status of image standardization')
    )

    # Post-conversion transformations (applied after initial conversion)
    post_conversion_transformations = models.JSONField(
        default=dict,
        blank=True,
        help_text=_('Client-side transformations applied after image conversion (rotation, etc.)')
    )

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='analysis_jobs',
        help_text=_('User who submitted this image')
    )

    # Processing
    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default='pending',
        help_text=_('Current status of the analysis')
    )
    cv_method = models.CharField(
        max_length=20,
        choices=CV_METHOD_CHOICES,
        default='openai',
        help_text=_('CV method used for identification')
    )
    model_name = models.CharField(
        max_length=100,
        default='gpt-4o',
        help_text=_('Specific model used (e.g., gpt-4o, gpt-5-mini)')
    )
    detail_level = models.CharField(
        max_length=20,
        default='auto',
        help_text=_('Image detail level for vision models')
    )

    # Results - Multiple Animals Support
    raw_response = models.JSONField(
        null=True,
        blank=True,
        help_text=_('Raw response from CV service')
    )
    parsed_prediction = models.TextField(
        blank=True,
        help_text=_('Parsed prediction text (first animal or all animals separated by |)')
    )

    # Legacy single animal (deprecated - kept for backward compatibility)
    identified_animal = models.ForeignKey(
        Animal,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='analysis_jobs',
        help_text=_('DEPRECATED: First identified animal (legacy single-animal workflow)')
    )
    confidence_score = models.FloatField(
        null=True,
        blank=True,
        help_text=_('Confidence score (0-1) for first/selected animal')
    )

    # New multiple animals support
    detected_animals = models.JSONField(
        default=list,
        blank=True,
        help_text=_(
            'List of all detected animals with metadata. '
            'Format: [{"scientific_name": str, "common_name": str, '
            '"confidence": float, "animal_id": uuid, "is_new": bool}, ...]'
        )
    )
    selected_animal_index = models.IntegerField(
        null=True,
        blank=True,
        help_text=_('Index of the animal selected by user from detected_animals list')
    )

    # Metrics
    cost_usd = models.DecimalField(
        max_digits=10,
        decimal_places=6,
        null=True,
        blank=True,
        help_text=_('Cost of this API call in USD')
    )
    processing_time = models.FloatField(
        null=True,
        blank=True,
        help_text=_('Processing time in seconds')
    )
    input_tokens = models.IntegerField(
        null=True,
        blank=True,
        help_text=_('Number of input tokens used')
    )
    output_tokens = models.IntegerField(
        null=True,
        blank=True,
        help_text=_('Number of output tokens generated')
    )

    # Error handling
    error_message = models.TextField(
        blank=True,
        help_text=_('Error message if job failed')
    )
    retry_count = models.IntegerField(
        default=0,
        help_text=_('Number of retry attempts')
    )

    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    started_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'analysis_jobs'
        verbose_name = _('Analysis Job')
        verbose_name_plural = _('Analysis Jobs')
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', 'status']),
            models.Index(fields=['status', 'created_at']),
            models.Index(fields=['identified_animal']),
            models.Index(fields=['created_at']),
        ]

    def __str__(self):
        return f"AnalysisJob {self.id} - {self.status} ({self.user.username})"

    @property
    def is_complete(self):
        """Check if job has finished (success or failure)."""
        return self.status in ['completed', 'failed']

    @property
    def duration(self):
        """Calculate total duration from creation to completion."""
        if self.completed_at and self.created_at:
            return (self.completed_at - self.created_at).total_seconds()
        return None

    def mark_processing(self):
        """Mark job as processing."""
        from django.utils import timezone
        self.status = 'processing'
        self.started_at = timezone.now()
        self.save(update_fields=['status', 'started_at'])

    def mark_completed(self, **kwargs):
        """
        Mark job as completed with results.
        Accepts: parsed_prediction, identified_animal, confidence_score,
                cost_usd, processing_time, raw_response, etc.
        """
        from django.utils import timezone
        self.status = 'completed'
        self.completed_at = timezone.now()

        for key, value in kwargs.items():
            if hasattr(self, key):
                setattr(self, key, value)

        self.save()

    def mark_failed(self, error_message):
        """Mark job as failed with error message."""
        from django.utils import timezone
        self.status = 'failed'
        self.error_message = error_message
        self.completed_at = timezone.now()
        self.save(update_fields=['status', 'error_message', 'completed_at'])

    def increment_retry(self):
        """Increment retry counter."""
        self.retry_count += 1
        self.save(update_fields=['retry_count'])
