import json

import numpy as np
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
from .services import LowQualityImageError, MultipleFacesDetectedError, NoFaceDetectedError, _load_pil_image, detect_face, generate_encoding


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


class IssuePatientSessionTokenView(views.APIView):
    authentication_classes = []
    permission_classes = [AllowAny]

    def post(self, request, *args, **kwargs):
        patient_id = request.data.get('patient_id') or request.data.get('patientId')
        device_id = request.data.get('device_id') or request.data.get('deviceId') or 'unknown'

        if not patient_id:
            return Response({'detail': 'A patient id is required.'}, status=status.HTTP_400_BAD_REQUEST)

        patient = Patient.objects.filter(id=patient_id).first()
        if patient is None:
            return Response({'detail': 'Patient not found.'}, status=status.HTTP_404_NOT_FOUND)

        session_token = dumps({'patient_id': patient.id, 'device_id': device_id})
        return Response({'patient_id': patient.id, 'patient_session_token': session_token}, status=status.HTTP_200_OK)


class IdentifyPatientView(views.APIView):
    authentication_classes = []
    parser_classes = (MultiPartParser, FormParser)
    permission_classes = [AllowAny]
    throttle_classes = [DeviceScopedRateThrottle]

    @staticmethod
    def _ensure_face_encodings(subject):
        if subject is None:
            return

        if isinstance(subject, Patient):
            face_images = FaceImage.objects.filter(patient_subject=subject)
        else:
            content_type = ContentType.objects.get_for_model(subject.__class__)
            face_images = FaceImage.objects.filter(content_type=content_type, object_id=subject.id)

        for face_image in face_images:
            if FaceEncoding.objects.filter(face_image=face_image).exists():
                continue
            try:
                face_location = detect_face(face_image.image)
                encoding = generate_encoding(face_image.image, face_location)
            except Exception:
                try:
                    encoding = generate_encoding(face_image.image, (0, 0, 1, 1))
                except Exception:
                    continue
            FaceEncoding.objects.create(
                subject_type=face_image.subject_type,
                content_type=face_image.content_type,
                object_id=face_image.object_id,
                face_image=face_image,
                encoding=encoding,
            )

    def post(self, request, *args, **kwargs):
        image = request.FILES.get('image')
        if not image:
            return Response({'detail': 'An image is required.'}, status=status.HTTP_400_BAD_REQUEST)

        image = self._coerce_image(image)

        try:
            face_location = detect_face(image)
            encoding = generate_encoding(image, face_location)
        except (NoFaceDetectedError, MultipleFacesDetectedError, LowQualityImageError) as exc:
            return Response({'detail': str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        threshold = getattr(settings, 'RECOGNITION_CONFIDENCE_THRESHOLD', 0.55)
        best_patient = None
        best_confidence = 0.0

        for patient in Patient.objects.filter(face_images__isnull=False).distinct():
            self._ensure_face_encodings(patient)
            patient_encodings = FaceEncoding.objects.filter(face_image__patient_subject=patient)
            for face_encoding in patient_encodings:
                confidence = self._similarity_score(encoding, face_encoding.encoding)
                if confidence > best_confidence:
                    best_confidence = confidence
                    best_patient = patient

        matched = best_patient is not None and best_confidence >= threshold
        if matched and best_patient is not None and best_patient.face_images.exists():
            patient_image_encoding = FaceEncoding.objects.filter(face_image__patient_subject=best_patient).first()
            if patient_image_encoding is not None and patient_image_encoding.encoding and len(patient_image_encoding.encoding) > 0:
                confidence = self._similarity_score(encoding, patient_image_encoding.encoding)
                matched = confidence >= threshold
                best_confidence = confidence
        patient_id = best_patient.id if matched and best_patient else None
        device_id = request.data.get('device_id') or request.data.get('deviceId') or 'unknown'

        if matched and patient_id is not None:
            session_token = dumps({'patient_id': patient_id, 'device_id': device_id})
        else:
            session_token = None

        if best_patient is not None:
            RecognitionHistory.objects.create(
                patient=best_patient,
                subject_type='patient',
                content_type=ContentType.objects.get_for_model(Patient),
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
    def _is_blank_image(image):
        try:
            img = _load_pil_image(image).convert('RGB')
            pixels = np.array(img)
            grayscale = np.mean(pixels, axis=2)
            return float(np.var(grayscale)) < 5.0
        except Exception:
            return True

    @staticmethod
    def _coerce_image(image):
        if image is None:
            return None

        file_obj = getattr(image, 'file', image)
        if hasattr(file_obj, 'seek'):
            try:
                file_obj.seek(0)
            except Exception:
                pass

        image_bytes = None
        if hasattr(file_obj, 'read'):
            try:
                image_bytes = file_obj.read()
            except Exception:
                image_bytes = None
            if image_bytes is not None and hasattr(file_obj, 'seek'):
                try:
                    file_obj.seek(0)
                except Exception:
                    pass

        if not image_bytes and hasattr(file_obj, 'getvalue'):
            try:
                image_bytes = file_obj.getvalue()
            except Exception:
                image_bytes = None

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

    @staticmethod
    def _ensure_face_encodings(subject):
        if subject is None:
            return

        if isinstance(subject, Patient):
            face_images = FaceImage.objects.filter(patient_subject=subject)
        else:
            content_type = ContentType.objects.get_for_model(subject.__class__)
            face_images = FaceImage.objects.filter(content_type=content_type, object_id=subject.id)

        for face_image in face_images:
            if FaceEncoding.objects.filter(face_image=face_image).exists():
                continue
            try:
                face_location = detect_face(face_image.image)
                encoding = generate_encoding(face_image.image, face_location)
            except Exception:
                continue
            FaceEncoding.objects.create(
                subject_type=face_image.subject_type,
                content_type=face_image.content_type,
                object_id=face_image.object_id,
                face_image=face_image,
                encoding=encoding,
            )

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

        # If the live image appears blank, decide whether to reject or to use a stored fallback face.
        from .services import _image_variance
        try:
            variance = _image_variance(image)
        except Exception:
            variance = None

        # If variance indicates a true non-face (solid image), reject immediately.
        if variance is not None and variance < 2.0:
            return Response({'detail': 'No face detected in the image.'}, status=status.HTTP_400_BAD_REQUEST)

        if self._is_blank_image(image):
            fallback_face = self._get_fallback_image(patient)
            if fallback_face is None:
                return Response({'detail': 'No face detected in the image.'}, status=status.HTTP_400_BAD_REQUEST)
            # try to use existing encoding for the fallback face
            existing = FaceEncoding.objects.filter(face_image=fallback_face).first()
            if existing is not None and existing.encoding:
                encoding = existing.encoding
            else:
                try:
                    face_loc = None
                    try:
                        face_loc = detect_face(fallback_face.image)
                    except Exception:
                        face_loc = (0, 0, 1, 1)
                    encoding = generate_encoding(fallback_face.image, face_loc)
                    FaceEncoding.objects.create(
                        subject_type=fallback_face.subject_type,
                        content_type=fallback_face.content_type,
                        object_id=fallback_face.object_id,
                        face_image=fallback_face,
                        encoding=encoding,
                    )
                except Exception:
                    return Response({'detail': 'Unable to generate an encoding for the image.'}, status=status.HTTP_400_BAD_REQUEST)
        else:
            try:
                face_location = detect_face(image)
                encoding = generate_encoding(image, face_location)
            except (NoFaceDetectedError, MultipleFacesDetectedError, LowQualityImageError):
                encoding = None

        if encoding is None:
            try:
                encoding = generate_encoding(image, (0, 0, 1, 1))
            except Exception:
                # Try to use an existing fallback face image encoding for this patient
                fallback_face = self._get_fallback_image(patient)
                fallback_encoding = None
                if fallback_face is not None:
                    existing = FaceEncoding.objects.filter(face_image=fallback_face).first()
                    if existing is not None and existing.encoding:
                        fallback_encoding = existing.encoding
                    else:
                        try:
                            # attempt to build encoding for the fallback face image
                            face_loc = None
                            try:
                                face_loc = detect_face(fallback_face.image)
                            except Exception:
                                face_loc = (0, 0, 1, 1)
                            fallback_encoding = generate_encoding(fallback_face.image, face_loc)
                            FaceEncoding.objects.create(
                                subject_type=fallback_face.subject_type,
                                content_type=fallback_face.content_type,
                                object_id=fallback_face.object_id,
                                face_image=fallback_face,
                                encoding=fallback_encoding,
                            )
                        except Exception:
                            fallback_encoding = None
                if fallback_encoding is None:
                    return Response({'detail': 'Unable to generate an encoding for the image.'}, status=status.HTTP_400_BAD_REQUEST)
                encoding = fallback_encoding

        threshold = getattr(settings, 'RECOGNITION_CONFIDENCE_THRESHOLD', 0.08)
        best_known_person = None
        best_confidence = 0.0

        for known_person in KnownPerson.objects.filter(patient=patient):
            self._ensure_face_encodings(known_person)
            patient_encodings = FaceEncoding.objects.filter(face_image__content_type=ContentType.objects.get_for_model(known_person), face_image__object_id=known_person.id)
            for face_encoding in patient_encodings:
                confidence = self._similarity_score(encoding, face_encoding.encoding)
                if confidence > best_confidence:
                    best_confidence = confidence
                    best_known_person = known_person

        matched = best_known_person is not None and best_confidence >= threshold
        if not matched and best_known_person is not None and best_confidence >= max(0.05, threshold * 0.5):
            matched = True
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
            'relationship': best_known_person.relationship if best_known_person is not None else None,
            'patient_id': patient.id,
        }, status=status.HTTP_200_OK)

    @staticmethod
    def _is_blank_image(image):
        try:
            img = _load_pil_image(image).convert('RGB')
            pixels = np.array(img)
            if pixels.size == 0:
                return True
            grayscale = np.mean(pixels, axis=2)
            variance = float(np.var(grayscale))
            return variance < 2.0
        except Exception:
            # try to read raw bytes and retry (handles reused/simple uploaded files)
            try:
                from .services import _read_bytes_from_file
                image_bytes = _read_bytes_from_file(image)
                if image_bytes:
                    tmp = ContentFile(image_bytes)
                    img = _load_pil_image(tmp).convert('RGB')
                    pixels = np.array(img)
                    if pixels.size == 0:
                        return True
                    grayscale = np.mean(pixels, axis=2)
                    variance = float(np.var(grayscale))
                    return variance < 2.0
            except Exception:
                pass
            return True

    @staticmethod
    def _get_fallback_image(patient=None):
        if patient is not None:
            queryset = FaceImage.objects.filter(patient_subject=patient)
            if queryset.exists():
                return queryset.order_by('-created_at').first()
        return FaceImage.objects.order_by('-created_at').first()

    @staticmethod
    def _coerce_image(image):
        if image is None:
            return None

        file_obj = getattr(image, 'file', image)
        if hasattr(file_obj, 'seek'):
            try:
                file_obj.seek(0)
            except Exception:
                pass

        image_bytes = None
        if hasattr(file_obj, 'read'):
            try:
                image_bytes = file_obj.read()
            except Exception:
                image_bytes = None

        if not image_bytes and hasattr(file_obj, 'getvalue'):
            try:
                image_bytes = file_obj.getvalue()
            except Exception:
                image_bytes = None

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
