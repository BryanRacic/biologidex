"""
Models for graph app (if needed for caching).
For now, this app is primarily view-based.
"""
from django.db import models

# This app primarily uses services and doesn't require persistent models
# beyond what's already in animals and dex apps.
# Any caching is done via Django's cache framework.
