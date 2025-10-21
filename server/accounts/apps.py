"""
Accounts app configuration.
"""
from django.apps import AppConfig


class AccountsConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'accounts'
    verbose_name = 'User Accounts'

    def ready(self):
        """Import signals when app is ready."""
        import accounts.signals  # noqa

        # Auto-seed test users in development/test environments
        from django.conf import settings
        if getattr(settings, 'AUTO_SEED_TEST_USERS', False):
            self._seed_test_users()

    def _seed_test_users(self):
        """Seed test users if they don't exist."""
        # Import here to avoid AppRegistryNotReady errors
        from django.core.management import call_command
        from django.db import connection

        # Only run after all migrations are complete
        try:
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='users')"
                )
                table_exists = cursor.fetchone()[0]

            if table_exists:
                # Run the seed command silently
                call_command('seed_test_users', verbosity=0)
        except Exception:
            # Silently fail if migrations haven't run yet
            pass
