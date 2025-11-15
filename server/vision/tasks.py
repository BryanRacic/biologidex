"""
Celery tasks for vision app.
"""
import logging
import re
from celery import shared_task
from django.utils import timezone
from .models import AnalysisJob
from .services import CVServiceFactory
from .image_processor import ImageProcessor
from animals.models import Animal

logger = logging.getLogger(__name__)


@shared_task(bind=True, max_retries=3)
def process_analysis_job(self, job_id: str, transformations: dict = None):
    """
    Process an animal identification job asynchronously.

    Args:
        job_id: UUID of the AnalysisJob to process
        transformations: Optional dict of image transformations to apply
            (e.g., {"rotation": 90, "crop": {...}})
    """
    try:
        job = AnalysisJob.objects.get(id=job_id)
    except AnalysisJob.DoesNotExist:
        logger.error(f"AnalysisJob {job_id} not found")
        return

    # Mark as processing
    job.mark_processing()
    logger.info(f"Processing AnalysisJob {job_id} with {job.cv_method}")

    try:
        # Process image to create dex-compatible version
        if not job.dex_compatible_image and job.image:
            logger.info(f"Processing image for job {job_id} with transformations: {transformations}")

            # Use EnhancedImageProcessor if transformations provided, otherwise use basic ImageProcessor
            if transformations:
                from images.processor import EnhancedImageProcessor
                processed_file, metadata = EnhancedImageProcessor.process_image_with_transformations(
                    job.image,
                    transformations=transformations,
                    apply_exif_rotation=True
                )
            else:
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
                # Original already meets criteria (only possible with no transformations)
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

        # Log complete CV response for debugging
        logger.info(
            f"[CV RESPONSE] Job {job_id} completed:\n"
            f"  Model: {job.model_name}\n"
            f"  Prediction: {result['prediction']}\n"
            f"  Cost: ${result['cost_usd']:.6f}\n"
            f"  Processing time: {result['processing_time']:.2f}s\n"
            f"  Input tokens: {result.get('input_tokens', 0)}\n"
            f"  Output tokens: {result.get('output_tokens', 0)}"
        )

        # Log raw response structure (first 500 chars to avoid spam)
        raw_response_str = str(result.get('raw_response', {}))
        if len(raw_response_str) > 500:
            raw_response_str = raw_response_str[:500] + "... (truncated)"
        logger.debug(f"[CV RESPONSE] Raw response structure: {raw_response_str}")

        # Parse the prediction to extract animal information
        animal = parse_and_create_animal(
            result['prediction'],
            user=job.user
        )

        # Mark job as completed
        job.mark_completed(
            parsed_prediction=result['prediction'],
            identified_animal=animal,
            cost_usd=result['cost_usd'],
            processing_time=result['processing_time'],
            raw_response=result['raw_response'],
            input_tokens=result.get('input_tokens'),
            output_tokens=result.get('output_tokens'),
        )

        logger.info(
            f"AnalysisJob {job_id} completed successfully. "
            f"Animal: {animal.scientific_name if animal else 'None'}"
        )

    except Exception as e:
        logger.error(f"AnalysisJob {job_id} failed: {e}", exc_info=True)

        # Increment retry count
        job.increment_retry()

        # Retry with exponential backoff
        if job.retry_count < 3:
            raise self.retry(exc=e, countdown=60 * (2 ** job.retry_count))
        else:
            # Max retries reached, mark as failed
            job.mark_failed(str(e))


def parse_and_create_animal(prediction: str, user) -> Animal:
    """
    Parse CV prediction and create/retrieve Animal record using taxonomy system.

    Expected format: "Genus species [subspecies] (common name)"

    Args:
        prediction: Prediction string from CV service
        user: User who submitted the image (for created_by field)

    Returns:
        Animal instance if successfully parsed and created/found, None otherwise
    """
    if not prediction or prediction.strip().upper() == "NO ANIMALS FOUND":
        logger.info("No animals found in image")
        return None

    try:
        # Parse the prediction
        # Expected formats:
        # - "*Genus species* (common name)" - with markdown italics
        # - "Genus species (common name)"
        # - "Genus, species (common name)"
        # - "Genus species subspecies (common name)" - with subspecies
        # - Multiple animals separated by newlines or commas

        # Take first animal if multiple
        first_line = prediction.split('\n')[0].strip()

        # Remove markdown formatting (asterisks, underscores)
        first_line = re.sub(r'[*_]', '', first_line)

        # Extract scientific name and common name
        # Pattern: Genus species [subspecies] (optional common name)
        # Improved pattern to capture genus, species, subspecies separately
        pattern = r'([A-Z][a-z]+)[,\s]+([a-z]+)(?:\s+([a-z]+))?\s*(?:\(([^)]+)\))?'
        match = re.search(pattern, first_line)

        if not match:
            logger.warning(f"Could not parse prediction: {prediction}")
            return None

        genus = match.group(1)
        species = match.group(2)
        subspecies = match.group(3) if match.group(3) else None
        common_name = match.group(4).strip() if match.group(4) else ""

        # Build scientific name
        if subspecies:
            scientific_name = f"{genus} {species} {subspecies}"
        else:
            scientific_name = f"{genus} {species}"

        logger.info(
            f"[CV PARSING] Successfully parsed prediction:\n"
            f"  Original: {first_line}\n"
            f"  Genus: {genus}\n"
            f"  Species: {species}\n"
            f"  Subspecies: {subspecies}\n"
            f"  Common name: {common_name}\n"
            f"  Scientific name: {scientific_name}"
        )

        # Use taxonomy-aware animal service for lookup/creation
        from animals.services import AnimalService

        animal, created, message = AnimalService.lookup_or_create_from_cv(
            genus=genus,
            species=species,
            subspecies=subspecies,
            common_name=common_name,
            confidence=0.0  # CV confidence will be set separately in AnalysisJob
        )

        if animal:
            # Set created_by if this is a newly created animal
            if created and user:
                animal.created_by = user
                animal.save(update_fields=['created_by'])

            logger.info(f"{'Created' if created else 'Found'} animal: {animal} - {message}")
            return animal
        else:
            logger.warning(f"Failed to create animal: {message}")
            return None

    except Exception as e:
        logger.error(f"Error parsing prediction: {e}", exc_info=True)
        return None


@shared_task
def cleanup_old_analysis_jobs(days: int = 30):
    """
    Clean up old completed/failed analysis jobs.

    Args:
        days: Delete jobs older than this many days
    """
    from datetime import timedelta
    cutoff_date = timezone.now() - timedelta(days=days)

    deleted_count = AnalysisJob.objects.filter(
        completed_at__lt=cutoff_date,
        status__in=['completed', 'failed']
    ).delete()[0]

    logger.info(f"Cleaned up {deleted_count} old analysis jobs")
    return deleted_count
