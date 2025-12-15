"""
Signal handlers for dex app.
"""
import logging
from django.db.models.signals import post_save, post_delete, pre_delete
from django.dispatch import receiver
from .models import DexEntry

logger = logging.getLogger(__name__)


# =============================================================================
# Image Cleanup on DexEntry Deletion
# =============================================================================

@receiver(pre_delete, sender=DexEntry)
def cleanup_dex_entry_images(sender, instance, **kwargs):
    """
    Delete image files when DexEntry is deleted.
    Only deletes if no other entries reference the same file.

    Handles:
    - original_image: Direct upload field on DexEntry
    - processed_image: Processed version field on DexEntry

    Note: Images stored in source_vision_job are NOT deleted here since they
    may be referenced by other entries or needed for audit purposes.
    """
    # Clean up original_image if it exists and isn't shared
    if instance.original_image:
        # Check if other entries use this exact image file path
        other_refs = DexEntry.objects.filter(
            original_image=instance.original_image.name
        ).exclude(id=instance.id).exists()

        if not other_refs:
            try:
                instance.original_image.delete(save=False)
                logger.info(
                    f"Deleted orphaned original_image for entry {instance.id}: "
                    f"{instance.original_image.name}"
                )
            except Exception as e:
                logger.warning(
                    f"Failed to delete original_image for entry {instance.id}: {e}"
                )

    # Clean up processed_image if it exists and isn't shared
    if instance.processed_image:
        other_refs = DexEntry.objects.filter(
            processed_image=instance.processed_image.name
        ).exclude(id=instance.id).exists()

        if not other_refs:
            try:
                instance.processed_image.delete(save=False)
                logger.info(
                    f"Deleted orphaned processed_image for entry {instance.id}: "
                    f"{instance.processed_image.name}"
                )
            except Exception as e:
                logger.warning(
                    f"Failed to delete processed_image for entry {instance.id}: {e}"
                )


@receiver(post_save, sender=DexEntry)
def update_profile_stats_on_save(sender, instance, created, **kwargs):
    """Update user profile stats when a new dex entry is created."""
    if created:
        instance.owner.profile.update_stats()


@receiver(post_delete, sender=DexEntry)
def update_profile_stats_on_delete(sender, instance, **kwargs):
    """Update user profile stats when a dex entry is deleted."""
    instance.owner.profile.update_stats()


# =============================================================================
# Taxonomic Tree Cache Invalidation Signals
# =============================================================================

@receiver(post_save, sender=DexEntry)
def invalidate_tree_on_dex_change(sender, instance, created, **kwargs):
    """
    Invalidate tree caches when dex entry changes.
    This ensures users see updated trees when animals are discovered.
    """
    # Import here to avoid circular dependency
    from graph.services_dynamic import DynamicTaxonomicTreeService

    # Only invalidate if entry was created (not just updated)
    if created:
        # Invalidate user's tree caches
        DynamicTaxonomicTreeService.invalidate_user_caches(instance.owner_id)

        # Also invalidate friends' caches since they include this user's data
        try:
            from social.models import Friendship
            friend_ids = Friendship.get_friend_ids(instance.owner)
            for friend_id in friend_ids:
                DynamicTaxonomicTreeService.invalidate_user_caches(friend_id)

            logger.info(
                f"Invalidated tree caches for user {instance.owner_id} "
                f"and {len(friend_ids)} friends after dex entry creation"
            )
        except Exception as e:
            logger.error(f"Error invalidating friend caches: {str(e)}", exc_info=True)

        # Invalidate global cache if it exists
        DynamicTaxonomicTreeService.invalidate_global_cache()


@receiver(post_delete, sender=DexEntry)
def invalidate_tree_on_dex_delete(sender, instance, **kwargs):
    """
    Invalidate tree caches when dex entry deleted.
    Ensures trees reflect current state after deletion.
    """
    # Import here to avoid circular dependency
    from graph.services_dynamic import DynamicTaxonomicTreeService

    # Invalidate user's tree caches
    DynamicTaxonomicTreeService.invalidate_user_caches(instance.owner_id)

    # Also invalidate friends' caches
    try:
        from social.models import Friendship
        friend_ids = Friendship.get_friend_ids(instance.owner)
        for friend_id in friend_ids:
            DynamicTaxonomicTreeService.invalidate_user_caches(friend_id)

        logger.info(
            f"Invalidated tree caches for user {instance.owner_id} "
            f"and {len(friend_ids)} friends after dex entry deletion"
        )
    except Exception as e:
        logger.error(f"Error invalidating friend caches: {str(e)}", exc_info=True)

    # Invalidate global cache
    DynamicTaxonomicTreeService.invalidate_global_cache()
