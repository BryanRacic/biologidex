"""
Middleware package for BiologiDex
"""
from .request_logging import RequestLoggingMiddleware

__all__ = ['RequestLoggingMiddleware']
