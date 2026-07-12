from django.core.signing import loads
from rest_framework import permissions, status, views
from rest_framework.response import Response
from .models import SafeZone, LocationPing
from .serializers import SafeZoneSerializer, LocationPingSerializer
from patients.models import Patient
from geofencing.services import check_and_alert


class SafeZoneView(views.APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, pk, *args, **kwargs):
        patient = Patient.objects.filter(id=pk, caregiver=request.user).first()
        if not patient:
            return Response({'detail': 'Patient not found or unauthorized.'}, status=status.HTTP_404_NOT_FOUND)

        safe_zone = SafeZone.objects.filter(patient=patient).first()
        if safe_zone is None:
            return Response({'detail': 'Safe zone not set.'}, status=status.HTTP_404_NOT_FOUND)

        serializer = SafeZoneSerializer(safe_zone)
        return Response(serializer.data)

    def put(self, request, pk, *args, **kwargs):
        patient = Patient.objects.filter(id=pk, caregiver=request.user).first()
        if not patient:
            return Response({'detail': 'Patient not found or unauthorized.'}, status=status.HTTP_404_NOT_FOUND)

        safe_zone = SafeZone.objects.filter(patient=patient).first()
        if safe_zone is None:
            safe_zone = SafeZone(patient=patient)

        serializer = SafeZoneSerializer(safe_zone, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save(patient=patient)
        return Response(serializer.data)


class LocationPingView(views.APIView):
    authentication_classes = []
    permission_classes = [permissions.AllowAny]

    def post(self, request, pk, *args, **kwargs):
        auth_header = request.META.get('HTTP_AUTHORIZATION', '')
        token = auth_header.replace('Bearer ', '', 1).strip() if auth_header.startswith('Bearer ') else ''
        if not token:
            return Response({'detail': 'A patient session token is required.'}, status=status.HTTP_401_UNAUTHORIZED)

        try:
            payload = loads(token)
        except Exception:
            return Response({'detail': 'Invalid patient session token.'}, status=status.HTTP_401_UNAUTHORIZED)

        if str(payload.get('patient_id')) != str(pk):
            return Response({'detail': 'Token patient_id does not match request patient_id.'}, status=status.HTTP_401_UNAUTHORIZED)

        patient = Patient.objects.filter(id=pk).first()
        if not patient:
            return Response({'detail': 'Patient not found.'}, status=status.HTTP_404_NOT_FOUND)

        serializer = LocationPingSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        location_ping = serializer.save(patient=patient)

        check_and_alert(patient, location_ping)

        safe_zone = getattr(patient, 'safe_zone', None)
        inside = False
        if safe_zone is not None and location_ping.distance_from_center_meters is not None:
            inside = location_ping.distance_from_center_meters <= safe_zone.radius_meters

        return Response({
            'id': location_ping.id,
            'latitude': location_ping.latitude,
            'longitude': location_ping.longitude,
            'distance_from_center_meters': location_ping.distance_from_center_meters,
            'inside_safe_zone': inside,
        })
