# taxonomy/models.py
import uuid
from django.db import models
from django.contrib.postgres.fields import ArrayField
from django.contrib.postgres.indexes import GinIndex
from django.core.validators import URLValidator
from django.utils import timezone


class DataSource(models.Model):
    """Registry of taxonomic data sources"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=100, unique=True, db_index=True)
    short_code = models.CharField(max_length=20, unique=True)  # e.g., 'col', 'gbif'
    full_name = models.CharField(max_length=200)
    url = models.URLField(validators=[URLValidator()])
    api_endpoint = models.URLField(blank=True, null=True)
    update_frequency = models.CharField(
        max_length=20,
        choices=[
            ('daily', 'Daily'),
            ('weekly', 'Weekly'),
            ('monthly', 'Monthly'),
            ('quarterly', 'Quarterly'),
            ('annual', 'Annual'),
            ('irregular', 'Irregular')
        ]
    )
    license = models.TextField(blank=True)
    citation_format = models.TextField(help_text="Template for citations")
    is_active = models.BooleanField(default=True)
    priority = models.IntegerField(default=100, help_text="Lower number = higher priority for conflicts")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['priority', 'name']
        indexes = [
            models.Index(fields=['is_active', 'priority']),
        ]

    def __str__(self):
        return f"{self.name} ({self.short_code})"


class ImportJob(models.Model):
    """Track data import jobs from sources"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    source = models.ForeignKey(DataSource, on_delete=models.CASCADE, related_name='import_jobs')
    version = models.CharField(max_length=50, help_text="Source dataset version")
    status = models.CharField(
        max_length=20,
        choices=[
            ('pending', 'Pending'),
            ('downloading', 'Downloading'),
            ('processing', 'Processing'),
            ('validating', 'Validating'),
            ('importing', 'Importing'),
            ('completed', 'Completed'),
            ('failed', 'Failed'),
            ('cancelled', 'Cancelled')
        ],
        default='pending'
    )
    started_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    file_path = models.CharField(max_length=500, blank=True)
    file_size_mb = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    records_total = models.IntegerField(null=True, blank=True)
    records_imported = models.IntegerField(default=0)
    records_failed = models.IntegerField(default=0)
    error_log = models.JSONField(default=dict, blank=True)
    metadata = models.JSONField(default=dict, blank=True)  # Store source-specific metadata
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['source', '-created_at']),
            models.Index(fields=['status', 'created_at']),
        ]

    def __str__(self):
        return f"{self.source.short_code} import {self.version} - {self.status}"


class TaxonomicRank(models.Model):
    """Reference table for taxonomic ranks"""
    name = models.CharField(max_length=50, unique=True)
    level = models.IntegerField(unique=True)  # Kingdom=10, Phylum=20, etc.
    plural = models.CharField(max_length=50)

    class Meta:
        ordering = ['level']

    def __str__(self):
        return self.name


class Taxonomy(models.Model):
    """Normalized, deduplicated taxonomic data"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    # Core identification
    source_taxon_id = models.CharField(max_length=100, db_index=True)
    source = models.ForeignKey(DataSource, on_delete=models.PROTECT)
    import_job = models.ForeignKey(ImportJob, on_delete=models.SET_NULL, null=True, blank=True)

    # Scientific nomenclature
    scientific_name = models.CharField(max_length=300, db_index=True)
    authorship = models.CharField(max_length=200, blank=True)
    rank = models.ForeignKey(TaxonomicRank, on_delete=models.PROTECT, null=True, blank=True)
    status = models.CharField(
        max_length=30,
        choices=[
            ('accepted', 'Accepted'),
            ('synonym', 'Synonym'),
            ('provisional', 'Provisionally Accepted'),
            ('ambiguous', 'Ambiguous Synonym'),
            ('misapplied', 'Misapplied'),
            ('doubtful', 'Doubtful')
        ],
        default='accepted',
        db_index=True
    )

    # Taxonomic hierarchy - denormalized for performance
    kingdom = models.CharField(max_length=100, blank=True, db_index=True)
    phylum = models.CharField(max_length=100, blank=True, db_index=True)
    class_name = models.CharField(max_length=100, blank=True, db_index=True, db_column='class')
    order = models.CharField(max_length=100, blank=True, db_index=True)
    family = models.CharField(max_length=100, blank=True, db_index=True)
    genus = models.CharField(max_length=100, blank=True, db_index=True)
    species = models.CharField(max_length=100, blank=True, db_index=True)

    # Extended hierarchy
    subkingdom = models.CharField(max_length=100, blank=True)
    subphylum = models.CharField(max_length=100, blank=True)
    subclass = models.CharField(max_length=100, blank=True)
    suborder = models.CharField(max_length=100, blank=True)
    superfamily = models.CharField(max_length=100, blank=True)
    subfamily = models.CharField(max_length=100, blank=True)
    tribe = models.CharField(max_length=100, blank=True)
    subtribe = models.CharField(max_length=100, blank=True)
    subgenus = models.CharField(max_length=100, blank=True)
    section = models.CharField(max_length=100, blank=True)
    subspecies = models.CharField(max_length=100, blank=True)
    variety = models.CharField(max_length=100, blank=True)
    form = models.CharField(max_length=100, blank=True)

    # Name components
    generic_name = models.CharField(max_length=100, blank=True, db_index=True)
    specific_epithet = models.CharField(max_length=100, blank=True, db_index=True)
    infraspecific_epithet = models.CharField(max_length=100, blank=True)

    # Metadata
    extinct = models.BooleanField(null=True, blank=True)
    environment = ArrayField(
        models.CharField(max_length=20),
        default=list,
        blank=True
    )  # ['marine', 'terrestrial', 'freshwater']

    nomenclatural_code = models.CharField(
        max_length=20,
        choices=[
            ('iczn', 'ICZN - Zoological'),
            ('icn', 'ICN - Botanical'),
            ('icnp', 'ICNP - Prokaryotes'),
            ('ictv', 'ICTV - Viruses'),
            ('icnafp', 'ICNAFP - Algae, Fungi, Plants')
        ],
        blank=True
    )

    # Relationships
    parent = models.ForeignKey(
        'self',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='children'
    )
    accepted_name = models.ForeignKey(
        'self',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='synonyms',
        help_text="For synonyms, points to accepted name"
    )

    # Source reference
    source_url = models.URLField(blank=True, help_text="Direct link to source record")
    source_reference = models.TextField(blank=True)

    # Quality metrics
    completeness_score = models.DecimalField(
        max_digits=3, decimal_places=2, null=True, blank=True,
        help_text="0-1 score of data completeness"
    )
    confidence_score = models.DecimalField(
        max_digits=3, decimal_places=2, null=True, blank=True,
        help_text="0-1 confidence in accuracy"
    )

    # Timestamps
    source_modified_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = [('source', 'source_taxon_id')]
        indexes = [
            models.Index(fields=['scientific_name', 'status']),
            models.Index(fields=['genus', 'specific_epithet', 'status']),
            GinIndex(fields=['environment']),
            models.Index(fields=['kingdom', 'phylum', 'class_name']),
            models.Index(fields=['created_at']),
            models.Index(fields=['updated_at']),
        ]

    def __str__(self):
        return f"{self.scientific_name} [{self.source.short_code}]"

    @property
    def full_hierarchy(self):
        """Return complete taxonomic hierarchy as dict"""
        return {
            'kingdom': self.kingdom,
            'phylum': self.phylum,
            'class': self.class_name,
            'order': self.order,
            'family': self.family,
            'genus': self.genus,
            'species': self.species,
            'subspecies': self.subspecies,
        }

    def calculate_completeness(self):
        """Calculate data completeness score"""
        fields = [
            self.kingdom, self.phylum, self.class_name,
            self.order, self.family, self.genus
        ]
        filled = sum(1 for f in fields if f)
        return filled / len(fields)


class CommonName(models.Model):
    """Vernacular/common names for taxa"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    taxonomy = models.ForeignKey(Taxonomy, on_delete=models.CASCADE, related_name='common_names')
    name = models.CharField(max_length=200, db_index=True)
    language = models.CharField(max_length=10, db_index=True)  # ISO 639-3
    country = models.CharField(max_length=2, blank=True, db_index=True)  # ISO 3166-1
    is_preferred = models.BooleanField(default=False)
    source = models.ForeignKey(DataSource, on_delete=models.PROTECT)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=['name', 'language']),
            models.Index(fields=['taxonomy', 'is_preferred']),
        ]
        unique_together = [('taxonomy', 'name', 'language', 'country')]

    def __str__(self):
        return f"{self.name} ({self.language})"


class GeographicDistribution(models.Model):
    """Geographic distribution records"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    taxonomy = models.ForeignKey(Taxonomy, on_delete=models.CASCADE, related_name='distributions')
    area_code = models.CharField(max_length=20)
    gazetteer = models.CharField(max_length=20)  # e.g., 'tdwg', 'iso'
    area_name = models.CharField(max_length=200, blank=True)
    establishment_means = models.CharField(
        max_length=30,
        choices=[
            ('native', 'Native'),
            ('introduced', 'Introduced'),
            ('naturalised', 'Naturalised'),
            ('invasive', 'Invasive'),
            ('managed', 'Managed'),
            ('uncertain', 'Uncertain')
        ],
        blank=True
    )
    occurrence_status = models.CharField(
        max_length=30,
        choices=[
            ('present', 'Present'),
            ('absent', 'Absent'),
            ('extinct', 'Extinct'),
            ('doubtful', 'Doubtful')
        ],
        default='present'
    )
    threat_status = models.CharField(max_length=20, blank=True)  # IUCN categories
    source = models.ForeignKey(DataSource, on_delete=models.PROTECT)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=['taxonomy', 'area_code']),
            models.Index(fields=['establishment_means']),
        ]

    def __str__(self):
        return f"{self.taxonomy.scientific_name} in {self.area_name or self.area_code}"
