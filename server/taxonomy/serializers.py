# taxonomy/serializers.py
from rest_framework import serializers
from .models import Taxonomy, DataSource, CommonName, GeographicDistribution, TaxonomicRank


class DataSourceSerializer(serializers.ModelSerializer):
    """Serializer for data sources"""

    class Meta:
        model = DataSource
        fields = [
            'id', 'name', 'short_code', 'full_name', 'url',
            'update_frequency', 'license', 'is_active', 'priority'
        ]


class TaxonomicRankSerializer(serializers.ModelSerializer):
    """Serializer for taxonomic ranks"""

    class Meta:
        model = TaxonomicRank
        fields = ['name', 'level', 'plural']


class CommonNameSerializer(serializers.ModelSerializer):
    """Serializer for common names"""

    class Meta:
        model = CommonName
        fields = ['name', 'language', 'country', 'is_preferred']


class GeographicDistributionSerializer(serializers.ModelSerializer):
    """Serializer for geographic distributions"""

    class Meta:
        model = GeographicDistribution
        fields = [
            'area_code', 'gazetteer', 'area_name',
            'establishment_means', 'occurrence_status', 'threat_status'
        ]


class TaxonomySerializer(serializers.ModelSerializer):
    """Serializer for taxonomy records"""
    source = DataSourceSerializer(read_only=True)
    rank = TaxonomicRankSerializer(read_only=True)
    common_names = CommonNameSerializer(many=True, read_only=True)
    distributions = GeographicDistributionSerializer(many=True, read_only=True)
    full_hierarchy = serializers.ReadOnlyField()

    class Meta:
        model = Taxonomy
        fields = [
            'id', 'source', 'source_taxon_id', 'scientific_name',
            'authorship', 'rank', 'status',
            # Hierarchy
            'kingdom', 'phylum', 'class_name', 'order', 'family',
            'subfamily', 'genus', 'species', 'subspecies',
            # Name components
            'generic_name', 'specific_epithet',
            # Metadata
            'extinct', 'environment', 'nomenclatural_code',
            'source_url', 'completeness_score', 'confidence_score',
            # Related data
            'common_names', 'distributions', 'full_hierarchy',
            # Timestamps
            'created_at', 'updated_at'
        ]


class TaxonomyMinimalSerializer(serializers.ModelSerializer):
    """Minimal serializer for taxonomy - used in lists"""
    source_name = serializers.CharField(source='source.short_code', read_only=True)
    rank_name = serializers.CharField(source='rank.name', read_only=True)
    common_names = CommonNameSerializer(many=True, read_only=True)

    class Meta:
        model = Taxonomy
        fields = [
            'id', 'scientific_name', 'rank_name', 'status',
            'kingdom', 'phylum', 'class_name', 'order', 'family', 'genus',
            'source_name', 'completeness_score', 'common_names'
        ]


class TaxonomyValidationSerializer(serializers.Serializer):
    """Serializer for validating scientific names"""
    scientific_name = serializers.CharField(required=True)
    common_name = serializers.CharField(required=False, allow_blank=True)
    confidence = serializers.FloatField(required=False, default=0.0)
