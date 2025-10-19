# BiologiDex
A Pokedex style social network app that allows users to share pictures of their real world zoologic observations in order to collaboratively build an ever expanding "evolutionary tree" with their friends.  


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
Inspired by Biological illustration: https://en.wikipedia.org/wiki/Biological_illustration
A modern & clean version like might be seen on the history channel (design-wise)
Individual animal records are formatted like "cards"
https://dribbble.com/shots/20557553-Pokedex-Pokemon-App-v2
https://dribbble.com/shots/11114913-Pok-dex-App
https://dribbble.com/shots/2978201-pokemon-Go
https://dribbble.com/shots/19287892-Pokemon-Neobrutalism


# Customization
Animal Record Cards
- Different background colors
- Different background color shapes
- Can add optional stickers & annotations
- Clicking on an image makes it full-resolution w/o any user customization visible

Player Record Cards
- Inherits Animal Record Card design but allows for far more customization
- Different Player Stats & Badges
- Can use any animal picture caught or seen as a pfp

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
        