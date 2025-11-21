## TODO

### Essentials
- dex entries should contain `username` & `catch date`
   - catch_date should be exclusively server side
- add version check and update alert
  - for both api version and client side version
    - maybe an automatic simplified api docs export for usage in updating the client api?
- ensure deletion of an animal record reindexes the rest of the animal record dscovery indexs
  - maybe re-index django command
    - ideally runnable on the admin interface
      - this should run anytime an animal record is deleted
      - prevent animal record creation unless confirmed by a user
- remove/delete dex entry
- retry failed dex entry

### Optimization
- Background downloading/cache (if possible in HTTP)
  - Friends
  - Dex records
    - download first 5 dex records in the background on login
- try to find a more "function" based OpenAI model interface
  - to fill a format w/ standardized output for subspecies if it exists and always "none" if not (which is gracefully handled on the animal addition side)

### Cleanup
- include additional data from COL export
  - VernacularName (now have NameRelation, need CommonName import)
  - SpeciesEstimate, TypeMaterial (locality)
- display dex entry on taxonomic tree
- evaluate server implementation
  - Remove unused code, outdated features
  - Identify inefficiant or non-optimal solutions/algorithmns
  - Identify potential security/privacy issues


### Polish
- add loading ux when downloading dex entries
- taxonomy db in admin panel gives 500 error
- update col_importer job to run multithreaded
- remove friend from friendlist
- retry Image ID if innaccurate
  - try different model/modify prompt
- allow upvotes on dex entries
  - Most upvoted entry is displayed on the tree
  - sort dex feed by likes vs timestamp
- If multiple dex entries on same node
  - New window with each dex entry
    - Each entry displays the username of the original author