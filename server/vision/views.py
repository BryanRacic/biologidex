"""
Views for vision app.
"""
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from django_filters.rest_framework import DjangoFilterBackend
from rest_framework import filters
from django.db import models, transaction
from .models import AnalysisJob
from .serializers import (
    AnalysisJobSerializer,
    AnalysisJobCreateSerializer,
    AnalysisJobListSerializer,
)
from .tasks import process_analysis_job


class AnalysisJobViewSet(viewsets.ModelViewSet):
    """
    ViewSet for AnalysisJob operations.
    Users can submit images for identification and check job status.
    """
    queryset = AnalysisJob.objects.select_related('user', 'identified_animal').all()
    serializer_class = AnalysisJobSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    filterset_fields = ['status', 'cv_method']
    ordering_fields = ['created_at', 'completed_at']
    ordering = ['-created_at']

    def get_queryset(self):
        """Users can only see their own jobs."""
        return self.queryset.filter(user=self.request.user)

    def get_serializer_class(self):
        """Return appropriate serializer based on action."""
        if self.action == 'list':
            return AnalysisJobListSerializer
        elif self.action == 'create':
            return AnalysisJobCreateSerializer
        return AnalysisJobSerializer

    def create(self, request, *args, **kwargs):
        """
        Create a new analysis job and start processing.
        """
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        job = serializer.save()

        # Trigger async processing AFTER transaction commits
        # This prevents race condition where Celery tries to fetch job before it's committed
        transaction.on_commit(lambda: process_analysis_job.delay(str(job.id)))

        # Return full job details
        response_serializer = AnalysisJobSerializer(job)
        return Response(
            response_serializer.data,
            status=status.HTTP_201_CREATED
        )

    @action(detail=False, methods=['get'])
    def pending(self, request):
        """Get user's pending analysis jobs."""
        jobs = self.get_queryset().filter(status='pending')
        serializer = AnalysisJobListSerializer(jobs, many=True)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def processing(self, request):
        """Get user's currently processing jobs."""
        jobs = self.get_queryset().filter(status='processing')
        serializer = AnalysisJobListSerializer(jobs, many=True)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def completed(self, request):
        """Get user's completed jobs."""
        jobs = self.get_queryset().filter(status='completed')
        page = self.paginate_queryset(jobs)
        if page is not None:
            serializer = AnalysisJobListSerializer(page, many=True)
            return self.get_paginated_response(serializer.data)

        serializer = AnalysisJobListSerializer(jobs, many=True)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def failed(self, request):
        """Get user's failed jobs."""
        jobs = self.get_queryset().filter(status='failed')
        serializer = AnalysisJobListSerializer(jobs, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['post'])
    def retry(self, request, pk=None):
        """
        Retry a failed analysis job.
        """
        job = self.get_object()

        if job.status not in ['failed']:
            return Response(
                {'error': 'Only failed jobs can be retried'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Reset job status
        job.status = 'pending'
        job.error_message = ''
        job.save(update_fields=['status', 'error_message'])

        # Trigger processing again AFTER transaction commits
        transaction.on_commit(lambda: process_analysis_job.delay(str(job.id)))

        serializer = self.get_serializer(job)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def stats(self, request):
        """Get statistics about user's analysis jobs."""
        queryset = self.get_queryset()

        stats = {
            'total_jobs': queryset.count(),
            'pending': queryset.filter(status='pending').count(),
            'processing': queryset.filter(status='processing').count(),
            'completed': queryset.filter(status='completed').count(),
            'failed': queryset.filter(status='failed').count(),
            'total_cost_usd': sum(
                float(job.cost_usd) for job in queryset.filter(cost_usd__isnull=False)
            ),
            'avg_processing_time': queryset.filter(
                processing_time__isnull=False
            ).aggregate(
                avg_time=models.Avg('processing_time')
            )['avg_time'],
        }

        return Response(stats)
