# Taxonomic Data Plan
Create a Taxonomic DB which holds searchable, reliable, primary information (source of truth) regarding animal species and associated taxonomic data. This initially will come from a single source (the Catalogue of Life) but needs to be future proofed and extensable to support several different sources in the future. Some sources are also updated on a regular schedule (Catalogue of Life is updated monthly)

Each source should have an associated "raw_source_name" table and a "data load" (script/command/celery job) that downloads the most recent data and imports it into the associated "raw" table. The final "taxonomy" table is combined, normalized, and deduplicated data from all "raw" source tables. 

It's essential that all rows on the taxonomic & raw tables are indexed w/ creation & modification  datetimes. And all rows on the taxonomic table should have a "source field" for the originating source dataset. The Taxonomic table should have a unique ID for each row for easy reference by the `animals` db

For this initial implementation, the "data load job" will only be run manually, and the "taxonomy" table will just `SELECT * FROM` the `raw_catalogue_of_life` table. 

# Taxonomic DB Usage
The `taxonomy` DB will be used as follows: For unreliable image identification sources (like the current ChatGPT method), when a new animal is identified, the common & scientific names will be searched in the taxonomic db before creating a new animal record. If a valid record match is found, that record will be added to the `animals` db (including the unique id of the taxonomy source) 

The `animals` db should be updated to include all the possible Taxonomic Hierarchy columns from the source data. Also the `common name`, `establishment means`, `conservation status` and location (calculated from `area code` & `geographic standard`). Finally the taxonomic `source` (which for the "catalogue_of_life" is just `https://www.catalogueoflife.org/data/taxon/INSERTTAXONIDHERE`)  

# Catalogue of Life 
Additional details: resources/catalogue_of_life/catalogue_of_life.md

## Catalogue of Life API
Get list of datasets (order by most recent)
```
curl -X 'GET' \
  'https://api.checklistbank.org/dataset?offset=0&limit=5&origin=RELEASE&sortBy=CREATED&reverse=false' \
  -H 'accept: application/json'
```
Download a specific dataset (get `key` from most recent dataset above)
```
curl -X 'GET' \
  'https://api.checklistbank.org/dataset/INSERTKEYHERE/export?format=COLDP&extended=false' \
  -H 'accept: application/octet-stream'
```
