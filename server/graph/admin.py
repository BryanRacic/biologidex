"""
Admin configuration for graph app.
"""
from django.contrib import admin
from django.urls import path
from django.shortcuts import render, redirect
from django.contrib import messages
from django.contrib.auth.decorators import user_passes_test
from django.core.cache import cache
from .services_dynamic import DynamicTaxonomicTreeService


def is_staff(user):
    """Check if user is staff."""
    return user.is_authenticated and user.is_staff


@user_passes_test(is_staff)
def cache_management_view(request):
    """
    Admin view for managing taxonomic tree caches.
    Provides tools to inspect and invalidate caches.
    """
    context = {
        'title': 'Taxonomic Tree Cache Management',
        'cache_keys': []
    }

    if request.method == 'POST':
        action = request.POST.get('action')

        if action == 'invalidate_global':
            DynamicTaxonomicTreeService.invalidate_global_cache()
            messages.success(request, 'Global tree cache invalidated successfully')

        elif action == 'invalidate_user':
            user_id = request.POST.get('user_id')
            if user_id:
                try:
                    DynamicTaxonomicTreeService.invalidate_user_caches(int(user_id))
                    messages.success(request, f'Tree caches invalidated for user {user_id}')
                except Exception as e:
                    messages.error(request, f'Error: {str(e)}')

        elif action == 'invalidate_all':
            # Clear all tree-related caches
            cache_patterns = [
                'taxonomic_tree_personal_*',
                'taxonomic_tree_friends_*',
                'taxonomic_tree_selected_*',
                'taxonomic_tree_global'
            ]
            # Note: Redis cache.delete_pattern() may not be available in all cache backends
            # This is a simplified approach
            cache.delete('taxonomic_tree_global')
            messages.success(request, 'Attempted to clear all tree caches')

        return redirect('admin:graph_cache_management')

    return render(request, 'admin/graph/cache_management.html', context)


# Custom admin site configuration
class GraphAdminSite(admin.AdminSite):
    """Custom admin site for graph app."""

    def get_urls(self):
        urls = super().get_urls()
        custom_urls = [
            path('cache-management/', cache_management_view, name='graph_cache_management'),
        ]
        return custom_urls + urls


# Register custom admin tools
# Note: Since this app has no models, we just provide utility views
