# Catalogue of Life (ColDP) Implementation Audit

**Date**: 2025-12-03
**Auditor**: Claude
**Documentation Reference**: https://github.com/CatalogueOfLife/coldp (v1.2, October 2025)

## Executive Summary

This audit compares the BiologiDex COL importer implementation against the official ColDP (Catalogue of Life Data Package) specification. The implementation uses the **NameUsage format** (merged Name/Taxon/Synonym entity), which is a valid and simpler approach per the ColDP docs.

### Critical Issues Found: 3
### Medium Issues Found: 5
### Minor/Improvement Opportunities: 6

---

## 1. Entity Model Analysis

### 1.1 ColDP Entity Architecture

ColDP supports two approaches:

**Canonical (Normalized) Format:**
```
Name ←── Taxon (via nameID)
  ↑
  └──── Synonym (via nameID + taxonID)
```

**Simplified (NameUsage) Format:**
```
NameUsage = Name + Taxon + Synonym combined
  - ID acts as both nameID and taxonID
  - parentID points to accepted taxon (synonyms) or taxonomic parent (accepted)
```

### 1.2 Current Implementation

**Status: CORRECT**

The implementation correctly uses the NameUsage format. Files parsed:
- `NameUsage.tsv` - Main taxonomic data
- `NameRelation.tsv` - Nomenclatural relationships
- `VernacularName.tsv` - Common names

This is valid per ColDP docs: *"As a simpler alternative to the 3 entities Name, Taxon and Synonym a single NameUsage entity can be supplied."*

---

## 2. CRITICAL ISSUES

### 2.1 NameRelation Type Confusion

**Location**: `server/taxonomy/models.py:343-356`, `server/taxonomy/services.py:266-269`

**Issue**: The NameRelation model and services conflate **nomenclatural name relations** with **taxonomic synonym statuses**.

**ColDP NameRelation Types** (valid values):
- `spelling correction`
- `basionym`
- `based on`
- `replacement name`
- `conserved`
- `later homonym`
- `superfluous`
- `type`

**Current Implementation Includes Invalid Types**:
```python
# models.py - INVALID entries marked with ❌
('spelling correction', 'Spelling Correction'),     # ✅ Valid
('basionym', 'Basionym'),                           # ✅ Valid
('based on', 'Based On'),                           # ✅ Valid
('replacement name', 'Replacement Name'),           # ✅ Valid
('conserved', 'Conserved'),                         # ✅ Valid
('later homonym', 'Later Homonym'),                 # ✅ Valid
('superfluous', 'Superfluous'),                     # ✅ Valid
('homotypic synonym', 'Homotypic Synonym'),         # ❌ INVALID - This is Synonym.status
('heterotypic synonym', 'Heterotypic Synonym'),     # ❌ INVALID - This is Synonym.status
('proparte synonym', 'Pro Parte Synonym'),          # ❌ INVALID - This is Synonym.status
('misapplied', 'Misapplied'),                       # ❌ INVALID - This is Synonym.status
('type', 'Type'),                                   # ✅ Valid
```

**services.py line 266-269**:
```python
relation_type__in=['spelling correction', 'basionym', 'homotypic synonym']
#                                                    ❌ INVALID
```

**Why This Matters**:
- NameRelation is for **nomenclatural** relationships between names (e.g., "Name A is a spelling correction of Name B")
- Synonym status (homotypic/heterotypic/misapplied) belongs on the **Synonym entity** or `NameUsage.status` field
- The COL export will never contain 'homotypic synonym' in NameRelation.type - this query will never match

**Recommendation**:
1. Remove invalid types from NameRelation.relation_type choices
2. Update services.py to use only valid nomenclatural relation types
3. If homotypic/heterotypic relationships are needed, derive them from `basionymID` linkages

---

### 2.2 Missing TaxonomicRank FK Population

**Location**: `server/taxonomy/importers/col_importer.py:694-749`

**Issue**: The `transform_record()` method never sets the `rank` ForeignKey on Taxonomy records.

```python
def transform_record(self, raw_record):
    # ... transforms data but never sets 'rank' FK
    return {
        'source_taxon_id': raw_record.col_id,
        # ...
        # 'rank': ???  <-- MISSING
    }
```

**Current Taxonomy Model**:
```python
rank = models.ForeignKey(TaxonomicRank, on_delete=models.PROTECT, null=True, blank=True)
```

**Impact**: The `rank` field on all Taxonomy records is NULL, preventing rank-based queries and filtering.

**Recommendation**:
1. Pre-populate TaxonomicRank table with standard ranks:
   ```python
   RANKS = [
       ('kingdom', 10), ('phylum', 20), ('class', 30), ('order', 40),
       ('family', 50), ('subfamily', 55), ('tribe', 58), ('subtribe', 59),
       ('genus', 60), ('subgenus', 65), ('section', 68),
       ('species', 70), ('subspecies', 80), ('variety', 85), ('form', 90)
   ]
   ```
2. In `transform_record()`, lookup or create TaxonomicRank and set FK

---

### 2.3 basionymID Not Linked

**Location**: `server/taxonomy/raw_models.py:18`, `server/taxonomy/importers/col_importer.py`

**Issue**: The `basionym_id` field is captured in RawCatalogueOfLife but never used to create relationships.

**ColDP Specification**:
> `basionymID`: Identifier of the name which is the original combination of this name. Also known as the basionym.

**Current Flow**:
```
NameUsage.tsv → RawCatalogueOfLife.basionym_id → (IGNORED)
```

**Impact**: Valuable nomenclatural data (original name relationships) is lost.

**Recommendation**:
1. Add `basionym` FK to Taxonomy model (self-referential)
2. In `_link_parent_ids()`, also process basionym_id linkages
3. Use basionym relationships to infer homotypic synonymy

---

## 3. MEDIUM ISSUES

### 3.1 Missing NameUsage Fields

**Issue**: Several valuable ColDP fields are not imported.

| ColDP Field | Purpose | Currently Imported |
|------------|---------|-------------------|
| `basionymID` | Link to original name | Captured but not used |
| `accordingToID` | Reference for taxon concept | Not imported |
| `scrutinizer` | Reviewer name | Not imported |
| `scrutinizerDate` | Review date | Not imported |
| `nameReferenceID` | Nomenclatural reference | Not imported |
| `referenceID` | Taxonomic references | Not imported |
| `namePhrase` | Qualifications (sensu lato) | Not imported |
| `temporalRangeStart/End` | Geological time range | Not imported |

**Recommendation**: Prioritize importing at least `basionymID` and `accordingToID` for better taxonomic accuracy.

---

### 3.2 Reference Data Not Imported

**Location**: N/A (not implemented)

**Issue**: Reference.tsv is completely ignored. All `referenceID` fields in other entities have no backing data.

**Impact**:
- Cannot display publication information for names
- Cannot cite sources for taxonomic decisions
- Loses valuable bibliographic metadata

**Recommendation**: Add Reference model and parser (lower priority - can be added later).

---

### 3.3 Incomplete Taxonomic Hierarchy Columns

**Location**: `server/taxonomy/raw_models.py:24-39`

**Issue**: RawCatalogueOfLife is missing some hierarchy columns that exist in Taxonomy model.

**Missing in RawCatalogueOfLife**:
- `subtribe` (exists in Taxonomy but not Raw)
- `subkingdom`, `subphylum`, `subclass`, `suborder` (in Taxonomy, unclear if in COL export)
- `superfamily` (in Taxonomy, unclear if in COL export)

**Recommendation**: Verify which columns exist in actual COL export and align raw model accordingly.

---

### 3.4 Column Name Prefix Assumption

**Location**: `server/taxonomy/importers/col_importer.py:356-383`

**Issue**: The importer assumes all columns have `col:` prefix:
```python
col_id=row.get('col:ID', ''),
parent_id=row.get('col:parentID', ''),
```

**Observation**: Standard ColDP files use unprefixed column names. The `col:` prefix may be specific to ChecklistBank's extended export format.

**Impact**: If COL changes their export format, parsing would break.

**Recommendation**: Add fallback for unprefixed column names:
```python
col_id = row.get('col:ID') or row.get('ID', '')
```

---

### 3.5 Status Mapping - 'doubtful' Not in ColDP

**Location**: `server/taxonomy/importers/col_importer.py:751-760`

**Issue**: The fallback status is 'doubtful' which isn't in ColDP vocabulary.

**ColDP Status Values**:
- `accepted`
- `provisionally accepted`
- `synonym`
- `ambiguous synonym`
- `misapplied`
- `bare name` (NameUsage only - name with no taxon/synonym record)

**Current Mapping**:
```python
def _map_status(self, col_status):
    status_map = {
        'accepted': 'accepted',
        'provisionally accepted': 'provisional',
        'synonym': 'synonym',
        'ambiguous synonym': 'ambiguous',
        'misapplied': 'misapplied'
    }
    return status_map.get(col_status.lower(), 'doubtful')  # 'doubtful' not in ColDP
```

**Recommendation**: Use 'provisional' or add 'bare name' to model choices; log unexpected status values.

---

## 4. MINOR ISSUES / IMPROVEMENTS

### 4.1 VernacularName.transliteration Not Imported

ColDP supports `transliteration` field for romanized versions of non-Latin script names. Currently not imported.

### 4.2 Distribution.tsv Parsing Noted but Not Implemented

Comment in code: `# TODO: Parse Distribution.tsv in future iterations`

GeographicDistribution model exists and is well-designed. Implementation would be straightforward.

### 4.3 Media.tsv Not Imported
***CLAUDE: Media.tsv is not populated, skip***
ColDP Media entity (images, audio, video for taxa) is not parsed. Would be useful for displaying species images.

### 4.4 TypeMaterial.tsv Not Imported

Type specimen data could enhance taxonomic accuracy but is specialized use case.

### 4.5 Species Estimate Data Not Imported

SpeciesEstimate entity provides estimated species counts per higher taxon. Useful for UI/statistics.

### 4.6 Potential for alternativeID Support

ColDP supports `alternativeID` arrays linking to external databases (GBIF, iNaturalist, IUCN, etc.). Would enable cross-database linking.

---

## 5. CORRECT IMPLEMENTATIONS

### 5.1 parentID Semantics ✅

**Location**: `server/taxonomy/importers/col_importer.py:775-894`

The `_link_parent_ids()` method correctly handles ColDP parentID semantics:
- Synonyms → `accepted_name` FK (parentID = accepted taxon)
- Accepted taxa → `parent` FK (parentID = taxonomic parent)

### 5.2 NameUsage Format Choice ✅

Using the merged NameUsage format is valid and simpler. The implementation correctly:
- Parses NameUsage.tsv as the primary data source
- Handles the dual meaning of ID (acts as both nameID and taxonID)
- Correctly interprets parentID based on status

### 5.3 Environment Field Parsing ✅

The environment field parsing correctly maps COL values:
```python
env_map = {
    'marine': 'marine',
    'terrestrial': 'terrestrial',
    'freshwater': 'freshwater',
    'brackish': 'marine'  # Reasonable mapping
}
```

### 5.4 Nomenclatural Code Mapping ✅

Code mapping is correct:
```python
code_map = {
    'botanical': 'icn',
    'zoological': 'iczn',
    'virus': 'ictv',
    'bacterial': 'icnp'
}
```

### 5.5 VernacularName Parsing ✅

VernacularName parsing correctly handles:
- taxonID lookup
- Language codes (with truncation for safety)
- Country codes (with normalization)
- Preferred flag parsing

---

## 6. RECOMMENDATIONS SUMMARY

### Immediate (Critical)

1. **Fix NameRelation types** - Remove invalid synonym status values from relation_type choices
2. **Fix services.py synonym resolution** - Remove 'homotypic synonym' from NameRelation queries
3. **Add TaxonomicRank population** - Pre-seed ranks and set FK during import

### Short-term (Medium Priority)

4. **Link basionymID** - Create basionym FK and populate during import
5. **Add column name fallbacks** - Support both prefixed and unprefixed column names
6. **Fix status mapping** - Handle 'bare name' status, remove 'doubtful'

### Long-term (Nice to Have)

7. **Import Reference.tsv** - Add bibliographic data support
8. **Import Distribution.tsv** - Enable geographic distribution queries
9. **Import alternativeID** - Enable cross-database linking
10. **Import Media.tsv** - Species images and media

---

## 7. DATA MODEL DIAGRAM

### Current Implementation
```
┌─────────────────┐       ┌─────────────────┐
│   DataSource    │       │   ImportJob     │
│  (col, gbif)    │◄──────│  (import run)   │
└────────┬────────┘       └────────┬────────┘
         │                         │
         ▼                         ▼
┌─────────────────────────────────────────────────────┐
│                    Taxonomy                          │
│  - source_taxon_id (col:ID)                         │
│  - scientific_name, authorship                       │
│  - status (accepted/synonym/etc)                     │
│  - kingdom, phylum, class, order, family, genus...  │
│  - parent FK (taxonomic hierarchy)                   │
│  - accepted_name FK (for synonyms)                   │
│  - rank FK (TaxonomicRank) ⚠️ NOT POPULATED         │
└───────────┬───────────────────────────┬─────────────┘
            │                           │
            ▼                           ▼
┌─────────────────────┐    ┌────────────────────────┐
│    CommonName       │    │     NameRelation       │
│  - taxonomy FK      │    │  - name FK             │
│  - name, language   │    │  - related_name FK     │
│  - country          │    │  - relation_type ⚠️    │
│  - is_preferred     │    │    (has invalid types) │
└─────────────────────┘    └────────────────────────┘
```

### ColDP Canonical Structure (for reference)
```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│    Name     │◄─────│    Taxon    │      │   Synonym   │
│  (namesake) │      │  (concept)  │◄─────│ (alt name)  │
│  - ID       │      │  - ID       │      │  - taxonID  │
│  - name     │      │  - nameID   │      │  - nameID   │
│  - rank     │      │  - parentID │      │  - status   │
└──────┬──────┘      └─────────────┘      └─────────────┘
       │
       ▼
┌─────────────┐
│NameRelation │
│ - nameID    │
│ - relatedID │
│ - type      │ ← Only nomenclatural types!
└─────────────┘
```

---

## 8. TESTING RECOMMENDATIONS

1. **Verify NameRelation data quality**: Query distinct relation_types in database to see what COL actually exports
2. **Check rank population**: Verify TaxonomicRank table has entries and Taxonomy.rank is populated
3. **Validate synonym resolution**: Test that synonym → accepted lookups work correctly
4. **Check basionymID coverage**: Count how many records have basionym_id in raw table

```sql
-- Check NameRelation types actually imported
SELECT DISTINCT relation_type, COUNT(*)
FROM taxonomy_namerelation
GROUP BY relation_type;

-- Check rank population
SELECT COUNT(*) FROM taxonomy_taxonomy WHERE rank_id IS NULL;

-- Check basionym data availability
SELECT COUNT(*) FROM taxonomy_raw_catalogue_of_life
WHERE basionym_id IS NOT NULL AND basionym_id != '';

-- Check synonym resolution rate
SELECT
    COUNT(*) as total_synonyms,
    COUNT(accepted_name_id) as linked_synonyms
FROM taxonomy_taxonomy
WHERE status = 'synonym';
```

---

## Appendix A: ColDP NameRelation Types (Official)

From ColDP spec `http://api.checklistbank.org/vocab/nomreltype`:

| Type | Description |
|------|-------------|
| `spelling correction` | A corrected spelling of the related name |
| `basionym` | The original name from which a new combination was made |
| `based on` | Name is based on another name (nomenclatural act) |
| `replacement name` | A substitute name for a preoccupied/rejected name |
| `conserved` | Name conserved over the related name |
| `later homonym` | A junior homonym of the related name |
| `superfluous` | A superfluous name for the related name |
| `type` | Type species/genus relationship |

## Appendix B: ColDP Taxonomic Status Values (Official)

From ColDP spec `http://api.checklistbank.org/vocab/taxonomicstatus`:

| Status | Entity | Description |
|--------|--------|-------------|
| `accepted` | Taxon/NameUsage | Valid accepted taxon |
| `provisionally accepted` | Taxon/NameUsage | Provisionally accepted |
| `synonym` | Synonym/NameUsage | General synonym |
| `ambiguous synonym` | Synonym/NameUsage | Synonym with uncertain placement |
| `misapplied` | Synonym/NameUsage | Name incorrectly applied to this taxon |
| `bare name` | NameUsage only | Name without taxon/synonym association |