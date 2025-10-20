"""
Animal models for BiologiDex.
"""
import uuid
from django.db import models
from django.conf import settings
from django.utils.translation import gettext_lazy as _
from django.core.cache import cache


class Animal(models.Model):
    """
    Canonical animal record with taxonomic and ecological information.
    Acts as the master database of species.
    """
    CONSERVATION_STATUS_CHOICES = [
        ('EX', 'Extinct'),
        ('EW', 'Extinct in the Wild'),
        ('CR', 'Critically Endangered'),
        ('EN', 'Endangered'),
        ('VU', 'Vulnerable'),
        ('NT', 'Near Threatened'),
        ('LC', 'Least Concern'),
        ('DD', 'Data Deficient'),
        ('NE', 'Not Evaluated'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    # Taxonomy
    scientific_name = models.CharField(
        max_length=200,
        unique=True,
        help_text=_('Binomial nomenclature (Genus species)')
    )
    common_name = models.CharField(
        max_length=200,
        help_text=_('Common name in English')
    )
    kingdom = models.CharField(max_length=100, default='Animalia')
    phylum = models.CharField(max_length=100, blank=True)
    class_name = models.CharField(
        max_length=100,
        blank=True,
        db_column='class',
        help_text=_('Taxonomic class')
    )
    order = models.CharField(max_length=100, blank=True)
    family = models.CharField(max_length=100, blank=True)
    genus = models.CharField(max_length=100, blank=True)
    species = models.CharField(max_length=100, blank=True)

    # Information
    description = models.TextField(
        blank=True,
        help_text=_('Detailed description of the animal')
    )
    habitat = models.TextField(
        blank=True,
        help_text=_('Natural habitat and geographic distribution')
    )
    diet = models.TextField(
        blank=True,
        help_text=_('Dietary habits')
    )
    conservation_status = models.CharField(
        max_length=2,
        choices=CONSERVATION_STATUS_CHOICES,
        default='NE',
        help_text=_('IUCN Red List conservation status')
    )
    interesting_facts = models.JSONField(
        default=list,
        blank=True,
        help_text=_('List of interesting facts about the animal')
    )

    # Metadata
    creation_index = models.PositiveIntegerField(
        unique=True,
        null=True,
        blank=True,
        help_text=_('Sequential discovery number (like Pokedex #)')
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='discovered_animals',
        help_text=_('First user to discover this animal')
    )
    verified = models.BooleanField(
        default=False,
        help_text=_('Whether this record has been verified by admins')
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'animals'
        verbose_name = _('Animal')
        verbose_name_plural = _('Animals')
        ordering = ['creation_index', 'scientific_name']
        indexes = [
            models.Index(fields=['scientific_name']),
            models.Index(fields=['common_name']),
            models.Index(fields=['genus', 'species']),
            models.Index(fields=['creation_index']),
            models.Index(fields=['verified']),
            models.Index(fields=['created_at']),
        ]

    def __str__(self):
        return f"#{self.creation_index or '???'} - {self.scientific_name} ({self.common_name})"

    def save(self, *args, **kwargs):
        """Auto-assign creation_index if not set."""
        if self.creation_index is None:
            # Get the highest index and add 1
            max_index = Animal.objects.aggregate(
                max_index=models.Max('creation_index')
            )['max_index']
            self.creation_index = (max_index or 0) + 1

        # Parse genus and species from scientific_name if not provided
        if not self.genus or not self.species:
            parts = self.scientific_name.split()
            if len(parts) >= 2:
                self.genus = parts[0]
                self.species = parts[1]

        super().save(*args, **kwargs)

        # Invalidate cache
        cache_key = f'animal_{self.id}'
        cache.delete(cache_key)

    @classmethod
    def get_cached(cls, animal_id):
        """Get animal from cache or database."""
        cache_key = f'animal_{animal_id}'
        animal = cache.get(cache_key)

        if animal is None:
            animal = cls.objects.get(id=animal_id)
            cache.set(cache_key, animal, settings.ANIMAL_CACHE_TTL)

        return animal

    @property
    def discovery_count(self):
        """Number of users who have captured this animal."""
        from dex.models import DexEntry
        return DexEntry.objects.filter(animal=self).values('owner').distinct().count()

    def get_taxonomic_tree(self):
        """Return the full taxonomic hierarchy as a dict."""
        return {
            'kingdom': self.kingdom,
            'phylum': self.phylum,
            'class': self.class_name,
            'order': self.order,
            'family': self.family,
            'genus': self.genus,
            'species': self.species,
        }
