"""
Signal handlers for accounts app.
"""
from django.db.models.signals import post_save
from django.dispatch import receiver
from .models import User, UserProfile
import logging

logger = logging.getLogger(__name__)


@receiver(post_save, sender=User)
def create_user_profile(sender, instance, created, **kwargs):
    """Create a UserProfile when a new User is created."""
    if created:
        UserProfile.objects.create(user=instance)


@receiver(post_save, sender=User)
def save_user_profile(sender, instance, **kwargs):
    """Save the UserProfile when User is saved."""
    if hasattr(instance, 'profile'):
        instance.profile.save()


@receiver(post_save, sender=User)
def create_admin_friendship(sender, instance, created, **kwargs):
    """
    Automatically create a friendship with the admin user when a new user is created.
    This allows admin to view all user data while remaining hidden from users.
    """
    if created and not instance.is_superuser:
        # Import here to avoid circular import
        from social.models import Friendship

        try:
            # Get the admin user (first superuser)
            admin_user = User.objects.filter(is_superuser=True).first()

            if admin_user and admin_user != instance:
                # Create an accepted friendship from admin to new user
                # Using from_user=admin ensures consistent filtering later
                Friendship.objects.create(
                    from_user=admin_user,
                    to_user=instance,
                    status='accepted'
                )
                logger.info(f"Created auto-friendship between admin and {instance.username}")
        except Exception as e:
            # Don't fail user creation if friendship creation fails
            logger.error(f"Failed to create admin friendship for {instance.username}: {e}")
