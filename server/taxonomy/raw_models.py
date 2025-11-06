# taxonomy/raw_models.py
"""
Raw import tables for staging data from sources.
These are temporary holding tables before normalization.
"""
import uuid
from django.db import models


class RawCatalogueOfLife(models.Model):
    """Raw import table for Catalogue of Life data"""
    id = models.BigAutoField(primary_key=True)  # Use BigAutoField for 9M+ records
    import_job = models.ForeignKey('taxonomy.ImportJob', on_delete=models.CASCADE)

    # Direct mapping from NameUsage.tsv columns
    col_id = models.CharField(max_length=50, db_index=True)
    parent_id = models.CharField(max_length=50, blank=True)
    basionym_id = models.CharField(max_length=50, blank=True)
    status = models.CharField(max_length=50)
    rank = models.CharField(max_length=50)
    scientific_name = models.CharField(max_length=300, db_index=True)
    authorship = models.CharField(max_length=500, blank=True)

    # Taxonomic hierarchy columns
    kingdom = models.CharField(max_length=100, blank=True)
    phylum = models.CharField(max_length=100, blank=True)
    class_name = models.CharField(max_length=100, blank=True, db_column='class')
    order = models.CharField(max_length=100, blank=True)
    family = models.CharField(max_length=100, blank=True)
    subfamily = models.CharField(max_length=100, blank=True)
    tribe = models.CharField(max_length=100, blank=True)
    subtribe = models.CharField(max_length=100, blank=True)
    genus = models.CharField(max_length=100, blank=True)
    subgenus = models.CharField(max_length=100, blank=True)
    section = models.CharField(max_length=100, blank=True)
    species = models.CharField(max_length=100, blank=True)
    subspecies = models.CharField(max_length=100, blank=True)
    variety = models.CharField(max_length=100, blank=True)
    form = models.CharField(max_length=100, blank=True)

    # Additional fields
    generic_name = models.CharField(max_length=100, blank=True)
    specific_epithet = models.CharField(max_length=100, blank=True)
    infraspecific_epithet = models.CharField(max_length=100, blank=True)
    code = models.CharField(max_length=20, blank=True)
    extinct = models.CharField(max_length=10, blank=True)
    environment = models.CharField(max_length=100, blank=True)

    # Processing flags
    is_processed = models.BooleanField(default=False, db_index=True)
    processing_errors = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'taxonomy_raw_catalogue_of_life'
        indexes = [
            models.Index(fields=['import_job', 'is_processed']),
            models.Index(fields=['scientific_name', 'status']),
            models.Index(fields=['col_id']),
        ]

    def __str__(self):
        return f"{self.scientific_name} (COL:{self.col_id})"
