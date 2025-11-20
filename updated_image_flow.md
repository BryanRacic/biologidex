# Updated Image Upload & Animal ID Workflow - Implementation Plan

## Current Workflow Overview
- User uploads image directly to vision job
- Image is converted server-side during CV analysis
- CV returns single animal (first one if multiple detected)
- User can only update via manual entry after job completes
- Image transformations (rotation) applied client-side pre-upload

## Proposed New Workflow
1. Upload image for conversion first
2. Download and display converted image
3. Allow client-side rotation/modifications
4. Submit modified image for CV analysis (using server copy)
5. Handle multiple animal results with selection UI
6. Create dex entry with selected animal

## Comprehensive Implementation Plan

### Phase 1: Image Upload & Conversion API
**Backend Changes (server/)**

#### 1.1 New Image Conversion Endpoint
```python
# server/images/views.py (NEW)
class ImageConversionViewSet:
    """
    POST /api/v1/images/convert/
    - Accept image upload
    - Convert to dex-compatible format (PNG, max 2560x2560)
    - Store temporarily with unique ID
    - Return conversion_id and download URL
    """

    # Request:
    # - image: multipart file upload
    # - transformations: optional JSON (rotation, crop, etc.)

    # Response:
    # {
    #   "conversion_id": "uuid",
    #   "download_url": "/api/v1/images/converted/{id}/",
    #   "metadata": {
    #     "original_format": "jpeg",
    #     "original_size": [3000, 2000],
    #     "converted_size": [2560, 1707],
    #     "transformations_applied": {},
    #     "checksum": "sha256..."
    #   }
    # }
```

#### 1.2 Image Storage Approach
```python
# server/images/models.py (NEW)
class ImageConversion(models.Model):
    """
    Track converted images using existing Django storage backend
    - Uses same storage as AnalysisJob (media/ or GCS)
    - Standard Django ImageField with upload_to path
    - Cleanup via Celery task for old conversions
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    original_image = models.ImageField(upload_to='conversions/originals/')
    converted_image = models.ImageField(upload_to='conversions/processed/')
    transformations = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()  # For cleanup task

# server/images/tasks.py (NEW)
@shared_task
def cleanup_expired_conversions():
    """Delete conversions older than 30 minutes"""
    expired = ImageConversion.objects.filter(
        expires_at__lt=timezone.now()
    )
    for conversion in expired:
        conversion.original_image.delete()
        conversion.converted_image.delete()
        conversion.delete()
```

#### 1.3 Replace Vision Job Creation
```python
# server/vision/views.py (REPLACE create method)
class AnalysisJobViewSet:
    def create():
        """
        ONLY accept conversion_id for pre-uploaded image
        Remove direct image upload capability

        Required field: conversion_id
        Optional field: transformations (for post-conversion transforms)
        """
```

### Phase 2: Multiple Animal Detection Support
**Backend Changes**

#### 2.1 Enhanced CV Response Parsing
```python
# server/vision/tasks.py (MODIFY)
def parse_and_create_animals(prediction: str, user) -> List[Animal]:
    """
    Parse ALL animals from CV response (split by |)
    Return list of Animal objects with confidence scores
    """
```

#### 2.2 Update AnalysisJob Model
```python
# server/vision/models.py (MODIFY)
class AnalysisJob:
    # Add fields:
    detected_animals = JSONField()  # List of all detected animals
    selected_animal_index = IntegerField()  # Which one was selected

class DetectedAnimal:
    # Structure for detected_animals JSON:
    # {
    #   "scientific_name": "Canis lupus",
    #   "common_name": "Gray Wolf",
    #   "confidence": 0.95,
    #   "animal_id": "uuid" (if matched),
    #   "is_new": false
    # }
```

#### 2.3 Animal Selection Endpoint
```python
# server/vision/views.py (ADD)
@action(detail=True, methods=['post'])
def select_animal(self, request, pk=None):
    """
    POST /api/v1/vision/jobs/{id}/select_animal/

    Select which detected animal to use for dex entry
    Body: {"animal_index": 0} or {"animal_id": "uuid"}
    """
```

### Phase 3: Frontend Implementation
**Client Changes (client/biologidex-client/)**

#### 3.1 New Image Service
```gdscript
# client/biologidex-client/api/services/image_service.gd (NEW)
extends BaseService

signal image_converted(response: Dictionary)
signal image_downloaded(image: Image)

func convert_image(
    image_data: PackedByteArray,
    file_name: String,
    file_type: String,
    transformations: Dictionary = {},
    callback: Callable = Callable()
) -> void:
    # POST to /api/v1/images/convert/

func download_converted_image(
    conversion_id: String,
    callback: Callable = Callable()
) -> void:
    # GET from /api/v1/images/converted/{id}/
```

#### 3.2 Updated Camera Scene Flow
```gdscript
# client/biologidex-client/camera.gd (MODIFY)

# New state management
enum CameraState {
    IDLE,
    IMAGE_SELECTED,
    IMAGE_CONVERTING,
    IMAGE_READY,
    ANALYZING,
    ANIMAL_SELECTION,
    COMPLETED
}

var current_state: CameraState = CameraState.IDLE
var conversion_id: String = ""
var detected_animals: Array = []
var selected_animal_index: int = -1

# Modified upload flow:
func _on_upload_pressed() -> void:
    match current_state:
        CameraState.IMAGE_SELECTED:
            _convert_image()  # Step 1: Convert image
        CameraState.IMAGE_READY:
            _analyze_image()  # Step 2: Run CV analysis

func _convert_image() -> void:
    # Upload image for conversion
    APIManager.images.convert_image(
        selected_file_data,
        selected_file_name,
        selected_file_type,
        pending_transformations,
        _on_image_converted
    )

func _on_image_converted(response: Dictionary, code: int) -> void:
    # Store conversion_id
    conversion_id = response.get("conversion_id", "")

    # Download converted image
    APIManager.images.download_converted_image(
        conversion_id,
        _on_converted_image_downloaded
    )

func _on_converted_image_downloaded(image: Image, code: int) -> void:
    # Display downloaded image
    # Enable rotation button
    # Update state to IMAGE_READY

func _analyze_image() -> void:
    # Create vision job using conversion_id
    APIManager.vision.create_vision_job_from_conversion(
        conversion_id,
        pending_transformations,  # Additional client-side transforms
        _on_analysis_complete
    )
```

#### 3.3 Animal Selection UI Component
```gdscript
# client/biologidex-client/components/animal_selection_popup.gd (NEW)
extends PopupPanel

signal animal_selected(animal_data: Dictionary)

var detected_animals: Array = []

func show_animals(animals: Array) -> void:
    # Display list of detected animals
    # Each item shows:
    # - Scientific name
    # - Common name
    # - Confidence score
    # - "Select" button

func _on_animal_selected(index: int) -> void:
    # Emit selection
    animal_selected.emit(detected_animals[index])

func _on_manual_entry_pressed() -> void:
    # Show manual entry popup for custom selection
```

#### 3.4 Modified Manual Entry Integration
```gdscript
# client/biologidex-client/components/manual_entry_popup.gd (MODIFY)

# Add mode for creating new entry vs updating existing
enum EntryMode {
    UPDATE_EXISTING,  # Current behavior
    CREATE_NEW,       # New animal selection mode
    SUGGEST_FROM_CV   # Pre-populate from CV suggestions
}

var entry_mode: EntryMode = EntryMode.UPDATE_EXISTING
var vision_job_id: String = ""  # For CREATE_NEW mode

func set_cv_suggestions(suggestions: Array) -> void:
    # Pre-populate search with CV suggestions
    # Show as "Suggested matches" section
```

### Phase 4: Backend API Updates

#### 4.1 Update Vision Service Response
```python
# server/vision/serializers.py (MODIFY)
class AnalysisJobSerializer:
    detected_animals = serializers.SerializerMethodField()

    def get_detected_animals(self, obj):
        # Return all detected animals with details
        return obj.detected_animals or []
```

#### 4.2 Dex Entry Creation Updates
```python
# server/dex/views.py (MODIFY)
class DexEntryViewSet:
    def create():
        """
        Accept either:
        1. animal_id (current)
        2. vision_job_id + selected_index (new)
        """
```

### Phase 5: Image Transformation Handling

#### 5.1 Client-Server Sync
```gdscript
# client/biologidex-client/camera.gd
# Track transformations locally, send only when analyzing

var total_rotation: int = 0  # Cumulative rotation (0, 90, 180, 270)
var displayed_image: Image  # Current displayed image with all transformations

func _on_rotate_image_pressed() -> void:
    # Apply rotation locally to displayed image
    total_rotation = (total_rotation + 90) % 360
    _apply_rotation_to_display()
    # Don't send anything to server yet

func _analyze_image() -> void:
    # Only NOW send the rotation data with the vision job request
    var final_transformations = {}
    if total_rotation > 0:
        final_transformations["rotation"] = total_rotation

    # Create vision job with conversion_id and final transformations
    APIManager.vision.create_vision_job_from_conversion(
        conversion_id,
        final_transformations,  # Send accumulated transformations
        _on_analysis_complete
    )
```

#### 5.2 Server Transformation Tracking
```python
# Additional transformations tracking for vision jobs
# server/vision/models.py (MODIFY)
class AnalysisJob:
    # Add field to track transformations applied after conversion
    post_conversion_transformations = models.JSONField(
        default=dict,
        blank=True,
        help_text="Client-side transformations applied after image conversion"
    )
```

### Phase 6: Error Handling & Edge Cases

#### 6.1 Conversion Failures
- Handle unsupported formats gracefully
- Provide clear error messages
- Allow retry with different settings

#### 6.2 No Animals Detected
- Show "No animals found" message
- Provide manual entry option immediately
- Allow re-analysis with different image

#### 6.3 Network Interruptions
- Cache converted images locally
- Resume from last successful step
- Prevent duplicate uploads

### Phase 7: Testing

#### 7.1 Backend Tests
```python
# server/vision/tests/test_multiple_animals.py
- Test parsing multiple animals from CV
- Test animal selection endpoint
- Test conversion_id flow

# server/images/tests/test_conversion.py
- Test image conversion endpoint
- Test transformation application
- Test access control
```

#### 7.2 Frontend Tests
- Test state transitions in camera flow
- Test animal selection UI
- Test error recovery
- Test rotation at different stages

### Phase 8: Database Migrations & Cleanup

#### 8.1 Database Changes
```python
# server/vision/migrations/00XX_add_multiple_animals.py
- Add detected_animals JSONField to AnalysisJob
- Add selected_animal_index field
- Add source_conversion_id field to replace image field

# server/images/migrations/00XX_add_image_conversions.py
- Create ImageConversion model
- Add indexes for user and expiry
```

#### 8.2 Code Cleanup
```python
# REMOVE old direct upload code:
- server/vision/serializers.py: Remove AnalysisJobCreateSerializer.image field
- server/vision/views.py: Remove direct image upload logic from create()
- client/camera.gd: Remove old upload flow without conversion
- client/api_manager.gd: Remove deprecated create_vision_job methods

# UPDATE documentation:
- Remove all references to direct image upload in API docs
- Update README with new workflow
- Update API endpoints documentation
```

### Implementation Priority & Timeline

**Week 1: Core API**
- [ ] Image conversion endpoint
- [ ] Temporary storage service
- [ ] Modified vision job to accept conversion_id

**Week 2: Multiple Animals**
- [ ] Parse all animals from CV response
- [ ] Store detected_animals in AnalysisJob
- [ ] Animal selection endpoint

**Week 3: Frontend Flow**
- [ ] Image service for conversion/download
- [ ] Updated camera scene state machine
- [ ] Display converted image

**Week 4: Selection UI**
- [ ] Animal selection popup component
- [ ] Integration with manual entry
- [ ] Updated dex entry creation

**Week 5: Polish & Testing**
- [ ] Error handling improvements
- [ ] Performance optimization
- [ ] Documentation

### Performance Considerations

1. **Image Caching**
   - Cache converted images in Redis (30 min TTL)
   - Client-side cache for downloaded images
   - Prevent redundant conversions

2. **Async Processing**
   - Use Celery for image conversion
   - Stream large image downloads
   - Progressive loading for UI

3. **Database Optimization**
   - Index on conversion_id for fast lookups
   - Cleanup job for expired conversions
   - Efficient JSON queries for detected_animals

### Security Considerations

1. **Access Control**
   - Verify user owns conversion before use
   - Rate limit conversion endpoint
   - Validate image formats strictly

2. **Data Privacy**
   - Auto-delete temporary images after 30 min
   - Don't log image data
   - Secure transmission over HTTPS

### Success Metrics

1. **User Experience**
   - Reduced time to successful dex entry
   - Increased accuracy of animal selection
   - Fewer manual corrections needed

2. **Technical Metrics**
   - Conversion success rate > 99%
   - CV analysis reuse rate > 80%
   - Average selection time < 5 seconds

3. **Business Metrics**
   - Reduced CV API costs (fewer retries)
   - Increased user engagement
   - Higher dex completion rates

## Summary

This implementation plan represents a **complete overhaul** of the image upload and animal identification workflow, replacing the existing direct upload system entirely. This is not a gradual migration - the old workflow will be completely removed.

### Key Changes:

1. **Mandatory two-step process** - All images must go through conversion before analysis (no direct upload)
2. **Multiple animal detection** - Parse and present all detected animals for user selection
3. **Client-side selection UI** - New UI components for choosing from multiple detections
4. **Clean architecture** - Remove all legacy code, deprecated methods, and old documentation
5. **Performance optimizations** - Built-in caching, async processing, and efficient data flow

### Migration Notes:
- **No backwards compatibility** - Old API endpoints will be removed
- **Complete replacement** - All existing vision job creation code must be updated
- **Clean codebase** - Remove all references to the old workflow to prevent confusion
