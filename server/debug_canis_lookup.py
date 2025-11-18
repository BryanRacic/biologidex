#!/usr/bin/env python
# Check how familiaris is actually stored
from taxonomy.models import Taxonomy
t = Taxonomy.objects.filter(scientific_name__icontains='familiaris').first()
if t:
    print(f"Scientific name: {t.scientific_name}")
    print(f"Genus field: '{t.genus}'")
    print(f"Species field: '{t.specific_epithet}'")
    print(f"Infraspecific epithet field: '{t.infraspecific_epithet}'")  # This is likely empty!
    print(f"Status: {t.status}")
