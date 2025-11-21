"""
Management command to recalculate creation_index for all animals.

This command renumbers all animals sequentially, filling any gaps caused by deletions.
For example, if animal #17 is deleted, animal #18 becomes #17, #19 becomes #18, etc.
"""
from django.core.management.base import BaseCommand
from django.db import transaction
from animals.models import Animal


class Command(BaseCommand):
    help = 'Recalculates creation_index for all animals, filling gaps from deletions'

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Show what would be changed without actually updating the database',
        )
        parser.add_argument(
            '--start-from',
            type=int,
            default=1,
            help='Starting index number (default: 1)',
        )

    def handle(self, *args, **options):
        dry_run = options['dry_run']
        start_from = options['start_from']

        if dry_run:
            self.stdout.write(self.style.WARNING('DRY RUN MODE - No changes will be saved'))

        # Get all animals ordered by their current creation_index, then by created_at
        # This preserves the discovery order
        animals = Animal.objects.all().order_by('creation_index', 'created_at')

        total_count = animals.count()

        if total_count == 0:
            self.stdout.write(self.style.WARNING('No animals found in database'))
            return

        self.stdout.write(f'Found {total_count} animals')
        self.stdout.write(f'Recalculating creation_index starting from {start_from}...\n')

        changes = []
        updates_needed = 0

        # Collect all changes first
        for idx, animal in enumerate(animals, start=start_from):
            old_index = animal.creation_index
            new_index = idx

            if old_index != new_index:
                changes.append({
                    'animal': animal,
                    'old_index': old_index,
                    'new_index': new_index,
                })
                updates_needed += 1

        if updates_needed == 0:
            self.stdout.write(self.style.SUCCESS('✓ All creation_index values are already correct'))
            return

        # Display changes
        self.stdout.write(f'{updates_needed} animals need updating:\n')
        for change in changes[:10]:  # Show first 10 changes
            self.stdout.write(
                f'  {change["animal"].scientific_name} ({change["animal"].common_name}): '
                f'{change["old_index"]} → {change["new_index"]}'
            )

        if len(changes) > 10:
            self.stdout.write(f'  ... and {len(changes) - 10} more')

        if dry_run:
            self.stdout.write(self.style.WARNING('\nDRY RUN - No changes made'))
            return

        # Perform the updates in a transaction
        try:
            with transaction.atomic():
                # Temporarily set all creation_index to negative values to avoid unique constraint violations
                self.stdout.write('\nTemporarily clearing indexes...')
                for idx, animal in enumerate(animals, start=1):
                    animal.creation_index = -idx
                    animal.save(update_fields=['creation_index'])

                # Now set the correct values
                self.stdout.write('Applying new indexes...')
                for idx, animal in enumerate(animals, start=start_from):
                    animal.creation_index = idx
                    animal.save(update_fields=['creation_index'])

            self.stdout.write(self.style.SUCCESS(f'\n✓ Successfully recalculated creation_index for {updates_needed} animals'))
            self.stdout.write(f'Index range: {start_from} to {start_from + total_count - 1}')

        except Exception as e:
            self.stdout.write(self.style.ERROR(f'\n✗ Error: {str(e)}'))
            self.stdout.write(self.style.ERROR('Transaction rolled back - no changes made'))
            raise
