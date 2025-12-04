# taxonomy/management/commands/link_col_parents.py
"""
One-time migration command to link COL parent IDs on existing data.

This fixes the missing accepted_name FK on synonym records by reading
the parent_id from the original NameUsage.tsv file.

Per ColDP spec (https://github.com/CatalogueOfLife/coldp):
- For synonyms: parentID points to the accepted taxon
- For accepted taxa: parentID points to the taxonomic parent

Uses streaming TSV reading + database-side UPDATE for memory efficiency.
"""
import csv
import os
import sys
from glob import glob

from django.conf import settings
from django.core.management.base import BaseCommand
from django.db import connection

from taxonomy.models import DataSource


class Command(BaseCommand):
    help = 'Link COL parent IDs (synonyms → accepted names) from NameUsage.tsv'

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Show what would be linked without making changes'
        )
        parser.add_argument(
            '--tsv-path',
            type=str,
            help='Path to NameUsage.tsv (auto-detects latest COL download if not specified)'
        )
        parser.add_argument(
            '--chunk-size',
            type=int,
            default=10000,
            help='Process updates in chunks of this size (default: 10000)'
        )

    def handle(self, *args, **options):
        dry_run = options['dry_run']
        tsv_path = options['tsv_path']
        chunk_size = options['chunk_size']

        self.stdout.write(self.style.SUCCESS('=== COL Parent ID Linking ==='))

        if dry_run:
            self.stdout.write(self.style.WARNING('DRY RUN - no changes will be made'))

        # Get COL source
        try:
            source = DataSource.objects.get(short_code='col')
        except DataSource.DoesNotExist:
            self.stdout.write(self.style.ERROR('COL data source not found. Run import_col first.'))
            return

        # Find NameUsage.tsv
        if not tsv_path:
            tsv_path = self._find_latest_nameusage_tsv()
            if not tsv_path:
                self.stdout.write(self.style.ERROR(
                    'No COL download found. Either:\n'
                    '  1. Run import_col to download COL data first, or\n'
                    '  2. Specify --tsv-path=/path/to/NameUsage.tsv'
                ))
                return

        if not os.path.exists(tsv_path):
            self.stdout.write(self.style.ERROR(f'File not found: {tsv_path}'))
            return

        self.stdout.write(f'Using: {tsv_path}')
        file_size_mb = os.path.getsize(tsv_path) / (1024 * 1024)
        self.stdout.write(f'File size: {file_size_mb:.1f} MB')

        # Build the lookup of source_taxon_id → taxonomy.id
        # Uses chunked fetching to avoid loading all 5M+ rows at once
        self.stdout.write('\nBuilding COL ID → Taxonomy ID lookup...')
        source_id = source.id

        taxonomy_lookup = {}
        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT source_taxon_id, id, accepted_name_id, parent_id
                FROM taxonomy_taxonomy
                WHERE source_id = %s
            """, [source_id])

            # Fetch in chunks to reduce peak memory
            loaded = 0
            while True:
                rows = cursor.fetchmany(50000)
                if not rows:
                    break
                for row in rows:
                    taxonomy_lookup[row[0]] = (row[1], row[2] is not None, row[3] is not None)
                loaded += len(rows)
                if loaded % 1000000 == 0:
                    self.stdout.write(f'  Loaded {loaded:,} records...')

        self.stdout.write(f'Loaded {len(taxonomy_lookup):,} taxonomy records')

        # Process the TSV file
        self.stdout.write('\nProcessing NameUsage.tsv...')

        # Increase CSV field size limit
        csv.field_size_limit(sys.maxsize)

        # Collect updates
        synonym_updates = []  # [(tax_id, accepted_tax_id), ...]
        parent_updates = []   # [(tax_id, parent_tax_id), ...]

        synonyms_to_link = 0
        synonyms_already_linked = 0
        parents_to_link = 0
        parents_already_linked = 0
        not_found = 0
        parent_not_found = 0
        processed = 0

        with open(tsv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f, delimiter='\t')

            for row in reader:
                processed += 1

                if processed % 500000 == 0:
                    self.stdout.write(f'  Scanned {processed:,} rows...')

                col_id = row.get('col:ID', '')
                parent_id = row.get('col:parentID', '')
                status = row.get('col:status', '').lower()

                if not col_id or not parent_id:
                    continue

                # Look up this record
                tax_info = taxonomy_lookup.get(col_id)
                if not tax_info:
                    not_found += 1
                    continue

                tax_id, has_accepted, has_parent = tax_info

                # Look up parent record
                parent_info = taxonomy_lookup.get(parent_id)
                if not parent_info:
                    parent_not_found += 1
                    continue

                parent_tax_id = parent_info[0]

                # Determine link type based on status
                if status == 'synonym':
                    if has_accepted:
                        synonyms_already_linked += 1
                    else:
                        synonym_updates.append((tax_id, parent_tax_id))
                        synonyms_to_link += 1
                else:
                    if has_parent:
                        parents_already_linked += 1
                    else:
                        parent_updates.append((tax_id, parent_tax_id))
                        parents_to_link += 1

        self.stdout.write(f'\nScan complete: {processed:,} rows processed')
        self.stdout.write(f'Synonyms to link:        {synonyms_to_link:,}')
        self.stdout.write(f'Synonyms already linked: {synonyms_already_linked:,}')
        self.stdout.write(f'Parents to link:         {parents_to_link:,}')
        self.stdout.write(f'Parents already linked:  {parents_already_linked:,}')
        self.stdout.write(f'Records not in DB:       {not_found:,}')
        self.stdout.write(f'Parent not in DB:        {parent_not_found:,}')

        if dry_run:
            self.stdout.write(self.style.WARNING('\nDRY RUN - no changes made'))
            return

        # Apply updates in chunks using temp table for efficiency
        if synonym_updates:
            self.stdout.write(f'\nLinking {len(synonym_updates):,} synonyms...')
            self._bulk_update_fk(synonym_updates, 'accepted_name_id', chunk_size)
            self.stdout.write(self.style.SUCCESS(f'  ✓ Linked {len(synonym_updates):,} synonyms'))

        if parent_updates:
            self.stdout.write(f'\nLinking {len(parent_updates):,} parents...')
            self._bulk_update_fk(parent_updates, 'parent_id', chunk_size)
            self.stdout.write(self.style.SUCCESS(f'  ✓ Linked {len(parent_updates):,} parents'))

        self.stdout.write(self.style.SUCCESS('\n✓ Parent ID linking completed'))

    def _find_latest_nameusage_tsv(self):
        """Find the most recent COL NameUsage.tsv from taxonomy_imports"""
        import_dir = os.path.join(settings.MEDIA_ROOT, 'taxonomy_imports')

        if not os.path.exists(import_dir):
            return None

        # Find extracted directories
        extracted_dirs = glob(os.path.join(import_dir, 'col_*_extracted'))
        if not extracted_dirs:
            return None

        # Sort by modification time (newest first)
        extracted_dirs.sort(key=os.path.getmtime, reverse=True)

        for extract_dir in extracted_dirs:
            nameusage_path = os.path.join(extract_dir, 'NameUsage.tsv')
            if os.path.exists(nameusage_path):
                return nameusage_path

        return None

    def _bulk_update_fk(self, updates, field_name, chunk_size):
        """Bulk update a foreign key field using a temp table"""
        with connection.cursor() as cursor:
            # Disable statement timeout for this long-running operation
            cursor.execute("SET statement_timeout = 0")

            total = len(updates)
            updated = 0

            for i in range(0, total, chunk_size):
                chunk = updates[i:i + chunk_size]

                # Create temp table for this chunk (UUID primary keys)
                cursor.execute("DROP TABLE IF EXISTS _link_updates")
                cursor.execute("""
                    CREATE TEMP TABLE _link_updates (
                        tax_id UUID PRIMARY KEY,
                        target_id UUID
                    )
                """)

                # Insert chunk data
                values_sql = ','.join(
                    cursor.mogrify('(%s,%s)', (tax_id, target_id)).decode()
                    for tax_id, target_id in chunk
                )
                cursor.execute(f'INSERT INTO _link_updates (tax_id, target_id) VALUES {values_sql}')

                # Perform the update
                cursor.execute(f"""
                    UPDATE taxonomy_taxonomy AS t
                    SET {field_name} = u.target_id
                    FROM _link_updates u
                    WHERE t.id = u.tax_id
                """)

                updated += cursor.rowcount
                self.stdout.write(f'  Progress: {updated:,}/{total:,}')

            # Clean up
            cursor.execute("DROP TABLE IF EXISTS _link_updates")
