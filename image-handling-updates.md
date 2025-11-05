# BiologiDex Image Handling Updates - Implementation Guide

## Executive Summary
This document outlines the implementation of enhanced image handling capabilities for the BiologiDex application, including client-side image rotation and improved server-client synchronization of dex entries with their associated images.

## Current State Analysis

### Existing Components
1. **Server-side Image Processing (vision/image_processor.py)**
   - Converts images to PNG format (max 2560x2560)
   - Handles transparency → RGB conversion
   - Stores both original and dex-compatible versions
   - EXIF orientation extraction capability exists but unused

2. **Vision Models (vision/models.py - AnalysisJob)**
   - Already stores original image and dex_compatible_image
   - Tracks conversion status and metadata
   - Links to DexEntry via source_vision_job FK

3. **DexEntry Model (dex/models.py)**
   - Has original_image and processed_image fields
   - Links to vision.AnalysisJob for dex_compatible_image access
   - display_image_url property provides smart fallback

4. **Client Image Handling (camera.gd)**
   - Uploads original format images
   - Downloads and caches dex-compatible images locally
   - Displays images but no modification capabilities

5. **Client Dex Gallery (dex.gd)**
   - Displays locally cached images
   - No server synchronization currently implemented

## Implementation Plan

### Phase 1: Image Management Infrastructure

#### 1.1 Create Centralized Image Model
**Location**: `server/images/` (new Django app)

```python
# server/images/models.py
class ProcessedImage(models.Model):
    """
    Central repository for all processed images in the system.
    Tracks transformations and provides versioning capability.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)

    # Source tracking
    source_type = models.CharField(max_length=20, choices=[
        ('vision_job', 'Vision Analysis Job'),
        ('user_upload', 'Direct User Upload'),
        ('dex_edit', 'Dex Entry Edit'),
    ])
    source_id = models.UUIDField(null=True, blank=True)  # Generic FK to source

    # Files
    original_file = models.ImageField(upload_to='images/original/%Y/%m/')
    processed_file = models.ImageField(upload_to='images/processed/%Y/%m/')
    thumbnail = models.ImageField(
        upload_to='images/thumbnails/%Y/%m/',
        null=True, blank=True
    )

    # Metadata
    original_format = models.CharField(max_length=10)
    original_dimensions = models.JSONField()  # {"width": int, "height": int}
    processed_dimensions = models.JSONField()
    file_size_bytes = models.IntegerField()

    # Transformations applied
    transformations = models.JSONField(default=dict)
    # Example: {
    #     "rotation": 90,
    #     "crop": {"x": 0, "y": 0, "width": 100, "height": 100},
    #     "brightness": 1.1,
    #     "contrast": 1.0
    # }

    # Processing details
    processing_warnings = models.JSONField(default=list)
    processing_errors = models.JSONField(default=list)
    exif_data = models.JSONField(default=dict, blank=True)

    # Versioning
    version = models.IntegerField(default=1)
    parent_image = models.ForeignKey(
        'self',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='versions'
    )

    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    # Checksums for deduplication
    original_checksum = models.CharField(max_length=64, db_index=True)
    processed_checksum = models.CharField(max_length=64, db_index=True)
```

**Actions Required**:
1. Create new Django app: `python manage.py startapp images`
2. Add to INSTALLED_APPS
3. Create and run migrations
4. Update AnalysisJob to optionally use ProcessedImage
5. Update DexEntry to reference ProcessedImage

#### 1.2 Enhanced Image Processor
**Location**: `server/images/processor.py`

```python
class EnhancedImageProcessor:
    """Extended image processor with rotation and transformation support."""

    @classmethod
    def apply_transformations(cls, img: Image, transformations: dict) -> Image:
        """Apply a series of transformations to an image."""

        # Handle rotation (including EXIF auto-rotation)
        if 'rotation' in transformations:
            angle = transformations['rotation']
            img = img.rotate(-angle, expand=True, fillcolor='white')

        # Handle crop
        if 'crop' in transformations:
            crop = transformations['crop']
            img = img.crop((
                crop['x'],
                crop['y'],
                crop['x'] + crop['width'],
                crop['y'] + crop['height']
            ))

        # Additional transformations for future
        # brightness, contrast, etc.

        return img

    @classmethod
    def auto_rotate_from_exif(cls, img: Image) -> Tuple[Image, int]:
        """Auto-rotate image based on EXIF orientation."""
        try:
            exif = img.getexif()
            orientation = exif.get(0x0112, 1)

            rotation_map = {
                3: 180,
                6: 270,
                8: 90
            }

            if orientation in rotation_map:
                angle = rotation_map[orientation]
                img = img.rotate(-angle, expand=True)
                return img, angle
        except:
            pass

        return img, 0
```

### Phase 2: Client-Side Image Rotation

#### 2.1 Add Rotation UI to Camera Scene
**Location**: `client/biologidex-client/camera.tscn` and `camera.gd`

**UI Changes**:
1. Add rotation controls after image selection
2. Show only when image is loaded and visible
3. Provide 90° increment rotation buttons

```gdscript
# camera.gd additions
var current_rotation: int = 0  # Track rotation angle (0, 90, 180, 270)
var pending_transformations: Dictionary = {}  # Track all modifications

@onready var rotation_controls: HBoxContainer = $Panel/.../RotationControls
@onready var rotate_left_button: Button = $Panel/.../RotateLeftButton
@onready var rotate_right_button: Button = $Panel/.../RotateRightButton

func _ready() -> void:
    # ... existing code ...
    rotate_left_button.pressed.connect(_on_rotate_left)
    rotate_right_button.pressed.connect(_on_rotate_right)
    rotation_controls.visible = false

func _on_file_loaded(...) -> void:
    # ... existing code ...
    rotation_controls.visible = true
    current_rotation = 0

func _on_rotate_left() -> void:
    current_rotation = (current_rotation - 90) % 360
    _apply_rotation_to_preview()
    pending_transformations["rotation"] = current_rotation

func _on_rotate_right() -> void:
    current_rotation = (current_rotation + 90) % 360
    _apply_rotation_to_preview()
    pending_transformations["rotation"] = current_rotation

func _apply_rotation_to_preview() -> void:
    # Apply visual rotation to the TextureRect
    simple_image.rotation_degrees = current_rotation
    bordered_image.rotation_degrees = current_rotation

    # Swap width/height for aspect ratio if 90 or 270
    if current_rotation == 90 or current_rotation == 270:
        var temp = current_image_width
        current_image_width = current_image_height
        current_image_height = temp

    _update_record_image_size()
```

#### 2.2 Send Transformations with Upload
**Location**: `client/biologidex-client/api_manager.gd`

```gdscript
func create_vision_job_with_transformations(
    image_data: PackedByteArray,
    filename: String,
    content_type: String,
    transformations: Dictionary,
    access_token: String,
    callback: Callable
) -> void:
    # Include transformations in multipart form data
    var form_data = [
        {"name": "image", "data": image_data, "filename": filename, "type": content_type},
        {"name": "transformations", "data": JSON.stringify(transformations)}
    ]
    # ... rest of upload logic
```

### Phase 3: Server-Side Processing Updates

#### 3.1 Update Vision API to Accept Transformations
**Location**: `server/vision/views.py`

```python
class AnalysisJobViewSet(viewsets.ModelViewSet):

    def create(self, request, *args, **kwargs):
        # Parse transformations from request
        transformations = request.data.get('transformations', {})
        if isinstance(transformations, str):
            transformations = json.loads(transformations)

        # Create job with transformations
        job = AnalysisJob.objects.create(
            user=request.user,
            image=request.FILES['image'],
            # Store transformations for processing
        )

        # Trigger async processing with transformations
        process_analysis_job.delay(str(job.id), transformations)
```

#### 3.2 Apply Transformations in Processing Pipeline
**Location**: `server/vision/tasks.py`

```python
@shared_task
def process_analysis_job(job_id: str, transformations: dict = None):
    # ... existing code ...

    # Apply transformations before creating dex-compatible
    if transformations:
        img = Image.open(job.image)
        img = EnhancedImageProcessor.apply_transformations(img, transformations)

        # Save transformed version
        temp_file = BytesIO()
        img.save(temp_file, format='PNG')
        temp_file.seek(0)

        # Process this transformed image
        processed_file, metadata = ImageProcessor.process_image(temp_file)
```

### Phase 4: Dex Synchronization

#### 4.1 Create Dex Sync API Endpoint
**Location**: `server/dex/views.py`

```python
@action(detail=False, methods=['get'])
def sync_entries(self, request):
    """
    Sync endpoint for client to check for updated dex entries.
    Returns entries with their image metadata for comparison.
    """
    last_sync = request.query_params.get('last_sync')

    entries = self.get_queryset().filter(owner=request.user)

    if last_sync:
        entries = entries.filter(updated_at__gt=last_sync)

    # Include image metadata for client comparison
    data = []
    for entry in entries:
        entry_data = DexEntrySyncSerializer(entry).data

        # Add image version/checksum for client comparison
        if entry.source_vision_job and entry.source_vision_job.dex_compatible_image:
            entry_data['image_checksum'] = calculate_checksum(
                entry.source_vision_job.dex_compatible_image
            )
            entry_data['image_updated_at'] = entry.source_vision_job.updated_at

        data.append(entry_data)

    return Response({
        'entries': data,
        'server_time': timezone.now()
    })
```

#### 4.2 Client Dex Sync Manager
**Location**: `client/biologidex-client/dex_sync_manager.gd` (new autoload)

```gdscript
extends Node

signal sync_started()
signal sync_completed(updated_count: int)
signal sync_failed(error: String)

const SYNC_INTERVAL: float = 60.0  # Sync every 60 seconds
const LAST_SYNC_KEY: String = "last_sync_timestamp"

var sync_timer: Timer
var is_syncing: bool = false

func _ready() -> void:
    # Set up periodic sync
    sync_timer = Timer.new()
    sync_timer.wait_time = SYNC_INTERVAL
    sync_timer.timeout.connect(_perform_sync)
    add_child(sync_timer)

    # Start sync timer if logged in
    if TokenManager.is_logged_in():
        sync_timer.start()
        _perform_sync()  # Initial sync

func _perform_sync() -> void:
    if is_syncing or not TokenManager.is_logged_in():
        return

    is_syncing = true
    sync_started.emit()

    var last_sync = _get_last_sync_timestamp()

    APIManager.sync_dex_entries(
        last_sync,
        TokenManager.get_access_token(),
        _on_sync_response
    )

func _on_sync_response(response: Dictionary, code: int) -> void:
    if code != 200:
        is_syncing = false
        sync_failed.emit("Sync failed: " + str(code))
        return

    var updated_count = 0
    var entries = response.get("entries", [])

    for entry_data in entries:
        var needs_update = _check_if_needs_update(entry_data)

        if needs_update:
            # Download updated image if needed
            var image_url = entry_data.get("dex_compatible_url", "")
            if image_url:
                await _download_and_cache_image(image_url)

            # Update local database
            DexDatabase.update_or_add_record(
                entry_data["creation_index"],
                entry_data["scientific_name"],
                entry_data["common_name"],
                _get_cached_image_path(image_url)
            )

            updated_count += 1

    # Save sync timestamp
    _save_last_sync_timestamp(response.get("server_time", ""))

    is_syncing = false
    sync_completed.emit(updated_count)

func _check_if_needs_update(server_entry: Dictionary) -> bool:
    var local_record = DexDatabase.get_record(server_entry["creation_index"])

    if local_record.is_empty():
        return true  # New entry

    # Check if image has been updated
    var server_checksum = server_entry.get("image_checksum", "")
    var local_checksum = _calculate_local_checksum(local_record["cached_image_path"])

    return server_checksum != local_checksum
```

### Phase 5: Migration and Deployment

#### 5.1 Database Migrations
```bash
# Server side
cd server
python manage.py startapp images
# Add 'images' to INSTALLED_APPS
python manage.py makemigrations images
python manage.py makemigrations vision dex  # For FK updates
python manage.py migrate
```

#### 5.2 Update Existing Data
Create management command to migrate existing images to new structure:

```python
# server/images/management/commands/migrate_images.py
from django.core.management.base import BaseCommand
from vision.models import AnalysisJob
from images.models import ProcessedImage

class Command(BaseCommand):
    def handle(self, *args, **options):
        for job in AnalysisJob.objects.filter(dex_compatible_image__isnull=False):
            ProcessedImage.objects.create(
                source_type='vision_job',
                source_id=job.id,
                original_file=job.image,
                processed_file=job.dex_compatible_image,
                # ... populate other fields
            )
```


### Risk Mitigation

1. **Data Loss Prevention**
   - Never delete original images
   - Version all transformations
   - Maintain backwards compatibility

2. **Performance Concerns**
   - Implement image processing queue limits
   - Add caching for processed images
   - Use thumbnails for list views

3. **Network Reliability**
   - Implement retry logic for sync
   - Queue failed uploads locally
   - Show sync status to user

4. **Storage Optimization**
   - Implement image deduplication via checksums
   - Clean up orphaned images periodically
   - Use progressive image loading

### Success Metrics

- Client can rotate images before upload
- Rotated images display correctly in dex
- Sync completes in <5 seconds for 100 entries
- No data loss during transformation
- Storage usage reduced by 20% via deduplication

### Future Enhancements

1. **Phase 7**: Additional image editing
   - Crop functionality
   - Brightness/contrast adjustment
   - Filter effects

2. **Phase 8**: Advanced sync
   - Selective sync (favorites only)
   - Conflict resolution UI
   - Offline mode with queue

3. **Phase 9**: Performance optimization
   - WebP format support
   - CDN integration
   - Progressive web app features