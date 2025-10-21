"""
Management command to seed test users for development/testing.
Creates three default users: basic user, admin, and verified user.
"""
from django.core.management.base import BaseCommand
from django.db import transaction
from accounts.models import User


class Command(BaseCommand):
    help = 'Seeds default test users for development/testing environment'

    TEST_USERS = [
        {
            'username': 'testuser',
            'email': 'testuser@example.com',
            'password': 'testpass123',
            'friend_code': 'TEST0001',
            'bio': 'Basic test user for development',
            'is_staff': False,
            'is_superuser': False,
            'badges': ['tester'],
        },
        {
            'username': 'admin',
            'email': 'admin@example.com',
            'password': 'adminpass123',
            'friend_code': 'ADMIN001',
            'bio': 'Administrator test account',
            'is_staff': True,
            'is_superuser': True,
            'badges': ['admin', 'tester'],
        },
        {
            'username': 'verified',
            'email': 'verified@example.com',
            'password': 'verifiedpass123',
            'friend_code': 'VERIFY01',
            'bio': 'Verified test user with special privileges',
            'is_staff': False,
            'is_superuser': False,
            'badges': ['verified', 'tester', 'early_adopter'],
        },
    ]

    def add_arguments(self, parser):
        parser.add_argument(
            '--force',
            action='store_true',
            help='Force recreation of test users (deletes existing)',
        )

    @transaction.atomic
    def handle(self, *args, **options):
        force = options.get('force', False)
        created_count = 0
        skipped_count = 0
        recreated_count = 0

        self.stdout.write('Seeding test users...')

        for user_data in self.TEST_USERS:
            username = user_data['username']
            email = user_data['email']

            # Check if user already exists
            existing_user = User.objects.filter(username=username).first()

            if existing_user:
                if force:
                    # Delete and recreate
                    self.stdout.write(
                        self.style.WARNING(f'Deleting existing user: {username}')
                    )
                    existing_user.delete()
                else:
                    self.stdout.write(
                        self.style.WARNING(f'User already exists: {username} (use --force to recreate)')
                    )
                    skipped_count += 1
                    continue

            # Create user
            password = user_data.pop('password')
            user = User(**user_data)
            user.set_password(password)
            user.save()

            if force and existing_user:
                recreated_count += 1
                self.stdout.write(
                    self.style.SUCCESS(f'Recreated user: {username} (friend_code: {user.friend_code})')
                )
            else:
                created_count += 1
                self.stdout.write(
                    self.style.SUCCESS(f'Created user: {username} (friend_code: {user.friend_code})')
                )

        # Summary
        self.stdout.write('\n' + '='*50)
        if created_count:
            self.stdout.write(self.style.SUCCESS(f'Created {created_count} new test user(s)'))
        if recreated_count:
            self.stdout.write(self.style.SUCCESS(f'Recreated {recreated_count} test user(s)'))
        if skipped_count:
            self.stdout.write(self.style.WARNING(f'Skipped {skipped_count} existing user(s)'))

        if created_count or recreated_count:
            self.stdout.write('\nTest User Credentials:')
            self.stdout.write('-' * 50)
            for user_data in self.TEST_USERS:
                self.stdout.write(f"  {user_data['username']:<12} | password: {user_data.get('password', 'N/A')}")
            self.stdout.write('='*50)