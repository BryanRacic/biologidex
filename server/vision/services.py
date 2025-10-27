"""
CV services for animal identification.
Integrates OpenAI Vision API and other CV methods.
"""
import base64
import logging
import time
from typing import Dict, Tuple, Optional
from django.conf import settings
from openai import OpenAI
from .constants import ANIMAL_ID_PROMPT, OPENAI_PRICING

logger = logging.getLogger(__name__)


class CVService:
    """Base class for computer vision services."""

    def identify_animal(self, image_path: str) -> Dict:
        """
        Identify animal in image.
        Returns dict with: prediction, cost_usd, processing_time, raw_response
        """
        raise NotImplementedError


class OpenAIVisionService(CVService):
    """
    OpenAI Vision API service for animal identification.
    Adapted from animal_id_benchmark.py
    """

    def __init__(self, model: str = "gpt-4o", detail: str = "auto"):
        """
        Initialize OpenAI Vision service.

        Args:
            model: OpenAI model to use (e.g., gpt-4o, gpt-5-mini)
            detail: Image detail level (auto, low, high)
        """
        api_key = settings.OPENAI_API_KEY
        if not api_key:
            logger.warning("OPENAI_API_KEY not configured - CV identification will not work")
            self.client = None
            self.configured = False
        else:
            self.client = OpenAI(api_key=api_key)
            self.configured = True

        self.model = model
        self.detail = detail

    def encode_image(self, image_path: str) -> str:
        """Encode image file to base64."""
        with open(image_path, "rb") as image_file:
            return base64.b64encode(image_file.read()).decode("utf-8")

    def encode_image_from_bytes(self, image_bytes: bytes) -> str:
        """Encode image bytes to base64."""
        return base64.b64encode(image_bytes).decode("utf-8")

    def identify_animal(self, image_path: str) -> Dict:
        """
        Identify animal using OpenAI Vision API.

        Returns:
            Dict with keys: prediction, cost_usd, processing_time, raw_response,
                          input_tokens, output_tokens
        """
        # Check if service is configured
        if not self.configured:
            error_msg = "OpenAI Vision API not configured - please set OPENAI_API_KEY"
            logger.error(error_msg)
            return {
                'prediction': "Service not configured",
                'cost_usd': 0.0,
                'processing_time': 0.0,
                'raw_response': error_msg,
                'input_tokens': 0,
                'output_tokens': 0,
                'error': error_msg
            }

        start_time = time.time()

        try:
            # Check if image_path is a file path or a Django File object
            if hasattr(image_path, 'read'):
                # It's a file-like object (Django File)
                base64_image = self.encode_image_from_bytes(image_path.read())
            else:
                # It's a file path
                base64_image = self.encode_image(image_path)

            # Determine token parameter based on model
            is_gpt5_or_later = (
                self.model.startswith("gpt-5") or
                self.model.startswith("o1") or
                self.model.startswith("o3") or
                self.model.startswith("o4")
            )

            # Build request parameters
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

            # Add appropriate token limit parameter
            if is_gpt5_or_later:
                request_params["max_completion_tokens"] = 300
            else:
                request_params["max_tokens"] = 300

            # Make API call
            response = self.client.chat.completions.create(**request_params)
            processing_time = time.time() - start_time

            # Extract prediction
            prediction = response.choices[0].message.content.strip()

            # Calculate cost
            cost_usd = self._calculate_cost(response.usage) if response.usage else 0.0

            # Get token counts
            input_tokens = response.usage.prompt_tokens if response.usage else 0
            output_tokens = response.usage.completion_tokens if response.usage else 0

            logger.info(
                f"OpenAI Vision API call completed: model={self.model}, "
                f"cost=${cost_usd:.6f}, time={processing_time:.2f}s"
            )

            return {
                'prediction': prediction,
                'cost_usd': float(cost_usd),
                'processing_time': processing_time,
                'raw_response': response.model_dump(),
                'input_tokens': input_tokens,
                'output_tokens': output_tokens,
            }

        except Exception as e:
            processing_time = time.time() - start_time
            logger.error(f"OpenAI Vision API error: {e}")
            raise

    def _calculate_cost(self, usage) -> float:
        """Calculate cost based on token usage and model pricing."""
        if not usage:
            return 0.0

        # Get pricing for model
        model_pricing = None
        for model_key in OPENAI_PRICING:
            if self.model.startswith(model_key):
                model_pricing = OPENAI_PRICING[model_key]
                break

        if not model_pricing:
            logger.warning(f"No pricing data for model {self.model}, using gpt-4o pricing")
            model_pricing = OPENAI_PRICING['gpt-4o']

        # Calculate cost (pricing is per 1K tokens)
        input_cost = (usage.prompt_tokens / 1000) * model_pricing['input']
        output_cost = (usage.completion_tokens / 1000) * model_pricing['output']

        return input_cost + output_cost


class CVServiceFactory:
    """Factory for creating CV services."""

    @staticmethod
    def create(method: str = 'openai', **kwargs) -> CVService:
        """
        Create a CV service instance.

        Args:
            method: CV method to use ('openai', 'fallback')
            **kwargs: Additional arguments for the service

        Returns:
            CVService instance
        """
        if method == 'openai':
            model = kwargs.get('model', 'gpt-4o')
            detail = kwargs.get('detail', 'auto')
            return OpenAIVisionService(model=model, detail=detail)
        else:
            raise ValueError(f"Unknown CV method: {method}")
