# taxonomy/services.py
import re
import logging
from typing import Optional, Dict, List, Tuple
from django.db.models import Q, Count
from django.core.cache import cache
from taxonomy.models import Taxonomy, CommonName, DataSource

logger = logging.getLogger(__name__)


class TaxonomyService:
    """Service for taxonomy lookups and validation"""

    CACHE_TTL = 3600  # 1 hour

    @classmethod
    def lookup_by_scientific_name(
        cls,
        scientific_name: str,
        include_synonyms: bool = False,
        source_code: Optional[str] = None
    ) -> Optional[Taxonomy]:
        """
        Lookup taxonomy by scientific name

        Args:
            scientific_name: Scientific name to search
            include_synonyms: Whether to search synonyms
            source_code: Specific source to search (e.g., 'col')

        Returns:
            Taxonomy object or None
        """
        # Clean scientific name
        scientific_name = cls._clean_scientific_name(scientific_name)

        # Check cache
        cache_key = f'taxonomy:{scientific_name}:{source_code or "all"}'
        cached = cache.get(cache_key)
        if cached:
            logger.debug(f"Cache hit for {scientific_name}")
            return cached

        # Build query
        query = Q(scientific_name__iexact=scientific_name)

        # Add binomial search (genus + species)
        parts = scientific_name.split()
        if len(parts) == 2:
            query |= Q(
                genus__iexact=parts[0],
                specific_epithet__iexact=parts[1]
            )

        # Filter by status
        if not include_synonyms:
            query &= Q(status__in=['accepted', 'provisional'])

        # Filter by source
        if source_code:
            query &= Q(source__short_code=source_code)

        # Execute query with priority ordering
        result = Taxonomy.objects.filter(query).select_related(
            'source', 'rank'
        ).order_by(
            'source__priority',  # Higher priority sources first
            '-completeness_score',  # More complete records first
            '-confidence_score'
        ).first()

        if result:
            # Cache the result
            cache.set(cache_key, result, cls.CACHE_TTL)
            logger.info(f"Found taxonomy for '{scientific_name}': {result}")

        return result

    @classmethod
    def lookup_or_create_from_cv(
        cls,
        genus: str,
        species: str,
        subspecies: Optional[str] = None,
        common_name: Optional[str] = None,
        confidence: float = 0.0
    ) -> Tuple[Optional[Taxonomy], bool, str]:
        """
        Lookup taxonomy from CV identification, matching ALL fields (genus, species, subspecies, common name)

        Args:
            genus: Genus name from CV
            species: Species epithet from CV
            subspecies: Subspecies/infraspecific epithet from CV (optional)
            common_name: Common name from CV (optional)
            confidence: CV confidence score

        Returns:
            (taxonomy, created, message)
        """
        # Build scientific name for logging
        if subspecies:
            scientific_name = f"{genus} {species} {subspecies}"
        else:
            scientific_name = f"{genus} {species}"

        logger.info(
            f"Looking up taxonomy: genus={genus}, species={species}, "
            f"subspecies={subspecies}, common_name={common_name}"
        )

        # Build query to match ALL fields
        query = Q(
            genus__iexact=genus,
            specific_epithet__iexact=species,
            status__in=['accepted', 'provisional', 'synonym']
        )

        # Match subspecies field (must match exactly, including None)
        if subspecies:
            query &= Q(infraspecific_epithet__iexact=subspecies)
        else:
            query &= (Q(infraspecific_epithet__isnull=True) | Q(infraspecific_epithet=''))

        # Execute query with priority ordering
        candidates = Taxonomy.objects.filter(query).select_related(
            'source', 'rank'
        ).order_by(
            'source__priority',  # Higher priority sources first
            '-completeness_score',  # More complete records first
            '-confidence_score'
        )

        # If common name provided, filter to match common name
        if common_name:
            # Try to find candidates that match the common name (fuzzy matching)
            matching_common_name = []
            for candidate in candidates:
                # Get common names for this taxonomy
                common_names = CommonName.objects.filter(
                    taxonomy=candidate
                ).values_list('name', flat=True)

                # Fuzzy match: check if one name is contained in the other (case-insensitive)
                common_name_lower = common_name.lower()
                for cn in common_names:
                    cn_lower = cn.lower()
                    # Accept if either name contains the other
                    if common_name_lower in cn_lower or cn_lower in common_name_lower:
                        matching_common_name.append(candidate)
                        break

            # If we found matches with common name, use those
            if matching_common_name:
                taxonomy = matching_common_name[0]
            else:
                # No match with common name - this might be a mismatch
                logger.warning(
                    f"Found taxonomy for {scientific_name} but common name '{common_name}' "
                    f"doesn't match any known names. Rejecting to avoid mismatch."
                )
                return None, False, f"Found {scientific_name} but common name mismatch"
        else:
            # No common name provided, use first candidate
            taxonomy = candidates.first() if candidates else None

        if taxonomy:
            # Found in taxonomy database
            if taxonomy.status == 'synonym':
                # Get accepted name
                if taxonomy.accepted_name:
                    taxonomy = taxonomy.accepted_name
                    message = f"Found synonym, using accepted name: {taxonomy.scientific_name}"
                else:
                    message = f"Found synonym without accepted name"
            else:
                message = f"Found in taxonomy: {taxonomy.scientific_name}"

            # Create or update animal
            from animals.services import AnimalService
            animal, created = AnimalService.create_or_update_from_taxonomy(
                taxonomy,
                common_name=common_name,
                cv_confidence=confidence
            )

            return taxonomy, created, message

        # Not found in taxonomy
        logger.warning(f"Taxonomy not found for: {scientific_name}")
        return None, False, f"Not found in taxonomy database: {scientific_name}"

    @classmethod
    def get_common_names(
        cls,
        taxonomy: Taxonomy,
        language: str = 'eng',
        limit: int = 5
    ) -> List[str]:
        """Get common names for a taxon"""
        names = CommonName.objects.filter(
            taxonomy=taxonomy
        ).filter(
            Q(language=language) | Q(is_preferred=True)
        ).values_list('name', flat=True)[:limit]

        return list(names)

    @classmethod
    def search_taxonomy(
        cls,
        query: str,
        rank: Optional[str] = None,
        kingdom: Optional[str] = None,
        limit: int = 20
    ) -> List[Taxonomy]:
        """
        Search taxonomy database

        Args:
            query: Search term
            rank: Filter by rank (e.g., 'species', 'genus')
            kingdom: Filter by kingdom
            limit: Maximum results
        """
        # Build search query
        search_q = (
            Q(scientific_name__icontains=query) |
            Q(genus__icontains=query) |
            Q(common_names__name__icontains=query)
        )

        filters = Q(status__in=['accepted', 'provisional'])

        if rank:
            filters &= Q(rank__name=rank)

        if kingdom:
            filters &= Q(kingdom__iexact=kingdom)

        results = Taxonomy.objects.filter(
            search_q & filters
        ).select_related(
            'source', 'rank'
        ).distinct().order_by(
            '-completeness_score',
            'scientific_name'
        )[:limit]

        return list(results)

    @classmethod
    def _clean_scientific_name(cls, name: str) -> str:
        """Clean and normalize scientific name"""
        # Remove extra whitespace
        name = ' '.join(name.split())
        # Remove common abbreviations
        name = re.sub(r'\bsp\.\s*$', '', name)
        name = re.sub(r'\bspp\.\s*$', '', name)
        # Capitalize genus, lowercase species
        parts = name.split()
        if parts:
            parts[0] = parts[0].capitalize()
            if len(parts) > 1:
                parts[1] = parts[1].lower()
        return ' '.join(parts)

    @classmethod
    def get_hierarchy_stats(cls) -> Dict:
        """Get statistics about taxonomic hierarchy"""
        cache_key = 'taxonomy:hierarchy_stats'
        stats = cache.get(cache_key)

        if not stats:
            stats = {
                'total_taxa': Taxonomy.objects.filter(status='accepted').count(),
                'kingdoms': Taxonomy.objects.filter(
                    status='accepted'
                ).values('kingdom').distinct().count(),
                'species': Taxonomy.objects.filter(
                    rank__name='species',
                    status='accepted'
                ).count(),
                'genera': Taxonomy.objects.filter(
                    rank__name='genus',
                    status='accepted'
                ).count(),
                'families': Taxonomy.objects.filter(
                    rank__name='family',
                    status='accepted'
                ).count(),
                'sources': DataSource.objects.filter(is_active=True).count(),
            }
            cache.set(cache_key, stats, 3600)

        return stats

    @classmethod
    def validate_scientific_name(cls, name: str) -> Tuple[bool, str]:
        """
        Validate scientific name format

        Returns:
            (is_valid, message)
        """
        if not name or len(name.strip()) == 0:
            return False, "Scientific name cannot be empty"

        # Basic format check: should have at least genus
        parts = name.split()
        if len(parts) < 1:
            return False, "Scientific name must have at least genus"

        # Check if first letter is capitalized
        if not parts[0][0].isupper():
            return False, "Genus must start with capital letter"

        # Check if species (if present) is lowercase
        if len(parts) >= 2 and parts[1][0].isupper():
            return False, "Species epithet should be lowercase"

        return True, "Valid format"

    @classmethod
    def get_taxonomic_lineage(cls, taxonomy: Taxonomy) -> List[Taxonomy]:
        """
        Get complete taxonomic lineage from kingdom to current taxon

        Returns:
            List of Taxonomy objects from highest to lowest rank
        """
        lineage = []
        current = taxonomy

        # Walk up the parent chain
        while current:
            lineage.insert(0, current)
            current = current.parent

        return lineage

    @classmethod
    def get_children(cls, taxonomy: Taxonomy, direct_only: bool = True) -> List[Taxonomy]:
        """
        Get child taxa

        Args:
            taxonomy: Parent taxonomy
            direct_only: If True, only direct children; if False, all descendants

        Returns:
            List of child Taxonomy objects
        """
        if direct_only:
            return list(taxonomy.children.filter(status='accepted').order_by('scientific_name'))
        else:
            # Get all descendants recursively
            descendants = []
            to_process = list(taxonomy.children.filter(status='accepted'))

            while to_process:
                current = to_process.pop(0)
                descendants.append(current)
                to_process.extend(current.children.filter(status='accepted'))

            return descendants
