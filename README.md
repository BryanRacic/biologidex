# BiologiDex
A Pokedex style social network app that allows users to share pictures of their real world zoologic observations in order to collaboratively build an ever expanding "evolutionary tree" with their friends.  

 This is a pokedex style app where CV is utilized to identify animals in user uploaded images which are turned into pokedex-style dex entries. In this version, friend's dex entries are counted as "seen animals" and displayed in a graph structure similar to an evolutionary tree.

Uses computer vision services to identify biological species (animals) in images taken by users. Once identified, the user adds the animal to their local database of seen animals with additional information & flavor as provided by the BiologiDex platform. BiologiDex is a placeholder name representing the walled-garden structure of the user networks and the giant evolutionary tree of animals being created by all "friends" of the user. 

## Evolutionary Tree
Find reference of actual evolutionary taxonomic tree which we can place animals & species on based on 

## Creating Animal Record Workflow
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

# Implementation
- Django API
    - Handles
        - User Account
            - Creation
            - Login
            - Management
            - Authentication
        - Animal Identification
        - Animal Record Lookups 
- MySQL DB
    - Tables for   
        - Users
        - Animals
            - name
            - description
            - metadata

# Project Usage
## Requirements
- pyenv
- poetry
- django 

## Setup
1. pyenv install 3.12.10
2. pyenv local 3.12.10
3. poetry install
4. apt install python3-django

