"""
User and Profile models for BiologiDex.
"""
import uuid
import secrets
import string
from django.contrib.auth.models import AbstractUser
from django.db import models
from django.utils.translation import gettext_lazy as _


def generate_friend_code():
    """Generate a unique 8-character friend code."""
    characters = string.ascii_uppercase + string.digits
    return ''.join(secrets.choice(characters) for _ in range(8))


class User(AbstractUser):
    """
    Custom User model extending Django's AbstractUser.
    Adds friend code, bio, and badge support.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(_('email address'), unique=True)
    friend_code = models.CharField(
        max_length=8,
        unique=True,
        default=generate_friend_code,
        help_text=_('Unique code for adding friends')
    )
    bio = models.TextField(max_length=500, blank=True, help_text=_('User biography'))
    avatar = models.ImageField(
        upload_to='avatars/',
        null=True,
        blank=True,
        help_text=_('User profile picture')
    )
    badges = models.JSONField(
        default=list,
        blank=True,
        help_text=_('User achievements and badges')
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    # Make email required
    REQUIRED_FIELDS = ['email']

    class Meta:
        db_table = 'users'
        verbose_name = _('User')
        verbose_name_plural = _('Users')
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['friend_code']),
            models.Index(fields=['email']),
            models.Index(fields=['created_at']),
        ]

    def __str__(self):
        return self.username

    def save(self, *args, **kwargs):
        """Ensure friend_code is unique on save."""
        if not self.friend_code:
            self.friend_code = generate_friend_code()
        # Ensure uniqueness
        while User.objects.filter(friend_code=self.friend_code).exclude(id=self.id).exists():
            self.friend_code = generate_friend_code()
        super().save(*args, **kwargs)


class UserProfile(models.Model):
    """
    Extended profile information for users.
    Auto-created via signals when User is created.
    """
    user = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name='profile',
        primary_key=True
    )
    total_catches = models.PositiveIntegerField(
        default=0,
        help_text=_('Total number of animals captured')
    )
    unique_species = models.PositiveIntegerField(
        default=0,
        help_text=_('Number of unique species in collection')
    )
    preferred_card_style = models.JSONField(
        default=dict,
        blank=True,
        help_text=_('User preferences for card styling')
    )
    join_date = models.DateField(auto_now_add=True)
    last_catch_date = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'user_profiles'
        verbose_name = _('User Profile')
        verbose_name_plural = _('User Profiles')

    def __str__(self):
        return f"{self.user.username}'s Profile"

    def update_stats(self):
        """Update catch statistics from DexEntry records."""
        from dex.models import DexEntry

        entries = DexEntry.objects.filter(owner=self.user)
        self.total_catches = entries.count()
        self.unique_species = entries.values('animal').distinct().count()

        latest_entry = entries.order_by('-catch_date').first()
        if latest_entry:
            self.last_catch_date = latest_entry.catch_date

        self.save(update_fields=['total_catches', 'unique_species', 'last_catch_date'])
