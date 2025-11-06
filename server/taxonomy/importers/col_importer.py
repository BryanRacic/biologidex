# taxonomy/importers/col_importer.py
import csv
import os
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

    def download_data(self) -> str:
        """Download COL dataset"""
        logger.info("Fetching latest COL dataset info...")

        # Get latest dataset info
        response = requests.get(
            f"{self.API_BASE}/dataset",
            params={
                'offset': 0,
                'limit': 1,
                'origin': 'RELEASE',
                'sortBy': 'CREATED',
                'reverse': True
            }
        )
        response.raise_for_status()
        datasets = response.json()

        if not datasets.get('result'):
            raise ValueError("No COL datasets available")

        latest = datasets['result'][0]
        dataset_key = latest['key']
        self.import_job.version = latest.get('version', dataset_key)
        self.import_job.metadata = {
            'dataset_key': dataset_key,
            'created': latest.get('created'),
            'title': latest.get('title')
        }
        self.import_job.save()

        logger.info(f"Latest COL dataset: {dataset_key} (version {self.import_job.version})")

        # Download dataset (use .zip endpoint which redirects to actual file)
        download_url = f"{self.API_BASE}/dataset/{dataset_key}/export.zip"
        params = {'format': 'COLDP'}

        # Create download directory
        download_dir = os.path.join(settings.MEDIA_ROOT, 'taxonomy_imports')
        os.makedirs(download_dir, exist_ok=True)

        file_path = os.path.join(
            download_dir,
            f'col_{dataset_key}_{datetime.now().strftime("%Y%m%d")}.zip'
        )

        logger.info(f"Downloading dataset to {file_path}...")

        with requests.get(download_url, params=params, stream=True) as r:
            r.raise_for_status()
            total_size = int(r.headers.get('content-length', 0))
            downloaded = 0

            with open(file_path, 'wb') as f:
                for chunk in r.iter_content(chunk_size=8192):
                    f.write(chunk)
                    downloaded += len(chunk)

                    # Log progress every 100MB
                    if downloaded % (100 * 1024 * 1024) == 0:
                        progress = (downloaded / total_size * 100) if total_size > 0 else 0
                        logger.info(f"Download progress: {progress:.1f}% ({downloaded / (1024*1024):.1f}MB)")

        self.import_job.file_size_mb = os.path.getsize(file_path) / (1024 * 1024)
        self.import_job.save()

        logger.info(f"Download complete: {self.import_job.file_size_mb:.2f}MB")
        return file_path

    def parse_file(self, file_path: str):
        """Parse COL TSV files from zip"""
        import zipfile

        logger.info(f"Extracting zip file: {file_path}")

        with zipfile.ZipFile(file_path, 'r') as zip_ref:
            # Extract to temp directory
            extract_path = file_path.replace('.zip', '_extracted')
            os.makedirs(extract_path, exist_ok=True)
            zip_ref.extractall(extract_path)

            logger.info(f"Extracted to: {extract_path}")

            # Parse NameUsage.tsv
            nameusage_file = os.path.join(extract_path, 'NameUsage.tsv')
            if os.path.exists(nameusage_file):
                self._parse_nameusage(nameusage_file)
            else:
                logger.warning(f"NameUsage.tsv not found in {extract_path}")

            # TODO: Parse VernacularName.tsv and Distribution.tsv in future iterations

    def _parse_nameusage(self, file_path: str):
        """Parse NameUsage.tsv file"""
        logger.info(f"Parsing NameUsage.tsv from {file_path}...")

        batch_size = 5000
        batch = []

        with open(file_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f, delimiter='\t')

            for row in reader:
                self.stats['records_read'] += 1

                # Skip non-accepted names in initial import (reduces dataset size)
                status = row.get('col:status', '').lower()
                if status not in ['accepted', 'provisionally accepted']:
                    continue

                # Create raw record
                raw = RawCatalogueOfLife(
                    import_job=self.import_job,
                    col_id=row.get('col:ID', ''),
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

                # Bulk create when batch is full
                if len(batch) >= batch_size:
                    RawCatalogueOfLife.objects.bulk_create(batch)
                    batch = []

                    # Log progress every 50k records
                    if self.stats['records_read'] % 50000 == 0:
                        logger.info(f"Read {self.stats['records_read']} records...")

            # Create remaining records
            if batch:
                RawCatalogueOfLife.objects.bulk_create(batch)

        logger.info(f"Finished parsing: {self.stats['records_read']} records read, {RawCatalogueOfLife.objects.filter(import_job=self.import_job).count()} records imported to staging")

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
