"""
Signal handlers for dex app.
"""
from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver
from .models import DexEntry


@receiver(post_save, sender=DexEntry)
def update_profile_stats_on_save(sender, instance, created, **kwargs):
    """Update user profile stats when a new dex entry is created."""
    if created:
        instance.owner.profile.update_stats()


@receiver(post_delete, sender=DexEntry)
def update_profile_stats_on_delete(sender, instance, **kwargs):
    """Update user profile stats when a dex entry is deleted."""
    instance.owner.profile.update_stats()
