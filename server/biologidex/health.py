"""
Health check endpoint for BiologiDex
Provides comprehensive system health status
"""
import time
from typing import Dict, Any

from django.http import JsonResponse
from django.db import connection
from django.core.cache import cache
from django.views.decorators.http import require_http_methods
from django.views.decorators.cache import never_cache
import redis
from celery import current_app

# Import settings
from django.conf import settings


@never_cache
@require_http_methods(["GET", "HEAD"])
def health_check(request) -> JsonResponse:
    """
    Comprehensive health check endpoint for monitoring

    Returns JSON response with:
    - Overall status (healthy/unhealthy)
    - Individual component health checks
    - Response time for each check
    - System metadata
    """
    start_time = time.time()
    health_status: Dict[str, Any] = {
        'status': 'healthy',
        'timestamp': time.time(),
        'checks': {},
        'metadata': {
            'environment': settings.ENVIRONMENT if hasattr(settings, 'ENVIRONMENT') else 'unknown',
            'version': settings.VERSION if hasattr(settings, 'VERSION') else '1.0.0',
            'debug': settings.DEBUG,
        }
    }

    # Database health check
    db_start = time.time()
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            result = cursor.fetchone()
            if result and result[0] == 1:
                health_status['checks']['database'] = {
                    'status': 'healthy',
                    'response_time_ms': round((time.time() - db_start) * 1000, 2)
                }
            else:
                raise Exception("Database returned unexpected result")
    except Exception as e:
        health_status['checks']['database'] = {
            'status': 'unhealthy',
            'error': str(e),
            'response_time_ms': round((time.time() - db_start) * 1000, 2)
        }
        health_status['status'] = 'unhealthy'

    # Redis/Cache health check
    redis_start = time.time()
    try:
        # Test cache operations
        test_key = 'health_check_test'
        test_value = f'ok_{time.time()}'
        cache.set(test_key, test_value, 1)
        retrieved_value = cache.get(test_key)

        if retrieved_value == test_value:
            health_status['checks']['redis'] = {
                'status': 'healthy',
                'response_time_ms': round((time.time() - redis_start) * 1000, 2)
            }
        else:
            raise Exception("Cache get/set mismatch")
    except Exception as e:
        health_status['checks']['redis'] = {
            'status': 'unhealthy',
            'error': str(e),
            'response_time_ms': round((time.time() - redis_start) * 1000, 2)
        }
        health_status['status'] = 'unhealthy'

    # Celery health check (non-blocking)
    celery_start = time.time()
    try:
        # Check if Celery app is configured
        if current_app._get_current_object():
            # Try to get active workers (with timeout)
            inspector = current_app.control.inspect(timeout=1.0)
            active_workers = inspector.active()

            if active_workers:
                worker_count = len(active_workers)
                total_tasks = sum(len(tasks) for tasks in active_workers.values())
                health_status['checks']['celery'] = {
                    'status': 'healthy',
                    'workers': worker_count,
                    'active_tasks': total_tasks,
                    'response_time_ms': round((time.time() - celery_start) * 1000, 2)
                }
            else:
                health_status['checks']['celery'] = {
                    'status': 'degraded',
                    'error': 'No active workers found',
                    'response_time_ms': round((time.time() - celery_start) * 1000, 2)
                }
                # Don't mark overall status as unhealthy for Celery issues
    except Exception as e:
        health_status['checks']['celery'] = {
            'status': 'unknown',
            'error': str(e),
            'response_time_ms': round((time.time() - celery_start) * 1000, 2)
        }

    # Storage health check (if using GCS)
    if hasattr(settings, 'GCS_BUCKET_NAME') and settings.GCS_BUCKET_NAME:
        storage_start = time.time()
        try:
            from django.core.files.storage import default_storage
            # Try to check if storage is accessible
            default_storage.exists('health_check.txt')
            health_status['checks']['storage'] = {
                'status': 'healthy',
                'bucket': settings.GCS_BUCKET_NAME,
                'response_time_ms': round((time.time() - storage_start) * 1000, 2)
            }
        except Exception as e:
            health_status['checks']['storage'] = {
                'status': 'unhealthy',
                'error': str(e),
                'response_time_ms': round((time.time() - storage_start) * 1000, 2)
            }
            # Storage issues shouldn't necessarily mark the whole system as unhealthy

    # Add total response time
    health_status['total_response_time_ms'] = round((time.time() - start_time) * 1000, 2)

    # Determine HTTP status code
    if health_status['status'] == 'healthy':
        status_code = 200
    else:
        status_code = 503  # Service Unavailable

    return JsonResponse(health_status, status=status_code)


@never_cache
@require_http_methods(["GET"])
def liveness_check(request) -> JsonResponse:
    """
    Simple liveness check for Kubernetes/Docker
    Returns 200 if the application is running
    """
    return JsonResponse({'status': 'alive'}, status=200)


@never_cache
@require_http_methods(["GET"])
def readiness_check(request) -> JsonResponse:
    """
    Readiness check for Kubernetes/Docker
    Returns 200 if the application is ready to serve traffic
    """
    try:
        # Quick database check
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            cursor.fetchone()

        # Quick cache check
        cache.set('readiness_check', 'ok', 1)

        return JsonResponse({'status': 'ready'}, status=200)
    except Exception as e:
        return JsonResponse({
            'status': 'not_ready',
            'error': str(e)
        }, status=503)