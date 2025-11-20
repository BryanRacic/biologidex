"""
Celery tasks for images app.
"""
import logging
from celery import shared_task
from django.utils import timezone
from .models import ImageConversion

logger = logging.getLogger(__name__)


@shared_task
def cleanup_expired_conversions():
    """
    Delete expired image conversions.
    Runs periodically to clean up conversions older than their expiration time.
    """
    try:
        now = timezone.now()
        expired_conversions = ImageConversion.objects.filter(expires_at__lt=now)
        count = expired_conversions.count()

        if count == 0:
            logger.info("No expired image conversions to clean up")
            return {"deleted": 0}

        # Delete files and records
        for conversion in expired_conversions:
            try:
                conversion.delete_files()
                conversion.delete()
                logger.debug(f"Deleted expired conversion: {conversion.id}")
            except Exception as e:
                logger.error(
                    f"Failed to delete conversion {conversion.id}: {str(e)}",
                    exc_info=True
                )

        logger.info(f"Cleaned up {count} expired image conversions")
        return {"deleted": count}

    except Exception as e:
        logger.error(f"Failed to clean up expired conversions: {str(e)}", exc_info=True)
        return {"error": str(e)}


@shared_task
def cleanup_unused_conversions(hours=1):
    """
    Delete unused image conversions that were never used in a vision job.
    Runs periodically to clean up conversions that are older than specified hours
    but were never used.

    Args:
        hours: Number of hours after which unused conversions should be deleted
    """
    try:
        from datetime import timedelta
        cutoff_time = timezone.now() - timedelta(hours=hours)

        unused_conversions = ImageConversion.objects.filter(
            used_in_job=False,
            created_at__lt=cutoff_time
        )
        count = unused_conversions.count()

        if count == 0:
            logger.info("No unused image conversions to clean up")
            return {"deleted": 0}

        # Delete files and records
        for conversion in unused_conversions:
            try:
                conversion.delete_files()
                conversion.delete()
                logger.debug(f"Deleted unused conversion: {conversion.id}")
            except Exception as e:
                logger.error(
                    f"Failed to delete unused conversion {conversion.id}: {str(e)}",
                    exc_info=True
                )

        logger.info(f"Cleaned up {count} unused image conversions older than {hours}h")
        return {"deleted": count}

    except Exception as e:
        logger.error(f"Failed to clean up unused conversions: {str(e)}", exc_info=True)
        return {"error": str(e)}
