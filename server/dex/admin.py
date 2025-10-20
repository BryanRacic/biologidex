"""
Admin configuration for dex app.
"""
from django.contrib import admin
from .models import DexEntry


@admin.register(DexEntry)
class DexEntryAdmin(admin.ModelAdmin):
    """Admin interface for DexEntry model."""
    list_display = [
        'id',
        'owner',
        'animal',
        'catch_date',
        'visibility',
        'is_favorite',
        'created_at',
    ]
    list_filter = ['visibility', 'is_favorite', 'catch_date', 'created_at']
    search_fields = [
        'owner__username',
        'animal__scientific_name',
        'animal__common_name',
        'notes',
    ]
    readonly_fields = ['id', 'created_at', 'updated_at']
    ordering = ['-catch_date']
    date_hierarchy = 'catch_date'

    fieldsets = (
        ('Basic Information', {
            'fields': ('id', 'owner', 'animal', 'catch_date')
        }),
        ('Images', {
            'fields': ('original_image', 'processed_image')
        }),
        ('Location', {
            'fields': ('location_lat', 'location_lon', 'location_name'),
            'classes': ('collapse',)
        }),
        ('User Data', {
            'fields': ('notes', 'customizations', 'visibility', 'is_favorite')
        }),
        ('Metadata', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )

    def get_queryset(self, request):
        """Optimize queryset with select_related."""
        return super().get_queryset(request).select_related('owner', 'animal')
