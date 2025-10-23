"""
Request logging middleware for BiologiDex API
Logs all incoming requests and outgoing responses for debugging
"""
import json
import logging
import time
from django.utils.deprecation import MiddlewareMixin
from django.http import HttpRequest, HttpResponse

logger = logging.getLogger('biologidex.api')


class RequestLoggingMiddleware(MiddlewareMixin):
    """
    Middleware to log all API requests and responses
    Useful for debugging client-server communication
    """

    def process_request(self, request: HttpRequest):
        """Log incoming request details"""
        # Only log API requests
        if not request.path.startswith('/api/'):
            return None

        # Store request start time
        request._start_time = time.time()

        # Log request details
        logger.info("=" * 80)
        logger.info("INCOMING REQUEST")
        logger.info("=" * 80)
        logger.info(f"Method: {request.method}")
        logger.info(f"Path: {request.path}")
        logger.info(f"Query Params: {dict(request.GET)}")

        # Log headers (excluding sensitive data)
        headers = {}
        for key, value in request.headers.items():
            if key.lower() in ['authorization', 'cookie']:
                headers[key] = '[REDACTED]'
            else:
                headers[key] = value
        logger.info(f"Headers: {json.dumps(headers, indent=2)}")

        # Log request body for POST/PUT/PATCH
        if request.method in ['POST', 'PUT', 'PATCH']:
            try:
                if request.content_type == 'application/json':
                    body = json.loads(request.body.decode('utf-8'))
                    # Redact sensitive fields
                    if 'password' in body:
                        body['password'] = '[REDACTED]'
                    if 'refresh' in body:
                        body['refresh'] = '[REDACTED]'
                    logger.info(f"Body: {json.dumps(body, indent=2)}")
                elif request.content_type and 'multipart/form-data' in request.content_type:
                    logger.info(f"Body: [MULTIPART DATA - {len(request.body)} bytes]")
                    # Log file names if present
                    if request.FILES:
                        for field_name, file in request.FILES.items():
                            logger.info(f"  File: {field_name} = {file.name} ({file.size} bytes)")
                else:
                    logger.info(f"Body: [Binary data - {len(request.body)} bytes]")
            except Exception as e:
                logger.warning(f"Could not parse request body: {e}")

        logger.info("-" * 80)

        return None

    def process_response(self, request: HttpRequest, response: HttpResponse):
        """Log outgoing response details"""
        # Only log API requests
        if not request.path.startswith('/api/'):
            return response

        # Calculate request duration
        duration = 0
        if hasattr(request, '_start_time'):
            duration = (time.time() - request._start_time) * 1000  # Convert to ms

        # Log response details
        logger.info("OUTGOING RESPONSE")
        logger.info("=" * 80)
        logger.info(f"Status: {response.status_code}")
        logger.info(f"Duration: {duration:.2f}ms")

        # Log response body (only for JSON responses and successful requests)
        try:
            if response['Content-Type'] and 'application/json' in response['Content-Type']:
                body = json.loads(response.content.decode('utf-8'))

                # Redact sensitive fields in response
                if isinstance(body, dict):
                    if 'access' in body:
                        body['access'] = '[REDACTED]'
                    if 'refresh' in body:
                        body['refresh'] = '[REDACTED]'

                logger.info(f"Body: {json.dumps(body, indent=2)}")
            else:
                logger.info(f"Body: [Non-JSON response - {len(response.content)} bytes]")
        except Exception as e:
            logger.warning(f"Could not parse response body: {e}")

        logger.info("=" * 80)
        logger.info("")

        return response

    def process_exception(self, request: HttpRequest, exception: Exception):
        """Log exceptions that occur during request processing"""
        if not request.path.startswith('/api/'):
            return None

        logger.error("=" * 80)
        logger.error("REQUEST EXCEPTION")
        logger.error("=" * 80)
        logger.error(f"Path: {request.path}")
        logger.error(f"Exception: {type(exception).__name__}")
        logger.error(f"Message: {str(exception)}")
        logger.error("=" * 80)
        logger.error("")

        return None
