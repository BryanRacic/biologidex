"""
Admin configuration for vision app.
"""
from django.contrib import admin
from .models import AnalysisJob


@admin.register(AnalysisJob)
class AnalysisJobAdmin(admin.ModelAdmin):
    """Admin interface for AnalysisJob model."""
    list_display = [
        'id',
        'user',
        'status',
        'cv_method',
        'model_name',
        'identified_animal',
        'cost_usd',
        'created_at',
        'completed_at',
    ]
    list_filter = ['status', 'cv_method', 'model_name', 'created_at']
    search_fields = [
        'user__username',
        'parsed_prediction',
        'identified_animal__scientific_name',
    ]
    readonly_fields = [
        'id',
        'created_at',
        'started_at',
        'completed_at',
        'duration',
        'raw_response',
    ]
    ordering = ['-created_at']
    date_hierarchy = 'created_at'

    fieldsets = (
        ('Basic Information', {
            'fields': ('id', 'user', 'image', 'status')
        }),
        ('CV Configuration', {
            'fields': ('cv_method', 'model_name', 'detail_level')
        }),
        ('Results', {
            'fields': (
                'parsed_prediction',
                'identified_animal',
                'confidence_score',
                'raw_response',
            )
        }),
        ('Metrics', {
            'fields': (
                'cost_usd',
                'processing_time',
                'input_tokens',
                'output_tokens',
            )
        }),
        ('Error Handling', {
            'fields': ('error_message', 'retry_count'),
            'classes': ('collapse',)
        }),
        ('Timestamps', {
            'fields': ('created_at', 'started_at', 'completed_at', 'duration'),
            'classes': ('collapse',)
        }),
    )

    def get_queryset(self, request):
        """Optimize queryset with select_related."""
        return super().get_queryset(request).select_related('user', 'identified_animal')

    actions = ['retry_failed_jobs']

    def retry_failed_jobs(self, request, queryset):
        """Retry selected failed jobs."""
        from .tasks import process_analysis_job

        failed_jobs = queryset.filter(status='failed')
        count = 0

        for job in failed_jobs:
            job.status = 'pending'
            job.error_message = ''
            job.save(update_fields=['status', 'error_message'])
            process_analysis_job.delay(str(job.id))
            count += 1

        self.message_user(request, f'{count} jobs queued for retry.')

    retry_failed_jobs.short_description = 'Retry selected failed jobs'
