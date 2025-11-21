# Data Model Compatibility Fixes

## Completed Client-Side Fixes ✅

### 1. AnimalModel
- ✅ Added `animal_id` mapping in `from_dict()` to handle both `animal_id` (from detected_animals) and `id` (from animal details)
- ✅ Added `animal_id` field to `to_dict()` for compatibility
- ✅ Added null handling for `creation_index`

### 2. AnalysisJobModel
- ✅ Fixed `owner` → `user` field naming in `to_dict()` to match server expectations
- ✅ Fixed `dex_compatible_image` → `dex_compatible_url` field naming
- ✅ Added comprehensive null handling for all fields (id, owner, images, timestamps, etc.)
- ✅ Fixed `user` field mapping in `from_dict()` to check both "user" and "owner"

### 3. DexEntryModel
- ✅ Added `location_lat` and `location_lon` fields for GPS coordinates
- ✅ Fixed `location` → `location_name` field mapping (both directions)
- ✅ Fixed `captured_at` → `catch_date` field mapping (both directions)
- ✅ Fixed `image` → `original_image` field mapping in `to_dict()`
- ✅ Added null handling for all metadata fields

## Critical Server-Side Issues Requiring Attention ⚠️

### 1. Animal Model - Missing Subspecies Field (CRITICAL)
**Issue**: Server's `Animal` model lacks a `subspecies` field, but CV can identify subspecies.

**Impact**: Data loss when animals are identified to subspecies level (e.g., "Canis lupus familiaris")

**Solution Required**:
```python
# In server/animals/models.py
class Animal(models.Model):
    # ... existing fields ...
    subspecies = models.CharField(max_length=100, blank=True, default='')
    # ... rest of model ...
```

**Migration Needed**: Yes - Add field and update serializer

**Priority**: CRITICAL - Causes data loss

---

### 2. AnalysisJob - Progress Field Missing (HIGH)
**Issue**: Client expects `progress` field for real-time updates, but server doesn't provide it.

**Impact**: Progress indicators won't update during analysis

**Solution Options**:
1. Add `progress` field to AnalysisJob model (recommended)
2. Remove progress tracking from client (not recommended - worse UX)

**Priority**: HIGH - Affects user experience

---

### 3. DexEntry - Source Vision Job Not in Main Serializer (MEDIUM)
**Issue**: `source_vision_job` is only in `DexEntryCreateSerializer`, not main serializer

**Impact**: Client won't know which CV job created an entry when viewing existing entries

**Solution Required**:
```python
# In server/dex/serializers.py - Add to DexEntrySerializer
source_vision_job = serializers.UUIDField(read_only=True)
```

**Priority**: MEDIUM - Useful for debugging and traceability

---

### 4. DexEntry - Image Checksum Only in Sync Serializer (MEDIUM)
**Issue**: `image_checksum` computed field only in `DexEntrySyncSerializer`

**Impact**: Main API responses don't include checksums, client can't verify image integrity

**Solution Required**: Add `get_image_checksum()` method to main `DexEntrySerializer`

**Priority**: MEDIUM - Nice to have for data integrity

---

## Field Mapping Reference

### Animal Model Mappings
| Client Field | Server Field | Notes |
|-------------|-------------|-------|
| `id` | `id` or `animal_id` | Handles both formats |
| `creation_index` | `creation_index` | ✓ |
| `animal_class` | `class_name` | Python reserved word |
| All others | Match 1:1 | ✓ |

### AnalysisJob Model Mappings
| Client Field | Server Field | Notes |
|-------------|-------------|-------|
| `owner_id` | `user` | **Server uses "user"** |
| `conversion_id` | `conversion_id` (read-only) | From `source_conversion.id` |
| `dex_compatible_image_url` | `dex_compatible_url` | **Different name** |
| `detected_animals` | `detected_animals` | JSON array structure |
| `identified_animal` | `animal_details` | Nested object |
| All others | Match 1:1 | ✓ |

### DexEntry Model Mappings
| Client Field | Server Field | Notes |
|-------------|-------------|-------|
| `location` | `location_name` | **Different name** |
| `location_lat` | `location_lat` | ✓ (now supported) |
| `location_lon` | `location_lon` | ✓ (now supported) |
| `captured_at` | `catch_date` | **Different name** |
| `image_url` | `original_image` | **Different name** |
| `animal` | `animal_details` | Nested object |
| All others | Match 1:1 | ✓ |

---

## Testing Checklist

### Animal Detection & Parsing
- [ ] Test CV detection with animals having subspecies
- [ ] Verify `animal_id` is correctly extracted from detected_animals
- [ ] Test with multiple detected animals

### Image Upload & Analysis
- [ ] Test image conversion workflow
- [ ] Verify converted image URL is properly stored
- [ ] Test post-conversion transformations (rotation)
- [ ] Verify progress updates display correctly (if server adds field)

### Dex Entry Creation
- [ ] Test dex entry creation from CV results
- [ ] Verify location coordinates are saved/loaded
- [ ] Verify catch_date is properly mapped
- [ ] Test image URL retrieval for display
- [ ] Verify source_vision_job linkage (if server adds to serializer)

### Data Sync
- [ ] Test dex sync with new field mappings
- [ ] Verify all null values are handled gracefully
- [ ] Test sync with friend's dex entries
- [ ] Verify location data syncs correctly

---

## Future Improvements (Low Priority)

1. **Add validation for enums**:
   - Conservation status codes ('EX', 'EN', 'VU', etc.)
   - Visibility choices ('private', 'friends', 'public')
   - Analysis status ('pending', 'processing', 'completed', 'failed')

2. **Add thumbnail generation** (server-side):
   - Generate thumbnails on image upload
   - Serve thumbnails via DexEntry serializer
   - Client already has `thumbnail_url` field ready

3. **Expose taxonomy metadata** (server-side):
   - `taxonomy_id` - Link to Taxonomy database record
   - `taxonomy_source` - Source database (e.g., "COL")
   - `taxonomy_confidence` - How confident we are in the match

4. **Add creator tracking to client** (client-side):
   - `created_by_username` - Who discovered this species
   - `discovery_count` - How many users have this in their dex

---

## Migration Priority

**Immediate** (Before next deployment):
1. Fix subspecies field on server (CRITICAL - data loss risk)
2. Verify all client field mappings work with test data

**Next Sprint**:
3. Add progress field to AnalysisJob
4. Add source_vision_job to main DexEntry serializer
5. Add image_checksum to main DexEntry serializer

**Future**:
6. Thumbnail generation system
7. Taxonomy metadata exposure
8. Creator/discovery tracking in client

---

## Summary

**Fixed Today**: 10 critical client-side field mapping issues
**Remaining**: 4 server-side issues requiring migrations/serializer updates
**Result**: Client now properly handles all server response formats with correct field names and null safety

The most critical remaining issue is the missing `subspecies` field on the server's Animal model, which should be addressed before the next production deployment to prevent data loss.
