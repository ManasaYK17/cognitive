from datetime import timedelta
from django.core.signing import loads
import mimetypes
from django.db import models
from django.db.models import Case, F, IntegerField, Q, Value, When
from django.db.models.functions import Coalesce
from django.utils import timezone
from django.http import FileResponse
from django.shortcuts import get_object_or_404
from django.urls import reverse
from django.contrib.contenttypes.models import ContentType
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView
from .models import RecognitionHistory
from .serializers import HistoryFeedSerializer, PatientHistorySummarySerializer, RecognitionHistorySerializer
from conversations.models import ConversationHistory
from conversations.services import localize_conversation_content
from known_people.models import KnownPerson
from patients.auth import resolve_patient_from_token
from patients.models import FaceImage


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
            'timestamp_alias', 'confidence_score', 'source', 'outcome', 'summary', 'transcript', 'error_message', 'captured_image'
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
            'timestamp_alias', 'confidence_score', 'source', 'outcome', 'summary', 'transcript', 'error_message', 'captured_image'
        )

        combined = []
        for item in recognition_data:
            item['timestamp'] = item.pop('timestamp_alias')
            item['captured_image'] = self._capture_image_url(request, item)
            combined.append(item)
        for item in conversation_data:
            item['timestamp'] = item.pop('timestamp_alias')
            item['captured_image'] = self._capture_image_url(request, item)
            combined.append(item)
        return sorted(combined, key=lambda item: item['timestamp'], reverse=True)

    @staticmethod
    def _capture_image_url(request, item):
        if not item.get('captured_image'):
            return None
        return request.build_absolute_uri(reverse(
            'history-capture-image',
            kwargs={'event_type': item['event_type'], 'pk': item['id']},
        ))


class HistoryCaptureImageView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, event_type, pk):
        if event_type == 'conversation':
            event = get_object_or_404(ConversationHistory, pk=pk, patient__caregiver=request.user)
        elif event_type == 'recognition':
            event = get_object_or_404(RecognitionHistory, pk=pk, patient__caregiver=request.user)
        else:
            return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)
        image = event.captured_image
        if not image:
            return Response({'detail': 'No capture image found.'}, status=status.HTTP_404_NOT_FOUND)
        return FileResponse(
            image.open('rb'),
            content_type=mimetypes.guess_type(image.name)[0] or 'application/octet-stream',
        )


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

        known_person_id = request.query_params.get('known_person_id')
        target_language = request.query_params.get('language') or 'English'
        summary_only = request.query_params.get('summary_only') == 'true'
        history_qs = ConversationHistory.objects.filter(patient_id=patient_id)
        if known_person_id:
            history_qs = history_qs.filter(known_person_id=known_person_id).order_by('-created_at')
            limit = request.query_params.get('limit')
            if limit:
                try:
                    history_qs = history_qs[:max(1, min(int(limit), 100))]
                except (TypeError, ValueError):
                    pass
            response_data = [
                self._serialize_conversation(request, item, target_language, include_transcript=not summary_only)
                for item in history_qs
            ]
            return Response(response_data)

        history_qs = history_qs.order_by('known_person_id', '-created_at')
        latest_by_person = {}
        for item in history_qs:
            kp_id = item.known_person_id
            if kp_id not in latest_by_person:
                latest_by_person[kp_id] = item

        latest_items = list(latest_by_person.values())
        limit = request.query_params.get('limit')
        if limit:
            try:
                latest_items = latest_items[:max(1, min(int(limit), 100))]
            except (TypeError, ValueError):
                pass

        response_data = []
        for item in latest_items:
            localized = localize_conversation_content(item, target_language, include_transcript=False)
            response_data.append({
                'known_person_id': item.known_person_id,
                'known_person_name': item.known_person.name,
                'known_person_image': self._patient_image_url(
                    request,
                    'known-person',
                    item.known_person_id,
                ) if item.known_person.name.strip().lower() not in {'unknown', 'unknown person'} else None,
                'last_summary': localized['summary'],
                'last_summary_at': item.created_at,
                'translation_error': localized['translation_error'],
            })

        serializer = PatientHistorySummarySerializer(response_data, many=True)
        return Response(serializer.data)

    @staticmethod
    def _patient_image_url(request, image_type, pk):
        return request.build_absolute_uri(reverse(
            'patient-history-image',
            kwargs={'image_type': image_type, 'pk': pk},
        ))

    @classmethod
    def _serialize_conversation(cls, request, item, target_language, include_transcript=True):
        localized = localize_conversation_content(item, target_language, include_transcript=include_transcript)
        return {
            'id': item.id,
            'known_person_id': item.known_person_id,
            'known_person_name': item.known_person.name,
            'summary': localized['summary'],
            'transcript': localized['transcript'],
            'error_message': item.error_message or localized['translation_error'],
            'created_at': item.created_at,
            'captured_image': cls._patient_image_url(request, 'conversation', item.id) if item.captured_image else None,
        }


class PatientHistoryImageView(APIView):
    authentication_classes = []
    permission_classes = [permissions.AllowAny]

    def get(self, request, image_type, pk):
        auth_header = request.META.get('HTTP_AUTHORIZATION', '')
        token = auth_header.replace('Bearer ', '', 1).strip() if auth_header.startswith('Bearer ') else ''
        patient = resolve_patient_from_token(token)
        if patient is None:
            return Response({'detail': 'Invalid patient session token.'}, status=status.HTTP_401_UNAUTHORIZED)

        if image_type == 'conversation':
            event = get_object_or_404(ConversationHistory, pk=pk, patient=patient)
            image = event.captured_image
        elif image_type == 'known-person':
            person = get_object_or_404(KnownPerson, pk=pk, patient=patient)
            content_type = ContentType.objects.get_for_model(KnownPerson)
            face = FaceImage.objects.filter(
                content_type=content_type,
                object_id=person.id,
            ).order_by('-created_at').first()
            image = face.image if face else None
        else:
            return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)

        if not image:
            return Response({'detail': 'No image found.'}, status=status.HTTP_404_NOT_FOUND)
        return FileResponse(
            image.open('rb'),
            content_type=mimetypes.guess_type(image.name)[0] or 'application/octet-stream',
        )

class PatientRecognitionView(APIView):
    authentication_classes = []
    permission_classes = [permissions.AllowAny]
    STALE_MATCH_WINDOW = timedelta(seconds=20)

    def get(self, request, *args, **kwargs):
        auth_header = request.META.get('HTTP_AUTHORIZATION', '')
        token = auth_header.replace('Bearer ', '', 1).strip() if auth_header.startswith('Bearer ') else ''
        try:
            payload = loads(token)
            patient_id = payload.get('patient_id') if isinstance(payload, dict) else None
        except Exception:
            patient_id = None
        if not patient_id:
            return Response({'detail': 'Invalid patient session token.'}, status=status.HTTP_401_UNAUTHORIZED)

        after = request.query_params.get('after')
        events = RecognitionHistory.objects.filter(
            patient_id=patient_id,
            subject_type='known_person',
            source='specs_hardware',
        ).order_by('-timestamp')
        if after:
            events = events.filter(timestamp__gt=after)
        event = events.first()
        if event is None:
            return Response({'match': False})
        timestamp = event.timestamp
        if timestamp < (timezone.now() - self.STALE_MATCH_WINDOW):
            return Response({'match': False})
        if event.outcome != 'matched' or event.subject is None:
            return Response({'match': False, 'timestamp': timestamp})
        person = event.subject
        if not isinstance(person, KnownPerson) or not person.name.strip() or person.name.lower().startswith('unnamed'):
            return Response({'match': False, 'timestamp': timestamp})
        return Response({
            'match': True,
            'patient_id': patient_id,
            'known_person_id': person.id,
            'name': person.name,
            'relationship': person.relationship,
            'timestamp': timestamp,
        })
