# Taxonomy Matching & Synonym Resolution

## Overview
Multi-stage taxonomy matching system that handles COL data quality issues (empty genus fields, unpopulated FKs) and resolves synonyms to accepted names.

## Architecture

### Core Models
```
Taxonomy
├── source_taxon_id (COL ID)
├── scientific_name
├── genus, specific_epithet, infraspecific_epithet (often empty in COL data)
├── accepted_name FK (often NULL)
└── status: accepted, synonym, provisional

NameRelation (from COL NameRelation.tsv)
├── name FK → Taxonomy (source)
├── related_name FK → Taxonomy (target)
├── relation_type: "spelling correction", "basionym", etc.
└── col_name_id, col_related_name_id (for import matching)
```

### Matching Pipeline
**Location**: `taxonomy/services.py:TaxonomyService.lookup_or_create_from_cv()`

**Input**: genus, species, subspecies, common_name from CV

**6-Stage Matching**:
1. **Exact field match**: genus + species + subspecies (filters by populated fields)
2. **Exact scientific name**: Catches synonyms with empty genus (e.g., "Canis lupus familiaris")
3. **Exact common name**: Via CommonName table
4. **Fuzzy field match**: Genus + species with fuzzy subspecies matching
5. **Fuzzy scientific name**: Contains search
6. **Fuzzy common name**: Contains search

### Synonym Resolution
When match has `status='synonym'`, resolve using **3 strategies**:

1. **FK lookup**: Check `accepted_name` field (often NULL in COL imports)
2. **NameRelation lookup**: Query for `spelling correction`, `basionym`, `homotypic synonym`
3. **Name parsing fallback**:
   - Trinomial "Canis lupus familiaris" → search "Canis familiaris" (genus + last epithet)
   - Returns first accepted match

### Field Population
If matched record has empty genus/species/subspecies:
- Parse from `scientific_name`
- Skip parentheticals like "(Scydmaenus)"
- Save back to database

## Data Quality Issues

### COL Import Problems
1. **Empty genus fields**: Many subspecies have genus='' (e.g., half of Canis lupus subspecies)
2. **Unpopulated accepted_name FK**: Import doesn't populate relationships
3. **NameRelation dependency**: Must import Taxonomy first, then NameRelation

### Solutions Implemented
- Stage 2 (exact scientific name) catches records with empty genus
- NameRelation table provides explicit synonym relationships
- Name parsing provides fallback resolution
- Field population fixes empty fields on-the-fly

## Import Process

### Files Required
- `NameUsage.tsv`: Main taxonomy data
- `NameRelation.tsv`: Synonym relationships

### Import Order
```bash
# 1. Import creates Taxonomy records from NameUsage.tsv
python manage.py import_col

# 2. Builds lookup dict: col_id → Taxonomy object
# 3. Imports NameRelation.tsv using lookup dict
# 4. Creates NameRelation records linking Taxonomy objects
```

### Importer Code
**Location**: `taxonomy/importers/col_importer.py`
- `_parse_nameusage()`: Imports Taxonomy records
- `_parse_namerelation()`: Imports synonym relationships (Step 7)

## Usage Examples

### Example 1: "Canis lupus familiaris" (domestic dog)
```
CV Input: genus=Canis, species=lupus, subspecies=familiaris

Stage 1: ❌ No match (genus field empty in DB)
Stage 2: ✅ Match "Canis lupus familiaris" by scientific_name
  → status=synonym, accepted_name=NULL, genus=''

Synonym Resolution:
  Strategy 1: ❌ accepted_name FK is NULL
  Strategy 2: ✅ NameRelation: "spelling correction" → "Canis familiaris"

Field Population:
  ✅ Parse "Canis familiaris" → populate genus='Canis', species='familiaris'

Result: Animal created with full Carnivora/Canidae taxonomy from "Canis familiaris"
```

### Example 2: Generic accepted name
```
CV Input: genus=Panthera, species=leo

Stage 1: ✅ Exact field match
  → status=accepted, full taxonomy present

Result: Animal created directly
```

## Testing

### Verify Synonym Resolution
```python
from taxonomy.services import TaxonomyService

# Test "Canis lupus familiaris"
tax, created, msg = TaxonomyService.lookup_or_create_from_cv(
    genus="Canis",
    species="lupus",
    subspecies="familiaris",
    common_name="domestic dog"
)

# Should resolve to "Canis familiaris" (accepted)
assert tax.status == 'accepted'
assert tax.scientific_name == 'Canis familiaris'
assert tax.genus == 'Canis'  # Field populated
```

### Check NameRelation Data
```python
from taxonomy.models import Taxonomy, NameRelation

# Find synonym record
synonym = Taxonomy.objects.get(scientific_name='Canis lupus familiaris')

# Check relationship
rel = NameRelation.objects.filter(name=synonym).first()
print(f"{rel.name.scientific_name} --[{rel.relation_type}]--> {rel.related_name.scientific_name}")
# Output: Canis lupus familiaris --[spelling correction]--> Canis familiaris
```

## Maintenance

### Re-importing COL Data
```bash
# Full re-import populates NameRelation
docker-compose -f docker-compose.production.yml run web python manage.py import_col
```

### Adding New Relationship Types
Edit `taxonomy/models.py:NameRelation.relation_type` choices
Edit `taxonomy/services.py` line 268: add to lookup filter

### Monitoring
Check Celery logs for taxonomy lookup messages:
- `[TAXONOMY LOOKUP] Stage X match`
- `[TAXONOMY LOOKUP] ✓ Resolved via NameRelation`
- `[TAXONOMY LOOKUP] Populated genus field from scientific name`
