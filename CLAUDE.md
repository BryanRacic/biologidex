# BiologiDex - Project Memory

## Project Overview
A Pokedex-style social network for sharing real-world zoological observations. Users photograph animals, which are identified via CV/LLM, then added to personal collections and a collaborative evolutionary tree shared with friends.

## Core Features
- **Animal ID Workflow**: User uploads image → CV/LLM identification → Manual verification → Database record creation
- **Layered ID Approach**: CV services (wildlifeinsights, inaturalist, animaldetect.com) → LLM image processing
- **Animal Records**: Cards containing species info (genus/species, kingdom/phylum, conservation status, facts)
- **Social Component**: Friend networks collaborate on shared evolutionary tree
- **Customization**: Card backgrounds, stickers, annotations, player badges

## Technical Architecture

### Tech Stack
- **Backend**: Django API (user auth, animal ID, record lookups)
- **Database**: MySQL (users, animals tables with name/description/metadata)
- **Frontend**: TBD
- **CV/AI Services**: OpenAI Vision API (primary), with fallback to specialized CV services

### Animal Identification Pipeline
1. **Prompt Template** (`ANIMAL_ID_PROMPT`): Requests specific species name in binomial nomenclature format `genus, species (common name)`, returns `NO ANIMALS FOUND` if none detected
2. **Multi-method support**: Abstract `CVMethod` base class enables testing different CV approaches
3. **OpenAI Implementation**: Base64 image encoding → Vision API → structured response

### Benchmarking System (`scripts/animal_id_benchmark.py`)

**Purpose**: Test accuracy/cost/speed of different CV methods against ground truth dataset

**Key Components**:
- `CVMethod` abstract base class for extensibility
- `OpenAIVisionMethod`: Handles GPT-4/GPT-5 vision models
- `AnimalIDBenchmark`: Orchestrates testing across images and methods
- Test images location: `resources/test_images/`
- Ground truth: `resources/test_images/image_key.csv`

**OpenAI Model Compatibility**:
- **GPT-4 models** (gpt-4o, gpt-4o-mini): Use `max_tokens` parameter
- **GPT-5+ models** (gpt-5, gpt-5-mini, gpt-5-nano, o-series): Use `max_completion_tokens` parameter
- Auto-detection logic checks model prefix to apply correct parameter

**Pricing (per 1K tokens)**:
- GPT-5 series: $0.00025-$0.01500 input, $0.00200-$0.12000 output
- GPT-4.1 series: $0.00020-$0.00300 input, $0.00080-$0.01200 output
- Legacy: gpt-4o, gpt-4o-mini with estimated rates

**Output Metrics**:
- Per-test: prediction, cost, runtime, accuracy (ground truth match)
- Aggregate: method-wise accuracy %, avg cost/runtime
- Logs to `animal_id_benchmark.log`

## Design Philosophy
- Inspired by biological illustration aesthetics
- Modern, clean History Channel-style presentation
- Card-based UI for animal/player records
- Neobrutalism design references

## Current Status
- Benchmarking infrastructure: ✓ Complete
- Animal ID prompt: ✓ Defined
- Backend framework: Django (planned)
- Database schema: MySQL (outlined)
- Frontend: Not started

## Environment Setup
- `.env` file in project root with `OPENAI_API_KEY`
- Python environment with: openai, python-dotenv, standard library modules
