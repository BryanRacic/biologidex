"""
Serializers for vision app.
"""
from rest_framework import serializers
from .models import AnalysisJob
from animals.serializers import AnimalListSerializer


class AnalysisJobSerializer(serializers.ModelSerializer):
    """Full serializer for AnalysisJob model."""
    animal_details = AnimalListSerializer(source='identified_animal', read_only=True)
    duration = serializers.ReadOnlyField()

    class Meta:
        model = AnalysisJob
        fields = [
            'id',
            'image',
            'user',
            'status',
            'cv_method',
            'model_name',
            'detail_level',
            'parsed_prediction',
            'identified_animal',
            'animal_details',
            'confidence_score',
            'cost_usd',
            'processing_time',
            'input_tokens',
            'output_tokens',
            'error_message',
            'retry_count',
            'created_at',
            'started_at',
            'completed_at',
            'duration',
        ]
        read_only_fields = [
            'id',
            'user',
            'status',
            'parsed_prediction',
            'identified_animal',
            'confidence_score',
            'cost_usd',
            'processing_time',
            'input_tokens',
            'output_tokens',
            'error_message',
            'retry_count',
            'created_at',
            'started_at',
            'completed_at',
        ]


class AnalysisJobCreateSerializer(serializers.ModelSerializer):
    """Serializer for creating analysis jobs."""

    class Meta:
        model = AnalysisJob
        fields = [
            'image',
            'cv_method',
            'model_name',
            'detail_level',
        ]

    def create(self, validated_data):
        """Set user from request context."""
        validated_data['user'] = self.context['request'].user
        return super().create(validated_data)


class AnalysisJobListSerializer(serializers.ModelSerializer):
    """Lightweight serializer for job lists."""

    class Meta:
        model = AnalysisJob
        fields = [
            'id',
            'status',
            'parsed_prediction',
            'identified_animal',
            'cost_usd',
            'created_at',
            'completed_at',
        ]
