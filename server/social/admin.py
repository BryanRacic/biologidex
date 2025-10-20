"""
Admin configuration for social app.
"""
from django.contrib import admin
from .models import Friendship


@admin.register(Friendship)
class FriendshipAdmin(admin.ModelAdmin):
    """Admin interface for Friendship model."""
    list_display = ['from_user', 'to_user', 'status', 'created_at', 'updated_at']
    list_filter = ['status', 'created_at']
    search_fields = ['from_user__username', 'to_user__username']
    readonly_fields = ['id', 'created_at', 'updated_at']
    ordering = ['-created_at']
    date_hierarchy = 'created_at'

    fieldsets = (
        ('Friendship', {
            'fields': ('id', 'from_user', 'to_user', 'status')
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )

    def get_queryset(self, request):
        """Optimize queryset with select_related."""
        return super().get_queryset(request).select_related('from_user', 'to_user')

    actions = ['accept_requests', 'reject_requests']

    def accept_requests(self, request, queryset):
        """Bulk accept friend requests."""
        pending = queryset.filter(status='pending')
        count = 0
        for friendship in pending:
            try:
                friendship.accept()
                count += 1
            except ValueError:
                pass
        self.message_user(request, f'{count} friend requests accepted.')

    accept_requests.short_description = 'Accept selected friend requests'

    def reject_requests(self, request, queryset):
        """Bulk reject friend requests."""
        pending = queryset.filter(status='pending')
        count = 0
        for friendship in pending:
            try:
                friendship.reject()
                count += 1
            except ValueError:
                pass
        self.message_user(request, f'{count} friend requests rejected.')

    reject_requests.short_description = 'Reject selected friend requests'
