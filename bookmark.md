# TODO 
- [done] always download/view dex if it doesn't exist locally
 - [check on] download first 5 in the background on login (if possible)
- catch_date should be exclusively server side
- add loading ux when downloading dex entries
- fix tree view (only loading friends not self?)
- add version check and update alert
  - for both api version and client side version
    - maybe an automatic simplified api docs export for usage in updating the client api?
- try to find a more "function" based OpenAI model interface
  - to fill a format w/ standardized output for subspecies if it exists and always "none" if not (which is gracefully handled on the animal addition side)
- ensure deletion of an animal record reindexes the rest of the animal record dscovery indexs
  - maybe re-index django command
    - ideally runnable on the admin interface

bryan@DeepThought:/opt/biologidex/server$ docker-compose -f docker-compose.production.yml run web python manage.py import_col --force
Creating server_web_run ... done
Email configured with SMTP backend
Sentry not configured - error tracking disabled
=== Catalogue of Life Import ===
Using existing data source: Catalogue of Life (col)
Created import job: a21ae5ae-c1c1-4b4a-a538-4022378686a6
Running import synchronously...
This may take 2-3 hours for full COL dataset
WARNING 2025-11-06 21:25:49 col_importer 7 138993397652352 ✗ Dataset 312898 export not available (HTTP 404)
ERROR 2025-11-06 21:59:27 base 7 138993397652352 Failed to normalize record CJPZG: value too long for type character varying(200)

ERROR 2025-11-06 22:01:49 base 7 138993397652352 Failed to normalize record CJN48: value too long for type character varying(200)

ERROR 2025-11-06 22:05:23 base 7 138993397652352 Failed to normalize record CJPYJ: value too long for type character varying(200)

ERROR 2025-11-06 22:10:42 base 7 138993397652352 Failed to normalize record 9B2QT: value too long for type character varying(200)

ERROR 2025-11-06 22:10:53 base 7 138993397652352 Failed to normalize record CJPZP: value too long for type character varying(200)

ERROR 2025-11-06 22:16:22 base 7 138993397652352 Failed to normalize record CJPY9: value too long for type character varying(200)

ERROR 2025-11-06 22:18:34 base 7 138993397652352 Failed to normalize record CJN4X: value too long for type character varying(200)

ERROR 2025-11-06 22:18:38 base 7 138993397652352 Failed to normalize record CJN49: value too long for type character varying(200)

ERROR 2025-11-06 22:19:14 base 7 138993397652352 Failed to normalize record 99Z4W: value too long for type character varying(200)

ERROR 2025-11-06 22:21:21 base 7 138993397652352 Failed to normalize record CJPZG: value too long for type character varying(200)

ERROR 2025-11-06 22:21:21 base 7 138993397652352 Failed to normalize record CJN48: value too long for type character varying(200)

ERROR 2025-11-06 22:21:21 base 7 138993397652352 Failed to normalize record CJPYJ: value too long for type character varying(200)


✓ Import completed successfully!
  Records imported: 1338841
  Records failed: 12
  Records read: 5357236

  First errors (12 total):
    - {'record_id': 'CJPZG', 'error': 'value too long for type character varying(200)\n'}
    - {'record_id': 'CJN48', 'error': 'value too long for type character varying(200)\n'}
    - {'record_id': 'CJPYJ', 'error': 'value too long for type character varying(200)\n'}
    - {'record_id': '9B2QT', 'error': 'value too long for type character varying(200)\n'}
    - {'record_id': 'CJPZP', 'error': 'value too long for type character varying(200)\n'}
