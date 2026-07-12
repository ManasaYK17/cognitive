from django.core.signing import loads
from django.db import models
from django.db.models import Case, F, IntegerField, Q, Value, When
from django.db.models.functions import Coalesce
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView
from .models import RecognitionHistory
from .serializers import HistoryFeedSerializer, PatientHistorySummarySerializer, RecognitionHistorySerializer
from conversations.models import ConversationHistory


class RecognitionHistoryListView(generics.ListAPIView):
    serializer_class = RecognitionHistorySerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return RecognitionHistory.objects.filter(patient__caregiver=self.request.user)


class HistoryFeedView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, *args, **kwargs):
        combined = self._build_feed(request)
        serializer = HistoryFeedSerializer(combined, many=True)
        return Response(serializer.data)

    def _build_feed(self, request):
        patient_id = request.query_params.get('patient_id')
        known_person_id = request.query_params.get('known_person_id')
        start_date = request.query_params.get('start_date')
        end_date = request.query_params.get('end_date')
        search = request.query_params.get('search')

        recognition_qs = RecognitionHistory.objects.filter(patient__caregiver=request.user)
        conversation_qs = ConversationHistory.objects.filter(patient__caregiver=request.user)

        if patient_id:
            recognition_qs = recognition_qs.filter(patient_id=patient_id)
            conversation_qs = conversation_qs.filter(patient_id=patient_id)

        if known_person_id:
            recognition_qs = recognition_qs.filter(object_id=known_person_id, subject_type='known_person')
            conversation_qs = conversation_qs.filter(known_person_id=known_person_id)

        if start_date:
            recognition_qs = recognition_qs.filter(timestamp__gte=start_date)
            conversation_qs = conversation_qs.filter(created_at__gte=start_date)

        if end_date:
            recognition_qs = recognition_qs.filter(timestamp__lte=end_date)
            conversation_qs = conversation_qs.filter(created_at__lte=end_date)

        if search:
            recognition_qs = recognition_qs.filter(
                Q(source__icontains=search) | Q(outcome__icontains=search)
            )
            conversation_qs = conversation_qs.filter(
                Q(summary__icontains=search) | Q(transcript__icontains=search)
            )

        recognition_data = recognition_qs.annotate(
            event_type=Value('recognition', output_field=models.CharField()),
            known_person_id=Case(
                When(subject_type='known_person', then=F('object_id')),
                default=Value(None),
                output_field=models.IntegerField(),
            ),
            known_person_name=Value(None, output_field=models.CharField()),
            timestamp_alias=F('timestamp'),
            summary=Value(None, output_field=models.CharField()),
            transcript=Value(None, output_field=models.CharField()),
            error_message=Value(None, output_field=models.CharField()),
        ).values(
            'id', 'event_type', 'patient_id', 'known_person_id', 'known_person_name',
            'timestamp_alias', 'confidence_score', 'source', 'outcome', 'summary', 'transcript', 'error_message'
        )

        conversation_data = conversation_qs.annotate(
            event_type=Value('conversation', output_field=models.CharField()),
            known_person_name=F('known_person__name'),
            timestamp_alias=F('created_at'),
            confidence_score=Value(None, output_field=models.FloatField()),
            source=Value(None, output_field=models.CharField()),
            outcome=Value(None, output_field=models.CharField()),
        ).values(
            'id', 'event_type', 'patient_id', 'known_person_id', 'known_person_name',
            'timestamp_alias', 'confidence_score', 'source', 'outcome', 'summary', 'transcript', 'error_message'
        )

        combined = []
        for item in recognition_data:
            item['timestamp'] = item.pop('timestamp_alias')
            combined.append(item)
        for item in conversation_data:
            item['timestamp'] = item.pop('timestamp_alias')
            combined.append(item)
        return sorted(combined, key=lambda item: item['timestamp'], reverse=True)


class PatientHistoryView(APIView):
    authentication_classes = []
    permission_classes = [permissions.AllowAny]

    def get(self, request, *args, **kwargs):
        auth_header = request.META.get('HTTP_AUTHORIZATION', '')
        token = auth_header.replace('Bearer ', '', 1).strip() if auth_header.startswith('Bearer ') else ''
        if not token:
            return Response({'detail': 'A patient session token is required.'}, status=status.HTTP_401_UNAUTHORIZED)

        try:
            payload = loads(token)
        except Exception:
            return Response({'detail': 'Invalid patient session token.'}, status=status.HTTP_401_UNAUTHORIZED)

        patient_id = payload.get('patient_id') if isinstance(payload, dict) else None
        if not patient_id:
            return Response({'detail': 'Invalid patient session token.'}, status=status.HTTP_401_UNAUTHORIZED)

        history_qs = ConversationHistory.objects.filter(patient_id=patient_id).order_by('known_person_id', '-created_at')
        latest_by_person = {}
        for item in history_qs:
            kp_id = item.known_person_id
            if kp_id not in latest_by_person:
                latest_by_person[kp_id] = {
                    'known_person_id': kp_id,
                    'known_person_name': item.known_person.name,
                    'last_summary': item.summary,
                    'last_summary_at': item.created_at,
                }

        serializer = PatientHistorySummarySerializer(list(latest_by_person.values()), many=True)
        return Response(serializer.data)
