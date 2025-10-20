#!/usr/bin/env python3
"""
A script that benchmarks performance of different image recognition methods
across a known dataset of test images located at: resources/test_images
"""

import base64
import csv
import logging
import os
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from dotenv import load_dotenv
from openai import OpenAI

# Load environment variables from parent directory's .env file
env_path = Path(__file__).parent.parent / ".env"
load_dotenv(dotenv_path=env_path)

# Prompt constant for animal identification
ANIMAL_ID_PROMPT = " ".join([
'Please identify the animal(s) in this image.',
'Provide a specific species name if possible, or a general animal type if the species cannot be determined.',
'If there are multiple animals, list all of them.',
'Your response should be formatted in Binomial nomenclature, formatted as the following `genus, species (common name)` if at least one animal can be identified.',
'If no animals can be identified, return `NO ANIMALS FOUND` ',
])


# Configuration
TEST_IMAGES_DIR = Path("../resources/test_images")
IMAGE_KEY_FILE = TEST_IMAGES_DIR / "image_key.csv"
LOG_FILE = "animal_id_benchmark.log"


@dataclass
class BenchmarkResult:
    """Results from a single image recognition test"""
    image_path: str
    ground_truth: str
    prediction: str
    model_name: str
    detail_level: str
    cost_usd: Optional[float]
    runtime_seconds: float
    timestamp: str


class CVMethod(ABC):
    """Abstract base class for computer vision methods"""
    
    @abstractmethod
    def identify_animal(self, image_path: str) -> Tuple[str, float, float]:
        """
        Identify animal in image
        Returns: (prediction, cost_usd, runtime_seconds)
        """
        pass
    
    @abstractmethod
    def get_method_name(self) -> str:
        """Get the name of this CV method"""
        pass


class OpenAIVisionMethod(CVMethod):
    """OpenAI Vision API implementation"""
    
    def __init__(self, model: str = "gpt-4o", detail: str = "auto"):
        api_key = os.getenv("OPENAI_API_KEY")
        if not api_key:
            raise ValueError("OPENAI_API_KEY not found in environment variables. Please set it in your .env file.")
        
        self.client = OpenAI(api_key=api_key)
        self.model = model
        self.detail = detail
        
    def encode_image(self, image_path: str) -> str:
        """Encode image to base64"""
        with open(image_path, "rb") as image_file:
            return base64.b64encode(image_file.read()).decode("utf-8")
    
    def identify_animal(self, image_path: str) -> Tuple[str, float, float]:
        """Identify animal using OpenAI Vision API"""
        start_time = time.time()

        try:
            base64_image = self.encode_image(image_path)

            # GPT-5 models use max_completion_tokens, GPT-4 and earlier use max_tokens
            is_gpt5_or_later = self.model.startswith("gpt-5") or self.model.startswith("o1") or self.model.startswith("o3") or self.model.startswith("o4")

            request_params = {
                "model": self.model,
                "messages": [
                    {
                        "role": "user",
                        "content": [
                            {"type": "text", "text": ANIMAL_ID_PROMPT},
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:image/jpeg;base64,{base64_image}",
                                    "detail": self.detail
                                }
                            }
                        ]
                    }
                ],
            }

            # Add the correct token limit parameter based on model version
            if is_gpt5_or_later:
                request_params["max_completion_tokens"] = 300
            else:
                request_params["max_tokens"] = 300

            response = self.client.chat.completions.create(**request_params)
            logging.info(response)
            runtime = time.time() - start_time
            prediction = response.choices[0].message.content.strip()
            
            # Calculate cost based on actual token usage and model pricing
            cost = self._calculate_cost(response.usage) if response.usage else 0.0
            
            return prediction, cost, runtime
            
        except Exception as e:
            runtime = time.time() - start_time
            logging.error(f"Error processing {image_path} with {self.get_method_name()}: {e}")
            return f"ERROR: {str(e)}", 0.0, runtime
    
    def _calculate_cost(self, usage) -> float:
        """Calculate exact cost based on OpenAI's actual token usage and current pricing"""
        if not usage:
            return 0.0
            
        # OpenAI pricing as of October 2025 (prices per 1K tokens)
        # Note: Prices shown are per 1M tokens from docs, converted to per 1K tokens here
        pricing = {
            # GPT-5 Series
            "gpt-5": {
                "input": 0.001250,   # $1.250 per 1M tokens = $0.001250 per 1K
                "output": 0.01000    # $10.000 per 1M tokens = $0.01000 per 1K
            },
            "gpt-5-mini": {
                "input": 0.00025,    # $0.250 per 1M tokens = $0.00025 per 1K
                "output": 0.00200    # $2.000 per 1M tokens = $0.00200 per 1K
            },
            "gpt-5-nano": {
                "input": 0.00005,    # $0.050 per 1M tokens = $0.00005 per 1K
                "output": 0.00040    # $0.400 per 1M tokens = $0.00040 per 1K
            },
            "gpt-5-pro": {
                "input": 0.01500,    # $15.00 per 1M tokens = $0.01500 per 1K
                "output": 0.12000    # $120.00 per 1M tokens = $0.12000 per 1K
            },
            # GPT-4.1 Series
            "gpt-4.1": {
                "input": 0.00300,    # $3.00 per 1M tokens = $0.00300 per 1K
                "output": 0.01200    # $12.00 per 1M tokens = $0.01200 per 1K
            },
            "gpt-4.1-mini": {
                "input": 0.00080,    # $0.80 per 1M tokens = $0.00080 per 1K
                "output": 0.00320    # $3.20 per 1M tokens = $0.00320 per 1K
            },
            "gpt-4.1-nano": {
                "input": 0.00020,    # $0.20 per 1M tokens = $0.00020 per 1K
                "output": 0.00080    # $0.80 per 1M tokens = $0.00080 per 1K
            },
            # o4-mini (for reinforcement fine-tuning)
            "o4-mini": {
                "input": 0.00400,    # $4.00 per 1M tokens = $0.00400 per 1K
                "output": 0.01600    # $16.00 per 1M tokens = $0.01600 per 1K
            },
            # Legacy models (keeping for compatibility)
            "gpt-4o": {
                "input": 0.00250,    # Estimated legacy pricing
                "output": 0.01000
            },
            "gpt-4o-mini": {
                "input": 0.00015,    # Estimated legacy pricing
                "output": 0.00060
            },
            "gpt-4-turbo": {
                "input": 0.01000,    # Estimated legacy pricing
                "output": 0.03000
            },
            "gpt-4": {
                "input": 0.03000,    # Estimated legacy pricing
                "output": 0.06000
            }
        }
        
        # Get pricing for the model, default to gpt-4o if not found
        model_pricing = pricing.get(self.model, pricing["gpt-4o"])
        
        # Calculate cost: (input_tokens / 1000) * input_rate + (output_tokens / 1000) * output_rate
        input_cost = (usage.prompt_tokens / 1000) * model_pricing["input"]
        output_cost = (usage.completion_tokens / 1000) * model_pricing["output"]
        
        return input_cost + output_cost
    
    def get_method_name(self) -> str:
        return f"OpenAI_{self.model}_{self.detail}"


class AnimalIDBenchmark:
    """Main benchmark orchestrator"""
    
    def __init__(self):
        self.setup_logging()
        self.ground_truth = self.load_ground_truth()
        self.results: List[BenchmarkResult] = []
    
    def setup_logging(self):
        """Configure logging to file"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(LOG_FILE, mode='w'),
                logging.StreamHandler()  # Also log to console
            ]
        )
        logging.info("Animal ID Benchmark starting...")
    
    def load_ground_truth(self) -> Dict[str, str]:
        """Load ground truth data from CSV"""
        ground_truth = {}
        try:
            with open(IMAGE_KEY_FILE, 'r') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    image_index = row['image index'].strip()
                    contents = row['image contents'].strip()
                    ground_truth[image_index] = contents
            logging.info(f"Loaded ground truth for {len(ground_truth)} images")
        except Exception as e:
            logging.error(f"Failed to load ground truth: {e}")
        return ground_truth
    
    def get_test_images(self) -> List[Path]:
        """Get list of test image files"""
        image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.tiff'}
        images = []
        
        for file_path in TEST_IMAGES_DIR.iterdir():
            if file_path.suffix.lower() in image_extensions and file_path.name != 'image_key.csv':
                images.append(file_path)
        
        images.sort(key=lambda x: x.stem)  # Sort by filename
        logging.info(f"Found {len(images)} test images")
        return images
    
    def run_benchmark(self, cv_methods: List[CVMethod]):
        """Run benchmark across all methods and images"""
        test_images = self.get_test_images()
        
        if not test_images:
            logging.error("No test images found!")
            return
        
        total_tests = len(test_images) * len(cv_methods)
        current_test = 0
        
        for image_path in test_images:
            # Extract image index from filename (e.g., "1.jpeg" -> "1")
            image_index = image_path.stem.split('.')[0]
            ground_truth = self.ground_truth.get(image_index, "UNKNOWN")
            
            logging.info(f"Processing image {image_index}: {image_path.name}")
            logging.info(f"Ground truth: {ground_truth}")
            
            for method in cv_methods:
                current_test += 1
                logging.info(f"Test {current_test}/{total_tests}: {method.get_method_name()} on {image_path.name}")
                
                prediction, cost, runtime = method.identify_animal(str(image_path))
                
                result = BenchmarkResult(
                    image_path=str(image_path),
                    ground_truth=ground_truth,
                    prediction=prediction,
                    model_name=method.get_method_name(),
                    detail_level=getattr(method, 'detail', 'N/A'),
                    cost_usd=cost,
                    runtime_seconds=runtime,
                    timestamp=time.strftime('%Y-%m-%d %H:%M:%S')
                )
                
                self.results.append(result)
                logging.info(f"Prediction: {prediction}")
                logging.info(f"Cost: ${cost:.4f}")
                logging.info(f"Runtime: {runtime:.2f}s")
                logging.info(f"Match: {'✓' if self.predictions_match(ground_truth, prediction) else '✗'}")
                logging.info("-" * 80)
    
    def predictions_match(self, ground_truth: str, prediction: str) -> bool:
        """Simple matching logic - can be enhanced with fuzzy matching"""
        if ground_truth == "UNKNOWN":
            return False
        
        # Convert to lowercase and check for key terms
        gt_lower = ground_truth.lower().replace('_', ' ')
        pred_lower = prediction.lower()
        
        # Split ground truth into words and check if any are in prediction
        gt_words = gt_lower.split()
        return any(word in pred_lower for word in gt_words if len(word) > 2)
    
    def generate_summary(self):
        """Generate benchmark summary"""
        if not self.results:
            logging.warning("No results to summarize")
            return
        
        logging.info("=" * 80)
        logging.info("BENCHMARK SUMMARY")
        logging.info("=" * 80)
        
        total_cost = sum(r.cost_usd or 0 for r in self.results)
        total_runtime = sum(r.runtime_seconds for r in self.results)
        total_tests = len(self.results)
        
        logging.info(f"Total tests: {total_tests}")
        logging.info(f"Total cost: ${total_cost:.4f}")
        logging.info(f"Total runtime: {total_runtime:.2f}s")
        logging.info(f"Average cost per test: ${total_cost/total_tests:.4f}")
        logging.info(f"Average runtime per test: {total_runtime/total_tests:.2f}s")
        
        # Method-wise summary
        method_stats = {}
        for result in self.results:
            method = result.model_name
            if method not in method_stats:
                method_stats[method] = {
                    'total_cost': 0,
                    'total_runtime': 0,
                    'total_tests': 0,
                    'matches': 0
                }
            
            method_stats[method]['total_cost'] += result.cost_usd or 0
            method_stats[method]['total_runtime'] += result.runtime_seconds
            method_stats[method]['total_tests'] += 1
            if self.predictions_match(result.ground_truth, result.prediction):
                method_stats[method]['matches'] += 1
        
        logging.info("\nMethod Performance:")
        for method, stats in method_stats.items():
            accuracy = stats['matches'] / stats['total_tests'] * 100
            avg_cost = stats['total_cost'] / stats['total_tests']
            avg_runtime = stats['total_runtime'] / stats['total_tests']
            
            logging.info(f"{method}:")
            logging.info(f"  Accuracy: {accuracy:.1f}% ({stats['matches']}/{stats['total_tests']})")
            logging.info(f"  Avg Cost: ${avg_cost:.4f}")
            logging.info(f"  Avg Runtime: {avg_runtime:.2f}s")


def main():
    """Main function to run the benchmark"""
    benchmark = AnimalIDBenchmark()
    
    # Define CV methods to test
    cv_methods = [
        # Legacy models
        #OpenAIVisionMethod("gpt-4o", "low"),
        #OpenAIVisionMethod("gpt-4o", "high"),
        OpenAIVisionMethod("gpt-4o-mini", "low"),
        #OpenAIVisionMethod("gpt-4o-mini", "high"),
        # Newer models (uncomment if available)
        # OpenAIVisionMethod("gpt-4.1", "low"),
        # OpenAIVisionMethod("gpt-4.1-mini", "low"),
        # OpenAIVisionMethod("gpt-4.1-nano", "low"),
        # OpenAIVisionMethod("gpt-5-nano", "low"),
        # OpenAIVisionMethod("gpt-5-mini", "low"),
    ]
    
    logging.info(f"Testing {len(cv_methods)} CV methods:")
    for method in cv_methods:
        logging.info(f"  - {method.get_method_name()}")
    
    # Run the benchmark
    benchmark.run_benchmark(cv_methods)
    
    # Generate summary
    benchmark.generate_summary()
    
    logging.info(f"Benchmark complete! Results logged to {LOG_FILE}")


if __name__ == "__main__":
    main()