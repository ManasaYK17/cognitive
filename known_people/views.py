from django.contrib.contenttypes.models import ContentType
from rest_framework import generics, permissions, status
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.response import Response
from .models import KnownPerson
from .serializers import KnownPersonSerializer
from .permissions import IsCaregiverForKnownPerson
from patients.models import FaceImage
from patients.serializers import FaceImageSerializer
from recognition.services import detect_face, generate_encoding
from recognition.models import FaceEncoding


class KnownPersonListCreateView(generics.ListCreateAPIView):
    serializer_class = KnownPersonSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return KnownPerson.objects.filter(patient__caregiver=self.request.user)

    def perform_create(self, serializer):
        patient_id = self.request.data.get('patient')
        patient = getattr(self.request.user, 'patient', None)
        if patient is None or str(patient.id) != str(patient_id):
            raise ValueError('Patient not found or not owned by this caregiver')
        serializer.save(patient=patient)


class KnownPersonDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = KnownPersonSerializer
    permission_classes = [permissions.IsAuthenticated, IsCaregiverForKnownPerson]

    def get_queryset(self):
        return KnownPerson.objects.filter(patient__caregiver=self.request.user)


class KnownPersonFaceImageView(generics.CreateAPIView):
    serializer_class = FaceImageSerializer
    permission_classes = [permissions.IsAuthenticated, IsCaregiverForKnownPerson]
    parser_classes = [MultiPartParser, FormParser]

    def get_queryset(self):
        return KnownPerson.objects.filter(patient__caregiver=self.request.user)

    def post(self, request, *args, **kwargs):
        known_person = self.get_queryset().get(pk=kwargs['pk'])
        self.check_object_permissions(request, known_person)
        files = request.FILES.getlist('files')
        if not files:
            return Response({'detail': 'No files provided.'}, status=status.HTTP_400_BAD_REQUEST)
        # Remove existing known-person face images so the new upload replaces previous faces
        content_type = ContentType.objects.get_for_model(known_person.__class__)
        FaceImage.objects.filter(content_type=content_type, object_id=known_person.id).delete()

        created_images = []
        for image_file in files:
            face_image = FaceImage.objects.create(
                subject_type='known_person',
                image=image_file,
                object_id=known_person.id,
                content_type=content_type,
            )
            # Ensure a FaceEncoding exists for the newly created face image (generate synchronously)
            try:
                face_location = detect_face(face_image.image)
                encoding = generate_encoding(face_image.image, face_location)
                FaceEncoding.objects.create(
                    subject_type=face_image.subject_type,
                    content_type=face_image.content_type,
                    object_id=face_image.object_id,
                    face_image=face_image,
                    encoding=encoding,
                )
            except Exception:
                # If encoding generation fails, continue — signal handler may still create it asynchronously
                pass
            created_images.append(FaceImageSerializer(face_image).data)
        return Response(created_images, status=status.HTTP_201_CREATED)
