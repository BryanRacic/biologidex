"""
Admin configuration for accounts app.
"""
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import User, UserProfile


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    """Admin interface for User model."""
    list_display = ['username', 'email', 'friend_code', 'is_staff', 'created_at']
    list_filter = ['is_staff', 'is_superuser', 'is_active', 'created_at']
    search_fields = ['username', 'email', 'friend_code']
    ordering = ['-created_at']

    fieldsets = BaseUserAdmin.fieldsets + (
        ('BiologiDex Info', {
            'fields': ('friend_code', 'bio', 'avatar', 'badges')
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )
    readonly_fields = ['created_at', 'updated_at', 'friend_code']


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    """Admin interface for UserProfile model."""
    list_display = ['user', 'total_catches', 'unique_species', 'join_date']
    search_fields = ['user__username', 'user__email']
    readonly_fields = ['join_date', 'total_catches', 'unique_species', 'last_catch_date']
    ordering = ['-join_date']

    fieldsets = (
        ('User', {
            'fields': ('user',)
        }),
        ('Statistics', {
            'fields': ('total_catches', 'unique_species', 'last_catch_date')
        }),
        ('Preferences', {
            'fields': ('preferred_card_style',)
        }),
        ('Metadata', {
            'fields': ('join_date',),
            'classes': ('collapse',)
        }),
    )
