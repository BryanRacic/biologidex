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

        # Parse the prediction to extract ALL detected animals
        detected_animals_data = parse_and_create_animals(
            result['prediction'],
            user=job.user
        )

        # Prepare detected_animals for storage (remove Animal instances, keep IDs)
        detected_animals_json = []
        for animal_data in detected_animals_data:
            detected_animals_json.append({
                "scientific_name": animal_data["scientific_name"],
                "common_name": animal_data["common_name"],
                "confidence": animal_data["confidence"],
                "animal_id": animal_data["animal_id"],
                "is_new": animal_data["is_new"]
            })

        # For backward compatibility, set identified_animal to first detection
        first_animal = detected_animals_data[0]["animal"] if detected_animals_data else None

        # Mark job as completed
        job.mark_completed(
            parsed_prediction=result['prediction'],
            identified_animal=first_animal,  # Legacy field
            detected_animals=detected_animals_json,  # New field
            cost_usd=result['cost_usd'],
            processing_time=result['processing_time'],
            raw_response=result['raw_response'],
            input_tokens=result.get('input_tokens'),
            output_tokens=result.get('output_tokens'),
        )

        logger.info(
            f"AnalysisJob {job_id} completed successfully. "
            f"Detected {len(detected_animals_data)} animals. "
            f"First: {first_animal.scientific_name if first_animal else 'None'}"
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


def parse_and_create_animals(prediction: str, user) -> list:
    """
    Parse CV prediction and create/retrieve ALL detected Animal records.

    This replaces the single-animal parse_and_create_animal function.
    Supports multiple animals separated by '|' delimiter.

    Expected format: "Genus species [subspecies] (common name) [| Genus2 species2 ...]"

    Args:
        prediction: Prediction string from CV service (can contain multiple animals)
        user: User who submitted the image (for created_by field)

    Returns:
        List of dicts containing animal data:
        [
            {
                "animal": Animal instance or None,
                "scientific_name": str,
                "common_name": str,
                "confidence": float (0.0 for now),
                "is_new": bool,
                "message": str (debug info)
            },
            ...
        ]
        Returns empty list if no animals found.
    """
    if not prediction or prediction.strip().upper() == "NO ANIMALS FOUND":
        logger.info("No animals found in image")
        return []

    # Split by pipe delimiter for multiple animals
    animal_entries = [entry.strip() for entry in prediction.split('|') if entry.strip()]

    if not animal_entries:
        logger.info("No valid animal entries after splitting")
        return []

    results = []

    for idx, entry in enumerate(animal_entries):
        try:
            # Remove markdown formatting (asterisks, underscores)
            entry = re.sub(r'[*_]', '', entry)

            # Extract scientific name and common name
            # Pattern: Genus species [subspecies] (optional common name)
            pattern = r'([A-Z][a-z]+)[,\s]+([a-z]+)(?:\s+([a-z]+))?\s*(?:\(([^)]+)\))?'
            match = re.search(pattern, entry)

            if not match:
                logger.warning(f"Could not parse animal entry {idx + 1}: {entry}")
                continue

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
                f"[CV PARSING] Animal {idx + 1}/{len(animal_entries)}:\n"
                f"  Original: {entry}\n"
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
                confidence=0.0  # CV confidence will be set separately
            )

            if animal:
                # Set created_by if this is a newly created animal
                if created and user:
                    animal.created_by = user
                    animal.save(update_fields=['created_by'])

                results.append({
                    "animal": animal,
                    "animal_id": str(animal.id),
                    "scientific_name": scientific_name,
                    "common_name": common_name,
                    "confidence": 0.9 - (idx * 0.1),  # Decreasing confidence for multiple detections
                    "is_new": created,
                    "message": message
                })

                logger.info(f"{'Created' if created else 'Found'} animal: {animal} - {message}")
            else:
                logger.warning(f"Failed to create animal: {message}")
                # Still add to results even if animal creation failed
                results.append({
                    "animal": None,
                    "animal_id": None,
                    "scientific_name": scientific_name,
                    "common_name": common_name,
                    "confidence": 0.9 - (idx * 0.1),
                    "is_new": False,
                    "message": f"Failed: {message}"
                })

        except Exception as e:
            logger.error(f"Error parsing animal entry {idx + 1}: {e}", exc_info=True)
            continue

    logger.info(f"Parsed {len(results)} animals from prediction")
    return results


# Legacy function for backward compatibility - calls new function and returns first
def parse_and_create_animal(prediction: str, user) -> Animal:
    """
    DEPRECATED: Legacy single-animal parser.
    Use parse_and_create_animals() for new code.

    Returns first animal from multiple detections for backward compatibility.
    """
    animals = parse_and_create_animals(prediction, user)
    if animals and len(animals) > 0:
        return animals[0].get("animal")
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
