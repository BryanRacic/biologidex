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
        Lookup taxonomy from CV identification using multi-stage matching.

        Matching stages:
        1. Exact match on genus + species + subspecies fields
        2. Exact match on scientific name field
        3. Exact match on common name
        4. Fuzzy match on genus + species + subspecies fields
        5. Fuzzy match on scientific name field
        6. Fuzzy match on common name

        If any fields are missing in the matched record, they will be populated
        by parsing the scientific name.

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
            f"[TAXONOMY LOOKUP] Starting multi-stage lookup: genus={genus}, species={species}, "
            f"subspecies={subspecies}, common_name={common_name}"
        )

        taxonomy = None
        match_method = None

        # Common filter for all searches
        status_filter = Q(status__in=['accepted', 'provisional', 'synonym'])

        # STAGE 1: Exact match on genus + species + subspecies fields
        logger.info("[TAXONOMY LOOKUP] Stage 1: Exact field match (genus + species + subspecies)")
        query = status_filter & Q(
            genus__iexact=genus,
            specific_epithet__iexact=species
        )

        if subspecies:
            query &= Q(infraspecific_epithet__iexact=subspecies)
        else:
            # If no subspecies, match records without subspecies
            query &= (Q(infraspecific_epithet__isnull=True) | Q(infraspecific_epithet=''))

        taxonomy = Taxonomy.objects.filter(query).select_related('source', 'rank').order_by(
            'source__priority', '-completeness_score', '-confidence_score'
        ).first()

        if taxonomy:
            match_method = "exact_field_match"
            logger.info(f"[TAXONOMY LOOKUP] ✓ Stage 1 match: {taxonomy.scientific_name}")

        # STAGE 2: Exact match on scientific name field
        if not taxonomy:
            logger.info("[TAXONOMY LOOKUP] Stage 2: Exact scientific name match")
            taxonomy = Taxonomy.objects.filter(
                status_filter & Q(scientific_name__iexact=scientific_name)
            ).select_related('source', 'rank').order_by(
                'source__priority', '-completeness_score', '-confidence_score'
            ).first()

            if taxonomy:
                match_method = "exact_scientific_name"
                logger.info(f"[TAXONOMY LOOKUP] ✓ Stage 2 match: {taxonomy.scientific_name}")

        # STAGE 3: Exact match on common name
        if not taxonomy and common_name:
            logger.info(f"[TAXONOMY LOOKUP] Stage 3: Exact common name match for '{common_name}'")
            common_name_matches = CommonName.objects.filter(
                name__iexact=common_name
            ).select_related('taxonomy', 'taxonomy__source', 'taxonomy__rank')

            for cn in common_name_matches:
                if cn.taxonomy.status in ['accepted', 'provisional', 'synonym']:
                    taxonomy = cn.taxonomy
                    match_method = "exact_common_name"
                    logger.info(f"[TAXONOMY LOOKUP] ✓ Stage 3 match: {taxonomy.scientific_name} via common name '{cn.name}'")
                    break

        # STAGE 4: Fuzzy match on genus + species + subspecies fields
        if not taxonomy:
            logger.info("[TAXONOMY LOOKUP] Stage 4: Fuzzy field match (genus + species)")
            # Get all candidates matching genus + species (ignore subspecies match requirement)
            all_candidates = Taxonomy.objects.filter(
                status_filter & Q(
                    genus__iexact=genus,
                    specific_epithet__iexact=species
                )
            ).select_related('source', 'rank').order_by(
                'source__priority', '-completeness_score', '-confidence_score'
            )

            candidate_count = all_candidates.count()
            logger.info(f"[TAXONOMY LOOKUP] Found {candidate_count} candidate(s) for fuzzy genus+species match")

            if subspecies and candidate_count > 0:
                # Apply fuzzy subspecies matching
                logger.info(f"[TAXONOMY LOOKUP] Applying fuzzy subspecies matching for: '{subspecies}'")

                for candidate in all_candidates:
                    db_subspecies = candidate.infraspecific_epithet
                    if db_subspecies and (subspecies.lower() in db_subspecies.lower() or
                                         db_subspecies.lower() in subspecies.lower()):
                        taxonomy = candidate
                        match_method = "fuzzy_field_with_subspecies"
                        logger.info(f"[TAXONOMY LOOKUP] ✓ Stage 4 match: {taxonomy.scientific_name} (fuzzy subspecies)")
                        break

            # If no subspecies match, just use first genus+species match
            if not taxonomy and candidate_count > 0:
                taxonomy = all_candidates.first()
                match_method = "fuzzy_field_without_subspecies"
                logger.info(f"[TAXONOMY LOOKUP] ✓ Stage 4 match: {taxonomy.scientific_name} (genus+species only)")

        # STAGE 5: Fuzzy match on scientific name field
        if not taxonomy:
            logger.info(f"[TAXONOMY LOOKUP] Stage 5: Fuzzy scientific name match")
            fuzzy_name_matches = Taxonomy.objects.filter(
                status_filter & Q(scientific_name__icontains=scientific_name)
            ).select_related('source', 'rank').order_by(
                'source__priority', '-completeness_score', '-confidence_score'
            )[:10]

            if fuzzy_name_matches:
                taxonomy = fuzzy_name_matches.first()
                match_method = "fuzzy_scientific_name"
                logger.info(f"[TAXONOMY LOOKUP] ✓ Stage 5 match: {taxonomy.scientific_name}")

        # STAGE 6: Fuzzy match on common name
        if not taxonomy and common_name:
            logger.info(f"[TAXONOMY LOOKUP] Stage 6: Fuzzy common name match")
            fuzzy_common_matches = CommonName.objects.filter(
                name__icontains=common_name
            ).select_related('taxonomy', 'taxonomy__source', 'taxonomy__rank')

            for cn in fuzzy_common_matches:
                if cn.taxonomy.status in ['accepted', 'provisional', 'synonym']:
                    taxonomy = cn.taxonomy
                    match_method = "fuzzy_common_name"
                    logger.info(f"[TAXONOMY LOOKUP] ✓ Stage 6 match: {taxonomy.scientific_name} via common name '{cn.name}'")
                    break

        if taxonomy:
            # Found in taxonomy database
            logger.info(f"[TAXONOMY LOOKUP] Match found via method: {match_method}")

            if taxonomy.status == 'synonym':
                # Resolve synonym to accepted name
                accepted = taxonomy.accepted_name

                # Strategy 1: Use accepted_name FK if populated
                if accepted:
                    logger.info(
                        f"[TAXONOMY LOOKUP] Synonym resolved via FK: "
                        f"{taxonomy.scientific_name} → {accepted.scientific_name}"
                    )
                    taxonomy = accepted
                    message = f"Found synonym, using accepted name: {taxonomy.scientific_name} (via {match_method})"
                else:
                    # Strategy 2: Check NameRelation table for spelling correction relationship
                    logger.info(
                        f"[TAXONOMY LOOKUP] Synonym has no FK, checking NameRelation for: {taxonomy.scientific_name}"
                    )

                    from taxonomy.models import NameRelation

                    # Look for spelling correction or other synonym relationships
                    relation = NameRelation.objects.filter(
                        name=taxonomy,
                        relation_type__in=['spelling correction', 'basionym', 'homotypic synonym']
                    ).select_related('related_name', 'related_name__source', 'related_name__rank').first()

                    if relation and relation.related_name.status == 'accepted':
                        accepted = relation.related_name
                        logger.info(
                            f"[TAXONOMY LOOKUP] ✓ Resolved via NameRelation ({relation.relation_type}): "
                            f"{taxonomy.scientific_name} → {accepted.scientific_name}"
                        )
                        taxonomy = accepted
                        message = f"Resolved synonym via {relation.relation_type}: {taxonomy.scientific_name} (via {match_method})"
                    else:
                        # Strategy 3: Parse name and search for accepted species-level name
                        # E.g., "Canis lupus familiaris" → try "Canis familiaris"
                        name_parts = taxonomy.scientific_name.split()

                        if len(name_parts) >= 3:
                            # Trinomial - try genus + last part
                            search_genus = name_parts[0]
                            search_species = name_parts[-1]  # Use last part

                            logger.info(
                                f"[TAXONOMY LOOKUP] Searching for species-level accepted name: "
                                f"{search_genus} {search_species}"
                            )

                            accepted = Taxonomy.objects.filter(
                                status_filter & Q(
                                    genus__iexact=search_genus,
                                    specific_epithet__iexact=search_species,
                                    status='accepted'
                                )
                            ).select_related('source', 'rank').order_by(
                                'source__priority', '-completeness_score'
                            ).first()

                            if accepted:
                                logger.info(
                                    f"[TAXONOMY LOOKUP] ✓ Found via name parsing: "
                                    f"{taxonomy.scientific_name} → {accepted.scientific_name}"
                                )
                                taxonomy = accepted
                                message = f"Resolved synonym via name parsing: {taxonomy.scientific_name} (via {match_method})"

                        # If still unresolved, use synonym as-is
                        if taxonomy.status == 'synonym':
                            logger.warning(
                                f"[TAXONOMY LOOKUP] Could not resolve synonym to accepted name for: {scientific_name}. "
                                f"Using synonym record (may have incomplete taxonomy)"
                            )
                            message = f"Using unresolved synonym (via {match_method})"
            else:
                message = f"Found in taxonomy: {taxonomy.scientific_name} (via {match_method})"

            # FIELD POPULATION: If genus/species/subspecies fields are empty, populate from scientific name
            needs_update = False
            if not taxonomy.genus or not taxonomy.specific_epithet:
                logger.warning(
                    f"[TAXONOMY LOOKUP] Taxonomy record has missing fields - "
                    f"genus='{taxonomy.genus}', species='{taxonomy.specific_epithet}', subspecies='{taxonomy.infraspecific_epithet}'"
                )

                # Parse scientific name to extract genus, species, subspecies
                name_parts = taxonomy.scientific_name.split()
                if len(name_parts) >= 2:
                    if not taxonomy.genus:
                        taxonomy.genus = name_parts[0]
                        needs_update = True
                        logger.info(f"[TAXONOMY LOOKUP] Populated genus field from scientific name: '{taxonomy.genus}'")

                    if not taxonomy.specific_epithet:
                        taxonomy.specific_epithet = name_parts[1]
                        needs_update = True
                        logger.info(f"[TAXONOMY LOOKUP] Populated species field from scientific name: '{taxonomy.specific_epithet}'")

                    if len(name_parts) >= 3 and not taxonomy.infraspecific_epithet:
                        # Skip parenthetical parts like "(Scydmaenus)" - only use plain words
                        potential_subspecies = [part for part in name_parts[2:] if not part.startswith('(')]
                        if potential_subspecies:
                            taxonomy.infraspecific_epithet = potential_subspecies[0]
                            needs_update = True
                            logger.info(f"[TAXONOMY LOOKUP] Populated subspecies field from scientific name: '{taxonomy.infraspecific_epithet}'")

                if needs_update:
                    try:
                        taxonomy.save()
                        logger.info(f"[TAXONOMY LOOKUP] Updated taxonomy record {taxonomy.id} with populated fields")
                    except Exception as e:
                        logger.error(f"[TAXONOMY LOOKUP] Failed to update taxonomy record: {e}")

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
        query: str = '',
        genus: str = '',
        species: str = '',
        common_name: str = '',
        rank: Optional[str] = None,
        kingdom: Optional[str] = None,
        limit: int = 20
    ) -> List[Taxonomy]:
        """
        Search taxonomy database with field-specific or general search

        Args:
            query: General search term (searches across all fields)
            genus: Search by genus field specifically
            species: Search by species epithet field specifically
            common_name: Search by common name specifically
            rank: Filter by rank (e.g., 'species', 'genus')
            kingdom: Filter by kingdom
            limit: Maximum results
        """
        # Build search query with Q objects
        search_queries = []

        # Field-specific searches (exact field matching with icontains)
        if genus:
            search_queries.append(Q(genus__icontains=genus))

        if species:
            search_queries.append(Q(specific_epithet__icontains=species))

        if common_name:
            search_queries.append(Q(common_names__name__icontains=common_name))

        # General query searches across multiple fields
        if query:
            search_queries.append(
                Q(scientific_name__icontains=query) |
                Q(genus__icontains=query) |
                Q(specific_epithet__icontains=query) |
                Q(common_names__name__icontains=query)
            )

        # Combine all search queries with AND logic (all must match)
        if not search_queries:
            return []

        # Combine search queries with AND
        combined_search = search_queries[0]
        for q in search_queries[1:]:
            combined_search &= q

        # Additional filters
        filters = Q(status__in=['accepted', 'provisional'])

        if rank:
            filters &= Q(rank__name=rank)

        if kingdom:
            filters &= Q(kingdom__iexact=kingdom)

        results = Taxonomy.objects.filter(
            combined_search & filters
        ).select_related(
            'source', 'rank'
        ).prefetch_related(
            'common_names'
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
