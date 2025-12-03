# taxonomy/management/commands/link_col_parents.py
"""
One-time migration command to link COL parent IDs on existing data.

This fixes the missing accepted_name FK on synonym records by reading
the parent_id from RawCatalogueOfLife and linking it properly.

Per ColDP spec (https://github.com/CatalogueOfLife/coldp):
- For synonyms: parentID points to the accepted taxon
- For accepted taxa: parentID points to the taxonomic parent
"""
from django.core.management.base import BaseCommand
from django.db import transaction
from taxonomy.models import Taxonomy, DataSource
from taxonomy.raw_models import RawCatalogueOfLife


class Command(BaseCommand):
    help = 'Link COL parent IDs (synonyms → accepted names) on existing data'

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Show what would be linked without making changes'
        )
        parser.add_argument(
            '--batch-size',
            type=int,
            default=5000,
            help='Batch size for bulk updates (default: 5000)'
        )

    def handle(self, *args, **options):
        dry_run = options['dry_run']
        batch_size = options['batch_size']

        self.stdout.write(self.style.SUCCESS('=== COL Parent ID Linking ==='))

        if dry_run:
            self.stdout.write(self.style.WARNING('DRY RUN - no changes will be made'))

        # Get COL source
        try:
            source = DataSource.objects.get(short_code='col')
        except DataSource.DoesNotExist:
            self.stdout.write(self.style.ERROR('COL data source not found. Run import_col first.'))
            return

        # Build lookup of COL ID → Taxonomy object
        self.stdout.write('Building COL ID → Taxonomy lookup...')
        taxonomy_by_col_id = {}
        for tax in Taxonomy.objects.filter(source=source).only('id', 'source_taxon_id', 'status', 'accepted_name_id', 'parent_id'):
            taxonomy_by_col_id[tax.source_taxon_id] = tax
        self.stdout.write(f'Loaded {len(taxonomy_by_col_id):,} taxonomy records')

        # Find raw records with parent_id
        self.stdout.write('Finding records with parent_id to link...')
        raw_records = RawCatalogueOfLife.objects.exclude(parent_id='').values('col_id', 'parent_id', 'status')
        total_count = raw_records.count()
        self.stdout.write(f'Found {total_count:,} records with parent_id')

        # Track statistics
        synonyms_linked = 0
        synonyms_already_linked = 0
        parents_linked = 0
        parents_already_linked = 0
        not_found_count = 0
        error_count = 0

        batch_updates_accepted_name = []
        batch_updates_parent = []
        processed = 0

        for raw in raw_records.iterator(chunk_size=batch_size):
            try:
                col_id = raw['col_id']
                parent_id = raw['parent_id']
                status = raw['status']

                # Get the taxonomy record
                taxonomy = taxonomy_by_col_id.get(col_id)
                if not taxonomy:
                    not_found_count += 1
                    continue

                # Get the parent/accepted taxonomy
                parent_taxonomy = taxonomy_by_col_id.get(parent_id)
                if not parent_taxonomy:
                    not_found_count += 1
                    continue

                # Link based on status
                if status.lower() == 'synonym':
                    if taxonomy.accepted_name_id:
                        synonyms_already_linked += 1
                    else:
                        batch_updates_accepted_name.append(
                            Taxonomy(id=taxonomy.id, accepted_name_id=parent_taxonomy.id)
                        )
                        synonyms_linked += 1
                else:
                    if taxonomy.parent_id:
                        parents_already_linked += 1
                    else:
                        batch_updates_parent.append(
                            Taxonomy(id=taxonomy.id, parent_id=parent_taxonomy.id)
                        )
                        parents_linked += 1

                processed += 1

                # Bulk update in batches
                if not dry_run:
                    if len(batch_updates_accepted_name) >= batch_size:
                        Taxonomy.objects.bulk_update(batch_updates_accepted_name, ['accepted_name_id'])
                        batch_updates_accepted_name = []

                    if len(batch_updates_parent) >= batch_size:
                        Taxonomy.objects.bulk_update(batch_updates_parent, ['parent_id'])
                        batch_updates_parent = []

                # Log progress
                if processed % 100000 == 0:
                    self.stdout.write(
                        f'Progress: {processed:,}/{total_count:,} - '
                        f'synonyms: {synonyms_linked:,} new, {synonyms_already_linked:,} existing'
                    )

            except Exception as e:
                error_count += 1
                if error_count <= 10:
                    self.stdout.write(self.style.ERROR(f'Error: {e}'))

        # Process remaining batches
        if not dry_run:
            if batch_updates_accepted_name:
                Taxonomy.objects.bulk_update(batch_updates_accepted_name, ['accepted_name_id'])
            if batch_updates_parent:
                Taxonomy.objects.bulk_update(batch_updates_parent, ['parent_id'])

        # Final statistics
        self.stdout.write('')
        self.stdout.write(self.style.SUCCESS('=== Results ==='))
        self.stdout.write(f'Total processed:           {processed:,}')
        self.stdout.write(f'Synonyms newly linked:     {synonyms_linked:,}')
        self.stdout.write(f'Synonyms already linked:   {synonyms_already_linked:,}')
        self.stdout.write(f'Parents newly linked:      {parents_linked:,}')
        self.stdout.write(f'Parents already linked:    {parents_already_linked:,}')
        self.stdout.write(f'Not found (skipped):       {not_found_count:,}')
        self.stdout.write(f'Errors:                    {error_count}')

        if dry_run:
            self.stdout.write(self.style.WARNING('\nDRY RUN - no changes were made'))
        else:
            self.stdout.write(self.style.SUCCESS('\n✓ Parent ID linking completed'))
