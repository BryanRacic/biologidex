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

        # Get all unprocessed records and collect their IDs upfront to avoid
        # queryset re-evaluation issues when marking records as processed
        logger.info("=" * 80)
        logger.info("STEP: NORMALIZE RAW DATA TO TAXONOMY TABLE")
        logger.info("=" * 80)

        raw_record_ids = list(
            RawCatalogueOfLife.objects.filter(
                import_job=self.import_job,
                is_processed=False
            ).values_list('id', flat=True)
        )

        total_records = len(raw_record_ids)
        logger.info(f"Collected {total_records:,} unprocessed record IDs upfront (prevents queryset re-evaluation bug)")

        if total_records == 0:
            logger.info("No unprocessed records found. Normalization complete.")
            return

        logger.info(f"Processing in batches of {batch_size}...")

        for batch_start in range(0, total_records, batch_size):
            batch_ids = raw_record_ids[batch_start:batch_start + batch_size]
            batch = RawCatalogueOfLife.objects.filter(id__in=batch_ids)

            batch_num = (batch_start // batch_size) + 1
            total_batches = (total_records + batch_size - 1) // batch_size
            logger.info(f"Processing batch {batch_num}/{total_batches} (records {batch_start+1:,} to {min(batch_start+batch_size, total_records):,})")

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

            # Log progress every 10 batches
            if batch_num % 10 == 0 or batch_num == total_batches:
                logger.info(f"Progress: {self.stats['records_imported']:,} imported, {self.stats['records_failed']} failed")

        # Final summary
        logger.info("=" * 80)
        logger.info("NORMALIZATION COMPLETE")
        logger.info("=" * 80)
        logger.info(f"Total records processed: {total_records:,}")
        logger.info(f"Successfully imported: {self.stats['records_imported']:,}")
        logger.info(f"Failed: {self.stats['records_failed']}")

        if self.stats['errors']:
            logger.warning(f"First 10 errors:")
            for i, error in enumerate(self.stats['errors'][:10], 1):
                logger.warning(f"  {i}. Record {error['record_id']}: {error['error']}")
