# taxonomy/importers/__init__.py
from .base import BaseImporter
from .col_importer import CatalogueOfLifeImporter

__all__ = ['BaseImporter', 'CatalogueOfLifeImporter']
