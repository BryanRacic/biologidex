#!/usr/bin/env python
"""Test script to verify Canis lupus familiaris lookup works"""

import os
import django
import sys

# Setup Django settings
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "biologidex.settings.production")
sys.path.insert(0, '/app')
django.setup()

from taxonomy.services import TaxonomyService

print("=" * 80)
print("TESTING CANIS LUPUS FAMILIARIS LOOKUP")
print("=" * 80)

# Test the lookup
genus = "Canis"
species = "lupus"
subspecies = "familiaris"
common_name = "domestic dog"

print(f"\nInput:")
print(f"  Genus: {genus}")
print(f"  Species: {species}")
print(f"  Subspecies: {subspecies}")
print(f"  Common name: {common_name}")
print()

try:
    taxonomy, created, message = TaxonomyService.lookup_or_create_from_cv(
        genus=genus,
        species=species,
        subspecies=subspecies,
        common_name=common_name,
        confidence=0.95
    )

    if taxonomy:
        print("\n" + "=" * 80)
        print("✓ SUCCESS - Taxonomy found!")
        print("=" * 80)
        print(f"Scientific name: {taxonomy.scientific_name}")
        print(f"Genus: '{taxonomy.genus}'")
        print(f"Species: '{taxonomy.specific_epithet}'")
        print(f"Subspecies: '{taxonomy.infraspecific_epithet}'")
        print(f"Status: {taxonomy.status}")
        print(f"Rank: {taxonomy.rank.name if taxonomy.rank else 'None'}")
        print(f"Message: {message}")
        print(f"Animal created: {created}")
        print()

        # Check if fields were populated
        from taxonomy.models import Taxonomy
        updated_record = Taxonomy.objects.get(id=taxonomy.id)
        print("Updated record in database:")
        print(f"  Genus: '{updated_record.genus}'")
        print(f"  Species: '{updated_record.specific_epithet}'")
        print(f"  Subspecies: '{updated_record.infraspecific_epithet}'")

    else:
        print("\n" + "=" * 80)
        print("✗ FAILED - Taxonomy not found")
        print("=" * 80)
        print(f"Message: {message}")

except Exception as e:
    print("\n" + "=" * 80)
    print("✗ ERROR during lookup")
    print("=" * 80)
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()
