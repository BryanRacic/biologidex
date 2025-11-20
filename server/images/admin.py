"""
Admin interface for images app.
"""
from django.contrib import admin
from .models import ProcessedImage, ImageConversion


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


@admin.register(ImageConversion)
class ImageConversionAdmin(admin.ModelAdmin):
    """Admin interface for ImageConversion model."""
    list_display = [
        'id',
        'user',
        'original_format',
        'used_in_job',
        'created_at',
        'expires_at',
        'is_expired',
    ]
    list_filter = ['used_in_job', 'original_format', 'created_at']
    search_fields = ['id', 'user__username', 'checksum']
    readonly_fields = [
        'id',
        'checksum',
        'created_at',
        'expires_at',
    ]
    fieldsets = (
        ('User Information', {
            'fields': ('user',)
        }),
        ('Images', {
            'fields': ('original_image', 'converted_image')
        }),
        ('Metadata', {
            'fields': (
                'original_format',
                'original_size',
                'converted_size',
                'checksum',
            )
        }),
        ('Transformations', {
            'fields': ('transformations',)
        }),
        ('Status', {
            'fields': ('used_in_job',)
        }),
        ('Timestamps', {
            'fields': ('created_at', 'expires_at'),
        }),
    )

    def is_expired(self, obj):
        """Show if conversion has expired."""
        return obj.is_expired
    is_expired.boolean = True
    is_expired.short_description = 'Expired'
