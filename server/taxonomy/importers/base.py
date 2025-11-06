# taxonomy/importers/base.py
import abc
import logging
from typing import Dict, Any, Optional, Tuple
from django.db import transaction
from django.core.exceptions import ValidationError
from django.utils import timezone

logger = logging.getLogger(__name__)


class BaseImporter(abc.ABC):
    """Abstract base class for taxonomic data importers"""

    def __init__(self, import_job):
        self.import_job = import_job
        self.source = import_job.source
        self.stats = {
            'records_read': 0,
            'records_imported': 0,
            'records_failed': 0,
            'errors': []
        }

    @abc.abstractmethod
    def download_data(self) -> str:
        """Download data from source. Return file path."""
        pass

    @abc.abstractmethod
    def parse_file(self, file_path: str):
        """Parse downloaded file and import to raw tables."""
        pass

    @abc.abstractmethod
    def validate_record(self, record: Dict[str, Any]) -> Tuple[bool, Optional[str]]:
        """Validate a single record. Return (is_valid, error_message)."""
        pass

    @abc.abstractmethod
    def transform_record(self, raw_record) -> Dict[str, Any]:
        """Transform raw record to normalized taxonomy format."""
        pass

    def run(self):
        """Main import pipeline"""
        try:
            self.import_job.status = 'downloading'
            self.import_job.started_at = timezone.now()
            self.import_job.save()

            # Download data
            file_path = self.download_data()
            self.import_job.file_path = file_path
            self.import_job.status = 'processing'
            self.import_job.save()

            # Parse and import to raw tables
            self.parse_file(file_path)

            # Transform and normalize
            self.import_job.status = 'importing'
            self.import_job.save()
            self.normalize_data()

            # Finalize
            self.import_job.status = 'completed'
            self.import_job.completed_at = timezone.now()
            self.import_job.records_imported = self.stats['records_imported']
            self.import_job.records_failed = self.stats['records_failed']
            self.import_job.error_log = {'errors': self.stats['errors'][:100]}  # Keep first 100 errors
            self.import_job.save()

            logger.info(f"Import job {self.import_job.id} completed: {self.stats['records_imported']} imported, {self.stats['records_failed']} failed")

        except Exception as e:
            logger.error(f"Import failed: {e}")
            self.import_job.status = 'failed'
            self.import_job.completed_at = timezone.now()
            self.import_job.error_log = {'fatal_error': str(e)}
            self.import_job.save()
            raise

    def normalize_data(self):
        """Transform raw data to normalized taxonomy records"""
        from taxonomy.models import Taxonomy
        from taxonomy.raw_models import RawCatalogueOfLife

        batch_size = 1000
        raw_records = RawCatalogueOfLife.objects.filter(
            import_job=self.import_job,
            is_processed=False
        )

        total_records = raw_records.count()
        logger.info(f"Normalizing {total_records} raw records...")

        for batch_start in range(0, total_records, batch_size):
            batch = raw_records[batch_start:batch_start + batch_size]

            with transaction.atomic():
                for raw in batch:
                    try:
                        # Transform to normalized format
                        data = self.transform_record(raw)

                        # Create or update taxonomy record
                        taxonomy, created = Taxonomy.objects.update_or_create(
                            source=self.source,
                            source_taxon_id=data['source_taxon_id'],
                            defaults=data
                        )

                        # Mark as processed
                        raw.is_processed = True
                        raw.save()

                        self.stats['records_imported'] += 1

                    except Exception as e:
                        logger.error(f"Failed to normalize record {raw.col_id}: {e}")
                        raw.processing_errors = {'error': str(e)}
                        raw.save()
                        self.stats['records_failed'] += 1
                        self.stats['errors'].append({
                            'record_id': str(raw.col_id),
                            'error': str(e)
                        })

            # Log progress
            if (batch_start + batch_size) % 10000 == 0:
                logger.info(f"Processed {batch_start + batch_size}/{total_records} records...")
