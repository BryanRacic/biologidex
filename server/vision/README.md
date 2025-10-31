# Vision App - Image Processing & Animal Identification

## Overview
Handles CV-based animal identification with standardized image processing pipeline.

## Image Processing Pipeline

### Architecture
```
Upload (any format) → AnalysisJob created → Celery task
  ↓
ImageProcessor (converts to PNG, resizes to ≤2560px)
  ↓
OpenAI Vision API (analyzes dex_compatible_image)
  ↓
Parse response → Create/lookup Animal → Complete job
```

### Key Files
- **models.py**: AnalysisJob with `image`, `dex_compatible_image`, `image_conversion_status`
- **image_processor.py**: ImageProcessor class for format conversion & resizing
- **tasks.py**: Celery task `process_analysis_job` with image processing
- **services.py**: OpenAIVisionService for CV analysis
- **serializers.py**: Returns `dex_compatible_url` in API responses
- **views.py**: DexCompatibleImageView serves processed images

### ImageProcessor Details
**Location**: `vision/image_processor.py`

**Process**:
1. Opens image with Pillow
2. Checks if processing needed (format != PNG or size > 2560px)
3. Converts transparency (RGBA/LA/P → RGB with white background)
4. Resizes if > 2560px (maintains aspect ratio, LANCZOS resampling)
5. Saves as optimized PNG

**Returns**: `(ContentFile, metadata_dict)` or `(None, metadata)` if already compatible

**Status Values**:
- `completed`: Successfully converted
- `unnecessary`: Original already PNG ≤2560px
- `failed`: Error during processing
- `pending`: Not yet processed
- `processing`: Currently converting

### API Endpoints

**POST /api/v1/vision/jobs/**
- Upload image (any format)
- Creates AnalysisJob, triggers async processing
- Response includes `dex_compatible_url` when ready

**GET /api/v1/vision/jobs/{job_id}/**
- Check job status
- Returns `dex_compatible_url` and `image_conversion_status`

**GET /api/v1/vision/jobs/{job_id}/dex-image/**
- Serves dex-compatible image directly
- Cache-Control: 1 year
- TODO: Add IAM permission checks

### Storage Structure
```
media/vision/analysis/
├── original/        # User uploads (any format)
│   └── 2025/10/
└── dex_compatible/  # Standardized PNGs
    └── 2025/10/
```

## Development Notes

### Testing Image Processing
```python
from vision.image_processor import ImageProcessor
from vision.models import AnalysisJob

job = AnalysisJob.objects.first()
processed, metadata = ImageProcessor.process_image(job.image)
print(metadata)  # Shows conversion details
```

### Common Issues
- **Missing dex_compatible_url**: Check `image_conversion_status` field
- **Celery not processing**: Verify celery_worker is running
- **Large images slow**: Processing >10MB images can take 2-3 seconds

### Dependencies
- **Pillow**: Image processing (installed via poetry)
- **Celery**: Async task processing
- **Redis**: Celery broker
