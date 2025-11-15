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
        Lookup taxonomy from CV identification, matching genus + species + subspecies.
        Common name is used for validation but won't block a valid scientific name match.

        Args:
            genus: Genus name from CV
            species: Species epithet from CV
            subspecies: Subspecies/infraspecific epithet from CV (optional)
            common_name: Common name from CV (optional, advisory only)
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
            f"[TAXONOMY LOOKUP] Starting lookup: genus={genus}, species={species}, "
            f"subspecies={subspecies}, common_name={common_name}"
        )

        # STEP 1: Build query to match genus + species ONLY (ignore subspecies for now)
        query = Q(
            genus__iexact=genus,
            specific_epithet__iexact=species,
            status__in=['accepted', 'provisional', 'synonym']
        )

        # Execute query to get ALL matches for genus + species
        all_candidates = Taxonomy.objects.filter(query).select_related(
            'source', 'rank'
        ).order_by(
            'source__priority',  # Higher priority sources first
            '-completeness_score',  # More complete records first
            '-confidence_score'
        )

        candidate_count = all_candidates.count()
        logger.info(f"[TAXONOMY LOOKUP] Found {candidate_count} candidate(s) for genus+species: {genus} {species}")

        # Log all genus+species candidates with their details
        if candidate_count > 0:
            logger.info(f"[TAXONOMY LOOKUP] All genus+species candidates found:")
            for idx, candidate in enumerate(all_candidates[:20], 1):  # Log up to 20 candidates
                subspecies_info = f"subspecies={candidate.infraspecific_epithet or 'None'}"
                logger.info(
                    f"  [{idx}] {candidate.scientific_name} "
                    f"({subspecies_info}, "
                    f"source: {candidate.source.short_code}, "
                    f"status: {candidate.status}, "
                    f"completeness: {candidate.completeness_score}, "
                    f"confidence: {candidate.confidence_score}, "
                    f"priority: {candidate.source.priority})"
                )
                # Log taxonomy hierarchy for first 3 candidates
                if idx <= 3:
                    logger.info(
                        f"      Taxonomy: kingdom={candidate.kingdom}, "
                        f"phylum={candidate.phylum}, class={candidate.class_name}, "
                        f"order={candidate.order}, family={candidate.family}"
                    )
            if candidate_count > 20:
                logger.info(f"  ... and {candidate_count - 20} more candidates (truncated)")

        # STEP 2: Apply fuzzy subspecies matching if subspecies provided
        candidates = all_candidates  # Start with all genus+species matches

        if subspecies and candidate_count > 0:
            logger.info(f"[TAXONOMY LOOKUP] Applying fuzzy subspecies matching for: '{subspecies}'")

            # Score each candidate by how well the subspecies matches
            exact_matches = []
            fuzzy_matches = []
            no_subspecies = []

            for candidate in all_candidates:
                db_subspecies = candidate.infraspecific_epithet

                if db_subspecies:
                    # Exact match (case-insensitive)
                    if db_subspecies.lower() == subspecies.lower():
                        exact_matches.append(candidate)
                        logger.info(
                            f"  ✓ EXACT subspecies match: {candidate.scientific_name} "
                            f"(CV: '{subspecies}' == DB: '{db_subspecies}')"
                        )
                    # Fuzzy match: one contains the other
                    elif (subspecies.lower() in db_subspecies.lower() or
                          db_subspecies.lower() in subspecies.lower()):
                        fuzzy_matches.append(candidate)
                        logger.info(
                            f"  ≈ FUZZY subspecies match: {candidate.scientific_name} "
                            f"(CV: '{subspecies}' ≈ DB: '{db_subspecies}')"
                        )
                    else:
                        logger.debug(
                            f"  ✗ No subspecies match: {candidate.scientific_name} "
                            f"(CV: '{subspecies}' vs DB: '{db_subspecies}')"
                        )
                else:
                    # Database has no subspecies for this candidate
                    no_subspecies.append(candidate)
                    logger.debug(
                        f"  - No subspecies in DB: {candidate.scientific_name} "
                        f"(CV requested: '{subspecies}', DB has: None)"
                    )

            # Select best match with priority: exact > fuzzy > no_subspecies
            if exact_matches:
                candidates = exact_matches
                logger.info(
                    f"[TAXONOMY LOOKUP] Selected {len(exact_matches)} EXACT subspecies match(es) "
                    f"from {candidate_count} total candidates"
                )
            elif fuzzy_matches:
                candidates = fuzzy_matches
                logger.info(
                    f"[TAXONOMY LOOKUP] Selected {len(fuzzy_matches)} FUZZY subspecies match(es) "
                    f"from {candidate_count} total candidates"
                )
            elif no_subspecies:
                # Fall back to species-level match (no subspecies in DB)
                candidates = no_subspecies
                logger.warning(
                    f"[TAXONOMY LOOKUP] No subspecies matches found for '{subspecies}'. "
                    f"Using {len(no_subspecies)} species-level candidate(s) without subspecies."
                )
            else:
                # No matches at all - keep all candidates as fallback
                logger.warning(
                    f"[TAXONOMY LOOKUP] No subspecies matches found for '{subspecies}'. "
                    f"Using all {candidate_count} genus+species candidates as fallback."
                )
        elif subspecies and candidate_count == 0:
            logger.info(
                f"[TAXONOMY LOOKUP] No genus+species candidates found to apply subspecies matching"
            )

        # STEP 3: Apply common name matching (advisory only)
        taxonomy = None
        common_name_matched = False

        # Convert to list if it's a queryset (after fuzzy subspecies matching)
        if not isinstance(candidates, list):
            candidates = list(candidates)

        if candidates:
            logger.info(
                f"[TAXONOMY LOOKUP] Final candidate pool after subspecies filtering: "
                f"{len(candidates)} candidate(s)"
            )

            if common_name:
                logger.info(f"[TAXONOMY LOOKUP] Attempting common name validation for: '{common_name}'")

                # Try to find candidates that match the common name (fuzzy matching)
                matching_common_name = []
                for idx, candidate in enumerate(candidates, 1):
                    # Get common names for this taxonomy
                    db_common_names = list(CommonName.objects.filter(
                        taxonomy=candidate
                    ).values_list('name', flat=True))

                    logger.debug(
                        f"[TAXONOMY LOOKUP] Candidate [{idx}] {candidate.scientific_name} "
                        f"has common names: {db_common_names}"
                    )

                    # Fuzzy match: check if one name is contained in the other (case-insensitive)
                    common_name_lower = common_name.lower()
                    for cn in db_common_names:
                        cn_lower = cn.lower()
                        # Accept if either name contains the other
                        if common_name_lower in cn_lower or cn_lower in common_name_lower:
                            matching_common_name.append(candidate)
                            common_name_matched = True
                            logger.info(
                                f"[TAXONOMY LOOKUP] ✓ Common name MATCH: CV '{common_name}' "
                                f"matched database '{cn}' for {candidate.scientific_name}"
                            )
                            break

                # Prefer common name match if available
                if matching_common_name:
                    taxonomy = matching_common_name[0]
                    logger.info(
                        f"[TAXONOMY LOOKUP] SELECTED (common name match): {taxonomy.scientific_name} "
                        f"from {len(matching_common_name)} matching candidate(s)"
                    )
                else:
                    # Common name didn't match, but use taxonomy anyway (advisory warning)
                    taxonomy = candidates[0]  # Use first from list
                    db_names = list(CommonName.objects.filter(
                        taxonomy=taxonomy
                    ).values_list('name', flat=True)[:5])
                    logger.warning(
                        f"[TAXONOMY LOOKUP] ⚠ Common name mismatch for {scientific_name}: "
                        f"CV provided '{common_name}' but database has {db_names}. "
                        f"SELECTED (best candidate): {taxonomy.scientific_name} "
                        f"(using taxonomy anyway - common name is advisory only)"
                    )
            else:
                # No common name provided, use first candidate
                taxonomy = candidates[0]  # Use first from list
                logger.info(
                    f"[TAXONOMY LOOKUP] SELECTED (no common name provided): {taxonomy.scientific_name} "
                    f"(best candidate by source priority={taxonomy.source.priority}, "
                    f"completeness={taxonomy.completeness_score})"
                )

        if taxonomy:
            # Found in taxonomy database
            if taxonomy.status == 'synonym':
                # Get accepted name
                if taxonomy.accepted_name:
                    logger.info(
                        f"[TAXONOMY LOOKUP] Found as synonym, resolving to accepted name: "
                        f"{taxonomy.scientific_name} → {taxonomy.accepted_name.scientific_name}"
                    )
                    taxonomy = taxonomy.accepted_name
                    message = f"Found synonym, using accepted name: {taxonomy.scientific_name}"
                else:
                    logger.warning(f"[TAXONOMY LOOKUP] Found synonym without accepted name for {scientific_name}")
                    message = f"Found synonym without accepted name"
            else:
                message = f"Found in taxonomy: {taxonomy.scientific_name}"

            # Log taxonomy completeness
            logger.info(
                f"[TAXONOMY LOOKUP] Taxonomy details for {taxonomy.scientific_name}: "
                f"kingdom={taxonomy.kingdom}, phylum={taxonomy.phylum}, "
                f"class={taxonomy.class_name}, order={taxonomy.order}, "
                f"family={taxonomy.family}, genus={taxonomy.genus}, "
                f"species={taxonomy.species or taxonomy.specific_epithet}"
            )

            # Create or update animal
            from animals.services import AnimalService
            animal, created = AnimalService.create_or_update_from_taxonomy(
                taxonomy,
                common_name=common_name,
                cv_confidence=confidence
            )

            logger.info(
                f"[TAXONOMY LOOKUP] {'Created' if created else 'Updated'} animal from taxonomy: "
                f"{animal.scientific_name} (#{animal.creation_index})"
            )

            return taxonomy, created, message

        # Not found in taxonomy - log detailed info for debugging
        logger.error(
            f"[TAXONOMY LOOKUP] FAILED - Taxonomy not found for: {scientific_name} "
            f"(genus={genus}, species={species}, subspecies={subspecies}). "
            f"This species is not in the Catalogue of Life database."
        )
        return None, False, f"Not found in taxonomy database: {scientific_name}"

    @classmethod
    def lookup_genus(cls, genus: str) -> Optional[Taxonomy]:
        """
        Lookup taxonomy by genus to get higher-level classification.
        Used as fallback when species lookup fails.

        Args:
            genus: Genus name to lookup

        Returns:
            Taxonomy object for the genus, or None if not found
        """
        logger.info(f"[TAXONOMY LOOKUP] Attempting genus-level lookup for: {genus}")

        # Look for accepted genus-level taxonomy entry
        genus_taxonomy = Taxonomy.objects.filter(
            genus__iexact=genus,
            rank__name='genus',
            status__in=['accepted', 'provisional']
        ).select_related('source', 'rank').order_by(
            'source__priority',
            '-completeness_score'
        ).first()

        if genus_taxonomy:
            logger.info(
                f"[TAXONOMY LOOKUP] Found genus-level taxonomy: {genus_taxonomy.scientific_name}, "
                f"kingdom={genus_taxonomy.kingdom}, phylum={genus_taxonomy.phylum}, "
                f"class={genus_taxonomy.class_name}, order={genus_taxonomy.order}, "
                f"family={genus_taxonomy.family}"
            )
            return genus_taxonomy

        logger.warning(f"[TAXONOMY LOOKUP] Genus-level taxonomy not found for: {genus}")
        return None

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
