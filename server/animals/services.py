# animals/services.py
import logging
from typing import Optional, Tuple
from django.utils import timezone
from django.db import transaction
from animals.models import Animal

logger = logging.getLogger(__name__)


class AnimalService:
    """Service layer for animal-related business logic"""

    @classmethod
    def create_or_update_from_taxonomy(
        cls,
        taxonomy: 'Taxonomy',
        common_name: Optional[str] = None,
        cv_confidence: float = 0.0
    ) -> Tuple[Animal, bool]:
        """
        Create or update Animal from Taxonomy record

        Args:
            taxonomy: Taxonomy object from taxonomy app
            common_name: Optional common name from CV
            cv_confidence: Confidence score from CV

        Returns:
            (animal, created) tuple
        """
        # Get preferred common name if not provided
        if not common_name:
            from taxonomy.services import TaxonomyService
            common_names = TaxonomyService.get_common_names(taxonomy, limit=1)
            common_name = common_names[0] if common_names else ''

        # Extract conservation status
        conservation_status = cls._get_conservation_status(taxonomy)

        # Extract native regions
        native_regions = cls._get_native_regions(taxonomy)

        # Determine verification method
        verification_method = 'taxonomy' if taxonomy else 'cv'

        # Create or update animal
        with transaction.atomic():
            animal, created = Animal.objects.update_or_create(
                scientific_name=taxonomy.scientific_name,
                defaults={
                    'common_name': common_name or taxonomy.scientific_name,
                    'kingdom': taxonomy.kingdom,
                    'phylum': taxonomy.phylum,
                    'class_name': taxonomy.class_name,
                    'order': taxonomy.order,
                    'family': taxonomy.family,
                    'subfamily': taxonomy.subfamily,
                    'genus': taxonomy.genus,
                    'species': taxonomy.specific_epithet or taxonomy.species,
                    'conservation_status': conservation_status,
                    'native_regions': native_regions,
                    # Taxonomy linking
                    'taxonomy_id': taxonomy.id,
                    'taxonomy_source': taxonomy.source.short_code,
                    'taxonomy_source_url': taxonomy.source_url,
                    'taxonomy_confidence': max(
                        cv_confidence,
                        float(taxonomy.confidence_score or 0)
                    ),
                    'verified': True,  # Verified via taxonomy database
                    'last_verified_at': timezone.now(),
                    'verification_method': verification_method
                }
            )

        if created:
            logger.info(f"Created animal from taxonomy: {animal} (#{animal.creation_index})")
        else:
            logger.info(f"Updated animal from taxonomy: {animal} (#{animal.creation_index})")

        return animal, created

    @staticmethod
    def _get_conservation_status(taxonomy) -> str:
        """
        Extract conservation status from taxonomy distributions

        Returns:
            IUCN category code (e.g., 'EN', 'VU', 'LC')
        """
        from taxonomy.models import GeographicDistribution

        # Check for threat status in distributions
        threat_statuses = GeographicDistribution.objects.filter(
            taxonomy=taxonomy,
            threat_status__isnull=False
        ).exclude(
            threat_status=''
        ).values_list('threat_status', flat=True).distinct()

        if threat_statuses:
            # Map IUCN categories to our status codes
            status_map = {
                'EX': 'EX',
                'EW': 'EW',
                'CR': 'CR',
                'EN': 'EN',
                'VU': 'VU',
                'NT': 'NT',
                'LC': 'LC',
                'DD': 'DD'
            }
            # Return first matching status
            for status in threat_statuses:
                status_upper = status.upper()
                if status_upper in status_map:
                    return status_map[status_upper]

        # Check if extinct based on taxonomy metadata
        if taxonomy.extinct:
            return 'EX'

        # Default to Not Evaluated
        return 'NE'

    @staticmethod
    def _get_native_regions(taxonomy) -> list:
        """
        Extract native regions from taxonomy distributions

        Returns:
            List of area names where species is native
        """
        from taxonomy.models import GeographicDistribution

        native_regions = GeographicDistribution.objects.filter(
            taxonomy=taxonomy,
            establishment_means='native',
            occurrence_status='present'
        ).exclude(
            area_name=''
        ).values_list('area_name', flat=True)[:10]

        return list(native_regions)

    @classmethod
    def lookup_or_create_from_cv(
        cls,
        genus: str,
        species: str,
        subspecies: Optional[str] = None,
        common_name: Optional[str] = None,
        confidence: float = 0.0
    ) -> Tuple[Optional[Animal], bool, str]:
        """
        Lookup or create animal from CV identification

        This method:
        1. Looks up taxonomy in the taxonomy database matching ALL fields
        2. If found, creates/updates animal from taxonomy
        3. If not found, creates basic animal record

        Args:
            genus: Genus name from CV
            species: Species epithet from CV
            subspecies: Subspecies/infraspecific epithet from CV (optional)
            common_name: Common name from CV
            confidence: CV confidence score

        Returns:
            (animal, created, message) tuple
        """
        from taxonomy.services import TaxonomyService

        # Build scientific name for logging
        if subspecies:
            scientific_name = f"{genus} {species} {subspecies}"
        else:
            scientific_name = f"{genus} {species}"

        # Try taxonomy lookup with all fields
        taxonomy, created, message = TaxonomyService.lookup_or_create_from_cv(
            genus=genus,
            species=species,
            subspecies=subspecies,
            common_name=common_name,
            confidence=confidence
        )

        if taxonomy:
            # Successfully found in taxonomy and created/updated animal
            animal = Animal.objects.get(scientific_name=taxonomy.scientific_name)
            return animal, created, message

        # Not found in taxonomy - create basic animal record from CV data
        logger.warning(f"Creating basic animal record for: {scientific_name}")

        animal, created = Animal.objects.get_or_create(
            scientific_name=scientific_name,
            defaults={
                'common_name': common_name or scientific_name,
                'genus': genus,
                'species': species,
                'verified': False,  # Not verified - needs manual review
                'verification_method': 'cv'
            }
        )

        message = f"Created basic animal record (not in taxonomy database): {scientific_name}"
        return animal, created, message
