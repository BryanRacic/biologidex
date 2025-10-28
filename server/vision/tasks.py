"""
Celery tasks for vision app.
"""
import logging
import re
from celery import shared_task
from django.utils import timezone
from .models import AnalysisJob
from .services import CVServiceFactory
from animals.models import Animal

logger = logging.getLogger(__name__)


@shared_task(bind=True, max_retries=3)
def process_analysis_job(self, job_id: str):
    """
    Process an animal identification job asynchronously.

    Args:
        job_id: UUID of the AnalysisJob to process
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
        # Create CV service
        cv_service = CVServiceFactory.create(
            method=job.cv_method,
            model=job.model_name,
            detail=job.detail_level
        )

        # Perform identification
        result = cv_service.identify_animal(job.image.path)

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
    Parse CV prediction and create/retrieve Animal record.

    Expected format: "Genus, species (common name)" or "Genus species (common name)"

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
        pattern = r'([A-Z][a-z]+)[,\s]+([a-z]+(?:\s+[a-z]+)?)\s*(?:\(([^)]+)\))?'
        match = re.search(pattern, first_line)

        if not match:
            logger.warning(f"Could not parse prediction: {prediction}")
            return None

        genus = match.group(1)
        species_full = match.group(2).strip()  # May include subspecies
        common_name = match.group(3).strip() if match.group(3) else ""

        # Split species from subspecies if present
        species_parts = species_full.split()
        species = species_parts[0]
        scientific_name = f"{genus} {species_full}"

        logger.info(f"Parsed: {scientific_name} ({common_name})")

        # Try to find existing animal
        try:
            animal = Animal.objects.get(scientific_name__iexact=scientific_name)
            logger.info(f"Found existing animal: {animal}")
            return animal
        except Animal.DoesNotExist:
            # Create new animal
            animal = Animal.objects.create(
                scientific_name=scientific_name,
                common_name=common_name or f"Unknown {genus}",  # Fallback if no common name
                genus=genus,
                species=species,
                created_by=user,
                verified=False,  # Needs admin verification
            )
            logger.info(f"Created new animal: {animal}")
            return animal

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
