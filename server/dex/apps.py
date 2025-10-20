"""
Dex app configuration.
"""
from django.apps import AppConfig


class DexConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'dex'
    verbose_name = 'Dex Entries'

    def ready(self):
        """Import signals when app is ready."""
        import dex.signals  # noqa
