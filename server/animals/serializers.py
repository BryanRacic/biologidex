"""
Serializers for animals app.
"""
from rest_framework import serializers
from .models import Animal


class AnimalSerializer(serializers.ModelSerializer):
    """Serializer for Animal model."""
    taxonomic_tree = serializers.ReadOnlyField(source='get_taxonomic_tree')
    discovery_count = serializers.ReadOnlyField()
    created_by_username = serializers.CharField(
        source='created_by.username',
        read_only=True
    )

    class Meta:
        model = Animal
        fields = [
            'id',
            'scientific_name',
            'common_name',
            'kingdom',
            'phylum',
            'class_name',
            'order',
            'family',
            'genus',
            'species',
            'description',
            'habitat',
            'diet',
            'conservation_status',
            'interesting_facts',
            'creation_index',
            'created_by',
            'created_by_username',
            'verified',
            'created_at',
            'updated_at',
            'taxonomic_tree',
            'discovery_count',
        ]
        read_only_fields = [
            'id',
            'creation_index',
            'created_by',
            'created_at',
            'updated_at',
        ]


class AnimalListSerializer(serializers.ModelSerializer):
    """Lightweight serializer for animal lists."""
    created_by_username = serializers.CharField(
        source='created_by.username',
        read_only=True
    )

    class Meta:
        model = Animal
        fields = [
            'id',
            'scientific_name',
            'common_name',
            'conservation_status',
            'creation_index',
            'created_by_username',
            'verified',
        ]


class AnimalCreateSerializer(serializers.ModelSerializer):
    """Serializer for creating new animals (from CV identification)."""

    class Meta:
        model = Animal
        fields = [
            'scientific_name',
            'common_name',
            'kingdom',
            'phylum',
            'class_name',
            'order',
            'family',
            'genus',
            'species',
            'description',
            'habitat',
            'diet',
            'conservation_status',
            'interesting_facts',
        ]

    def create(self, validated_data):
        """Create animal and set created_by from context."""
        user = self.context.get('user')
        if user and user.is_authenticated:
            validated_data['created_by'] = user
        return super().create(validated_data)
