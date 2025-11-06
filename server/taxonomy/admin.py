# taxonomy/admin.py
from django.contrib import admin
from django.utils.html import format_html
from django.urls import reverse
from django.db.models import Count
from .models import (
    DataSource, ImportJob, Taxonomy, CommonName,
    GeographicDistribution, TaxonomicRank
)
from .raw_models import RawCatalogueOfLife


@admin.register(DataSource)
class DataSourceAdmin(admin.ModelAdmin):
    list_display = ['name', 'short_code', 'update_frequency', 'is_active', 'priority', 'created_at']
    list_filter = ['is_active', 'update_frequency']
    search_fields = ['name', 'short_code', 'full_name']
    ordering = ['priority', 'name']
    readonly_fields = ['id', 'created_at', 'updated_at']

    fieldsets = (
        ('Basic Information', {
            'fields': ('id', 'name', 'short_code', 'full_name', 'url')
        }),
        ('Configuration', {
            'fields': ('api_endpoint', 'update_frequency', 'priority', 'is_active')
        }),
        ('Attribution', {
            'fields': ('license', 'citation_format')
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at')
        })
    )


@admin.register(ImportJob)
class ImportJobAdmin(admin.ModelAdmin):
    list_display = [
        'id_short', 'source', 'version', 'status',
        'records_imported', 'records_failed', 'file_size_display', 'created_at'
    ]
    list_filter = ['status', 'source', 'created_at']
    search_fields = ['version', 'id']
    readonly_fields = [
        'id', 'source', 'version', 'started_at', 'completed_at',
        'created_at', 'updated_at', 'error_log', 'metadata'
    ]
    ordering = ['-created_at']

    fieldsets = (
        ('Job Information', {
            'fields': ('id', 'source', 'version', 'status')
        }),
        ('Progress', {
            'fields': (
                'records_total', 'records_imported', 'records_failed',
                'file_path', 'file_size_mb'
            )
        }),
        ('Timestamps', {
            'fields': ('created_at', 'started_at', 'completed_at', 'updated_at')
        }),
        ('Details', {
            'classes': ('collapse',),
            'fields': ('metadata', 'error_log')
        })
    )

    def has_add_permission(self, request):
        return False  # Prevent manual creation

    def has_delete_permission(self, request, obj=None):
        # Only allow deletion of failed or old completed jobs
        if obj and obj.status in ['completed', 'failed']:
            return True
        return False

    def id_short(self, obj):
        """Show short version of UUID"""
        return str(obj.id)[:8]
    id_short.short_description = 'ID'

    def file_size_display(self, obj):
        """Format file size nicely"""
        if obj.file_size_mb:
            return f"{obj.file_size_mb:.2f} MB"
        return "-"
    file_size_display.short_description = 'File Size'


@admin.register(TaxonomicRank)
class TaxonomicRankAdmin(admin.ModelAdmin):
    list_display = ['name', 'level', 'plural']
    ordering = ['level']
    search_fields = ['name', 'plural']


@admin.register(Taxonomy)
class TaxonomyAdmin(admin.ModelAdmin):
    list_display = [
        'scientific_name', 'rank', 'status', 'kingdom',
        'phylum', 'class_name', 'source_link', 'completeness_display'
    ]
    list_filter = [
        'status', 'kingdom', 'phylum', 'rank__name', 'source__short_code',
        'extinct', 'nomenclatural_code'
    ]
    search_fields = [
        'scientific_name', 'genus', 'species',
        'source_taxon_id', 'common_names__name'
    ]
    readonly_fields = [
        'id', 'created_at', 'updated_at', 'completeness_score',
        'full_hierarchy_display'
    ]

    fieldsets = (
        ('Identification', {
            'fields': (
                'id', 'source', 'source_taxon_id', 'import_job',
                'scientific_name', 'authorship', 'rank', 'status'
            )
        }),
        ('Main Taxonomy', {
            'fields': (
                'kingdom', 'phylum', 'class_name', 'order',
                'family', 'subfamily', 'genus', 'species', 'subspecies'
            )
        }),
        ('Extended Taxonomy', {
            'classes': ('collapse',),
            'fields': (
                'subkingdom', 'subphylum', 'subclass', 'suborder',
                'superfamily', 'tribe', 'subtribe', 'subgenus',
                'section', 'variety', 'form'
            )
        }),
        ('Name Components', {
            'classes': ('collapse',),
            'fields': (
                'generic_name', 'specific_epithet', 'infraspecific_epithet'
            )
        }),
        ('Metadata', {
            'fields': (
                'extinct', 'environment', 'nomenclatural_code',
                'source_url', 'source_reference',
                'completeness_score', 'confidence_score'
            )
        }),
        ('Relationships', {
            'fields': ('parent', 'accepted_name')
        }),
        ('Hierarchy View', {
            'classes': ('collapse',),
            'fields': ('full_hierarchy_display',)
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at', 'source_modified_at')
        })
    )

    def source_link(self, obj):
        if obj.source_url:
            return format_html(
                '<a href="{}" target="_blank">{}</a>',
                obj.source_url,
                obj.source.short_code
            )
        return obj.source.short_code
    source_link.short_description = 'Source'

    def completeness_display(self, obj):
        """Display completeness score as percentage"""
        if obj.completeness_score:
            percent = float(obj.completeness_score) * 100
            color = 'green' if percent >= 80 else 'orange' if percent >= 50 else 'red'
            return format_html(
                '<span style="color: {};">{:.0f}%</span>',
                color, percent
            )
        return '-'
    completeness_display.short_description = 'Completeness'

    def full_hierarchy_display(self, obj):
        """Display full taxonomic hierarchy"""
        hierarchy = obj.full_hierarchy
        html = '<table style="border: 1px solid #ddd;">'
        for rank, value in hierarchy.items():
            if value:
                html += f'<tr><td style="padding: 4px; font-weight: bold;">{rank.capitalize()}:</td><td style="padding: 4px;">{value}</td></tr>'
        html += '</table>'
        return format_html(html)
    full_hierarchy_display.short_description = 'Full Hierarchy'


@admin.register(CommonName)
class CommonNameAdmin(admin.ModelAdmin):
    list_display = ['name', 'taxonomy_link', 'language', 'country', 'is_preferred', 'source']
    list_filter = ['language', 'is_preferred', 'country', 'source__short_code']
    search_fields = ['name', 'taxonomy__scientific_name']
    autocomplete_fields = ['taxonomy']

    def taxonomy_link(self, obj):
        url = reverse('admin:taxonomy_taxonomy_change', args=[obj.taxonomy.id])
        return format_html('<a href="{}">{}</a>', url, obj.taxonomy.scientific_name)
    taxonomy_link.short_description = 'Taxonomy'


@admin.register(GeographicDistribution)
class GeographicDistributionAdmin(admin.ModelAdmin):
    list_display = [
        'taxonomy_link', 'area_name', 'area_code', 'gazetteer',
        'establishment_means', 'occurrence_status', 'threat_status'
    ]
    list_filter = [
        'establishment_means', 'occurrence_status', 'gazetteer', 'source__short_code'
    ]
    search_fields = ['taxonomy__scientific_name', 'area_name', 'area_code']
    autocomplete_fields = ['taxonomy']

    def taxonomy_link(self, obj):
        url = reverse('admin:taxonomy_taxonomy_change', args=[obj.taxonomy.id])
        return format_html('<a href="{}">{}</a>', url, obj.taxonomy.scientific_name)
    taxonomy_link.short_description = 'Taxonomy'


@admin.register(RawCatalogueOfLife)
class RawCatalogueOfLifeAdmin(admin.ModelAdmin):
    list_display = [
        'id', 'col_id', 'scientific_name', 'status', 'rank',
        'is_processed', 'import_job', 'created_at'
    ]
    list_filter = ['is_processed', 'status', 'rank', 'import_job']
    search_fields = ['col_id', 'scientific_name', 'genus', 'species']
    readonly_fields = ['id', 'created_at', 'processing_errors']
    ordering = ['-created_at']

    fieldsets = (
        ('Processing', {
            'fields': ('import_job', 'is_processed', 'processing_errors')
        }),
        ('Identification', {
            'fields': (
                'col_id', 'parent_id', 'basionym_id', 'status', 'rank',
                'scientific_name', 'authorship'
            )
        }),
        ('Taxonomy', {
            'fields': (
                'kingdom', 'phylum', 'class_name', 'order',
                'family', 'subfamily', 'tribe', 'subtribe',
                'genus', 'subgenus', 'section',
                'species', 'subspecies', 'variety', 'form'
            )
        }),
        ('Name Components', {
            'fields': (
                'generic_name', 'specific_epithet', 'infraspecific_epithet'
            )
        }),
        ('Metadata', {
            'fields': ('code', 'extinct', 'environment')
        }),
        ('Timestamps', {
            'fields': ('created_at',)
        })
    )

    def has_add_permission(self, request):
        return False  # Prevent manual creation
