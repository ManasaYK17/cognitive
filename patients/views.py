from datetime import timedelta

from django.db import models
from django.db.models import Count, Q
from django.utils import timezone
from rest_framework import generics, permissions, status, views
from rest_framework.response import Response
from rest_framework.parsers import MultiPartParser, FormParser
from .models import Patient, FaceImage
from .serializers import PatientSerializer, FaceImageSerializer
from .permissions import IsCaregiverOwner
from conversations.models import ConversationHistory
from geofencing.models import LocationPing, SafeZone
from history.models import RecognitionHistory


class CaregiverPatientView(views.APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, *args, **kwargs):
        patient = getattr(request.user, 'patient', None)
        if patient is None:
            return Response({'detail': 'No patient found for this caregiver.'}, status=status.HTTP_404_NOT_FOUND)
        serializer = PatientSerializer(patient)
        return Response(serializer.data)

    def post(self, request, *args, **kwargs):
        if getattr(request.user, 'patient', None) is not None:
            return Response({'detail': 'Patient already exists for this caregiver.'}, status=status.HTTP_400_BAD_REQUEST)
        serializer = PatientSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save(caregiver=request.user)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    def put(self, request, *args, **kwargs):
        patient = getattr(request.user, 'patient', None)
        if patient is None:
            return Response({'detail': 'No patient found for this caregiver.'}, status=status.HTTP_404_NOT_FOUND)
        serializer = PatientSerializer(patient, data=request.data, partial=False)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)

    def delete(self, request, *args, **kwargs):
        patient = getattr(request.user, 'patient', None)
        if patient is None:
            return Response({'detail': 'No patient found for this caregiver.'}, status=status.HTTP_404_NOT_FOUND)
        patient.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class PatientDashboardSummaryView(views.APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, pk, *args, **kwargs):
        patient = Patient.objects.filter(id=pk, caregiver=request.user).first()
        if patient is None:
            return Response({'detail': 'Patient not found or unauthorized.'}, status=status.HTTP_404_NOT_FOUND)

        now = timezone.now()
        start_of_today = now.replace(hour=0, minute=0, second=0, microsecond=0)
        start_of_week = start_of_today - timedelta(days=start_of_today.weekday())

        recognition_qs = RecognitionHistory.objects.filter(patient=patient)
        today_recognition = recognition_qs.filter(timestamp__gte=start_of_today)
        week_recognition = recognition_qs.filter(timestamp__gte=start_of_week)

        known_today = today_recognition.filter(outcome='matched').count()
        unknown_today = today_recognition.filter(outcome='not_matched').count()

        weekly_counts = list(
            week_recognition.extra({'day': 'date(timestamp)'}).values('day').annotate(total=Count('id')).order_by('day')
        )
        weekly_series = []
        for idx in range(7):
            day = start_of_week + timedelta(days=idx)
            date_str = day.date().strftime('%Y-%m-%d')
            match = next((item for item in weekly_counts if item['day'] == date_str), None)
            weekly_series.append({'day': day.strftime('%a'), 'count': int(match['total']) if match else 0})

        total_recognitions = week_recognition.count()
        known_week = week_recognition.filter(outcome='matched').count()
        known_ratio = round((known_week / total_recognitions) * 100, 1) if total_recognitions else 0.0
        unknown_ratio = round(100 - known_ratio, 1) if total_recognitions else 0.0

        average_confidence = round(
            week_recognition.exclude(confidence_score__isnull=True).aggregate(avg=models.Avg('confidence_score'))['avg'] or 0.0,
            2,
        )

        conversations_saved = ConversationHistory.objects.filter(patient=patient).count()

        safe_zone = SafeZone.objects.filter(patient=patient).first()
        last_ping = LocationPing.objects.filter(patient=patient).order_by('-timestamp').first()
        safe_zone_payload = {
            'configured': safe_zone is not None,
            'inside': False,
            'name': safe_zone.name if safe_zone else 'Home',
            'distance_meters': None,
            'last_checked_at': last_ping.timestamp.isoformat() if last_ping else None,
        }
        if safe_zone is not None and last_ping is not None and last_ping.distance_from_center_meters is not None:
            safe_zone_payload['distance_meters'] = round(last_ping.distance_from_center_meters, 1)
            safe_zone_payload['inside'] = last_ping.distance_from_center_meters <= safe_zone.radius_meters

        recent_activity = []
        for item in RecognitionHistory.objects.filter(patient=patient).order_by('-timestamp')[:5]:
            recent_activity.append({
                'id': item.id,
                'event_type': 'recognition',
                'title': 'Recognition event' if item.outcome == 'matched' else 'Unknown face detected',
                'timestamp': item.timestamp.isoformat(),
                'outcome': item.outcome,
            })
        for item in ConversationHistory.objects.filter(patient=patient).order_by('-created_at')[:5]:
            recent_activity.append({
                'id': item.id,
                'event_type': 'conversation',
                'title': 'Conversation saved',
                'timestamp': item.created_at.isoformat(),
            })
        recent_activity = sorted(recent_activity, key=lambda entry: entry['timestamp'], reverse=True)[:5]

        return Response({
            'patient': {
                'id': patient.id,
                'name': patient.name,
                'age': patient.age,
                'date_of_birth': patient.date_of_birth,
            },
            'today': {
                'known_detections': known_today,
                'unknown_detections': unknown_today,
            },
            'conversations_saved': conversations_saved,
            'weekly_counts': weekly_series,
            'known_vs_unknown': {
                'known_percent': known_ratio,
                'unknown_percent': unknown_ratio,
            },
            'average_match_confidence': average_confidence,
            'safe_zone': safe_zone_payload,
            'recent_activity': recent_activity,
        })


class PatientFaceImageView(generics.CreateAPIView):
    serializer_class = FaceImageSerializer
    permission_classes = [permissions.IsAuthenticated, IsCaregiverOwner]
    parser_classes = [MultiPartParser, FormParser]

    def get_queryset(self):
        return Patient.objects.filter(caregiver=self.request.user)

    def post(self, request, *args, **kwargs):
        patient = self.get_queryset().get(pk=kwargs['pk'])
        self.check_object_permissions(request, patient)
        files = request.FILES.getlist('files')
        if not files:
            return Response({'detail': 'No files provided.'}, status=status.HTTP_400_BAD_REQUEST)
        if len(files) < 1:
            return Response({'detail': 'At least one face image is required.'}, status=status.HTTP_400_BAD_REQUEST)

        FaceImage.objects.filter(patient_subject=patient).delete()
        created_images = []
        for image_file in files:
            face_image = FaceImage.objects.create(subject_type='patient', patient_subject=patient, image=image_file)
            created_images.append(FaceImageSerializer(face_image).data)
        return Response(created_images, status=status.HTTP_201_CREATED)
