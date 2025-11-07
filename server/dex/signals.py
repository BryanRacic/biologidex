"""
Signal handlers for dex app.
"""
import logging
from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver
from .models import DexEntry

logger = logging.getLogger(__name__)


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
