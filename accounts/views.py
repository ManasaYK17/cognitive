from rest_framework import generics, permissions
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenRefreshView
from rest_framework_simplejwt.tokens import RefreshToken
from .models import Caregiver
from .serializers import (
    CaregiverRegistrationSerializer,
    CaregiverProfileSerializer,
    CaregiverLoginSerializer,
)


class CaregiverRegisterView(generics.CreateAPIView):
    queryset = Caregiver.objects.all()
    serializer_class = CaregiverRegistrationSerializer
    permission_classes = [permissions.AllowAny]


class CaregiverLoginView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request, *args, **kwargs):
        serializer = CaregiverLoginSerializer(data=request.data, context={'request': request})
        serializer.is_valid(raise_exception=True)
        caregiver = serializer.validated_data['user']
        refresh = RefreshToken.for_user(caregiver)
        return Response({
            'refresh': str(refresh),
            'access': str(refresh.access_token),
        })


class CaregiverTokenRefreshView(TokenRefreshView):
    permission_classes = [permissions.AllowAny]


class CaregiverMeView(generics.RetrieveAPIView):
    serializer_class = CaregiverProfileSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_object(self):
        return self.request.user


class RegisterDeviceTokenView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, *args, **kwargs):
        from .serializers import DeviceTokenRegistrationSerializer

        serializer = DeviceTokenRegistrationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        request.user.fcm_device_token = serializer.validated_data['device_token']
        request.user.save(update_fields=['fcm_device_token'])
        return Response({'detail': 'Device token registered.'})
