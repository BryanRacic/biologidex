"""
Monitoring middleware for BiologiDex
Provides Prometheus metrics and request tracking
"""
import time
import logging
from typing import Optional, Callable
from django.http import HttpRequest, HttpResponse
from django.urls import resolve
from django.urls.exceptions import Resolver404

try:
    from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
except ImportError:
    # Prometheus client not installed, create dummy classes
    class DummyMetric:
        def labels(self, **kwargs):
            return self
        def inc(self, amount=1):
            pass
        def observe(self, amount):
            pass
        def set(self, value):
            pass

    Counter = Histogram = Gauge = DummyMetric
    generate_latest = lambda: b''
    CONTENT_TYPE_LATEST = 'text/plain'

logger = logging.getLogger(__name__)

# Metrics definitions
http_requests_total = Counter(
    'django_http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status_code']
)

http_request_duration_seconds = Histogram(
    'django_http_request_duration_seconds',
    'HTTP request duration in seconds',
    ['method', 'endpoint'],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
)

http_requests_in_progress = Gauge(
    'django_http_requests_in_progress',
    'HTTP requests currently being processed'
)

api_requests_total = Counter(
    'api_requests_total',
    'Total API requests',
    ['method', 'endpoint', 'status_code', 'version']
)

api_request_duration_seconds = Histogram(
    'api_request_duration_seconds',
    'API request duration in seconds',
    ['method', 'endpoint', 'version']
)

# CV Processing metrics
cv_processing_total = Counter(
    'cv_processing_total',
    'Total CV processing jobs',
    ['status', 'model']
)

cv_processing_duration_seconds = Histogram(
    'cv_processing_duration_seconds',
    'CV processing duration in seconds',
    ['model'],
    buckets=[1, 2, 5, 10, 20, 30, 60, 120]
)

cv_processing_cost_usd = Counter(
    'cv_processing_cost_usd',
    'Total CV processing cost in USD',
    ['model']
)

# Celery task metrics
celery_tasks_total = Counter(
    'celery_tasks_total',
    'Total Celery tasks',
    ['task_name', 'status']
)

celery_task_duration_seconds = Histogram(
    'celery_task_duration_seconds',
    'Celery task duration in seconds',
    ['task_name']
)

active_celery_tasks = Gauge(
    'active_celery_tasks',
    'Number of active Celery tasks',
    ['task_name']
)

# Database metrics
db_queries_total = Counter(
    'django_db_queries_total',
    'Total database queries',
    ['operation']  # SELECT, INSERT, UPDATE, DELETE
)

db_query_duration_seconds = Histogram(
    'django_db_query_duration_seconds',
    'Database query duration in seconds',
    ['operation']
)

# Cache metrics
cache_operations_total = Counter(
    'django_cache_operations_total',
    'Total cache operations',
    ['operation', 'hit']  # operation: get/set, hit: true/false
)

# User metrics
active_users = Gauge(
    'active_users',
    'Number of active users in the last 5 minutes'
)

total_dex_entries = Gauge(
    'total_dex_entries',
    'Total number of dex entries'
)

total_animals = Gauge(
    'total_animals',
    'Total number of animals in database'
)


class PrometheusMiddleware:
    """
    Middleware to collect Prometheus metrics for each request
    """

    def __init__(self, get_response: Callable):
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        """Process each request and collect metrics"""

        # Skip metrics endpoint itself to avoid recursion
        if request.path == '/metrics/':
            return self.get_response(request)

        # Start tracking
        http_requests_in_progress.inc()
        start_time = time.time()

        # Extract endpoint name
        endpoint = self._get_endpoint_name(request)

        # Process request
        response = None
        exception = None

        try:
            response = self.get_response(request)
        except Exception as e:
            exception = e
            logger.error(f"Request failed: {e}", exc_info=True)

        # Calculate duration
        duration = time.time() - start_time

        # Record metrics
        http_requests_in_progress.dec()

        if response:
            status_code = response.status_code
        else:
            status_code = 500

        # General HTTP metrics
        http_requests_total.labels(
            method=request.method,
            endpoint=endpoint,
            status_code=status_code
        ).inc()

        http_request_duration_seconds.labels(
            method=request.method,
            endpoint=endpoint
        ).observe(duration)

        # API-specific metrics
        if request.path.startswith('/api/'):
            version = self._extract_api_version(request.path)
            api_requests_total.labels(
                method=request.method,
                endpoint=endpoint,
                status_code=status_code,
                version=version
            ).inc()

            api_request_duration_seconds.labels(
                method=request.method,
                endpoint=endpoint,
                version=version
            ).observe(duration)

        # Log slow requests
        if duration > 1.0:  # Requests taking more than 1 second
            logger.warning(
                f"Slow request: {request.method} {request.path} "
                f"took {duration:.2f}s (status: {status_code})"
            )

        # Re-raise exception if occurred
        if exception:
            raise exception

        return response

    def _get_endpoint_name(self, request: HttpRequest) -> str:
        """Extract endpoint name from request"""
        try:
            resolver_match = resolve(request.path)
            if resolver_match:
                view_name = resolver_match.view_name
                # Simplify the view name for metrics
                if view_name:
                    # Convert 'app:view-name' to 'app.view_name'
                    return view_name.replace(':', '.').replace('-', '_')
        except Resolver404:
            pass

        # Fallback to simplified path
        path_parts = request.path.strip('/').split('/')
        if len(path_parts) > 3:
            # Truncate long paths
            return '/'.join(path_parts[:3]) + '/...'
        return request.path

    def _extract_api_version(self, path: str) -> str:
        """Extract API version from path"""
        parts = path.strip('/').split('/')
        if len(parts) > 1 and parts[0] == 'api':
            # Return version if it looks like v1, v2, etc.
            if parts[1].startswith('v'):
                return parts[1]
        return 'unknown'


def metrics_view(request: HttpRequest) -> HttpResponse:
    """
    Endpoint to expose Prometheus metrics
    """
    # Update some gauges with current values
    try:
        from accounts.models import User
        from animals.models import Animal
        from dex.models import DexEntry
        from django.utils import timezone
        from datetime import timedelta

        # Count active users (logged in within last 5 minutes)
        five_minutes_ago = timezone.now() - timedelta(minutes=5)
        active_count = User.objects.filter(last_login__gte=five_minutes_ago).count()
        active_users.set(active_count)

        # Count total dex entries
        total_dex_entries.set(DexEntry.objects.count())

        # Count total animals
        total_animals.set(Animal.objects.count())
    except Exception as e:
        logger.error(f"Error updating metrics gauges: {e}")

    # Generate metrics output
    metrics_output = generate_latest()

    return HttpResponse(
        metrics_output,
        content_type=CONTENT_TYPE_LATEST
    )


# Celery signal handlers for task metrics
try:
    from celery.signals import task_prerun, task_postrun, task_failure

    task_start_times = {}

    @task_prerun.connect
    def task_prerun_handler(sender=None, task_id=None, task=None, **kwargs):
        """Track task start"""
        task_name = task.name if task else 'unknown'
        task_start_times[task_id] = time.time()
        active_celery_tasks.labels(task_name=task_name).inc()

    @task_postrun.connect
    def task_postrun_handler(sender=None, task_id=None, task=None, state=None, **kwargs):
        """Track task completion"""
        task_name = task.name if task else 'unknown'

        # Record task completion
        celery_tasks_total.labels(task_name=task_name, status='success').inc()
        active_celery_tasks.labels(task_name=task_name).dec()

        # Record duration
        if task_id in task_start_times:
            duration = time.time() - task_start_times[task_id]
            celery_task_duration_seconds.labels(task_name=task_name).observe(duration)
            del task_start_times[task_id]

    @task_failure.connect
    def task_failure_handler(sender=None, task_id=None, task=None, **kwargs):
        """Track task failure"""
        task_name = task.name if task else 'unknown'
        celery_tasks_total.labels(task_name=task_name, status='failure').inc()
        active_celery_tasks.labels(task_name=task_name).dec()

        # Clean up start time
        if task_id in task_start_times:
            del task_start_times[task_id]

except ImportError:
    # Celery not installed
    pass


# Export function for CV processing metrics
def track_cv_processing(model: str, status: str, duration: float, cost: float):
    """
    Track CV processing metrics

    Args:
        model: The CV model used (e.g., 'gpt-4-vision')
        status: Processing status ('success', 'failure')
        duration: Processing duration in seconds
        cost: Processing cost in USD
    """
    cv_processing_total.labels(status=status, model=model).inc()
    cv_processing_duration_seconds.labels(model=model).observe(duration)
    cv_processing_cost_usd.labels(model=model).inc(cost)