# BiologiDex Image Overhaul Implementation Plan

## Overview

This plan addresses the need to standardize image handling across the BiologiDex platform to accommodate various image formats (including problematic Samsung MPO files) while providing consistent, reliable image display and storage. The core strategy is to maintain original uploads while creating standardized "dex-compatible" versions for display.

## Current State Summary

### Client (Godot 4.5)
- **Robust loading**: 3-stage fallback with MPO extraction
- **Upload format**: All images converted to PNG before upload
- **Display modes**: Simple preview → Bordered display after identification
- **Problem**: Cannot preview all formats; MPO files require complex extraction

### Server (Django)
- **Storage**: Original images stored in `vision/analysis/` directory
- **Processing**: Base64 encoded and sent to OpenAI Vision API
- **DexEntry**: Has `processed_image` field (unused placeholder)
- **Problem**: No standardized image conversion; relies on client PNG conversion

## Proposed Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      NEW IMAGE FLOW                          │
├─────────────────────────────────────────────────────────────┤
│ CLIENT:                                                       │
│ 1. Select image → Attempt preview (with format warning)      │
│ 2. Upload original file (no conversion)                      │
│ 3. Receive job with dex_compatible_url                       │
│ 4. Download and cache dex-compatible image                   │
│ 5. Use cached image for all displays                         │
│                                                               │
│ SERVER:                                                       │
│ 1. Receive original image → Store as-is                      │
│ 2. Convert to PNG (max 2560x2560) → Store as dex_compatible │
│ 3. Send to Vision API (use dex_compatible)                   │
│ 4. Return URLs for both original and dex_compatible          │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Server-Side Image Processing Pipeline

#### 1.1 Update AnalysisJob Model
**File**: `server/vision/models.py`

Add new field for standardized image:
```python
class AnalysisJob(models.Model):
    # Existing fields...
    image = models.ImageField(
        upload_to='vision/analysis/original/%Y/%m/',  # Change path
        help_text=_('Original uploaded image')
    )

    # NEW FIELD
    dex_compatible_image = models.ImageField(
        upload_to='vision/analysis/dex_compatible/%Y/%m/',
        null=True,
        blank=True,
        help_text=_('Standardized PNG image for display (max 2560x2560)')
    )

    # NEW FIELD for tracking conversion
    image_conversion_status = models.CharField(
        max_length=20,
        choices=[
            ('pending', 'Pending'),
            ('processing', 'Processing'),
            ('completed', 'Completed'),
            ('failed', 'Failed'),
            ('unnecessary', 'Unnecessary'),  # Original already meets criteria
        ],
        default='pending',
        help_text=_('Status of image standardization')
    )
```

#### 1.2 Create Image Processor Service
**New File**: `server/vision/image_processor.py`

```python
import os
from PIL import Image
from io import BytesIO
from django.core.files.base import ContentFile
from typing import Tuple, Optional
import logging

logger = logging.getLogger(__name__)

class ImageProcessor:
    """Handles image format conversion and resizing for BiologiDex."""

    MAX_DIMENSION = 2560
    OUTPUT_FORMAT = 'PNG'
    JPEG_QUALITY = 95  # For future JPEG support

    @classmethod
    def process_image(cls, image_file) -> Tuple[Optional[ContentFile], dict]:
        """
        Process an image to create a dex-compatible version.

        Args:
            image_file: Django ImageField file object

        Returns:
            Tuple of (ContentFile or None, metadata dict)
        """
        metadata = {
            'original_format': None,
            'original_dimensions': None,
            'processed_dimensions': None,
            'was_resized': False,
            'was_converted': False,
            'error': None
        }

        try:
            # Open image with Pillow
            image_file.seek(0)
            img = Image.open(image_file)

            # Store original metadata
            metadata['original_format'] = img.format
            metadata['original_dimensions'] = img.size

            # Check if processing needed
            needs_resize = max(img.size) > cls.MAX_DIMENSION
            needs_conversion = img.format != cls.OUTPUT_FORMAT

            if not needs_resize and not needs_conversion:
                # Original already meets criteria
                return None, metadata

            # Convert RGBA to RGB if necessary (for PNG with transparency)
            if img.mode in ('RGBA', 'LA', 'P'):
                # Create white background
                background = Image.new('RGB', img.size, (255, 255, 255))
                if img.mode == 'P':
                    img = img.convert('RGBA')
                background.paste(img, mask=img.split()[-1] if img.mode == 'RGBA' else None)
                img = background
            elif img.mode != 'RGB':
                img = img.convert('RGB')

            # Resize if needed (maintain aspect ratio)
            if needs_resize:
                img.thumbnail((cls.MAX_DIMENSION, cls.MAX_DIMENSION), Image.Resampling.LANCZOS)
                metadata['was_resized'] = True
                metadata['processed_dimensions'] = img.size
            else:
                metadata['processed_dimensions'] = metadata['original_dimensions']

            # Convert to PNG
            output = BytesIO()
            img.save(output, format=cls.OUTPUT_FORMAT, optimize=True)
            output.seek(0)

            metadata['was_converted'] = needs_conversion

            # Create ContentFile for Django
            filename = f"dex_compatible_{os.path.splitext(os.path.basename(image_file.name))[0]}.png"
            return ContentFile(output.read(), name=filename), metadata

        except Exception as e:
            logger.error(f"Image processing failed: {str(e)}")
            metadata['error'] = str(e)
            return None, metadata

    @classmethod
    def extract_image_metadata(cls, image_file) -> dict:
        """Extract useful metadata from image."""
        try:
            image_file.seek(0)
            img = Image.open(image_file)

            # Extract EXIF if available
            exif = img.getexif() if hasattr(img, 'getexif') else {}

            return {
                'format': img.format,
                'mode': img.mode,
                'size': img.size,
                'width': img.width,
                'height': img.height,
                'has_transparency': img.mode in ('RGBA', 'LA', 'P'),
                'exif_orientation': exif.get(0x0112, 1) if exif else 1,  # EXIF Orientation tag
            }
        except Exception as e:
            logger.error(f"Metadata extraction failed: {str(e)}")
            return {}
```

#### 1.3 Update Vision Task
**File**: `server/vision/tasks.py`

Modify the `process_analysis_job` task to create dex-compatible image:

```python
from vision.image_processor import ImageProcessor

@shared_task(bind=True, max_retries=3)
def process_analysis_job(self, job_id: str):
    """Process an analysis job to identify animal in image."""
    try:
        job = AnalysisJob.objects.get(id=job_id)

        # Mark as processing
        job.mark_processing()

        # NEW: Process image to create dex-compatible version
        if not job.dex_compatible_image and job.image:
            processed_file, metadata = ImageProcessor.process_image(job.image)

            if processed_file:
                # Save the processed image
                job.dex_compatible_image.save(
                    processed_file.name,
                    processed_file,
                    save=False
                )
                job.image_conversion_status = 'completed'
                logger.info(f"Created dex-compatible image: {metadata}")
            elif metadata.get('error'):
                job.image_conversion_status = 'failed'
                logger.error(f"Image conversion failed: {metadata['error']}")
            else:
                # Original already meets criteria
                job.dex_compatible_image = job.image
                job.image_conversion_status = 'unnecessary'
                logger.info("Original image already dex-compatible")

            job.save()

        # Use dex-compatible image for CV analysis (or original if conversion failed)
        image_to_analyze = job.dex_compatible_image or job.image

        # Create CV service
        cv_service = CVServiceFactory.create(
            method=job.cv_method,
            model=job.model_name,
            detail=job.detail_level
        )

        # Perform identification with the processed image
        result = cv_service.identify_animal(image_to_analyze.path)

        # Rest of the existing task code...
```

#### 1.4 Update Serializers
**File**: `server/vision/serializers.py`

Add dex-compatible image URL to response:

```python
class AnalysisJobSerializer(serializers.ModelSerializer):
    animal_details = AnimalListSerializer(source='identified_animal', read_only=True)
    duration = serializers.SerializerMethodField()

    # NEW FIELD
    dex_compatible_url = serializers.SerializerMethodField()

    class Meta:
        model = AnalysisJob
        fields = [
            'id', 'image', 'dex_compatible_url',  # NEW FIELD ADDED
            'user', 'status', 'cv_method', 'model_name',
            'detail_level', 'parsed_prediction', 'identified_animal',
            'animal_details', 'confidence_score', 'cost_usd',
            'processing_time', 'input_tokens', 'output_tokens',
            'error_message', 'retry_count', 'created_at',
            'started_at', 'completed_at', 'duration',
            'image_conversion_status',  # NEW FIELD
        ]
        read_only_fields = ['id', 'user', 'created_at', 'duration']

    def get_dex_compatible_url(self, obj):
        """Return URL for dex-compatible image."""
        if obj.dex_compatible_image:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.dex_compatible_image.url)
            return obj.dex_compatible_image.url
        return None
```

#### 1.5 Add Public Access Endpoint (Temporary)
**File**: `server/vision/views.py`

Add endpoint for public image access (with TODO for future authentication):

```python
from django.http import HttpResponse, Http404
from django.views import View

class DexCompatibleImageView(View):
    """
    Serve dex-compatible images.

    TODO: Add proper IAM/permission checks:
    - Verify user owns the image OR
    - Image is from a public dex entry OR
    - User has friend access to the owner
    """

    def get(self, request, job_id):
        try:
            job = AnalysisJob.objects.get(id=job_id)

            # TODO: Add permission checks here
            # For now, all dex-compatible images are public

            if not job.dex_compatible_image:
                raise Http404("Dex-compatible image not found")

            # Serve the image
            image_file = job.dex_compatible_image
            response = HttpResponse(image_file.read(), content_type='image/png')
            response['Content-Disposition'] = f'inline; filename="dex_{job_id}.png"'
            response['Cache-Control'] = 'public, max-age=31536000'  # 1 year cache
            return response

        except AnalysisJob.DoesNotExist:
            raise Http404("Job not found")
```

Update URLs:
```python
# In vision/urls.py
urlpatterns = [
    # ... existing patterns
    path('jobs/<uuid:job_id>/dex-image/', DexCompatibleImageView.as_view(), name='dex-compatible-image'),
]
```

### Phase 2: Client-Side Updates

#### 2.1 Update Camera Scene
**File**: `client/biologidex-client/camera.gd`

Modify to handle unsupported formats and remove PNG conversion:

```gdscript
# Add at top of file
var unsupported_format_warning := false
var dex_compatible_url := ""
var cached_dex_image: Image = null

func _on_file_loaded(file_name: String, file_type: String, file_data: PackedByteArray) -> void:
    """Handle file loaded from file picker or test image."""
    print("[Camera] File loaded: %s (type: %s, size: %d bytes)" % [
        file_name, file_type, file_data.size()
    ])

    # Store original file data (no conversion!)
    selected_file_name = file_name
    selected_file_type = file_type
    selected_file_data = file_data  # Keep original format

    # Try to preview the image
    var preview_result = _attempt_image_preview(file_data, file_type)

    if preview_result.success:
        # Show preview
        _display_simple_preview(preview_result.image)
        current_image_width = float(preview_result.image.get_width())
        current_image_height = float(preview_result.image.get_height())
        unsupported_format_warning = false
    else:
        # Show warning but allow upload
        _show_format_warning()
        unsupported_format_warning = true

    # Enable upload button regardless
    upload_button.disabled = false
    upload_button.text = "Upload for Analysis"

func _attempt_image_preview(data: PackedByteArray, mime_type: String) -> Dictionary:
    """Try to load image for preview. Returns {success: bool, image: Image}."""
    var result = {"success": false, "image": null}

    var image := Image.new()
    var load_error := OK

    # Try robust loading (existing code)
    image = _load_image_robust(data, mime_type)

    if image and not image.is_empty():
        result.success = true
        result.image = image

    return result

func _show_format_warning() -> void:
    """Display warning that image cannot be previewed."""
    # Hide the image preview
    var image_node = $RecordImage/Image
    image_node.texture = null

    # Show warning message
    status_label.text = "⚠️ Image format not supported for preview, but can still be uploaded"
    status_label.modulate = Color(1.0, 0.8, 0.0)  # Yellow warning

    # Could also show a placeholder image
    var placeholder = preload("res://resources/unsupported_format_placeholder.png")
    if placeholder:
        image_node.texture = placeholder

func _upload_image() -> void:
    """Upload the ORIGINAL image file to server (no conversion)."""
    if not selected_file_data or selected_file_data.is_empty():
        return

    # Show upload progress
    _show_upload_progress()

    # Upload ORIGINAL file data (not converted)
    var result = await api_manager.upload_image_for_analysis(
        selected_file_data,
        selected_file_name,
        selected_file_type  # Original MIME type
    )

    if result.success:
        # ... existing success handling
        pass

func _on_job_completed(response: Dictionary) -> void:
    """Handle completed job with dex-compatible image URL."""
    # ... existing code ...

    # NEW: Download and cache dex-compatible image
    if response.has("dex_compatible_url"):
        dex_compatible_url = response["dex_compatible_url"]
        await _download_and_cache_dex_image(dex_compatible_url)

    # Display using cached dex image
    if cached_dex_image:
        _display_bordered_image(cached_dex_image)

    # ... rest of existing code

func _download_and_cache_dex_image(url: String) -> void:
    """Download the dex-compatible image and cache it locally."""
    print("[Camera] Downloading dex-compatible image: %s" % url)

    var http := HTTPRequest.new()
    add_child(http)

    var headers := []
    if TokenManager.has_valid_token():
        headers.append("Authorization: Bearer %s" % TokenManager.get_access_token())

    http.request(url, headers)
    var response = await http.request_completed

    # Parse response
    var result_code = response[1]  # HTTP status code
    var body = response[3]  # PackedByteArray

    if result_code == 200 and body.size() > 0:
        # Load the PNG image
        var image := Image.new()
        var error := image.load_png_from_buffer(body)

        if error == OK:
            cached_dex_image = image

            # Save to user://dex_cache/ for persistence
            _save_cached_image(dex_compatible_url, body)

            print("[Camera] Dex image cached successfully")
        else:
            push_error("[Camera] Failed to load dex image: %s" % error)
    else:
        push_error("[Camera] Failed to download dex image: HTTP %d" % result_code)

    http.queue_free()

func _save_cached_image(url: String, data: PackedByteArray) -> void:
    """Save cached image to local storage."""
    var cache_dir := "user://dex_cache/"
    var dir := DirAccess.open("user://")

    if not dir.dir_exists("dex_cache"):
        dir.make_dir("dex_cache")

    # Use URL hash as filename
    var filename := cache_dir + url.md5_text() + ".png"
    var file := FileAccess.open(filename, FileAccess.WRITE)
    if file:
        file.store_buffer(data)
        file.close()
        print("[Camera] Cached image saved to: %s" % filename)

func _load_cached_image(url: String) -> Image:
    """Load previously cached image if available."""
    var filename := "user://dex_cache/" + url.md5_text() + ".png"

    if FileAccess.file_exists(filename):
        var file := FileAccess.open(filename, FileAccess.READ)
        if file:
            var data := file.get_buffer(file.get_length())
            file.close()

            var image := Image.new()
            if image.load_png_from_buffer(data) == OK:
                return image

    return null
```

#### 2.2 Update API Manager
**File**: `client/biologidex-client/api_manager.gd`

Remove PNG conversion from upload:

```gdscript
func upload_image_for_analysis(image_data: PackedByteArray,
                               file_name: String,
                               mime_type: String) -> Dictionary:
    """
    Upload image for CV analysis.
    Now sends ORIGINAL format, not converted to PNG.
    """
    var url := "%s/vision/jobs/" % API_BASE_URL
    var access_token := TokenManager.get_access_token()

    if not access_token:
        return _create_error_response("No access token available")

    # Prepare request
    var http_request := HTTPRequest.new()
    add_child(http_request)
    http_request.timeout = 30.0

    # Build multipart body with ORIGINAL data
    const boundary := "GodotBiologiDexBoundary"
    var headers := [
        "Content-Type: multipart/form-data; boundary=%s" % boundary,
        "Authorization: Bearer %s" % access_token
    ]

    # Use original MIME type instead of forcing image/png
    var body := _build_multipart_body(boundary, "image", file_name, mime_type, image_data)

    # Send request
    var error := http_request.request_raw(url, headers, HTTPClient.METHOD_POST, body)

    # ... rest remains the same
```

### Phase 3: Database Migration

#### 3.1 Create Migration
```bash
python manage.py makemigrations vision -n add_dex_compatible_image
```

#### 3.2 Data Migration for Existing Images
**File**: `server/vision/migrations/XXXX_process_existing_images.py`

```python
from django.db import migrations
from django.db.models import F

def process_existing_images(apps, schema_editor):
    """Process existing images to create dex-compatible versions."""
    AnalysisJob = apps.get_model('vision', 'AnalysisJob')

    # Import within function to avoid issues
    from vision.image_processor import ImageProcessor

    jobs_to_process = AnalysisJob.objects.filter(
        dex_compatible_image__isnull=True,
        image__isnull=False
    )

    for job in jobs_to_process:
        try:
            processed_file, metadata = ImageProcessor.process_image(job.image)

            if processed_file:
                job.dex_compatible_image.save(
                    processed_file.name,
                    processed_file,
                    save=True
                )
                job.image_conversion_status = 'completed'
            else:
                # Original already compatible
                job.dex_compatible_image = job.image
                job.image_conversion_status = 'unnecessary'

            job.save()
        except Exception as e:
            print(f"Failed to process job {job.id}: {e}")
            job.image_conversion_status = 'failed'
            job.save()

def reverse_migration(apps, schema_editor):
    """Remove dex-compatible images."""
    AnalysisJob = apps.get_model('vision', 'AnalysisJob')
    AnalysisJob.objects.update(
        dex_compatible_image=None,
        image_conversion_status='pending'
    )

class Migration(migrations.Migration):
    dependencies = [
        ('vision', 'XXXX_add_dex_compatible_image'),
    ]

    operations = [
        migrations.RunPython(process_existing_images, reverse_migration),
    ]
```

### Phase 4: Update DexEntry for Future Use

#### 4.1 Update DexEntry Model
**File**: `server/dex/models.py`

Link to standardized image from vision job:

```python
class DexEntry(models.Model):
    # ... existing fields ...

    # Link to vision job for standardized image
    source_vision_job = models.ForeignKey(
        'vision.AnalysisJob',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='dex_entries',
        help_text=_('Source vision job with dex-compatible image')
    )

    @property
    def display_image_url(self):
        """Get URL for display image (dex-compatible or processed)."""
        if self.processed_image:
            return self.processed_image.url
        elif self.source_vision_job and self.source_vision_job.dex_compatible_image:
            return self.source_vision_job.dex_compatible_image.url
        else:
            return self.original_image.url
```

## Testing Plan

### Unit Tests

1. **Image Processor Tests** (`server/vision/tests/test_image_processor.py`)
   - Test PNG conversion
   - Test resizing logic
   - Test format detection
   - Test error handling

2. **API Tests** (`server/vision/tests/test_api.py`)
   - Test upload with various formats
   - Test dex_compatible_url in response
   - Test image download endpoint

### Integration Tests

1. **Client-Server Flow**
   - Upload unsupported format → Verify warning shown
   - Upload large image → Verify resizing
   - Download dex-compatible → Verify caching

2. **Edge Cases**
   - Corrupted images
   - Extremely large images (>50MB)
   - Unusual formats (TIFF, RAW)
   - Network interruption during download

### Manual Testing Checklist

- [ ] Upload JPEG → Preview works → Dex image downloaded
- [ ] Upload PNG → Preview works → Dex image downloaded
- [ ] Upload MPO → Warning shown → Upload succeeds → Dex image downloaded
- [ ] Upload WebP → Preview works → Converted to PNG on server
- [ ] Upload 5000x5000 image → Resized to 2560x2560
- [ ] Upload <2560 image → No resize, only format conversion if needed
- [ ] Offline mode → Cached images still display
- [ ] Clear cache → Images re-downloaded on next view

## Performance Considerations

### Server Performance

1. **Async Processing**
   - Image conversion happens in Celery task
   - Doesn't block API response
   - Can be parallelized

2. **Caching Strategy**
   - Cache dex-compatible images in CDN
   - Set long cache headers (1 year)
   - Use ETags for validation

3. **Storage Optimization**
   - Consider WebP format in future (30-40% smaller)
   - Implement progressive JPEG for slow connections
   - Add thumbnail generation for list views

### Client Performance

1. **Local Caching**
   - Store dex images in `user://dex_cache/`
   - Implement cache size limits (e.g., 100MB)
   - LRU eviction policy

2. **Progressive Loading**
   - Show low-res preview first
   - Load full image in background
   - Lazy load images in lists

3. **Memory Management**
   - Free Image resources after use
   - Limit concurrent image loads
   - Use texture atlasing for small images

## Security & Privacy

### Access Control (TODO)

```python
# Future implementation in DexCompatibleImageView
def check_access(self, request, job):
    """Check if user can access this image."""
    # Owner always has access
    if job.user == request.user:
        return True

    # Check if image is in public dex entry
    public_entries = DexEntry.objects.filter(
        source_vision_job=job,
        visibility='public'
    )
    if public_entries.exists():
        return True

    # Check friend access
    if job.user in request.user.get_friends():
        friend_entries = DexEntry.objects.filter(
            source_vision_job=job,
            visibility='friends'
        )
        if friend_entries.exists():
            return True

    return False
```

### Privacy Considerations

1. **Metadata Stripping**
   - Remove EXIF GPS data
   - Remove camera identifying information
   - Preserve only essential metadata (dimensions, format)

2. **URL Security**
   - Use signed URLs for sensitive images
   - Implement rate limiting
   - Log access for audit trail

## Rollback Plan

If issues arise:

1. **Client Rollback**
   - Revert to PNG conversion on client
   - Disable dex image download
   - Use original upload for display

2. **Server Rollback**
   - Keep original image field
   - Serve original instead of dex-compatible
   - Disable image processor in Celery task

3. **Database Rollback**
   - Migration is reversible
   - Can null out dex_compatible_image field
   - Original images preserved

## Success Metrics

1. **Technical Metrics**
   - Image preview success rate: >95%
   - Conversion success rate: >99%
   - Average processing time: <2 seconds
   - Storage reduction: 20-30% (from resizing)

2. **User Experience Metrics**
   - Reduced "cannot display image" errors
   - Faster image loading (cached + optimized)
   - Consistent image quality across devices

3. **System Metrics**
   - Reduced bandwidth usage
   - Lower storage costs
   - Fewer support tickets about images

## Timeline

### Week 1: Server Implementation
- Day 1-2: Implement ImageProcessor service
- Day 3-4: Update models and migrations
- Day 5: Testing and bug fixes

### Week 2: Client Implementation
- Day 1-2: Update camera scene for new flow
- Day 3-4: Implement caching system
- Day 5: Integration testing

### Week 3: Deployment & Monitoring
- Day 1: Deploy to staging
- Day 2-3: Load testing and optimization
- Day 4: Production deployment
- Day 5: Monitor and address issues

## Future Enhancements

1. **Advanced Processing**
   - Auto-crop to focus on animal
   - Background blur for better focus
   - Color correction for poor lighting

2. **Format Optimization**
   - WebP support (30% smaller files)
   - AVIF for cutting-edge browsers
   - Responsive image sets

3. **Smart Caching**
   - Predictive pre-loading
   - Shared cache between app instances
   - Delta updates for modified images

4. **AI Enhancement**
   - Super-resolution for low-quality images
   - Automatic species highlighting
   - Multiple animal detection

## Conclusion

This overhaul addresses the core issue of format compatibility while establishing a robust foundation for future image features. The dual-storage approach (original + dex-compatible) provides flexibility while ensuring consistent user experience across all devices and image formats.