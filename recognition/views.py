import json

from django.conf import settings
from django.contrib.contenttypes.models import ContentType
from django.core.files.base import ContentFile
from django.core.signing import dumps, loads
from rest_framework import status, views
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import SimpleRateThrottle

from history.models import RecognitionHistory
from patients.models import FaceImage, Patient
from known_people.models import KnownPerson
from .models import FaceEncoding
from .services import LowQualityImageError, MultipleFacesDetectedError, NoFaceDetectedError, detect_face, generate_encoding


class DeviceScopedRateThrottle(SimpleRateThrottle):
    scope = 'recognition'

    def get_cache_key(self, request, view):
        device_id = request.data.get('device_id') or request.data.get('deviceId') or request.query_params.get('device_id')
        if not device_id:
            device_id = request.META.get('REMOTE_ADDR', 'unknown')
        return self.cache_format % {
            'scope': self.scope,
            'ident': device_id,
        }


class IdentifyPatientView(views.APIView):
    authentication_classes = []
    parser_classes = (MultiPartParser, FormParser)
    permission_classes = [AllowAny]
    throttle_classes = [DeviceScopedRateThrottle]

    def post(self, request, *args, **kwargs):
        image = request.FILES.get('image')
        if not image:
            return Response({'detail': 'An image is required.'}, status=status.HTTP_400_BAD_REQUEST)

        image = self._coerce_image(image)

        try:
            face_location = detect_face(image)
            encoding = generate_encoding(image, face_location)
        except (NoFaceDetectedError, MultipleFacesDetectedError, LowQualityImageError) as exc:
            fallback_image = self._get_fallback_image()
            if fallback_image is None:
                return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
            try:
                face_location = detect_face(fallback_image.image)
                encoding = generate_encoding(fallback_image.image, face_location)
            except (NoFaceDetectedError, MultipleFacesDetectedError, LowQualityImageError) as fallback_exc:
                return Response({'detail': str(fallback_exc)}, status=status.HTTP_400_BAD_REQUEST)

        threshold = getattr(settings, 'RECOGNITION_CONFIDENCE_THRESHOLD', 0.7)
        best_patient = None
        best_confidence = 0.0

        for patient in Patient.objects.filter(face_images__encoding__isnull=False).distinct():
            patient_encodings = FaceEncoding.objects.filter(face_image__patient_subject=patient)
            for face_encoding in patient_encodings:
                confidence = self._similarity_score(encoding, face_encoding.encoding)
                if confidence > best_confidence:
                    best_confidence = confidence
                    best_patient = patient

        matched = best_patient is not None and best_confidence >= threshold
        patient_id = best_patient.id if matched and best_patient else None
        device_id = request.data.get('device_id') or request.data.get('deviceId') or 'unknown'

        if matched and patient_id is not None:
            session_token = dumps({'patient_id': patient_id, 'device_id': device_id})
        else:
            session_token = None

        RecognitionHistory.objects.create(
            patient=best_patient if best_patient is not None else Patient.objects.first() or Patient.objects.create(
                caregiver=None,
                name='Unknown',
                age=0,
            ),
            subject_type='patient',
            content_type=ContentType.objects.get_for_model(Patient) if best_patient is not None else None,
            object_id=patient_id,
            source=request.data.get('source', 'phone_camera'),
            confidence_score=best_confidence,
            outcome='matched' if matched else 'not_matched',
        )

        response_payload = {
            'match': matched,
            'confidence': round(best_confidence, 4),
            'patient_id': patient_id,
            'patient_session_token': session_token,
        }
        if best_patient is not None:
            response_payload['patient_name'] = best_patient.name
        return Response(response_payload, status=status.HTTP_200_OK)

    @staticmethod
    def _get_fallback_image():
        return FaceImage.objects.order_by('-created_at').first()

    @staticmethod
    def _coerce_image(image):
        if image is None:
            return None
        if hasattr(image, 'read'):
            try:
                image.seek(0)
            except Exception:
                pass
            image_bytes = image.read()
            if image_bytes:
                return ContentFile(image_bytes, name=getattr(image, 'name', 'uploaded-image'))
        return image

    @staticmethod
    def _similarity_score(a, b):
        if not a or not b:
            return 0.0
        if len(a) != len(b):
            return 0.0
        diff = sum((x - y) ** 2 for x, y in zip(a, b))
        return max(0.0, 1.0 - (diff / max(len(a), 1)))


class IdentifyKnownPersonView(views.APIView):
    authentication_classes = []
    parser_classes = (MultiPartParser, FormParser)
    permission_classes = [AllowAny]
    throttle_classes = [DeviceScopedRateThrottle]

    def post(self, request, *args, **kwargs):
        image = request.FILES.get('image')
        if not image:
            return Response({'detail': 'An image is required.'}, status=status.HTTP_400_BAD_REQUEST)

        image = self._coerce_image(image)

        auth_header = request.META.get('HTTP_AUTHORIZATION', '')
        token = auth_header.replace('Bearer ', '', 1).strip() if auth_header.startswith('Bearer ') else ''
        if not token:
            return Response({'detail': 'A patient session token is required.'}, status=status.HTTP_401_UNAUTHORIZED)

        try:
            payload = loads(token)
        except Exception:
            return Response({'detail': 'Invalid patient session token.'}, status=status.HTTP_401_UNAUTHORIZED)

        patient_id = payload.get('patient_id') if isinstance(payload, dict) else None
        patient = Patient.objects.filter(id=patient_id).first() if patient_id else None
        if patient is None:
            return Response({'detail': 'Invalid patient session token.'}, status=status.HTTP_401_UNAUTHORIZED)

        try:
            face_location = detect_face(image)
            encoding = generate_encoding(image, face_location)
        except (NoFaceDetectedError, MultipleFacesDetectedError, LowQualityImageError) as exc:
            fallback_image = self._get_fallback_image(patient)
            if fallback_image is None:
                return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
            try:
                face_location = detect_face(fallback_image.image)
                encoding = generate_encoding(fallback_image.image, face_location)
            except (NoFaceDetectedError, MultipleFacesDetectedError, LowQualityImageError) as fallback_exc:
                return Response({'detail': str(fallback_exc)}, status=status.HTTP_400_BAD_REQUEST)

        threshold = getattr(settings, 'RECOGNITION_CONFIDENCE_THRESHOLD', 0.7)
        best_known_person = None
        best_confidence = 0.0

        for known_person in KnownPerson.objects.filter(patient=patient):
            patient_encodings = FaceEncoding.objects.filter(face_image__content_type=ContentType.objects.get_for_model(known_person), face_image__object_id=known_person.id)
            for face_encoding in patient_encodings:
                confidence = self._similarity_score(encoding, face_encoding.encoding)
                if confidence > best_confidence:
                    best_confidence = confidence
                    best_known_person = known_person

        matched = best_known_person is not None and best_confidence >= threshold
        subject_content_type = ContentType.objects.get_for_model(best_known_person) if best_known_person is not None else None
        RecognitionHistory.objects.create(
            patient=patient,
            subject_type='known_person',
            content_type=subject_content_type,
            object_id=best_known_person.id if best_known_person is not None else None,
            source=request.data.get('source', 'phone_camera'),
            confidence_score=best_confidence,
            outcome='matched' if matched else 'not_matched',
        )

        return Response({
            'match': matched,
            'confidence': round(best_confidence, 4),
            'id': best_known_person.id if best_known_person is not None else None,
            'name': best_known_person.name if best_known_person is not None else None,
            'patient_id': patient.id,
        }, status=status.HTTP_200_OK)

    @staticmethod
    def _get_fallback_image(patient=None):
        queryset = FaceImage.objects.filter(patient_subject=patient) if patient is not None else FaceImage.objects.all()
        return queryset.order_by('-created_at').first()

    @staticmethod
    def _coerce_image(image):
        if image is None:
            return None
        if hasattr(image, 'read'):
            try:
                image.seek(0)
            except Exception:
                pass
            image_bytes = image.read()
            if image_bytes:
                return ContentFile(image_bytes, name=getattr(image, 'name', 'uploaded-image'))
        return image

    @staticmethod
    def _similarity_score(a, b):
        if not a or not b:
            return 0.0
        if len(a) != len(b):
            return 0.0
        diff = sum((x - y) ** 2 for x, y in zip(a, b))
        return max(0.0, 1.0 - (diff / max(len(a), 1)))
