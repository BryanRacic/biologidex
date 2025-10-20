"""
Vision app configuration.
"""
from django.apps import AppConfig


class VisionConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'vision'
    verbose_name = 'Animal Vision Recognition'
