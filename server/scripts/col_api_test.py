#!/usr/bin/env python3
"""
Catalogue of Life API Testing & Prototyping Script

This script provides functions to interact with the ChecklistBank API
and download COL datasets. Use this for rapid testing and troubleshooting.

API Documentation:
- Main API: https://api.checklistbank.org/
- OpenAPI Spec: https://api.checklistbank.org/openapi
- COL Website: https://www.catalogueoflife.org/

Usage:
    python col_api_test.py [--dataset-key 312578] [--format ColDP] [--extended]
"""

import argparse
import csv
import hashlib
import json
import logging
import os
import sys
import time
import zipfile
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional, List, Tuple
import requests


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(f'col_api_test_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log')
    ]
)
logger = logging.getLogger(__name__)


class ChecklistBankAPI:
    """Client for interacting with the ChecklistBank API"""

    BASE_URL = "https://api.checklistbank.org"

    # Available export formats
    FORMATS = {
        'ColDP': 'Catalogue of Life Data Package (recommended)',
        'DWCA': 'Darwin Core Archive',
        'ACEF': 'Annual Checklist Exchange Format',
        'TEXT_TREE': 'Simple indented text format',
        'NEWICK': 'Graph-theoretical tree format',
        'DOT': 'Graphviz dot format'
    }

    def __init__(self, timeout: int = 300):
        """
        Initialize the API client

        Args:
            timeout: Request timeout in seconds (default 300 = 5 minutes)
        """
        self.timeout = timeout
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'BiologiDex-COL-Importer/1.0 (https://github.com/yourusername/biologidex)'
        })

    def get_datasets(
        self,
        limit: int = 10,
        offset: int = 0,
        origin: str = 'RELEASE',
        sort_by: str = 'CREATED',
        reverse: bool = True
    ) -> Dict:
        """
        Get list of datasets from ChecklistBank

        Args:
            limit: Number of results to return
            offset: Offset for pagination
            origin: Filter by origin (RELEASE, EXTERNAL, etc.)
            sort_by: Sort field (CREATED, TITLE, KEY, etc.)
            reverse: Sort in reverse order (newest first)

        Returns:
            Dict with 'result', 'total', 'offset', 'limit' keys
        """
        url = f"{self.BASE_URL}/dataset"
        params = {
            'limit': limit,
            'offset': offset,
            'origin': origin,
            'sortBy': sort_by,
            'reverse': str(reverse).lower()
        }

        logger.info(f"Fetching datasets from {url}")
        logger.debug(f"Parameters: {params}")

        response = self.session.get(url, params=params, timeout=self.timeout)
        response.raise_for_status()

        data = response.json()
        logger.info(f"Found {data.get('total', 0)} total datasets")

        return data

    def get_latest_col_release(self) -> Dict:
        """
        Get the latest COL release dataset

        Returns:
            Dataset metadata dict
        """
        logger.info("Fetching latest COL release...")

        datasets = self.get_datasets(limit=1, origin='RELEASE')

        if not datasets.get('result'):
            raise ValueError("No COL release datasets found")

        latest = datasets['result'][0]
        logger.info(f"Latest COL release:")
        logger.info(f"  Key: {latest['key']}")
        logger.info(f"  Version: {latest.get('version', 'N/A')}")
        logger.info(f"  Title: {latest.get('title', 'N/A')}")
        logger.info(f"  DOI: {latest.get('doi', 'N/A')}")
        logger.info(f"  Created: {latest.get('created', 'N/A')}")
        logger.info(f"  Size: {latest.get('size', 0):,} records")

        return latest

    def get_dataset_metadata(self, dataset_key: int) -> Dict:
        """
        Get detailed metadata for a specific dataset

        Args:
            dataset_key: The dataset's integer key

        Returns:
            Dataset metadata dict
        """
        url = f"{self.BASE_URL}/dataset/{dataset_key}"
        logger.info(f"Fetching metadata for dataset {dataset_key}")

        response = self.session.get(url, timeout=self.timeout)
        response.raise_for_status()

        return response.json()

    def check_export_availability(
        self,
        dataset_key: int,
        format_type: str = 'ColDP',
        extended: bool = True
    ) -> Dict:
        """
        Check if export is available and get headers (doesn't download)

        Args:
            dataset_key: The dataset's integer key
            format_type: Export format (ColDP, DWCA, etc.)
            extended: Include extended data (XR additions)

        Returns:
            Dict with status info and headers
        """
        url = f"{self.BASE_URL}/dataset/{dataset_key}/export.zip"
        params = {
            'format': format_type,
            'extended': str(extended).lower()
        }

        logger.info(f"Checking export availability: {url}")
        logger.debug(f"Parameters: {params}")

        # Use HEAD request to check without downloading
        response = self.session.head(url, params=params, timeout=self.timeout, allow_redirects=True)

        info = {
            'url': url,
            'params': params,
            'status_code': response.status_code,
            'available': response.status_code == 200,
            'final_url': response.url,
            'content_type': response.headers.get('Content-Type'),
            'content_length': response.headers.get('Content-Length'),
            'content_disposition': response.headers.get('Content-Disposition'),
            'headers': dict(response.headers)
        }

        if info['content_length']:
            size_mb = int(info['content_length']) / (1024 * 1024)
            info['size_mb'] = round(size_mb, 2)
            logger.info(f"Export available: {size_mb:.2f} MB")
        else:
            logger.warning("Export availability unclear - no Content-Length header")

        return info

    def download_export(
        self,
        dataset_key: int,
        output_path: str,
        format_type: str = 'ColDP',
        extended: bool = True,
        chunk_size: int = 8192
    ) -> str:
        """
        Download dataset export

        Args:
            dataset_key: The dataset's integer key
            output_path: Where to save the file
            format_type: Export format (ColDP, DWCA, etc.)
            extended: Include extended data (XR additions)
            chunk_size: Download chunk size in bytes

        Returns:
            Path to downloaded file
        """
        url = f"{self.BASE_URL}/dataset/{dataset_key}/export.zip"
        params = {
            'format': format_type,
            'extended': str(extended).lower()
        }

        logger.info(f"Starting download from {url}")
        logger.debug(f"Parameters: {params}")
        logger.info(f"Output path: {output_path}")

        # Create output directory if needed
        os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)

        # Stream download
        start_time = time.time()
        response = self.session.get(
            url,
            params=params,
            stream=True,
            timeout=self.timeout,
            allow_redirects=True
        )
        response.raise_for_status()

        total_size = int(response.headers.get('content-length', 0))
        downloaded = 0
        last_log_mb = 0

        logger.info(f"Total size: {total_size / (1024*1024):.2f} MB")

        with open(output_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=chunk_size):
                if chunk:
                    f.write(chunk)
                    downloaded += len(chunk)

                    # Log progress every 100MB
                    current_mb = downloaded / (1024 * 1024)
                    if current_mb - last_log_mb >= 100:
                        if total_size > 0:
                            progress = (downloaded / total_size) * 100
                            logger.info(f"Download progress: {progress:.1f}% ({current_mb:.1f}MB)")
                        else:
                            logger.info(f"Downloaded: {current_mb:.1f}MB")
                        last_log_mb = current_mb

        elapsed = time.time() - start_time
        final_size_mb = downloaded / (1024 * 1024)
        speed_mbps = final_size_mb / elapsed if elapsed > 0 else 0

        logger.info(f"Download complete!")
        logger.info(f"  Size: {final_size_mb:.2f} MB")
        logger.info(f"  Time: {elapsed:.1f} seconds")
        logger.info(f"  Speed: {speed_mbps:.2f} MB/s")

        return output_path

    def verify_zip_integrity(self, zip_path: str) -> Tuple[bool, Optional[str]]:
        """
        Verify zip file integrity

        Args:
            zip_path: Path to zip file

        Returns:
            Tuple of (is_valid, error_message)
        """
        logger.info(f"Verifying zip integrity: {zip_path}")

        if not os.path.exists(zip_path):
            return False, f"File not found: {zip_path}"

        try:
            with zipfile.ZipFile(zip_path, 'r') as zf:
                # Test zip integrity
                bad_file = zf.testzip()
                if bad_file:
                    return False, f"Corrupted file in archive: {bad_file}"

                logger.info(f"✓ Zip integrity verified")
                return True, None

        except zipfile.BadZipFile as e:
            return False, f"Bad zip file: {e}"
        except Exception as e:
            return False, f"Error reading zip: {e}"

    def extract_and_validate(self, zip_path: str, extract_dir: Optional[str] = None) -> Dict:
        """
        Extract zip and validate contents

        Args:
            zip_path: Path to zip file
            extract_dir: Directory to extract to (default: zip_path without .zip)

        Returns:
            Dict with validation results and file information
        """
        logger.info(f"Extracting and validating: {zip_path}")

        # Verify integrity first
        is_valid, error = self.verify_zip_integrity(zip_path)
        if not is_valid:
            raise ValueError(f"Zip integrity check failed: {error}")

        # Determine extract directory
        if extract_dir is None:
            extract_dir = zip_path.replace('.zip', '_extracted')

        os.makedirs(extract_dir, exist_ok=True)
        logger.info(f"Extracting to: {extract_dir}")

        # Extract all files
        start_time = time.time()
        with zipfile.ZipFile(zip_path, 'r') as zf:
            file_list = zf.namelist()
            logger.info(f"Archive contains {len(file_list)} files")

            zf.extractall(extract_dir)

        elapsed = time.time() - start_time
        logger.info(f"Extraction complete in {elapsed:.1f} seconds")

        # Validate structure
        validation = self._validate_coldp_structure(extract_dir)
        validation['extract_dir'] = extract_dir
        validation['extraction_time'] = elapsed

        return validation

    def _validate_coldp_structure(self, extract_dir: str) -> Dict:
        """
        Validate ColDP (Catalogue of Life Data Package) structure

        Expected files:
        - metadata.yaml (required)
        - NameUsage.tsv (required - main taxonomy data)
        - VernacularName.tsv (optional - common names)
        - Distribution.tsv (optional - geographic distribution)
        - Reference.tsv (optional - bibliographic references)
        - TypeMaterial.tsv (optional - type specimens)
        - SpeciesEstimate.tsv (optional)
        - SpeciesInteraction.tsv (optional)
        - TaxonConceptRelation.tsv (optional)
        - TaxonProperty.tsv (optional)
        - NameRelation.tsv (optional)
        - Media.tsv (optional)
        - reference.json/jsonl/bib (optional - alternative reference formats)

        Args:
            extract_dir: Directory containing extracted files

        Returns:
            Dict with validation results
        """
        logger.info("Validating ColDP structure...")

        # Expected files
        required_files = ['metadata.yaml', 'NameUsage.tsv']
        optional_files = [
            'VernacularName.tsv',
            'Distribution.tsv',
            'Reference.tsv',
            'TypeMaterial.tsv',
            'SpeciesEstimate.tsv',
            'SpeciesInteraction.tsv',
            'TaxonConceptRelation.tsv',
            'TaxonProperty.tsv',
            'NameRelation.tsv',
            'Media.tsv',
            'reference.json',
            'reference.jsonl',
            'reference.bib',
            'logo.png'
        ]

        validation = {
            'valid': True,
            'errors': [],
            'warnings': [],
            'files_found': {},
            'files_missing': [],
            'metadata': None,
            'record_counts': {}
        }

        # Check for required files
        for filename in required_files:
            filepath = os.path.join(extract_dir, filename)
            if os.path.exists(filepath):
                size = os.path.getsize(filepath)
                validation['files_found'][filename] = {
                    'path': filepath,
                    'size': size,
                    'size_mb': round(size / (1024 * 1024), 2)
                }
                logger.info(f"✓ Found required file: {filename} ({validation['files_found'][filename]['size_mb']} MB)")
            else:
                validation['valid'] = False
                validation['errors'].append(f"Missing required file: {filename}")
                validation['files_missing'].append(filename)
                logger.error(f"✗ Missing required file: {filename}")

        # Check for optional files
        for filename in optional_files:
            filepath = os.path.join(extract_dir, filename)
            if os.path.exists(filepath):
                size = os.path.getsize(filepath)
                validation['files_found'][filename] = {
                    'path': filepath,
                    'size': size,
                    'size_mb': round(size / (1024 * 1024), 2)
                }
                logger.info(f"  Found optional file: {filename} ({validation['files_found'][filename]['size_mb']} MB)")

        # Parse metadata.yaml if present
        metadata_path = os.path.join(extract_dir, 'metadata.yaml')
        if os.path.exists(metadata_path):
            try:
                import yaml
                with open(metadata_path, 'r', encoding='utf-8') as f:
                    metadata = yaml.safe_load(f)
                    validation['metadata'] = {
                        'key': metadata.get('key'),
                        'doi': metadata.get('doi'),
                        'title': metadata.get('title'),
                        'alias': metadata.get('alias'),
                        'version': metadata.get('version'),
                        'issued': metadata.get('issued'),
                        'description': metadata.get('description', '')[:200]
                    }
                    logger.info(f"✓ Parsed metadata: {metadata.get('title')} ({metadata.get('version')})")
            except ImportError:
                validation['warnings'].append("PyYAML not installed, skipping metadata parsing")
                logger.warning("PyYAML not installed, skipping metadata parsing")
            except Exception as e:
                validation['warnings'].append(f"Error parsing metadata.yaml: {e}")
                logger.warning(f"Error parsing metadata.yaml: {e}")

        # Count records in TSV files
        for filename in validation['files_found']:
            if filename.endswith('.tsv'):
                try:
                    filepath = validation['files_found'][filename]['path']
                    with open(filepath, 'r', encoding='utf-8') as f:
                        # Count lines (subtract 1 for header)
                        line_count = sum(1 for _ in f) - 1
                        validation['record_counts'][filename] = line_count
                        logger.info(f"  {filename}: {line_count:,} records")
                except Exception as e:
                    validation['warnings'].append(f"Error counting records in {filename}: {e}")
                    logger.warning(f"Error counting records in {filename}: {e}")

        # Validate NameUsage.tsv structure
        nameusage_path = os.path.join(extract_dir, 'NameUsage.tsv')
        if os.path.exists(nameusage_path):
            try:
                with open(nameusage_path, 'r', encoding='utf-8') as f:
                    reader = csv.DictReader(f, delimiter='\t')
                    fieldnames = reader.fieldnames

                    # Expected core fields
                    expected_fields = ['col:ID', 'col:scientificName', 'col:rank', 'col:status']
                    missing_fields = [f for f in expected_fields if f not in fieldnames]

                    if missing_fields:
                        validation['errors'].append(f"NameUsage.tsv missing expected fields: {missing_fields}")
                        validation['valid'] = False
                        logger.error(f"✗ NameUsage.tsv missing fields: {missing_fields}")
                    else:
                        logger.info(f"✓ NameUsage.tsv has all expected core fields")

                    validation['nameusage_fields'] = fieldnames
                    logger.info(f"  NameUsage.tsv has {len(fieldnames)} columns")

            except Exception as e:
                validation['errors'].append(f"Error validating NameUsage.tsv structure: {e}")
                logger.error(f"✗ Error validating NameUsage.tsv: {e}")

        # Check for unexpected directory structure
        extracted_items = os.listdir(extract_dir)
        if len(extracted_items) == 1 and os.path.isdir(os.path.join(extract_dir, extracted_items[0])):
            # Files are in a subdirectory - common issue
            subdir = os.path.join(extract_dir, extracted_items[0])
            validation['warnings'].append(f"Files extracted to subdirectory: {extracted_items[0]}")
            validation['actual_data_dir'] = subdir
            logger.warning(f"⚠ Files are in subdirectory: {extracted_items[0]}")
            logger.warning(f"⚠ Actual data location: {subdir}")

        # Summary
        logger.info(f"\n{'='*60}")
        logger.info(f"Validation Summary:")
        logger.info(f"  Valid: {validation['valid']}")
        logger.info(f"  Files found: {len(validation['files_found'])}")
        logger.info(f"  Errors: {len(validation['errors'])}")
        logger.info(f"  Warnings: {len(validation['warnings'])}")
        if validation['record_counts']:
            total_records = sum(validation['record_counts'].values())
            logger.info(f"  Total records: {total_records:,}")
        logger.info(f"{'='*60}\n")

        return validation

    def calculate_file_hash(self, filepath: str, algorithm: str = 'sha256') -> str:
        """
        Calculate hash of a file

        Args:
            filepath: Path to file
            algorithm: Hash algorithm (md5, sha1, sha256)

        Returns:
            Hex digest string
        """
        hash_obj = hashlib.new(algorithm)
        with open(filepath, 'rb') as f:
            for chunk in iter(lambda: f.read(8192), b''):
                hash_obj.update(chunk)
        return hash_obj.hexdigest()

    def get_archive_info(self, dataset_key: int, attempt: Optional[int] = None) -> Dict:
        """
        Get archive metadata (import attempt information)

        Args:
            dataset_key: The dataset's integer key
            attempt: Specific import attempt number (None = latest)

        Returns:
            Archive metadata dict
        """
        url = f"{self.BASE_URL}/dataset/{dataset_key}/archive"
        params = {}
        if attempt is not None:
            params['attempt'] = attempt

        logger.info(f"Fetching archive info for dataset {dataset_key}")
        if attempt:
            logger.info(f"  Attempt: {attempt}")

        response = self.session.head(url, params=params, timeout=self.timeout)

        return {
            'status_code': response.status_code,
            'available': response.status_code == 200,
            'headers': dict(response.headers)
        }


def print_dataset_info(dataset: Dict):
    """Pretty print dataset information"""
    print("\n" + "=" * 80)
    print("DATASET INFORMATION")
    print("=" * 80)
    print(f"Key:         {dataset.get('key')}")
    print(f"Title:       {dataset.get('title')}")
    print(f"Version:     {dataset.get('version', 'N/A')}")
    print(f"Alias:       {dataset.get('alias', 'N/A')}")
    print(f"DOI:         {dataset.get('doi', 'N/A')}")
    print(f"Created:     {dataset.get('created', 'N/A')}")
    print(f"Size:        {dataset.get('size', 0):,} records")
    print(f"Origin:      {dataset.get('origin', 'N/A')}")
    print(f"Type:        {dataset.get('type', 'N/A')}")

    if dataset.get('description'):
        print(f"\nDescription:")
        desc = dataset['description']
        if len(desc) > 300:
            desc = desc[:300] + "..."
        print(f"  {desc}")
    print("=" * 80 + "\n")


def test_api_endpoints(dataset_key: int = 312578, download_and_validate: bool = False):
    """
    Run comprehensive tests on API endpoints

    Args:
        dataset_key: Dataset key to test (default: 312578 = latest COL XR release)
        download_and_validate: If True, actually download and validate the dataset
    """
    print("\n" + "=" * 80)
    print("CATALOGUE OF LIFE API TEST SUITE")
    print("=" * 80 + "\n")

    api = ChecklistBankAPI()

    # Test 1: Get latest release
    print("\n[TEST 1] Fetching latest COL release...")
    try:
        latest = api.get_latest_col_release()
        print("✓ SUCCESS")
        print_dataset_info(latest)
    except Exception as e:
        print(f"✗ FAILED: {e}")
        logger.exception("Test 1 failed")
        return

    # Test 2: Get specific dataset metadata
    print(f"\n[TEST 2] Fetching metadata for dataset {dataset_key}...")
    try:
        metadata = api.get_dataset_metadata(dataset_key)
        print("✓ SUCCESS")
        print_dataset_info(metadata)
    except Exception as e:
        print(f"✗ FAILED: {e}")
        logger.exception("Test 2 failed")

    # Test 3: Check export availability for each format
    print(f"\n[TEST 3] Checking export availability for all formats...")
    for format_type, description in api.FORMATS.items():
        print(f"\n  Format: {format_type} - {description}")
        try:
            info = api.check_export_availability(dataset_key, format_type, extended=True)
            if info['available']:
                print(f"  ✓ Available")
                if info.get('size_mb'):
                    print(f"    Size: {info['size_mb']} MB")
                print(f"    URL: {info['final_url']}")
            else:
                print(f"  ✗ Not available (HTTP {info['status_code']})")
        except Exception as e:
            print(f"  ✗ Error: {e}")
            logger.exception(f"Format {format_type} check failed")

    # Test 4: Archive endpoint
    print(f"\n[TEST 4] Checking archive endpoint...")
    try:
        archive_info = api.get_archive_info(dataset_key)
        if archive_info['available']:
            print("✓ Archive available")
        else:
            print(f"✗ Archive not available (HTTP {archive_info['status_code']})")
    except Exception as e:
        print(f"✗ Error: {e}")
        logger.exception("Test 4 failed")

    # Test 5: Download and validate (optional)
    if download_and_validate:
        print(f"\n[TEST 5] Downloading and validating dataset...")
        try:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            output_path = f"col_test_{dataset_key}_{timestamp}.zip"

            print(f"  Downloading to: {output_path}")
            downloaded_path = api.download_export(dataset_key, output_path, 'ColDP', extended=True)
            print(f"  ✓ Download complete")

            # Calculate hash
            print(f"  Calculating SHA256 hash...")
            file_hash = api.calculate_file_hash(downloaded_path)
            print(f"  SHA256: {file_hash}")

            # Verify and extract
            print(f"  Verifying zip integrity...")
            is_valid, error = api.verify_zip_integrity(downloaded_path)
            if is_valid:
                print(f"  ✓ Zip integrity verified")

                print(f"  Extracting and validating structure...")
                validation = api.extract_and_validate(downloaded_path)

                if validation['valid']:
                    print(f"  ✓ Structure validation PASSED")
                else:
                    print(f"  ✗ Structure validation FAILED")
                    for error in validation['errors']:
                        print(f"    ERROR: {error}")

                if validation['warnings']:
                    print(f"  ⚠ Warnings:")
                    for warning in validation['warnings']:
                        print(f"    {warning}")

                print(f"\n  Files found: {len(validation['files_found'])}")
                for filename, info in validation['files_found'].items():
                    record_count = validation['record_counts'].get(filename, '')
                    count_str = f" ({record_count:,} records)" if record_count else ""
                    print(f"    - {filename}: {info['size_mb']} MB{count_str}")

                if validation.get('metadata'):
                    print(f"\n  Metadata:")
                    for key, value in validation['metadata'].items():
                        print(f"    {key}: {value}")

                print(f"\n  ✓ TEST 5 COMPLETE")
                print(f"  Downloaded file: {os.path.abspath(downloaded_path)}")
                print(f"  Extracted to: {validation['extract_dir']}")

            else:
                print(f"  ✗ Zip integrity check FAILED: {error}")

        except Exception as e:
            print(f"  ✗ FAILED: {e}")
            logger.exception("Test 5 failed")

    print("\n" + "=" * 80)
    print("TEST SUITE COMPLETE")
    print("=" * 80 + "\n")


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Test and download Catalogue of Life datasets via ChecklistBank API',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run full test suite (without download)
  python col_api_test.py --test

  # Run full test with download and validation
  python col_api_test.py --full-test --dataset-key 312578

  # Download latest COL eXtended Release (with extended data - default)
  python col_api_test.py --download --dataset-key 312578

  # Download Base Release content only (exclude extended data)
  python col_api_test.py --download --dataset-key 312563 --no-extended

  # Check what's available
  python col_api_test.py --check --dataset-key 312578

  # Get latest release info
  python col_api_test.py --latest
        """
    )

    parser.add_argument(
        '--test',
        action='store_true',
        help='Run comprehensive API tests'
    )

    parser.add_argument(
        '--full-test',
        action='store_true',
        help='Run full test including download and validation (warning: downloads ~1GB+)'
    )

    parser.add_argument(
        '--download',
        action='store_true',
        help='Download dataset export'
    )

    parser.add_argument(
        '--check',
        action='store_true',
        help='Check export availability without downloading'
    )

    parser.add_argument(
        '--latest',
        action='store_true',
        help='Get latest COL release info'
    )

    parser.add_argument(
        '--dataset-key',
        type=int,
        default=312578,
        help='Dataset key to download (default: 312578 = COL 2025-10-10 XR)'
    )

    parser.add_argument(
        '--format',
        choices=list(ChecklistBankAPI.FORMATS.keys()),
        default='ColDP',
        help='Export format (default: ColDP)'
    )

    parser.add_argument(
        '--no-extended',
        action='store_false',
        dest='extended',
        default=True,
        help='Exclude extended data (XR additions). By default, extended data IS included for XR releases.'
    )

    parser.add_argument(
        '--output',
        type=str,
        help='Output file path (default: auto-generated)'
    )

    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Enable verbose logging'
    )

    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Show help if no action specified
    if not any([args.test, args.full_test, args.download, args.check, args.latest]):
        parser.print_help()
        print("\n" + "=" * 80)
        print("No action specified. Use --test, --full-test, --download, --check, or --latest")
        print("=" * 80 + "\n")
        return

    api = ChecklistBankAPI()

    try:
        if args.latest:
            latest = api.get_latest_col_release()
            print_dataset_info(latest)

        if args.test:
            test_api_endpoints(args.dataset_key, download_and_validate=False)

        if args.full_test:
            test_api_endpoints(args.dataset_key, download_and_validate=True)

        if args.check:
            print(f"\nChecking export availability for dataset {args.dataset_key}...")
            info = api.check_export_availability(args.dataset_key, args.format, args.extended)

            print(f"\nStatus: {'Available' if info['available'] else 'Not Available'}")
            print(f"HTTP Status: {info['status_code']}")
            print(f"Final URL: {info['final_url']}")

            if info.get('size_mb'):
                print(f"Size: {info['size_mb']} MB")

            print(f"\nHeaders:")
            for key, value in info['headers'].items():
                print(f"  {key}: {value}")

        if args.download:
            # Generate output path if not specified
            output_path = args.output
            if not output_path:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                output_path = f"col_{args.dataset_key}_{args.format}_{timestamp}.zip"

            print(f"\nDownloading dataset {args.dataset_key}...")
            print(f"Format: {args.format}")
            print(f"Extended: {args.extended}")
            print(f"Output: {output_path}")
            print()

            downloaded_path = api.download_export(
                args.dataset_key,
                output_path,
                args.format,
                args.extended
            )

            print(f"\n{'=' * 80}")
            print(f"SUCCESS! Dataset downloaded to:")
            print(f"  {os.path.abspath(downloaded_path)}")
            print(f"{'=' * 80}\n")

    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n\n{'=' * 80}")
        print(f"ERROR: {e}")
        print(f"{'=' * 80}\n")
        logger.exception("Fatal error")
        sys.exit(1)


if __name__ == '__main__':
    main()
