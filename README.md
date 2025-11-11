# BiologiDex

A Pokedex-style social network for sharing real-world zoological observations. Users photograph animals, which are identified via CV/LLM, then added to personal collections and a collaborative taxonomic tree shared with friends.

## Recent Updates (2025-11-11)

### Multi-User Dex System v2.0 ✨
Complete overhaul enabling friend dex viewing with production-ready performance:
- **Incremental Sync**: Only downloads changed entries using timestamps
- **Multi-User Storage**: View own + friends' dex with user-partitioned local storage
- **Image Deduplication**: Cross-user cache sharing reduces bandwidth/storage
- **Smart Caching**: HTTP caching (5 min full sync, 2 min friends overview)
- **Retry Logic**: Exponential backoff for network resilience (1s → 2s → 4s)
- **Database Optimization**: Composite indexes on `(owner, updated_at)`, `(visibility, updated_at)`

#### API Enhancements
- `GET /dex/entries/user/{user_id}/entries/` - Sync any user's dex with permission checks
- `GET /dex/entries/friends_overview/` - Summary of all friends' collections
- `POST /dex/entries/batch_sync/` - Sync multiple users in one request

#### Migration Notes
- **Auto-Migration**: v1 → v2 database migration on first launch (backs up old DB)
- **Backwards Compatible**: Legacy single-user methods still work
- **New Storage**: `user://dex_data/{user_id}_dex.json` + `user://sync_state.json`

## Overview

Uses computer vision services to identify biological species in images taken by users. Once identified, the user adds the animal to their local database of discovered animals with additional metadata. Friends' dex entries appear in a shared taxonomic tree visualization. 

## Future Enhancements

### Phase 6: Advanced Image Management
- Multiple images per dex entry with image history
- User-selectable primary photo for dex cards
- Swipeable image gallery view

### Phase 7: Collaborative Collections
- Shared themed collections (Birds of North America, Endangered Species, etc.)
- Collaborator permissions and custom ordering
- Public/private collection visibility

### Phase 8: Dex Pages (Scrapbook Feature)
- Transform entries into rich journal pages with custom layouts
- Multiple layout templates (field notes, photo essay, comparison grid)
- Additional content blocks: audio notes, weather data, companions, habitat notes
- Export as images/PDFs, share to social media

### Phase 9: Offline & Sync Enhancements
- Offline queue with conflict resolution
- Background automatic syncing
- Predictive prefetching based on usage patterns
- Cloud backup for local database

### Phase 10: Social Features
- Activity feed showing friends' recent discoveries
- Achievement system for collection milestones
- Leaderboards and discovery counts
- Themed challenges (find 10 birds this week, complete a family)

### Phase 11: Data Management
- Export/import in CSV, JSON, PDF formats
- Data portability (import from other wildlife tracking apps)
- Scheduled backups and restore functionality
- Storage quotas with LRU eviction

## Taxonomic Tree
Find reference of actual taxonomic tree which we can place animals & species on based on 

# Design
- Inspired by Biological illustration: https://en.wikipedia.org/wiki/Biological_illustration
- A modern & clean version like might be seen on the history channel (design-wise)
- Individual animal records are formatted like "cards"
- https://dribbble.com/shots/20557553-Pokedex-Pokemon-App-v2
- https://dribbble.com/shots/11114913-Pok-dex-App
- https://dribbble.com/shots/2978201-pokemon-Go
- https://dribbble.com/shots/19287892-Pokemon-Neobrutalism


# Customization
Animal Record Cards
- Different background colors
- Different background color shapes
- Can add optional stickers & annotations
- Clicking on an image makes it full-resolution w/o any user customization visible
- Mark animal as wild/captive

Player Record Cards
- Inherits Animal Record Card design but allows for far more customization
- Different Player Stats & Badges
- Can use any animal picture caught or seen as a pfp

# Planned Additions
- Support "breeds" for subset of animal species
- "Verified" biologist accounts
- Wikipedia-style moderation hierarchy for platform-wide animal data
    - Animal metadata
    - Taxonomic tree organization
    - etc. 

# FAQ (To be displayed on website/to current/potentional users)
- What prevents users from being dishonest about animal identification
    - Nothing. The point is to share, inspire and engage with only other users you enjoy sharing the experience with. If at any point you feel another player's engagement with the platform conflicts with your enjoyment, you're encouraged to unfriend them or hide their nodes from your tree  
- Is it cheating if I take pictures at a zoo/aquarium?
    - The opposite actually! It's always up to you to decide what types of records you enjoy creating and viewing, but the intention of the platform is to encourage engagement and compassion for the natural world. Zoos and aquariums provide essential   
- How is AI used in this project
    - Sparingly (we belive in responsible, ethical AI use)
        - AI use policy
            - Only when essential for core features that prove a substantial benefit
                - Platform development, updates, security, feature delivery
                - Platform accessiblity, user knowledge, 
            - Minimize & optimize usage wherever possible
                - Prioritize other options and use the "least power hungry" model wherever possible
        - Image recognition
            - how
                - images are sent to openai for identification 
            - why
                - accessiblity for users without zoology knowledge/background
                - minimal available resources
            - responsible
                - See section on attempts to minimze modern LLM usage
                - ID tier system based on preferred 
        - Animal metadata
            - how
                - Compiling & summarizing data from existing sources
            - why
                - accessiblity for users without zoology knowledge/background
                - minimal available resources
            - responsible
                - only generated once, allow verified biologists to review & edit or have non-validated tags on those that haven't been human validated
        - Code generation
            - how
                - Claude & ChatGPT for code/documentation generation
            - why
                - manpower & time limitations
            - responsible
                - Only used for menial tasks (filling out templates, generating internal documentation, implementing human designed architectural requirements)
                - All AI changes are individually human reviewed before entering production
                    - Only working with technologies & frameworks I already professionally specalize in
                - Utilized only when non-ai alternative tools are not possible 
                    - ex. we're going to use regex through an IDE rather than having chatgpt find & replace
                - Building reusable, non-ai powered tooling (with ai)
                    - ex. making traditional reusable scripts whenever possible for common AI-actions to minimize AI usage 
- Is my data used to train an AI?
    - At the moment our only image identification system runs through OpenAI's API, which at the time of writing, [does not train models on API requests](https://platform.openai.com/docs/concepts)    
    - The Biologidex team considers your data and privacy to be our #1 focus, while at some point in the near future, we'd like to give back to the scientific community by providing any useful crowd sourced-data. That'll never be enabled without explict consent from users. And we'll never retroactively apply any data sharing permission modifications without a user's express consent  
- Can I opt out of AI features
    - Yes! (mostly)
        - AI generated animal metadata is initally populated plaform-wide. So anytime a new animal that's *novel to the platform* is introduced, a limited number of calls to an AI are made to gather & summarize intial information about that animal. This cannot be easily disabled/hidden at the individual user level. But AI-powered image detection (__the only other application of AI__) can be completely disabled. We plan to retain the ability to opt-out of any AI features included in the future.  
- How does useage of this APP impact my carbon footprint? 
    - Probably less than you expect
        - LLMs have become exponentially more power efficient based on the limited (and biased) data provided by LLM providers.   
        - We're working to migrate as much of the traditional LLM-based image identification services to a computer-vision specific model trained on different animal images. 
            - These are low power, purpose-built models that have existed in-industry for over a quarter century and as such consume *orders of magnitude* less power than their contemporary "all-in-one" counterparts.
            - Unfortunately most of the publicly available services are prohibitively expensive, have strict usage limits, or are limited to exclusively academic purposes. 
                - Migrating to these services usually require extensive collaboration between our team and the custodians of each service, and we expect services will respond more favorably to inqieries as our reputation and resources grow
    - Working on transparent carbon footprint reporting 
    - Short reminder that while being concious of your individual carbon footprint is important, large corporations create a disproportionate... 
- Have you considered carbon credit offsets
    - Unfortunately these are usually the product of greenwashing

# Required Pages/User Workflow
1. Login
    - Show If
        - no valid refresh token
    - Details
        - login form
            - username
                - prepopulated from local account details 
            - password
        - login button
            - on success
                - login process
                    - get refresh token (long term)
                        - `POST /api/v1/auth/refresh/`: Refresh access token
                            - TODO double check this generates a refresh token
                    - login/get jwt token (short term, uses refresh token)
                        - `POST /api/v1/auth/login/`: Get JWT tokens
                    - save account details locally
                        - username, refresh token
                        - TODO make saving username/account details optional
                    3. Home
                        4. Create animal record (take/upload photo)
                            - upload picture
                                - HTML5 build
                                    - use godot-file-access-web plugin
                                        - Code & Examples: client/biologidex-client/addons/godot-file-access-web
                                        - Source: https://github.com/Scrawach/godot-file-access-web/tree/main
                                - `POST /api/v1/vision/jobs/`: Upload image, triggers async CV analysis
                            - on upload success
                                - display loading icon
                                    - `GET /api/v1/vision/jobs/{id}/`: Check analysis status
                        5. View taxonomic tree(s)
                        6. Profile
                            - Details
                                - Username (display only)
                                - Firstname
                                - Lastname
                                - Bio
                            7. Friends (view/manage/add)
                            8. Settings
                                - Change password
                                - Change email
                                - Details
                                    - Logout
        - reset password button
            - TODO
        - create account button
            2. Create account
                - Details        
                    - account creation form
                        - username
                        - email
                        - password
                        - confirm password
                    - create account button
                            - `POST /api/v1/users/`: Register new user (no auth required)
                                - TODO add validation
                                    - username, email, password match
                            - on success
                                - see login process


## Creating Animal Record Workflow (Planned)
- User uploads image
- AI Processing & Animal ID
    - Start w/ LLM service for ease of use
    - Layered ID approach 
        - Iterate over the following until a match is identified (or steps exhausted)
            - CV-specific animal ID service
                - wildlifeinsights
                - inaturalist
                - animaldetect.com
            - LLM Image Processing service
    - If a match is identified
        - Display match to user (and source) 
        - Ask user if they want to manually enter
    - If a match is not identified
        - Ask the user to manually enter
        - Or upload a different image
- Once animal is ID
    - Query Animal DB
        - If animal doesn't exist
            - Then create animal record
                - animal name
                - animal info lookup (primary free apis first, then LLM fallback)
                    - genus species  
                    - kingdom phylum
                    - conservation status
                    - fact/info/about
                        -  start w/ summarization/RAG find by LLM
                - animal creation index
                    - similar to pokedex number, users are encouraged to "find them all"
        - If animal does exist
            - Lookup animal record
        - Create animal record in player's animal record DB