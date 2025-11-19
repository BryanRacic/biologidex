"""
Social models for BiologiDex.
"""
import uuid
from django.db import models
from django.conf import settings
from django.utils.translation import gettext_lazy as _


class Friendship(models.Model):
    """
    Bidirectional friendship model.
    When accepted, creates mutual friendship relationship.
    """
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('accepted', 'Accepted'),
        ('rejected', 'Rejected'),
        ('blocked', 'Blocked'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    # The user who sent the friend request
    from_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='sent_friend_requests',
        help_text=_('User who sent the friend request')
    )

    # The user who received the friend request
    to_user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='received_friend_requests',
        help_text=_('User who received the friend request')
    )

    status = models.CharField(
        max_length=10,
        choices=STATUS_CHOICES,
        default='pending',
        help_text=_('Current status of the friendship')
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'friendships'
        verbose_name = _('Friendship')
        verbose_name_plural = _('Friendships')
        unique_together = [['from_user', 'to_user']]
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['from_user', 'status']),
            models.Index(fields=['to_user', 'status']),
            models.Index(fields=['status', 'created_at']),
        ]

    def __str__(self):
        return f"{self.from_user.username} → {self.to_user.username} ({self.status})"

    def save(self, *args, **kwargs):
        """Prevent self-friendship."""
        if self.from_user == self.to_user:
            raise ValueError("Users cannot be friends with themselves")
        super().save(*args, **kwargs)

    @classmethod
    def are_friends(cls, user1, user2):
        """Check if two users are friends (bidirectional check)."""
        return cls.objects.filter(
            models.Q(from_user=user1, to_user=user2, status='accepted') |
            models.Q(from_user=user2, to_user=user1, status='accepted')
        ).exists()

    @classmethod
    def get_friends(cls, user):
        """Get all friends of a user, excluding admin users."""
        from django.contrib.auth import get_user_model
        User = get_user_model()

        # Get IDs of friends
        friend_ids = cls.get_friend_ids(user)

        # Return User queryset, excluding superusers (admin)
        return User.objects.filter(id__in=friend_ids, is_superuser=False)

    @classmethod
    def get_friend_ids(cls, user):
        """Get list of friend user IDs, excluding admin users."""
        from django.contrib.auth import get_user_model
        User = get_user_model()

        # Friends where user sent request
        sent_friend_ids = list(
            cls.objects.filter(
                from_user=user,
                status='accepted'
            ).exclude(
                to_user__is_superuser=True
            ).values_list('to_user_id', flat=True)
        )

        # Friends where user received request
        received_friend_ids = list(
            cls.objects.filter(
                to_user=user,
                status='accepted'
            ).exclude(
                from_user__is_superuser=True
            ).values_list('from_user_id', flat=True)
        )

        return sent_friend_ids + received_friend_ids

    @classmethod
    def get_pending_requests(cls, user):
        """Get pending friend requests for a user (requests they received), excluding admin."""
        return cls.objects.filter(
            to_user=user,
            status='pending'
        ).exclude(
            from_user__is_superuser=True
        ).select_related('from_user')

    @classmethod
    def create_request(cls, from_user, to_user):
        """
        Create a friend request.
        Checks for existing relationships first.
        """
        # Check if already friends or request exists
        existing = cls.objects.filter(
            models.Q(from_user=from_user, to_user=to_user) |
            models.Q(from_user=to_user, to_user=from_user)
        ).first()

        if existing:
            if existing.status == 'accepted':
                raise ValueError("Users are already friends")
            elif existing.status == 'pending':
                raise ValueError("Friend request already pending")
            elif existing.status == 'blocked':
                raise ValueError("Cannot send friend request")

        # Create new request
        return cls.objects.create(
            from_user=from_user,
            to_user=to_user,
            status='pending'
        )

    def accept(self):
        """Accept a friend request."""
        if self.status != 'pending':
            raise ValueError("Only pending requests can be accepted")
        self.status = 'accepted'
        self.save(update_fields=['status', 'updated_at'])

    def reject(self):
        """Reject a friend request."""
        if self.status != 'pending':
            raise ValueError("Only pending requests can be rejected")
        self.status = 'rejected'
        self.save(update_fields=['status', 'updated_at'])

    def block(self):
        """Block a user (from any state)."""
        self.status = 'blocked'
        self.save(update_fields=['status', 'updated_at'])

    def unfriend(self):
        """Remove friendship (delete the record)."""
        self.delete()
