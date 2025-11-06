# taxonomy/management/commands/import_col.py
from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone
from datetime import timedelta
from taxonomy.models import DataSource, ImportJob
from taxonomy.importers.col_importer import CatalogueOfLifeImporter


class Command(BaseCommand):
    help = 'Import Catalogue of Life data'

    def add_arguments(self, parser):
        parser.add_argument(
            '--async',
            action='store_true',
            help='Run import as async Celery task'
        )
        parser.add_argument(
            '--force',
            action='store_true',
            help='Force import even if recent import exists'
        )
        parser.add_argument(
            '--file',
            type=str,
            help='Path to local COL zip file (skip download)'
        )

    def handle(self, *args, **options):
        self.stdout.write(self.style.SUCCESS('=== Catalogue of Life Import ==='))

        # Get or create COL data source
        source, created = DataSource.objects.get_or_create(
            short_code='col',
            defaults={
                'name': 'Catalogue of Life',
                'full_name': 'Catalogue of Life eXtended Release',
                'url': 'https://www.catalogueoflife.org',
                'api_endpoint': 'https://api.checklistbank.org',
                'update_frequency': 'monthly',
                'license': 'CC BY 4.0',
                'citation_format': 'Bánki, O., Roskov, Y., et al. ({year}). Catalogue of Life.',
                'priority': 10  # High priority
            }
        )

        if created:
            self.stdout.write(self.style.SUCCESS(f'✓ Created data source: {source}'))
        else:
            self.stdout.write(f'Using existing data source: {source}')

        # Check for recent imports
        if not options['force']:
            recent = ImportJob.objects.filter(
                source=source,
                status='completed',
                created_at__gte=timezone.now() - timedelta(days=30)
            ).first()

            if recent:
                self.stdout.write(self.style.WARNING(
                    f'Recent import exists: {recent.version} from {recent.created_at}'
                ))
                raise CommandError(
                    'Recent import exists. Use --force to override.'
                )

        # Create import job
        import_job = ImportJob.objects.create(
            source=source,
            status='pending',
            version='pending'
        )

        self.stdout.write(f'Created import job: {import_job.id}')

        if options['async']:
            # Run as Celery task
            from taxonomy.tasks import run_import_job
            task = run_import_job.delay(str(import_job.id))
            self.stdout.write(
                self.style.SUCCESS(
                    f'✓ Import job queued for async processing (Task ID: {task.id})'
                )
            )
            self.stdout.write('Monitor progress in Django admin or logs')
        else:
            # Run synchronously
            self.stdout.write('Running import synchronously...')
            self.stdout.write(self.style.WARNING('This may take 2-3 hours for full COL dataset'))

            importer = CatalogueOfLifeImporter(import_job)

            if options['file']:
                # Use local file
                self.stdout.write(f'Using local file: {options["file"]}')
                import_job.file_path = options['file']
                import_job.status = 'processing'
                import_job.save()
                importer.parse_file(options['file'])
                importer.normalize_data()
                import_job.status = 'completed'
                import_job.completed_at = timezone.now()
                import_job.save()
            else:
                # Full import pipeline
                importer.run()

            self.stdout.write(
                self.style.SUCCESS(
                    f'\n✓ Import completed successfully!'
                )
            )
            self.stdout.write(f'  Records imported: {importer.stats["records_imported"]}')
            self.stdout.write(f'  Records failed: {importer.stats["records_failed"]}')
            self.stdout.write(f'  Records read: {importer.stats["records_read"]}')

            if importer.stats['errors']:
                self.stdout.write(
                    self.style.WARNING(
                        f'\n  First errors ({len(importer.stats["errors"])} total):'
                    )
                )
                for error in importer.stats['errors'][:5]:
                    self.stdout.write(f'    - {error}')
