from rest_framework import generics, permissions, status, views
from rest_framework.response import Response
from rest_framework.parsers import MultiPartParser, FormParser
from .models import Patient, FaceImage
from .serializers import PatientSerializer, FaceImageSerializer
from .permissions import IsCaregiverOwner


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
        created_images = []
        for image_file in files:
            face_image = FaceImage.objects.create(subject_type='patient', patient_subject=patient, image=image_file)
            created_images.append(FaceImageSerializer(face_image).data)
        return Response(created_images, status=status.HTTP_201_CREATED)
