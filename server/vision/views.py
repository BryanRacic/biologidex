"""
Views for vision app.
"""
import json
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from django_filters.rest_framework import DjangoFilterBackend
from rest_framework import filters
from django.db import models, transaction
from django.http import HttpResponse, Http404
from django.views import View
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
        Accepts optional 'transformations' parameter (JSON string or dict).
        """
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        job = serializer.save()

        # Parse transformations from request
        transformations = request.data.get('transformations', None)
        if transformations:
            # Handle both JSON string and dict formats
            if isinstance(transformations, str):
                try:
                    transformations = json.loads(transformations)
                except json.JSONDecodeError:
                    return Response(
                        {'error': 'Invalid transformations JSON'},
                        status=status.HTTP_400_BAD_REQUEST
                    )

        # Trigger async processing AFTER transaction commits
        # This prevents race condition where Celery tries to fetch job before it's committed
        transaction.on_commit(lambda: process_analysis_job.delay(str(job.id), transformations))

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
        Accepts optional 'transformations' parameter to apply new transformations.
        """
        job = self.get_object()

        if job.status not in ['failed']:
            return Response(
                {'error': 'Only failed jobs can be retried'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Parse transformations from request (optional)
        transformations = request.data.get('transformations', None)
        if transformations and isinstance(transformations, str):
            try:
                transformations = json.loads(transformations)
            except json.JSONDecodeError:
                return Response(
                    {'error': 'Invalid transformations JSON'},
                    status=status.HTTP_400_BAD_REQUEST
                )

        # Reset job status
        job.status = 'pending'
        job.error_message = ''
        job.save(update_fields=['status', 'error_message'])

        # Trigger processing again AFTER transaction commits
        transaction.on_commit(lambda: process_analysis_job.delay(str(job.id), transformations))

        serializer = self.get_serializer(job)
        return Response(serializer.data)

    @action(detail=True, methods=['post'])
    def select_animal(self, request, pk=None):
        """
        Select an animal from multiple detected animals.

        POST /api/v1/vision/jobs/{id}/select_animal/
        Body: {"animal_index": 0} or {"animal_id": "uuid"}

        Updates the selected_animal_index field to indicate which animal
        the user selected from the detected_animals list.
        """
        job = self.get_object()

        if not job.detected_animals or len(job.detected_animals) == 0:
            return Response(
                {'error': 'No animals detected in this job'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Accept either animal_index or animal_id
        animal_index = request.data.get('animal_index')
        animal_id = request.data.get('animal_id')

        if animal_index is None and not animal_id:
            return Response(
                {'error': 'Either animal_index or animal_id must be provided'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # If animal_id provided, find the index
        if animal_id:
            found_index = None
            for idx, animal_data in enumerate(job.detected_animals):
                if animal_data.get('animal_id') == str(animal_id):
                    found_index = idx
                    break

            if found_index is None:
                return Response(
                    {'error': 'Animal ID not found in detected animals'},
                    status=status.HTTP_404_NOT_FOUND
                )

            animal_index = found_index

        # Validate index
        if animal_index < 0 or animal_index >= len(job.detected_animals):
            return Response(
                {'error': f'Invalid animal_index. Must be 0-{len(job.detected_animals) - 1}'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Update selected_animal_index
        job.selected_animal_index = animal_index
        selected_animal_data = job.detected_animals[animal_index]

        # Update identified_animal (legacy field) to point to selected animal
        if selected_animal_data.get('animal_id'):
            from animals.models import Animal
            try:
                selected_animal = Animal.objects.get(id=selected_animal_data['animal_id'])
                job.identified_animal = selected_animal
            except Animal.DoesNotExist:
                pass

        job.save(update_fields=['selected_animal_index', 'identified_animal'])

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


class DexCompatibleImageView(View):
    """
    Serve dex-compatible images.

    TODO: Add proper IAM/permission checks:
    - Verify user owns the image OR
    - Image is from a public dex entry OR
    - User has friend access to the owner
    """

    def get(self, request, job_id):
        try:
            job = AnalysisJob.objects.get(id=job_id)

            # TODO: Add permission checks here
            # For now, all dex-compatible images are public

            if not job.dex_compatible_image:
                raise Http404("Dex-compatible image not found")

            # Serve the image
            image_file = job.dex_compatible_image
            response = HttpResponse(image_file.read(), content_type='image/png')
            response['Content-Disposition'] = f'inline; filename="dex_{job_id}.png"'
            response['Cache-Control'] = 'public, max-age=31536000'  # 1 year cache
            return response

        except AnalysisJob.DoesNotExist:
            raise Http404("Job not found")
