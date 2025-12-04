# taxonomy/importers/col_importer.py
import csv
import os
import sys
import requests
import logging
from datetime import datetime
from django.conf import settings
from django.db import transaction
from .base import BaseImporter
from taxonomy.raw_models import RawCatalogueOfLife

logger = logging.getLogger(__name__)


class CatalogueOfLifeImporter(BaseImporter):
    """Importer for Catalogue of Life data"""

    API_BASE = "https://api.checklistbank.org"

    def run(self):
        """
        Override base run() to add parent ID linking step.

        The COL import requires a second pass after normalization to link:
        - Synonyms to their accepted names (via parentID)
        - Accepted taxa to their taxonomic parents (via parentID)
        """
        from django.utils import timezone

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

            # COL-specific: Link parent IDs after all records exist
            # This sets accepted_name FK for synonyms and parent FK for taxa
            self._link_parent_ids()

            # Finalize
            self.import_job.status = 'completed'
            self.import_job.completed_at = timezone.now()
            self.import_job.records_imported = self.stats['records_imported']
            self.import_job.records_failed = self.stats['records_failed']
            self.import_job.error_log = {'errors': self.stats['errors'][:100]}
            self.import_job.save()

            logger.info(f"Import job {self.import_job.id} completed: {self.stats['records_imported']} imported, {self.stats['records_failed']} failed")

        except Exception as e:
            logger.error(f"Import failed: {e}")
            self.import_job.status = 'failed'
            self.import_job.completed_at = timezone.now()
            self.import_job.error_log = {'fatal_error': str(e)}
            self.import_job.save()
            raise

    def download_data(self) -> str:
        """Download COL dataset"""
        logger.info("=" * 80)
        logger.info("STEP 1: Fetching latest COL base release info...")
        logger.info("=" * 80)

        # Get multiple recent base releases (not XR/extended releases)
        # Release types by origin:
        #   - 'release': Base releases (curated, expert-verified)
        #   - 'xrelease': XR/eXtended releases (base + programmatic additions)
        # Note: API sorting is inverted - reverse=False gives newest first
        # Note: Newest releases may not have exports ready yet, so we check top 5
        logger.info("Querying ChecklistBank API for recent base releases...")
        response = requests.get(
            f"{self.API_BASE}/dataset",
            params={
                'offset': 0,
                'limit': 5,  # Get top 5 to find one with available export
                'origin': 'release',  # lowercase 'release' for base releases
                'sortBy': 'CREATED',
                'reverse': False  # False gives newest first (API quirk)
            }
        )
        response.raise_for_status()
        datasets = response.json()

        if not datasets.get('result'):
            raise ValueError("No COL base release datasets available")

        logger.info(f"Found {len(datasets['result'])} recent base releases")

        # Find the latest dataset with an available export
        dataset_key = None
        dataset_meta = None
        params = {
            'format': 'ColDP',      # Case-sensitive! Must be 'ColDP' not 'COLDP'
            'extended': 'true'      # Required for full ColDP format with NameUsage.tsv
        }

        for i, dataset in enumerate(datasets['result'], 1):
            key = dataset['key']
            version = dataset.get('version', 'unknown')
            logger.info(f"Checking dataset {i}/5: {key} (version {version})")

            # Check if export is available (HEAD request)
            check_url = f"{self.API_BASE}/dataset/{key}/export.zip"
            try:
                check_response = requests.head(check_url, params=params, allow_redirects=True, timeout=10)
                if check_response.status_code == 200:
                    dataset_key = key
                    dataset_meta = dataset
                    logger.info(f"✓ Found dataset with available export: {key} (version {version})")
                    break
                else:
                    logger.warning(f"✗ Dataset {key} export not available (HTTP {check_response.status_code})")
            except requests.RequestException as e:
                logger.warning(f"✗ Failed to check export for dataset {key}: {e}")
                continue

        if not dataset_key:
            raise ValueError("No COL base release with available export found in recent releases")

        self.import_job.version = dataset_meta.get('version', str(dataset_key))
        self.import_job.metadata = {
            'dataset_key': dataset_key,
            'created': dataset_meta.get('created'),
            'title': dataset_meta.get('title'),
            'version': dataset_meta.get('version'),
            'doi': dataset_meta.get('doi'),
            'size': dataset_meta.get('size'),
            'origin': dataset_meta.get('origin')
        }
        self.import_job.save()

        logger.info(f"Selected dataset: {dataset_meta.get('title', 'Unknown')}")
        logger.info(f"Version: {self.import_job.version}")
        logger.info(f"DOI: {dataset_meta.get('doi', 'N/A')}")

        # Download dataset (use .zip endpoint which redirects to actual file)
        download_url = f"{self.API_BASE}/dataset/{dataset_key}/export.zip"

        # Create download directory
        download_dir = os.path.join(settings.MEDIA_ROOT, 'taxonomy_imports')
        os.makedirs(download_dir, exist_ok=True)

        file_path = os.path.join(
            download_dir,
            f'col_{dataset_key}_{datetime.now().strftime("%Y%m%d")}.zip'
        )

        # Check if file already exists locally
        if os.path.exists(file_path):
            logger.info(f"Found existing file: {file_path}")
            logger.info(f"File size: {os.path.getsize(file_path) / (1024*1024):.2f}MB")
            logger.info("Validating existing file...")

            # Try to validate existing file
            import zipfile
            try:
                with zipfile.ZipFile(file_path, 'r') as zf:
                    bad_file = zf.testzip()
                    if bad_file:
                        logger.warning(f"Existing file is corrupted (bad file: {bad_file}), will re-download")
                        os.remove(file_path)
                    else:
                        logger.info("✓ Existing file validated successfully, reusing it")
                        self.import_job.file_size_mb = os.path.getsize(file_path) / (1024 * 1024)
                        self.import_job.save()
                        return file_path
            except zipfile.BadZipFile as e:
                logger.warning(f"Existing file is not a valid zip ({e}), will re-download")
                os.remove(file_path)

        # Download the file
        logger.info("=" * 80)
        logger.info("STEP 2: Downloading dataset...")
        logger.info("=" * 80)
        logger.info(f"URL: {download_url}")
        logger.info(f"Destination: {file_path}")

        with requests.get(download_url, params=params, stream=True, allow_redirects=True) as r:
            r.raise_for_status()
            total_size = int(r.headers.get('content-length', 0))
            downloaded = 0
            last_log_mb = 0

            logger.info(f"Total size: {total_size / (1024*1024):.2f}MB")
            logger.info("Starting download...")

            with open(file_path, 'wb') as f:
                for chunk in r.iter_content(chunk_size=8192):
                    f.write(chunk)
                    downloaded += len(chunk)

                    # Log progress every 50MB
                    downloaded_mb = downloaded / (1024 * 1024)
                    if downloaded_mb - last_log_mb >= 50:
                        progress = (downloaded / total_size * 100) if total_size > 0 else 0
                        logger.info(f"Progress: {progress:.1f}% ({downloaded_mb:.1f}MB / {total_size/(1024*1024):.1f}MB)")
                        last_log_mb = downloaded_mb

        self.import_job.file_size_mb = os.path.getsize(file_path) / (1024 * 1024)
        self.import_job.save()

        logger.info(f"✓ Download complete: {self.import_job.file_size_mb:.2f}MB")

        # Verify zip integrity
        logger.info("=" * 80)
        logger.info("STEP 3: Verifying zip integrity...")
        logger.info("=" * 80)
        import zipfile
        try:
            with zipfile.ZipFile(file_path, 'r') as zf:
                bad_file = zf.testzip()
                if bad_file:
                    raise ValueError(f"Corrupted file in archive: {bad_file}")
                logger.info(f"Archive contains {len(zf.namelist())} files")
        except zipfile.BadZipFile as e:
            raise ValueError(f"Downloaded file is not a valid zip: {e}")

        logger.info("✓ Zip integrity verified successfully")
        return file_path

    def parse_file(self, file_path: str):
        """Parse COL TSV files from zip"""
        import zipfile

        logger.info("=" * 80)
        logger.info("STEP 4: Extracting archive...")
        logger.info("=" * 80)
        logger.info(f"Source: {file_path}")

        extract_path = file_path.replace('.zip', '_extracted')

        # Check if already extracted
        if os.path.exists(extract_path):
            logger.info(f"Found existing extracted directory: {extract_path}")
            logger.info("Reusing existing extraction")
        else:
            with zipfile.ZipFile(file_path, 'r') as zip_ref:
                file_list = zip_ref.namelist()
                logger.info(f"Archive contains {len(file_list)} files")
                logger.info("Extracting files...")

                os.makedirs(extract_path, exist_ok=True)
                zip_ref.extractall(extract_path)

            logger.info(f"✓ Extracted to: {extract_path}")

        # Validate ColDP structure
        logger.info("=" * 80)
        logger.info("STEP 5: Validating ColDP structure...")
        logger.info("=" * 80)
        self._validate_coldp_structure(extract_path)
        logger.info("✓ ColDP structure validated successfully")

        # Parse NameUsage.tsv
        logger.info("=" * 80)
        logger.info("STEP 6: Parsing taxonomic data...")
        logger.info("=" * 80)
        nameusage_file = os.path.join(extract_path, 'NameUsage.tsv')
        if os.path.exists(nameusage_file):
            file_size_mb = os.path.getsize(nameusage_file) / (1024 * 1024)
            logger.info(f"NameUsage.tsv size: {file_size_mb:.2f}MB")
            self._parse_nameusage(nameusage_file)
        else:
            raise ValueError(f"NameUsage.tsv not found in {extract_path}")

        # Parse NameRelation.tsv if available
        namerelation_file = os.path.join(extract_path, 'NameRelation.tsv')
        if os.path.exists(namerelation_file):
            file_size_mb = os.path.getsize(namerelation_file) / (1024 * 1024)
            logger.info(f"NameRelation.tsv size: {file_size_mb:.2f}MB")
            self._parse_namerelation(namerelation_file)
        else:
            logger.warning("NameRelation.tsv not found - synonym relationships will not be imported")

        # Parse VernacularName.tsv if available
        vernacular_file = os.path.join(extract_path, 'VernacularName.tsv')
        if os.path.exists(vernacular_file):
            file_size_mb = os.path.getsize(vernacular_file) / (1024 * 1024)
            logger.info(f"VernacularName.tsv size: {file_size_mb:.2f}MB")
            self._parse_vernacular_names(vernacular_file)
        else:
            logger.warning("VernacularName.tsv not found - common names will not be imported")

        # TODO: Parse Distribution.tsv in future iterations

    def _validate_coldp_structure(self, extract_path: str):
        """Validate that extracted directory has required ColDP files"""
        required_files = ['metadata.yaml', 'NameUsage.tsv']

        for filename in required_files:
            filepath = os.path.join(extract_path, filename)
            if not os.path.exists(filepath):
                raise ValueError(f"Missing required ColDP file: {filename}")

        logger.info(f"Found all required files: {', '.join(required_files)}")

    def _parse_nameusage(self, file_path: str):
        """Parse NameUsage.tsv file"""
        logger.info(f"Parsing NameUsage.tsv from {file_path}...")

        # Increase CSV field size limit to handle large text fields
        # Some COL records have very large remarks/descriptions that exceed the default 131072 byte limit
        maxInt = sys.maxsize
        while True:
            try:
                csv.field_size_limit(maxInt)
                break
            except OverflowError:
                maxInt = int(maxInt / 10)

        logger.info(f"Set CSV field size limit to {maxInt} bytes")

        batch_size = 5000
        batch = []

        # Initialize error tracking
        if 'records_errored' not in self.stats:
            self.stats['records_errored'] = 0

        error_log = []  # Store errors for summary
        accepted_count = 0
        last_log_count = 0

        logger.info("Starting to read NameUsage.tsv...")
        logger.info("Importing ALL taxonomic records (no status filter)")

        with open(file_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f, delimiter='\t')

            for row_num, row in enumerate(reader, start=2):  # Start at 2 (1 is header)
                self.stats['records_read'] += 1

                try:
                    # REMOVED: Status filter that was skipping synonyms and other non-accepted names
                    # This ensures all taxonomic records are imported, including synonyms which are
                    # important for species identification and taxonomic relationships

                    # Get ID for error logging
                    col_id = row.get('col:ID', 'UNKNOWN')

                    # Create raw record
                    raw = RawCatalogueOfLife(
                        import_job=self.import_job,
                        col_id=col_id,
                        parent_id=row.get('col:parentID', ''),
                        status=row.get('col:status', ''),
                        rank=row.get('col:rank', ''),
                        scientific_name=row.get('col:scientificName', ''),
                        authorship=row.get('col:authorship', ''),
                        kingdom=row.get('col:kingdom', ''),
                        phylum=row.get('col:phylum', ''),
                        class_name=row.get('col:class', ''),
                        order=row.get('col:order', ''),
                        family=row.get('col:family', ''),
                        subfamily=row.get('col:subfamily', ''),
                        tribe=row.get('col:tribe', ''),
                        genus=row.get('col:genus', ''),
                        subgenus=row.get('col:subgenus', ''),
                        species=row.get('col:species', ''),
                        subspecies=row.get('col:subspecies', ''),
                        variety=row.get('col:variety', ''),
                        form=row.get('col:form', ''),
                        generic_name=row.get('col:genericName', ''),
                        specific_epithet=row.get('col:specificEpithet', ''),
                        infraspecific_epithet=row.get('col:infraspecificEpithet', ''),
                        code=row.get('col:code', ''),
                        extinct=row.get('col:extinct', ''),
                        environment=row.get('col:environment', '')
                    )
                    batch.append(raw)
                    accepted_count += 1

                    # Bulk create when batch is full
                    if len(batch) >= batch_size:
                        try:
                            RawCatalogueOfLife.objects.bulk_create(batch)
                        except Exception as e:
                            # If bulk create fails, try one by one to identify problematic record
                            logger.warning(f"Bulk create failed, attempting individual inserts for batch...")
                            for individual_raw in batch:
                                try:
                                    individual_raw.save()
                                except Exception as individual_e:
                                    self.stats['records_errored'] += 1
                                    error_msg = f"Row {row_num}, ID {individual_raw.col_id}: {str(individual_e)[:100]}"
                                    error_log.append(error_msg)
                                    logger.error(f"Failed to save record: {error_msg}")

                        batch = []

                        # Log progress every 10k accepted records
                        if accepted_count - last_log_count >= 10000:
                            logger.info(
                                f"Progress: Read {self.stats['records_read']:,} rows, "
                                f"Imported {accepted_count:,} records, "
                                f"Errors {self.stats['records_errored']}"
                            )
                            last_log_count = accepted_count

                except Exception as e:
                    # Log error but continue processing
                    self.stats['records_errored'] += 1
                    col_id = row.get('col:ID', 'UNKNOWN')
                    error_msg = f"Row {row_num}, ID {col_id}: {str(e)[:100]}"
                    error_log.append(error_msg)
                    logger.error(f"Error processing record: {error_msg}")
                    continue

            # Create remaining records
            if batch:
                try:
                    RawCatalogueOfLife.objects.bulk_create(batch)
                except Exception as e:
                    logger.warning(f"Final bulk create failed, attempting individual inserts...")
                    for individual_raw in batch:
                        try:
                            individual_raw.save()
                        except Exception as individual_e:
                            self.stats['records_errored'] += 1
                            error_msg = f"ID {individual_raw.col_id}: {str(individual_e)[:100]}"
                            error_log.append(error_msg)
                            logger.error(f"Failed to save record: {error_msg}")

        # Final statistics
        imported_count = RawCatalogueOfLife.objects.filter(import_job=self.import_job).count()

        logger.info("=" * 80)
        logger.info("PARSING COMPLETE")
        logger.info("=" * 80)
        logger.info(f"Total rows read:           {self.stats['records_read']:,}")
        logger.info(f"Records imported:          {accepted_count:,}")
        logger.info(f"Errored records:           {self.stats['records_errored']}")
        logger.info(f"Successfully saved to DB:  {imported_count:,}")

        if error_log:
            logger.warning("=" * 80)
            logger.warning(f"ERRORS ENCOUNTERED: {len(error_log)}")
            logger.warning("=" * 80)
            if len(error_log) <= 20:
                for error in error_log:
                    logger.warning(f"  - {error}")
            else:
                logger.warning(f"Showing first 20 errors (total: {len(error_log)}):")
                for error in error_log[:20]:
                    logger.warning(f"  - {error}")
                logger.warning(f"... and {len(error_log) - 20} more errors")

        logger.info("✓ Parsing completed successfully")

    def _parse_namerelation(self, file_path: str):
        """Parse NameRelation.tsv file for synonym relationships"""
        from taxonomy.models import Taxonomy, NameRelation

        logger.info("=" * 80)
        logger.info("STEP 7: Parsing name relationships...")
        logger.info("=" * 80)
        logger.info(f"Parsing NameRelation.tsv from {file_path}...")

        # Create lookup dict for COL IDs to Taxonomy objects
        logger.info("Building taxonomy ID lookup...")
        taxonomy_by_col_id = {}
        for tax in Taxonomy.objects.filter(source=self.source).select_related('source'):
            taxonomy_by_col_id[tax.source_taxon_id] = tax
        logger.info(f"Loaded {len(taxonomy_by_col_id)} taxonomy records for lookup")

        batch_size = 1000
        batch = []
        imported_count = 0
        skipped_count = 0
        error_count = 0
        last_log_count = 0

        logger.info("Starting to read NameRelation.tsv...")

        with open(file_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f, delimiter='\t')

            for row_num, row in enumerate(reader, start=2):
                try:
                    name_id = row.get('col:nameID', '')
                    related_name_id = row.get('col:relatedNameID', '')
                    relation_type = row.get('col:type', '')

                    # Skip if missing required fields
                    if not name_id or not related_name_id or not relation_type:
                        skipped_count += 1
                        continue

                    # Look up both taxonomy objects
                    name_tax = taxonomy_by_col_id.get(name_id)
                    related_tax = taxonomy_by_col_id.get(related_name_id)

                    if not name_tax or not related_tax:
                        # One or both IDs not in our taxonomy table - skip
                        skipped_count += 1
                        continue

                    # Create NameRelation object
                    relation = NameRelation(
                        name=name_tax,
                        related_name=related_tax,
                        relation_type=relation_type,
                        col_name_id=name_id,
                        col_related_name_id=related_name_id,
                        col_source_id=row.get('col:sourceID', ''),
                        reference_id=row.get('col:referenceID', ''),
                        page=row.get('col:page', ''),
                        remarks=row.get('col:remarks', ''),
                        source=self.source,
                        import_job=self.import_job
                    )
                    batch.append(relation)
                    imported_count += 1

                    # Bulk create when batch is full
                    if len(batch) >= batch_size:
                        try:
                            NameRelation.objects.bulk_create(batch, ignore_conflicts=True)
                        except Exception as e:
                            logger.error(f"Bulk create failed: {e}")
                            error_count += len(batch)
                        batch = []

                        # Log progress every 10k records
                        if imported_count - last_log_count >= 10000:
                            logger.info(
                                f"Progress: Imported {imported_count:,} relationships, "
                                f"Skipped {skipped_count:,}, Errors {error_count}"
                            )
                            last_log_count = imported_count

                except Exception as e:
                    error_count += 1
                    logger.error(f"Error processing row {row_num}: {str(e)[:100]}")
                    continue

            # Create remaining records
            if batch:
                try:
                    NameRelation.objects.bulk_create(batch, ignore_conflicts=True)
                except Exception as e:
                    logger.error(f"Final bulk create failed: {e}")
                    error_count += len(batch)

        # Final statistics
        final_count = NameRelation.objects.filter(import_job=self.import_job).count()

        logger.info("=" * 80)
        logger.info("NAME RELATION PARSING COMPLETE")
        logger.info("=" * 80)
        logger.info(f"Relationships imported:    {imported_count:,}")
        logger.info(f"Skipped (missing refs):    {skipped_count:,}")
        logger.info(f"Errors:                    {error_count}")
        logger.info(f"Successfully saved to DB:  {final_count:,}")
        logger.info("✓ Name relationship parsing completed successfully")

    def _parse_vernacular_names(self, file_path: str):
        """Parse VernacularName.tsv file for common names"""
        from taxonomy.models import Taxonomy, CommonName

        logger.info("=" * 80)
        logger.info("STEP 8: Parsing vernacular names...")
        logger.info("=" * 80)
        logger.info(f"Parsing VernacularName.tsv from {file_path}...")

        # Create lookup dict for COL IDs to Taxonomy objects
        logger.info("Building taxonomy ID lookup...")
        taxonomy_by_col_id = {}
        for tax in Taxonomy.objects.filter(source=self.source).select_related('source'):
            taxonomy_by_col_id[tax.source_taxon_id] = tax
        logger.info(f"Loaded {len(taxonomy_by_col_id)} taxonomy records for lookup")

        batch_size = 1000
        batch = []
        imported_count = 0
        skipped_count = 0
        error_count = 0
        last_log_count = 0

        logger.info("Starting to read VernacularName.tsv...")

        with open(file_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f, delimiter='\t')

            for row_num, row in enumerate(reader, start=2):
                try:
                    taxon_id = row.get('col:taxonID', '')
                    name = row.get('col:name', '').strip()
                    language = row.get('col:language', 'en').strip()  # Default to English
                    country = row.get('col:country', '').strip()

                    # Skip if missing required fields
                    if not taxon_id or not name:
                        skipped_count += 1
                        continue

                    # Look up taxonomy object
                    taxonomy = taxonomy_by_col_id.get(taxon_id)
                    if not taxonomy:
                        # Taxon ID not in our taxonomy table - skip
                        skipped_count += 1
                        continue

                    # Parse preferred status
                    is_preferred = False
                    preferred_raw = row.get('col:preferred', '').strip().lower()
                    if preferred_raw in ('true', '1', 'yes', 't'):
                        is_preferred = True

                    # Normalize language code (truncate to 10 chars max)
                    if len(language) > 10:
                        language = language[:10]

                    # Normalize country code (truncate to 2 chars max)
                    if len(country) > 2:
                        country = country[:2].upper()

                    # Create CommonName object
                    common_name = CommonName(
                        taxonomy=taxonomy,
                        name=name,
                        language=language,
                        country=country,
                        is_preferred=is_preferred,
                        source=self.source
                    )
                    batch.append(common_name)
                    imported_count += 1

                    # Bulk create when batch is full
                    if len(batch) >= batch_size:
                        try:
                            CommonName.objects.bulk_create(batch, ignore_conflicts=True)
                        except Exception as e:
                            logger.error(f"Bulk create failed: {e}")
                            error_count += len(batch)
                        batch = []

                        # Log progress every 10k records
                        if imported_count - last_log_count >= 10000:
                            logger.info(
                                f"Progress: Imported {imported_count:,} common names, "
                                f"Skipped {skipped_count:,}, Errors {error_count}"
                            )
                            last_log_count = imported_count

                except Exception as e:
                    error_count += 1
                    logger.error(f"Error processing row {row_num}: {str(e)[:100]}")
                    continue

            # Create remaining records
            if batch:
                try:
                    CommonName.objects.bulk_create(batch, ignore_conflicts=True)
                except Exception as e:
                    logger.error(f"Final bulk create failed: {e}")
                    error_count += len(batch)

        # Final statistics
        final_count = CommonName.objects.filter(source=self.source).count()

        logger.info("=" * 80)
        logger.info("VERNACULAR NAME PARSING COMPLETE")
        logger.info("=" * 80)
        logger.info(f"Common names imported:     {imported_count:,}")
        logger.info(f"Skipped (missing refs):    {skipped_count:,}")
        logger.info(f"Errors:                    {error_count}")
        logger.info(f"Successfully saved to DB:  {final_count:,}")
        logger.info("✓ Vernacular name parsing completed successfully")

    def validate_record(self, record):
        """Validate COL record"""
        if not record.scientific_name:
            return False, "Missing scientific name"
        if not record.col_id:
            return False, "Missing COL ID"
        return True, None

    def transform_record(self, raw_record):
        """Transform raw COL record to normalized taxonomy"""
        # Parse environment field
        environments = []
        if raw_record.environment:
            env_map = {
                'marine': 'marine',
                'terrestrial': 'terrestrial',
                'freshwater': 'freshwater',
                'brackish': 'marine'
            }
            for env in raw_record.environment.split(','):
                env_lower = env.strip().lower()
                if env_lower in env_map:
                    mapped = env_map[env_lower]
                    if mapped not in environments:
                        environments.append(mapped)

        # Build source URL
        source_url = f"https://www.catalogueoflife.org/data/taxon/{raw_record.col_id}"

        # Calculate completeness score
        fields = [
            raw_record.kingdom, raw_record.phylum, raw_record.class_name,
            raw_record.order, raw_record.family, raw_record.genus
        ]
        completeness = sum(1 for f in fields if f) / len(fields)

        return {
            'source_taxon_id': raw_record.col_id,
            'import_job': self.import_job,
            'scientific_name': raw_record.scientific_name,
            'authorship': raw_record.authorship,
            'status': self._map_status(raw_record.status),
            'kingdom': raw_record.kingdom,
            'phylum': raw_record.phylum,
            'class_name': raw_record.class_name,
            'order': raw_record.order,
            'family': raw_record.family,
            'subfamily': raw_record.subfamily,
            'tribe': raw_record.tribe,
            'genus': raw_record.genus,
            'subgenus': raw_record.subgenus,
            'species': raw_record.species,
            'subspecies': raw_record.subspecies,
            'variety': raw_record.variety,
            'form': raw_record.form,
            'generic_name': raw_record.generic_name,
            'specific_epithet': raw_record.specific_epithet,
            'infraspecific_epithet': raw_record.infraspecific_epithet,
            'nomenclatural_code': self._map_code(raw_record.code),
            'extinct': raw_record.extinct.lower() == 'true' if raw_record.extinct else None,
            'environment': environments,
            'source_url': source_url,
            'completeness_score': completeness,
        }

    def _map_status(self, col_status):
        """Map COL status to our status values"""
        status_map = {
            'accepted': 'accepted',
            'provisionally accepted': 'provisional',
            'synonym': 'synonym',
            'ambiguous synonym': 'ambiguous',
            'misapplied': 'misapplied'
        }
        return status_map.get(col_status.lower(), 'doubtful')

    def _map_code(self, col_code):
        """Map COL nomenclatural code"""
        if not col_code:
            return ''

        code_map = {
            'botanical': 'icn',
            'zoological': 'iczn',
            'virus': 'ictv',
            'bacterial': 'icnp'
        }
        return code_map.get(col_code.lower(), '')

    def _link_parent_ids(self):
        """
        Second pass: Link parentID references after all records are created.

        Per ColDP spec (https://github.com/CatalogueOfLife/coldp):
        - For synonyms: parentID points to the accepted taxon
        - For accepted taxa: parentID points to the taxonomic parent

        This MUST run after normalize_data() since parent records may not exist
        when child records are processed in the first pass.

        Uses memory-efficient approach:
        - Stores only IDs in lookup dict (not full ORM objects)
        - Uses raw SQL with temp tables for bulk updates
        """
        from django.db import connection
        from taxonomy.raw_models import RawCatalogueOfLife

        logger.info("=" * 80)
        logger.info("STEP: LINKING PARENT IDs (synonyms → accepted names)")
        logger.info("=" * 80)

        # Build lookup of COL ID → taxonomy_id (IDs only, not full objects)
        logger.info("Building COL ID → Taxonomy ID lookup...")
        taxonomy_by_col_id = {}
        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT source_taxon_id, id
                FROM taxonomy_taxonomy
                WHERE source_id = %s
            """, [self.source.id])

            loaded = 0
            while True:
                rows = cursor.fetchmany(50000)
                if not rows:
                    break
                for row in rows:
                    taxonomy_by_col_id[row[0]] = row[1]
                loaded += len(rows)
                if loaded % 1000000 == 0:
                    logger.info(f"  Loaded {loaded:,} records...")

        logger.info(f"Loaded {len(taxonomy_by_col_id):,} taxonomy records for lookup")

        # Process raw records that have parent_id set
        logger.info("Finding records with parent_id to link...")
        raw_records_with_parent = RawCatalogueOfLife.objects.filter(
            import_job=self.import_job,
            is_processed=True
        ).exclude(parent_id='').values('col_id', 'parent_id', 'status')

        total_count = raw_records_with_parent.count()
        logger.info(f"Found {total_count:,} records with parent_id to process")

        # Collect updates as tuples (much more memory efficient than ORM objects)
        synonym_updates = []  # [(tax_id, accepted_tax_id), ...]
        parent_updates = []   # [(tax_id, parent_tax_id), ...]
        not_found_count = 0
        processed = 0
        last_log = 0

        for raw in raw_records_with_parent.iterator(chunk_size=10000):
            col_id = raw['col_id']
            parent_id = raw['parent_id']
            status = raw['status']

            # Get the taxonomy ID for this col_id
            tax_id = taxonomy_by_col_id.get(col_id)
            if not tax_id:
                not_found_count += 1
                continue

            # Get the parent/accepted taxonomy ID
            parent_tax_id = taxonomy_by_col_id.get(parent_id)
            if not parent_tax_id:
                not_found_count += 1
                continue

            # Collect update based on status
            if status.lower() == 'synonym':
                synonym_updates.append((tax_id, parent_tax_id))
            else:
                parent_updates.append((tax_id, parent_tax_id))

            processed += 1

            # Log progress every 500k records
            if processed - last_log >= 500000:
                logger.info(
                    f"Progress: {processed:,}/{total_count:,} scanned, "
                    f"synonyms: {len(synonym_updates):,}, "
                    f"parents: {len(parent_updates):,}"
                )
                last_log = processed

        logger.info(f"Scan complete: {processed:,} records processed")
        logger.info(f"Synonyms to link: {len(synonym_updates):,}")
        logger.info(f"Parents to link: {len(parent_updates):,}")

        # Apply updates using efficient temp table approach
        chunk_size = 10000

        if synonym_updates:
            logger.info(f"Linking {len(synonym_updates):,} synonyms to accepted names...")
            self._bulk_update_fk(synonym_updates, 'accepted_name_id', chunk_size)

        if parent_updates:
            logger.info(f"Linking {len(parent_updates):,} taxa to parents...")
            self._bulk_update_fk(parent_updates, 'parent_id', chunk_size)

        # Final statistics
        logger.info("=" * 80)
        logger.info("PARENT ID LINKING COMPLETE")
        logger.info("=" * 80)
        logger.info(f"Total processed:       {processed:,}")
        logger.info(f"Synonyms → accepted:   {len(synonym_updates):,}")
        logger.info(f"Taxa → parent:         {len(parent_updates):,}")
        logger.info(f"Not found (skipped):   {not_found_count:,}")
        logger.info("✓ Parent ID linking completed successfully")

    def _bulk_update_fk(self, updates, field_name, chunk_size):
        """Bulk update a foreign key field using temp table for efficiency."""
        from django.db import connection

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
                logger.info(f"  Progress: {updated:,}/{total:,}")

            # Clean up
            cursor.execute("DROP TABLE IF EXISTS _link_updates")
