## TODO
- Merge friends & dex feed scenes
  - use (bullet journal style) tabs
- Overlay nav arrows on tree edges
  - Click to auto scroll to the next node in the path
- Update dex scene
  - Scrolling up/down automatically moves & recenters the next/prev entry w/in the screen
- Update dex to display full/half page w/ additional context from COL
- Reduce dex compatible image size (for faster loading)
- Implement basic CDN for faster image retrieval
  - Dedicated file upload service
  - Direct uploads to cloud storage
  - chunked/resumable uploads
  - Look at Cloudflare R2


### Design updates
- Login page is composition notebook front cover
- Create account is filling out (if found return to) in composition book
- Home screen has lineage tree background
- Dex page & feed pan across screen (horizontal for page, vertical for feed)

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
- server_audit.md


### Polish
- add loading ux when downloading dex entries
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
- Allow download/export of dex record image
- Overlapping label detection/fix logic
- Support 1:1 aspect ratio selection/crop of images as part of dex entry
  - Replace images on tree w/ circular cutouts
  - More fun table of contents w/ pfp of each animal

### Future Features
- Take a picture of placards/info at the zoo/aquarium and extract text into dex entry
  - Location, facts, etc.