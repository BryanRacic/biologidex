"""
Admin configuration for animals app.
"""
from django.contrib import admin
from .models import Animal


@admin.register(Animal)
class AnimalAdmin(admin.ModelAdmin):
    """Admin interface for Animal model."""
    list_display = [
        'creation_index',
        'scientific_name',
        'common_name',
        'conservation_status',
        'verified',
        'created_at',
    ]
    list_filter = ['verified', 'conservation_status', 'kingdom', 'phylum', 'family']
    search_fields = ['scientific_name', 'common_name', 'genus', 'species']
    readonly_fields = ['id', 'creation_index', 'created_at', 'updated_at', 'discovery_count']
    ordering = ['creation_index']

    fieldsets = (
        ('Basic Information', {
            'fields': ('id', 'scientific_name', 'common_name', 'creation_index')
        }),
        ('Taxonomy', {
            'fields': ('kingdom', 'phylum', 'class_name', 'order', 'family', 'genus', 'species')
        }),
        ('Details', {
            'fields': ('description', 'habitat', 'diet', 'conservation_status', 'interesting_facts')
        }),
        ('Metadata', {
            'fields': ('created_by', 'verified', 'created_at', 'updated_at', 'discovery_count'),
            'classes': ('collapse',)
        }),
    )

    actions = ['mark_verified', 'mark_unverified']

    def mark_verified(self, request, queryset):
        """Mark selected animals as verified."""
        updated = queryset.update(verified=True)
        self.message_user(request, f'{updated} animals marked as verified.')

    mark_verified.short_description = 'Mark selected animals as verified'

    def mark_unverified(self, request, queryset):
        """Mark selected animals as unverified."""
        updated = queryset.update(verified=False)
        self.message_user(request, f'{updated} animals marked as unverified.')

    mark_unverified.short_description = 'Mark selected animals as unverified'
