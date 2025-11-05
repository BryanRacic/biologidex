"""
Admin interface for images app.
"""
from django.contrib import admin
from .models import ProcessedImage


@admin.register(ProcessedImage)
class ProcessedImageAdmin(admin.ModelAdmin):
    """Admin interface for ProcessedImage model."""
    list_display = [
        'id',
        'source_type',
        'source_id',
        'version',
        'original_format',
        'created_at',
    ]
    list_filter = ['source_type', 'original_format', 'created_at']
    search_fields = ['id', 'source_id', 'original_checksum', 'processed_checksum']
    readonly_fields = [
        'id',
        'original_checksum',
        'processed_checksum',
        'created_at',
        'updated_at',
    ]
    fieldsets = (
        ('Source Information', {
            'fields': ('source_type', 'source_id')
        }),
        ('Files', {
            'fields': ('original_file', 'processed_file', 'thumbnail')
        }),
        ('Metadata', {
            'fields': (
                'original_format',
                'original_dimensions',
                'processed_dimensions',
                'file_size_bytes',
            )
        }),
        ('Transformations', {
            'fields': ('transformations', 'exif_data')
        }),
        ('Processing', {
            'fields': ('processing_warnings', 'processing_errors')
        }),
        ('Versioning', {
            'fields': ('version', 'parent_image')
        }),
        ('Checksums', {
            'fields': ('original_checksum', 'processed_checksum'),
            'classes': ('collapse',)
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )
