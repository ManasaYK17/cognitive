from django.db import IntegrityError
from django.utils import timezone
from rest_framework import permissions, status, views
from rest_framework.response import Response
from rest_framework_simplejwt.authentication import JWTAuthentication
from patients.auth import resolve_patient_from_token
from patients.models import Patient
from .models import GameResult, Reminder
from .serializers import GameResultCreateSerializer, GameResultSerializer, ReminderSerializer


def patient_from_session(request):
    header = request.META.get('HTTP_AUTHORIZATION', '')
    token = header.replace('Bearer ', '', 1).strip() if header.startswith('Bearer ') else ''
    return resolve_patient_from_token(token) if token else None


def caregiver_from_request(request):
    result = JWTAuthentication().authenticate(request)
    return result[0] if result else None


def serialize_reminders(queryset):
    return ReminderSerializer(queryset, many=True).data


class GameResultListCreateView(views.APIView):
    authentication_classes = []
    permission_classes = [permissions.AllowAny]

    def get(self, request, *args, **kwargs):
        caregiver = caregiver_from_request(request)
        patient = Patient.objects.filter(id=request.query_params.get('patient'), caregiver=caregiver).first() if caregiver else patient_from_session(request)
        if patient is None:
            return Response({'detail': 'Patient not found or unauthorized.'}, status=status.HTTP_404_NOT_FOUND)
        return Response(GameResultSerializer(GameResult.objects.filter(patient=patient), many=True).data)

    def post(self, request, *args, **kwargs):
        patient = patient_from_session(request)
        if patient is None:
            return Response({'detail': 'A patient session token is required.'}, status=status.HTTP_401_UNAUTHORIZED)
        serializer = GameResultCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        result = serializer.save(patient=patient)
        return Response(GameResultSerializer(result).data, status=status.HTTP_201_CREATED)


class ReminderListCreateView(views.APIView):
    authentication_classes = []
    permission_classes = [permissions.AllowAny]

    def get(self, request, *args, **kwargs):
        caregiver = caregiver_from_request(request)
        patient = Patient.objects.filter(id=request.query_params.get('patient'), caregiver=caregiver).first() if caregiver else patient_from_session(request)
        if patient is None:
            return Response({'detail': 'Patient not found or unauthorized.'}, status=status.HTTP_404_NOT_FOUND)
        reminders = Reminder.objects.filter(patient=patient)
        if caregiver is None:
            now = timezone.now()
            due = reminders.filter(status=Reminder.PENDING, scheduled_for__lte=now)
            due.update(status=Reminder.TRIGGERED, triggered_at=now)
            reminders = Reminder.objects.filter(patient=patient)
        return Response(serialize_reminders(reminders))

    def post(self, request, *args, **kwargs):
        caregiver = caregiver_from_request(request)
        if caregiver is None:
            return Response({'detail': 'Caregiver authentication is required.'}, status=status.HTTP_401_UNAUTHORIZED)
        patient = Patient.objects.filter(id=request.data.get('patient'), caregiver=caregiver).first()
        if patient is None:
            return Response({'detail': 'Patient not found or unauthorized.'}, status=status.HTTP_404_NOT_FOUND)
        serializer = ReminderSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            reminder = serializer.save(patient=patient, caregiver=caregiver)
        except IntegrityError:
            return Response({'detail': 'This reminder already exists.'}, status=status.HTTP_409_CONFLICT)
        return Response(ReminderSerializer(reminder).data, status=status.HTTP_201_CREATED)


class ReminderStatusView(views.APIView):
    authentication_classes = []
    permission_classes = [permissions.AllowAny]

    def put(self, request, pk, *args, **kwargs):
        return self.patch(request, pk, *args, **kwargs)

    def patch(self, request, pk, *args, **kwargs):
        reminder = Reminder.objects.filter(pk=pk).first()
        if reminder is None:
            return Response({'detail': 'Reminder not found.'}, status=status.HTTP_404_NOT_FOUND)
        patient = patient_from_session(request)
        caregiver = caregiver_from_request(request)
        if caregiver:
            if reminder.caregiver_id != caregiver.id:
                return Response({'detail': 'Reminder not found or unauthorized.'}, status=status.HTTP_404_NOT_FOUND)
        elif patient is None or patient.id != reminder.patient_id:
            return Response({'detail': 'Invalid patient session token.'}, status=status.HTTP_401_UNAUTHORIZED)

        requested = request.data.get('status')
        if requested not in (Reminder.COMPLETED, Reminder.MISSED):
            return Response({'detail': 'Status must be completed or missed.'}, status=status.HTTP_400_BAD_REQUEST)
        now = timezone.now()
        reminder.status = requested
        if requested == Reminder.COMPLETED:
            reminder.completed_at = now
        else:
            reminder.missed_at = now
        reminder.save(update_fields=['status', 'completed_at', 'missed_at'])
        return Response(ReminderSerializer(reminder).data)
