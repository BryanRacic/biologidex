"""
Client version management for BiologiDex
Handles version checking and compatibility validation
"""
import json
import os
from pathlib import Path
from typing import Dict, Any, Optional

from django.http import JsonResponse
from django.views.decorators.http import require_http_methods
from django.views.decorators.cache import cache_page
from django.views.decorators.csrf import csrf_exempt
from django.conf import settings

# Version check configuration
VERSION_CHECK_ENABLED = getattr(settings, 'VERSION_CHECK_ENABLED', True)
VERSION_FILE_PATH = getattr(settings, 'CLIENT_VERSION_FILE',
                           Path(settings.BASE_DIR).parent / 'client_version.json')


def load_version_info() -> Dict[str, Any]:
    """
    Load version information from the version file.

    Returns:
        Dict containing version information or defaults if file not found
    """
    default_info = {
        'client_version': 'unknown',
        'build_timestamp': None,
        'build_number': 0,
        'git_commit': 'unknown',
        'git_commit_full': 'unknown',
        'git_message': 'Version information not available',
        'git_branch': 'unknown',
        'godot_version': 'unknown',
        'minimum_api_version': '1.0.0',
        'features': {
            'multi_animal_detection': True,
            'two_step_upload': True,
            'taxonomic_tree': True,
            'dex_sync_v2': True
        }
    }

    try:
        if VERSION_FILE_PATH.exists():
            with open(VERSION_FILE_PATH, 'r') as f:
                stored_version = json.load(f)
                # Merge with defaults to ensure all keys exist
                default_info.update(stored_version)
                # Use git_commit as the primary version identifier
                default_info['client_version'] = stored_version.get('git_commit', 'unknown')
    except (IOError, json.JSONDecodeError) as e:
        # Log error but don't crash
        if settings.DEBUG:
            print(f"[Version] Error loading version file: {e}")

    return default_info


def check_version_compatibility(client_version: str, expected_version: str) -> Dict[str, Any]:
    """
    Check if client version is compatible with server expectations.

    Args:
        client_version: Version reported by client
        expected_version: Expected version from server

    Returns:
        Dict with compatibility information
    """
    # Handle special cases
    if client_version == 'unknown' or expected_version == 'unknown':
        return {
            'compatible': True,  # Allow unknown versions to proceed
            'update_required': False,
            'update_recommended': True,
            'reason': 'Version information unavailable'
        }

    # Check for exact match (ideal case)
    if client_version == expected_version:
        return {
            'compatible': True,
            'update_required': False,
            'update_recommended': False,
            'reason': 'Version match'
        }

    # For now, any mismatch requires update
    # In future, could implement semantic versioning or compatibility matrix
    return {
        'compatible': False,
        'update_required': True,
        'update_recommended': True,
        'reason': 'Version mismatch'
    }


@csrf_exempt
@cache_page(60)  # Cache for 1 minute
@require_http_methods(["GET", "HEAD"])
def client_version_check(request) -> JsonResponse:
    """
    Returns expected client version information.
    Used by clients to detect when updates are required.

    Headers:
        X-Client-Version: Current client version (optional)

    Returns:
        JSON response with version information and update requirements
    """
    # Check if version checking is enabled
    if not VERSION_CHECK_ENABLED:
        return JsonResponse({
            'version_check_enabled': False,
            'update_required': False,
            'message': 'Version checking is currently disabled'
        })

    # Load current version information
    version_info = load_version_info()

    # Get client's reported version from headers
    client_version = request.headers.get('X-Client-Version', 'unknown')
    client_build = request.headers.get('X-Client-Build', '0')

    # Check compatibility
    compatibility = check_version_compatibility(
        client_version,
        version_info['client_version']
    )

    # Build response
    response_data = {
        'version_check_enabled': True,
        'client_version': client_version,
        'expected_version': version_info['client_version'],
        'git_commit': version_info['git_commit'],
        'git_message': version_info['git_message'],
        'build_timestamp': version_info['build_timestamp'],
        'build_number': version_info['build_number'],
        'features': version_info['features'],
        'minimum_api_version': version_info['minimum_api_version'],
        'update_required': compatibility['update_required'],
        'update_recommended': compatibility['update_recommended'],
        'compatibility_reason': compatibility['reason']
    }

    # Add update message if needed
    if compatibility['update_required']:
        response_data['update_message'] = (
            f"Your client is out of date and may not work as expected! "
            f"Please clear your cache and reload the application. "
            f"Current version: {client_version}, "
            f"Expected version: {version_info['client_version']}"
        )
    elif compatibility['update_recommended']:
        response_data['update_message'] = (
            f"A new version is available. "
            f"Please consider updating for the best experience. "
            f"Current version: {client_version}, "
            f"Latest version: {version_info['client_version']}"
        )

    return JsonResponse(response_data)


@csrf_exempt
@require_http_methods(["GET"])
def version_metrics(request) -> JsonResponse:
    """
    Returns metrics about client version distribution.
    Requires authentication and admin privileges.
    """
    # Check if user is authenticated and is staff
    if not request.user.is_authenticated or not request.user.is_staff:
        return JsonResponse({'error': 'Unauthorized'}, status=403)

    # This would typically query a metrics database
    # For now, return placeholder data
    metrics = {
        'total_users': 0,
        'version_distribution': {},
        'update_success_rate': 0.0,
        'average_update_time_hours': 0.0,
        'collection_timestamp': None
    }

    # In production, you would collect these metrics from:
    # - Server logs
    # - Analytics service
    # - Database queries
    # Example:
    # from django.contrib.sessions.models import Session
    # sessions = Session.objects.filter(expire_date__gte=timezone.now())
    # for session in sessions:
    #     data = session.get_decoded()
    #     client_version = data.get('client_version', 'unknown')
    #     metrics['version_distribution'][client_version] = ...

    return JsonResponse(metrics)