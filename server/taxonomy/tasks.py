# taxonomy/tasks.py
from celery import shared_task
from django.core.cache import cache
from django.utils import timezone
from datetime import timedelta
import logging

logger = logging.getLogger(__name__)


@shared_task(bind=True, max_retries=3)
def run_import_job(self, import_job_id):
    """Run taxonomy import job asynchronously"""
    from .models import ImportJob
    from .importers.col_importer import CatalogueOfLifeImporter

    try:
        import_job = ImportJob.objects.get(id=import_job_id)
        logger.info(f"Starting import job {import_job_id} for {import_job.source.short_code}")

        importer = CatalogueOfLifeImporter(import_job)
        importer.run()

        # Clear taxonomy caches
        cache.delete_pattern('taxonomy:*')

        logger.info(f"Import job {import_job_id} completed successfully")

        return {
            'status': 'completed',
            'imported': import_job.records_imported,
            'failed': import_job.records_failed
        }

    except ImportJob.DoesNotExist:
        logger.error(f"Import job {import_job_id} not found")
        raise

    except Exception as e:
        logger.error(f"Import job {import_job_id} failed: {e}", exc_info=True)
        # Retry with exponential backoff (300s, 900s, 2700s)
        self.retry(countdown=300 * (2 ** self.request.retries))


@shared_task
def sync_taxonomy_to_animals():
    """Sync verified taxonomy to animals table"""
    from .models import Taxonomy
    from animals.services import AnimalService

    logger.info("Starting taxonomy to animals sync")

    # Process recently added taxonomy (last 24 hours)
    recent_taxa = Taxonomy.objects.filter(
        status='accepted',
        created_at__gte=timezone.now() - timedelta(hours=24)
    ).select_related('source')

    synced = 0
    errors = 0

    for taxon in recent_taxa:
        try:
            animal, created = AnimalService.create_or_update_from_taxonomy(taxon)
            if created:
                synced += 1
        except Exception as e:
            logger.error(f"Failed to sync taxon {taxon.id}: {e}")
            errors += 1

    logger.info(f"Taxonomy sync completed: {synced} synced, {errors} errors")
    return {'synced': synced, 'errors': errors}


@shared_task
def cleanup_old_imports():
    """Clean up old import jobs and raw data"""
    from .models import ImportJob
    from .raw_models import RawCatalogueOfLife

    logger.info("Starting cleanup of old import data")

    # Delete processed raw records older than 30 days
    old_date = timezone.now() - timedelta(days=30)

    raw_deleted = RawCatalogueOfLife.objects.filter(
        is_processed=True,
        created_at__lt=old_date
    ).delete()

    logger.info(f"Deleted {raw_deleted[0]} old raw records")

    # Archive old import jobs (keep metadata but mark as archived)
    archived = ImportJob.objects.filter(
        status='completed',
        created_at__lt=old_date
    ).update(
        metadata=models.F('metadata') | {'archived': True}
    )

    logger.info(f"Archived {archived} old import jobs")

    return {
        'raw_records_deleted': raw_deleted[0],
        'jobs_archived': archived
    }


@shared_task
def update_taxonomy_completeness_scores():
    """Recalculate completeness scores for all taxonomy records"""
    from .models import Taxonomy

    logger.info("Updating taxonomy completeness scores")

    updated = 0
    batch_size = 1000

    taxa = Taxonomy.objects.all()
    total = taxa.count()

    for i in range(0, total, batch_size):
        batch = taxa[i:i + batch_size]

        for taxon in batch:
            try:
                completeness = taxon.calculate_completeness()
                if taxon.completeness_score != completeness:
                    taxon.completeness_score = completeness
                    taxon.save(update_fields=['completeness_score'])
                    updated += 1
            except Exception as e:
                logger.error(f"Failed to update completeness for {taxon.id}: {e}")

        if (i + batch_size) % 10000 == 0:
            logger.info(f"Processed {i + batch_size}/{total} taxa")

    logger.info(f"Completeness update completed: {updated} updated")
    return {'updated': updated, 'total': total}


@shared_task
def cache_taxonomy_stats():
    """Pre-cache taxonomy statistics"""
    from .services import TaxonomyService

    logger.info("Caching taxonomy statistics")

    stats = TaxonomyService.get_hierarchy_stats()

    logger.info(f"Cached stats: {stats}")
    return stats
