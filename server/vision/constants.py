"""
Constants for vision app.
"""

# Animal identification prompt from benchmarking script
ANIMAL_ID_PROMPT = " ".join([
    'Please identify the animal(s) in this image.',
    'Bugs, arachnids & other invertabrits are considered animals for the purpose of this task.',
    'Provide a specific species name if possible, or a general animal type if the species cannot be determined.',
    'If there are multiple animals, list all of them separated by the `|` character',
    'Your response should be formatted in Trinomial nomenclature, formatted as the following `genus species subspecies (common name)` if at least one animal can be identified.',
    'If no animals can be identified, return `NO ANIMALS FOUND`',
])

# OpenAI pricing as of October 2025 (prices per 1K tokens)
OPENAI_PRICING = {
    # GPT-5 Series
    "gpt-5": {
        "input": 0.001250,   # $1.250 per 1M tokens
        "output": 0.01000    # $10.000 per 1M tokens
    },
    "gpt-5-mini": {
        "input": 0.00025,    # $0.250 per 1M tokens
        "output": 0.00200    # $2.000 per 1M tokens
    },
    "gpt-5-nano": {
        "input": 0.00005,    # $0.050 per 1M tokens
        "output": 0.00040    # $0.400 per 1M tokens
    },
    "gpt-5-pro": {
        "input": 0.01500,    # $15.00 per 1M tokens
        "output": 0.12000    # $120.00 per 1M tokens
    },
    # GPT-4.1 Series
    "gpt-4.1": {
        "input": 0.00300,
        "output": 0.01200
    },
    "gpt-4.1-mini": {
        "input": 0.00080,
        "output": 0.00320
    },
    "gpt-4.1-nano": {
        "input": 0.00020,
        "output": 0.00080
    },
    # o4-mini
    "o4-mini": {
        "input": 0.00400,
        "output": 0.01600
    },
    # Legacy models (estimated pricing)
    "gpt-4o": {
        "input": 0.00250,
        "output": 0.01000
    },
    "gpt-4o-mini": {
        "input": 0.00015,
        "output": 0.00060
    },
    "gpt-4-turbo": {
        "input": 0.01000,
        "output": 0.03000
    },
    "gpt-4": {
        "input": 0.03000,
        "output": 0.06000
    }
}
