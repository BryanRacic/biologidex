#!/usr/bin/env python
"""Debug script to check Canis lupus familiaris in database"""

import os
import django
import sys

# Setup Django settings
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "biologidex.settings.development")
sys.path.insert(0, '/home/bryan/Development/Git/biologidex/server')
django.setup()

from taxonomy.models import Taxonomy
from django.db.models import Q

# Query 1: Find all Canis lupus entries
print("=" * 80)
print("SEARCHING FOR ALL CANIS LUPUS ENTRIES:")
print("=" * 80)

canis_lupus_entries = Taxonomy.objects.filter(
    genus__iexact='Canis',
    specific_epithet__iexact='lupus'
).select_related('source', 'rank')

print(f"\nFound {canis_lupus_entries.count()} Canis lupus entries:\n")

for idx, entry in enumerate(canis_lupus_entries[:30], 1):
    print(f"{idx:3}. ID: {entry.id}")
    print(f"     Scientific name: {entry.scientific_name}")
    print(f"     Status: {entry.status}")
    print(f"     Rank: {entry.rank.name if entry.rank else 'None'}")
    print(f"     Subspecies (infraspecific_epithet): '{entry.infraspecific_epithet or 'None'}'")
    print(f"     Source: {entry.source.short_code}")
    print(f"     COL ID: {entry.col_id}")
    print(f"     Completeness: {entry.completeness_score}")
    print(f"     Priority: {entry.source.priority}")
    print(f"     Is processed: {entry.is_processed}")
    print()

# Query 2: Specifically look for familiaris
print("=" * 80)
print("SEARCHING SPECIFICALLY FOR FAMILIARIS:")
print("=" * 80)

# Look for familiaris in scientific name
familiaris_by_name = Taxonomy.objects.filter(
    scientific_name__icontains='familiaris'
).select_related('source', 'rank')

print(f"\nFound {familiaris_by_name.count()} entries with 'familiaris' in scientific name:\n")

for idx, entry in enumerate(familiaris_by_name[:10], 1):
    print(f"{idx:3}. ID: {entry.id}")
    print(f"     Scientific name: {entry.scientific_name}")
    print(f"     Genus: {entry.genus}")
    print(f"     Species: {entry.specific_epithet}")
    print(f"     Subspecies (infraspecific_epithet): '{entry.infraspecific_epithet or 'None'}'")
    print(f"     Status: {entry.status}")
    print(f"     Rank: {entry.rank.name if entry.rank else 'None'}")
    print(f"     COL ID: {entry.col_id}")
    print(f"     Source: {entry.source.short_code}")
    print(f"     Is processed: {entry.is_processed}")
    print()

# Query 3: Look for infraspecific_epithet = familiaris
print("=" * 80)
print("SEARCHING BY INFRASPECIFIC_EPITHET = 'familiaris':")
print("=" * 80)

familiaris_infra = Taxonomy.objects.filter(
    infraspecific_epithet__iexact='familiaris'
).select_related('source', 'rank')

print(f"\nFound {familiaris_infra.count()} entries with infraspecific_epithet='familiaris':\n")

for idx, entry in enumerate(familiaris_infra[:10], 1):
    print(f"{idx:3}. ID: {entry.id}")
    print(f"     Scientific name: {entry.scientific_name}")
    print(f"     Genus: {entry.genus}")
    print(f"     Species: {entry.specific_epithet}")
    print(f"     Subspecies (infraspecific_epithet): '{entry.infraspecific_epithet}'")
    print(f"     Status: {entry.status}")
    print(f"     Rank: {entry.rank.name if entry.rank else 'None'}")
    print(f"     COL ID: {entry.col_id}")
    print()

# Query 4: Check the specific record you mentioned
print("=" * 80)
print("LOOKING FOR SPECIFIC COL ID 5G6ZJ:")
print("=" * 80)

specific_record = Taxonomy.objects.filter(col_id='5G6ZJ').first()
if specific_record:
    print(f"\nFound record with COL ID 5G6ZJ:")
    print(f"  ID: {specific_record.id}")
    print(f"  Scientific name: {specific_record.scientific_name}")
    print(f"  Genus: {specific_record.genus}")
    print(f"  Species (specific_epithet): '{specific_record.specific_epithet or 'None'}'")
    print(f"  Subspecies (infraspecific_epithet): '{specific_record.infraspecific_epithet or 'None'}'")
    print(f"  Status: {specific_record.status}")
    print(f"  Rank: {specific_record.rank.name if specific_record.rank else 'None'}")
    print(f"  Is processed: {specific_record.is_processed}")
    print(f"  Import job: {specific_record.import_job}")
    print()
    print(f"  Full data fields:")
    print(f"    Kingdom: {specific_record.kingdom}")
    print(f"    Phylum: {specific_record.phylum}")
    print(f"    Class: {specific_record.class_name}")
    print(f"    Order: {specific_record.order}")
    print(f"    Family: {specific_record.family}")
else:
    print("  Record not found!")