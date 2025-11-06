# Catalogue of Life Dataset Documentation

## Overview

This document describes the structure and format of the **Catalogue of Life (COL) eXtended Release (XR)** dataset, version 2025-10-10. This is a comprehensive taxonomic database containing information about all known species on Earth, integrating data from 59,182 taxonomic and nomenclatural data sources.


## Dataset Statistics

- **Total Name Usage Records:** ~9.4 million taxonomic entries
- **Species Records:** ~4.9 million species
- **Genera:** ~522,000 genera
- **Common Names:** ~638,000 vernacular names
- **Distribution Records:** ~2.7 million geographic distributions
- **References:** ~2 million scientific references

## File Structure

The dataset consists of multiple tab-separated value (TSV) files, each serving a specific purpose:

### Core Files

#### 1. **NameUsage.tsv** (Primary Taxonomy File)
**Size:** ~2.9 GB, ~9.4 million records
**Purpose:** Contains the complete taxonomic hierarchy and nomenclature information

**Key Fields for Taxonomic Search:**
- `col:ID` - Unique identifier for each taxon
- `col:scientificName` - Complete scientific name (e.g., "Apis mellifera")
- `col:rank` - Taxonomic rank (species, genus, family, etc.)
- `col:status` - Taxonomic status (accepted, synonym, provisional, etc.)

**Taxonomic Hierarchy Columns (columns 50-65):**
- `col:species` - Species name
- `col:section` - Section (botanical)
- `col:subgenus` - Subgenus
- `col:genus` - Genus name
- `col:subtribe` - Subtribe
- `col:tribe` - Tribe
- `col:subfamily` - Subfamily
- `col:family` - Family name
- `col:superfamily` - Superfamily
- `col:suborder` - Suborder
- `col:order` - Order name
- `col:subclass` - Subclass
- `col:class` - Class name
- `col:subphylum` - Subphylum
- `col:phylum` - Phylum name
- `col:kingdom` - Kingdom (Animalia, Plantae, Fungi, etc.)

**Other Important Fields:**
- `col:authorship` - Author citation (e.g., "Linnaeus, 1758")
- `col:code` - Nomenclatural code (botanical, zoological, etc.)
- `col:extinct` - Extinction status
- `col:environment` - Habitat type (marine, terrestrial, freshwater)
- `col:parentID` - Parent taxon ID for hierarchy navigation
- `col:genericName` - Genus part of binomial name
- `col:specificEpithet` - Species epithet part of binomial name

#### 2. **VernacularName.tsv**
**Size:** ~638,000 records
**Purpose:** Common names in multiple languages

**Key Fields:**
- `col:taxonID` - Links to NameUsage.tsv ID
- `col:name` - Common name
- `col:language` - ISO 639-3 language code
- `col:country` - Country code where name is used
- `col:preferred` - Whether this is the preferred common name

#### 3. **Distribution.tsv**
**Size:** ~2.7 million records
**Purpose:** Geographic distribution data

**Key Fields:**
- `col:taxonID` - Links to NameUsage.tsv ID
- `col:area` - Area code
- `col:gazetteer` - Geographic standard (e.g., "tdwg")
- `col:establishmentMeans` - Native, introduced, etc.
- `col:threatStatus` - Conservation status

#### 4. **Reference.tsv**
**Size:** ~2 million records
**Purpose:** Scientific literature references

**Key Fields:**
- `col:ID` - Reference identifier
- `col:citation` - Full citation text
- `col:author` - Author names
- `col:title` - Publication title
- `col:doi` - Digital Object Identifier
- `col:issued` - Publication year

#### 5. **NameRelation.tsv**
**Size:** ~1.9 million records
**Purpose:** Relationships between names (synonyms, basionyms, etc.)

### Supporting Files

- **TypeMaterial.tsv** - Type specimen information
- **SpeciesEstimate.tsv** - Estimated species counts by group
- **metadata.yaml** - Complete dataset metadata
- **source/** - Directory with YAML files describing each data source

## Data Format Details

### File Format
- **Encoding:** UTF-8
- **Delimiter:** Tab character (\t)
- **Headers:** First row contains column names with "col:" prefix
- **Line endings:** Unix-style (LF)

### Status Values in NameUsage.tsv
- `accepted` - Currently accepted valid name
- `synonym` - Taxonomic synonym
- `provisionally accepted` - Tentatively accepted
- `ambiguous synonym` - Unclear synonym status
- `misapplied` - Incorrectly applied name

### Taxonomic Ranks (Most Common)
1. species (~4.9M records)
2. unranked (~3.1M records)
3. genus (~522K records)
4. variety (~389K records)
5. subspecies (~363K records)
6. form (~78K records)
7. family (~30K records)
8. order (~3K records)
9. class (~750 records)
10. phylum (~280 records)
11. kingdom (~10 records)

## Search Implementation Strategy

For implementing a searchable interface that returns complete taxonomy from a scientific name:

### Recommended Approach

1. **Index Creation:**
   - Create an index on `col:scientificName` field for fast lookups
   - Consider indexing `col:genus` and `col:specificEpithet` for partial matches
   - Index `col:ID` for joining with other tables

2. **Search Process:**
   ```
   1. Search NameUsage.tsv for matching scientificName
   2. Filter for status = 'accepted' (or include synonyms as needed)
   3. Extract complete taxonomy from columns 50-65
   4. Optionally join with:
      - VernacularName.tsv for common names
      - Distribution.tsv for geographic data
      - Reference.tsv for citations
   ```

3. **Example Record Structure:**
   ```
   Scientific Name: Apis mellifera
   Common Name: Western honey bee
   Taxonomy:
     Kingdom: Animalia
     Phylum: Arthropoda
     Class: Insecta
     Order: Hymenoptera
     Family: Apidae
     Genus: Apis
     Species: mellifera
   Author: Linnaeus, 1758
   Status: accepted
   ```

### Performance Considerations

Given the large size (~2.9GB for NameUsage.tsv):

1. **Database Import:** Consider importing into PostgreSQL or similar for efficient querying
2. **Indexing:** Create appropriate indexes on search fields
3. **Caching:** Cache frequently searched taxa
4. **Pagination:** Implement result pagination for large result sets
5. **Text Search:** Use full-text search capabilities for fuzzy matching

### Sample Query Patterns

```sql
-- Find species by exact scientific name
SELECT * FROM name_usage
WHERE scientific_name = 'Apis mellifera'
  AND status = 'accepted';

-- Find all species in a genus
SELECT * FROM name_usage
WHERE genus = 'Apis'
  AND rank = 'species'
  AND status = 'accepted';

-- Get complete taxonomy for a species
SELECT scientific_name, kingdom, phylum, class,
       order, family, genus, species
FROM name_usage
WHERE scientific_name = 'Apis mellifera'
  AND status = 'accepted';

-- Find common names for a species
SELECT nu.scientific_name, vn.name, vn.language
FROM name_usage nu
JOIN vernacular_name vn ON nu.id = vn.taxon_id
WHERE nu.scientific_name = 'Apis mellifera';
```

## Data Quality Notes

1. The dataset includes both verified (Base Release) and programmatically integrated (XR) data
2. Some records may have incomplete taxonomic hierarchies
3. ~3.1M records are marked as "unranked" in taxonomic hierarchy
4. Multiple synonyms may exist for a single accepted name
5. Geographic distributions use various gazetteer standards (primarily TDWG)

## Update Frequency

The Catalogue of Life releases updates monthly. This dataset is from the October 2025 release.

## License and Citation

- **DOI:** 10.48580/dgtpl
- **ISSN:** 2405-8858
- **Recommended Citation:** Bánki, O., Roskov, Y., et al. (2025). Catalogue of Life eXtended Release 2025-10-10.

## Contact

- **Support Email:** support@catalogueoflife.org
- **Issues:** https://github.com/CatalogueOfLife/data/issues
- **Website:** https://www.catalogueoflife.org