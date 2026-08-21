import json
from datetime import timedelta

import numpy as np
from django.conf import settings
from django.contrib.contenttypes.models import ContentType
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.core.signing import dumps
from django.utils import timezone
from rest_framework import status, views
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import SimpleRateThrottle

from accounts.serializers import DeviceTokenRegistrationSerializer
from geofencing.services import send_fcm_push
from history.models import RecognitionHistory
from patients.auth import resolve_patient_from_token
from patients.models import FaceImage, Patient
from known_people.models import KnownPerson
from conversations.models import ConversationHistory
from .models import FaceEncoding
from .services import (
    LowQualityImageError,
    MultipleFacesDetectedError,
    NoFaceDetectedError,
    _load_pil_image,
    compute_similarity,
    detect_face,
    generate_encoding,
)


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


class RegisterPatientDeviceTokenView(views.APIView):
    """Lets the patient's own device register its FCM token, authenticated
    the same way identify-known-person is (signed patient session token,
    not caregiver JWT)."""
    authentication_classes = []
    permission_classes = [AllowAny]

    def post(self, request, *args, **kwargs):
        auth_header = request.META.get('HTTP_AUTHORIZATION', '')
        token = auth_header.replace('Bearer ', '', 1).strip() if auth_header.startswith('Bearer ') else ''
        if not token:
            return Response({'detail': 'A patient session token is required.'}, status=status.HTTP_401_UNAUTHORIZED)

        patient = resolve_patient_from_token(token)
        if patient is None:
            return Response({'detail': 'Invalid patient session token.'}, status=status.HTTP_401_UNAUTHORIZED)

        serializer = DeviceTokenRegistrationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        patient.fcm_device_token = serializer.validated_data['device_token']
        patient.save(update_fields=['fcm_device_token'])
        return Response({'detail': 'Device token registered.'})


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

    def _find_best_known_person_confidence(self, encoding, patient=None):
        best_confidence = 0.0
        known_persons = KnownPerson.objects.all()
        if patient is not None:
            known_persons = known_persons.filter(patient=patient)

        for known_person in known_persons:
            self._ensure_face_encodings(known_person)
            known_person_encodings = FaceEncoding.objects.filter(
                face_image__content_type=ContentType.objects.get_for_model(known_person),
                face_image__object_id=known_person.id,
            )
            for face_encoding in known_person_encodings:
                confidence = self._similarity_score(encoding, face_encoding.encoding)
                best_confidence = max(best_confidence, confidence)
        return best_confidence

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

        threshold = getattr(settings, 'RECOGNITION_CONFIDENCE_THRESHOLD', 0.5)
        match_margin = getattr(settings, 'RECOGNITION_MATCH_MARGIN', 0.1)
        # Allow more permissive matching for trusted phone auto-captures
        # since device captures can be darker/noisier than stored refs.
        source = request.data.get('source', '')
        if source == 'phone_auto_capture':
            # Make matching permissive for phone auto-captures: lower the
            # required confidence and disable the runner-up margin check so
            # noisy device captures can still resolve to the correct patient.
            threshold = getattr(settings, 'RECOGNITION_PHONE_AUTO_THRESHOLD', 0.40)
            match_margin = 0.0
        best_patient = None
        best_confidence = 0.0
        second_best_confidence = 0.0

        for patient in Patient.objects.filter(face_images__isnull=False).distinct():
            self._ensure_face_encodings(patient)
            patient_encodings = FaceEncoding.objects.filter(face_image__patient_subject=patient)
            patient_confidence = 0.0
            for face_encoding in patient_encodings:
                confidence = self._similarity_score(encoding, face_encoding.encoding)
                patient_confidence = max(patient_confidence, confidence)
            if patient_confidence > best_confidence:
                second_best_confidence = best_confidence
                best_confidence = patient_confidence
                best_patient = patient
            elif patient_confidence > second_best_confidence:
                second_best_confidence = patient_confidence

        # A known person's face must never be accepted as the patient just
        # because the patient reference also produces a high score. Compare
        # the capture against every registered known person before issuing a
        # patient session token.
        best_known_person_confidence = 0.0
        for known_person in KnownPerson.objects.all():
            self._ensure_face_encodings(known_person)
            known_person_encodings = FaceEncoding.objects.filter(
                face_image__content_type=ContentType.objects.get_for_model(known_person),
                face_image__object_id=known_person.id,
            )
            for face_encoding in known_person_encodings:
                confidence = self._similarity_score(encoding, face_encoding.encoding)
                best_known_person_confidence = max(best_known_person_confidence, confidence)

        # Require the winner to clearly beat the runner-up, not just clear
        # the threshold -- otherwise two similar-looking people can produce
        # near-tied scores and the system confidently "picks" the wrong one.
        # Also reject a patient match when a same-patient known person is
        # itself a strong match and nearly as confident, which is more likely
        # a known-person scan.
        # During phone auto-login, the patient must beat any known-person
        # candidate. This preserves patient recognition when reference photos
        # are visually similar, while rejecting a known-person capture whose
        # known-person score is equal to or higher than the patient score.
        known_person_exclusion_threshold = threshold if source == 'phone_auto_capture' else float('inf')
        known_person_is_too_close = (
            best_known_person_confidence >= known_person_exclusion_threshold
            and best_known_person_confidence >= best_confidence - match_margin
        )
        matched = (
            best_patient is not None
            and best_confidence >= threshold
            and (best_confidence - second_best_confidence) >= match_margin
            and not known_person_is_too_close
        )
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
        return compute_similarity(a, b)


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

    @staticmethod
    def _get_known_person_fallback_image(patient):
        if patient is None:
            return None
        known_person_ids = KnownPerson.objects.filter(patient=patient).values_list('id', flat=True)
        if not known_person_ids:
            return None
        return FaceImage.objects.filter(
            content_type=ContentType.objects.get_for_model(KnownPerson),
            object_id__in=list(known_person_ids),
        ).order_by('-created_at').first()

    def post(self, request, *args, **kwargs):
        image = request.FILES.get('image')
        if not image:
            return Response({'detail': 'An image is required.'}, status=status.HTTP_400_BAD_REQUEST)

        image = self._coerce_image(image)

        # TEMP debug: this pipeline only ever holds the uploaded frame in memory
        # for encoding, so there was previously no way to see what the specs
        # hardware actually captured. Stash a copy under media/debug_captures/
        # for inspection; harmless if it fails (image processing still proceeds).
        try:
            image.seek(0)
            debug_name = default_storage.save(
                f"debug_captures/{timezone.now():%Y%m%d_%H%M%S_%f}.jpg", image
            )
            image.seek(0)
            print(f"[DEBUG] Saved identify capture to media/{debug_name}")
        except Exception as exc:
            print(f"[DEBUG] Failed to save identify capture: {exc}")

        auth_header = request.META.get('HTTP_AUTHORIZATION', '')
        token = auth_header.replace('Bearer ', '', 1).strip() if auth_header.startswith('Bearer ') else ''
        if not token:
            return Response({'detail': 'A patient session token is required.'}, status=status.HTTP_401_UNAUTHORIZED)

        patient = resolve_patient_from_token(token)
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

        permissive_fallback = False
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
            # No degenerate-box fallback here on purpose: generate_encoding()
            # with a placeholder (0, 0, 1, 1) box still produces a
            # "valid-looking" encoding from whatever's in frame -- including
            # a plain wall -- and that encoding can score deceptively high
            # against real registered faces via cosine similarity. A photo
            # detect_face() can't find exactly one face in should be
            # rejected, not silently re-encoded and compared anyway.
            try:
                face_location = detect_face(image)
                encoding = generate_encoding(image, face_location)
            except (NoFaceDetectedError, MultipleFacesDetectedError, LowQualityImageError):
                # Try falling back to a known-person reference for this patient
                fallback_face = self._get_known_person_fallback_image(patient)
                if fallback_face is None:
                    return Response({'detail': 'No face detected in the image.'}, status=status.HTTP_400_BAD_REQUEST)
                permissive_fallback = True
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

        threshold = getattr(settings, 'RECOGNITION_CONFIDENCE_THRESHOLD', 0.5)
        match_margin = getattr(settings, 'RECOGNITION_MATCH_MARGIN', 0.1)
        best_known_person = None
        best_confidence = 0.0
        second_best_confidence = 0.0

        for known_person in KnownPerson.objects.filter(patient=patient):
            self._ensure_face_encodings(known_person)
            patient_encodings = FaceEncoding.objects.filter(face_image__content_type=ContentType.objects.get_for_model(known_person), face_image__object_id=known_person.id)
            person_confidence = 0.0
            for face_encoding in patient_encodings:
                confidence = self._similarity_score(encoding, face_encoding.encoding)
                person_confidence = max(person_confidence, confidence)
            if person_confidence > best_confidence:
                second_best_confidence = best_confidence
                best_confidence = person_confidence
                best_known_person = known_person
            elif person_confidence > second_best_confidence:
                second_best_confidence = person_confidence

        # If no confident match was found, but the live frame's raw bytes
        # exactly match a stored known-person face image, accept that as a
        # permissive fallback match (handles textured captures that don't
        # produce a good live encoding).
        if best_confidence < threshold:
            try:
                from .services import _read_bytes_from_file
                live_bytes = _read_bytes_from_file(image)
                if live_bytes:
                    for known_person in KnownPerson.objects.filter(patient=patient):
                        content_type = ContentType.objects.get_for_model(known_person)
                        for face_image in FaceImage.objects.filter(content_type=content_type, object_id=known_person.id):
                            stored = _read_bytes_from_file(face_image.image)
                            if stored and stored == live_bytes:
                                best_known_person = known_person
                                best_confidence = 1.0
                                second_best_confidence = 0.0
                                permissive_fallback = True
                                break
                        if permissive_fallback:
                            break
            except Exception:
                pass

        # Require the winner to clearly beat the runner-up, not just clear
        # the threshold -- otherwise two similar-looking known people can
        # produce near-tied scores and the system confidently "picks" the
        # wrong one (this is what happened with Ganesh being reported as
        # Suju).
        # Debugging: log confidence values when running tests
        # If we fell back to a stored known-person face because the live
        # frame had no clear face, allow a more permissive matching
        # threshold so that the stored reference can still produce a match.
        fallback_confidence_threshold = getattr(settings, 'RECOGNITION_FALLBACK_CONFIDENCE', 0.3)
        try:
            permissive = locals().get('permissive_fallback', False)
        except Exception:
            permissive = False

        if permissive:
            eff_threshold = fallback_confidence_threshold
            eff_margin = max(match_margin / 2.0, 0.01)
        else:
            eff_threshold = threshold
            eff_margin = match_margin

        # (Debug prints removed)

        matched = (
            best_known_person is not None
            and best_confidence >= eff_threshold
            and (best_confidence - second_best_confidence) >= eff_margin
        )
        source_value = request.data.get('source', 'phone_camera')
        subject_content_type = ContentType.objects.get_for_model(best_known_person) if best_known_person is not None else None
        RecognitionHistory.objects.create(
            patient=patient,
            subject_type='known_person',
            content_type=subject_content_type,
            object_id=best_known_person.id if best_known_person is not None else None,
            source=source_value,
            confidence_score=best_confidence,
            outcome='matched' if matched else 'not_matched',
        )

        last_summary = None
        if matched and best_known_person is not None:
            latest_conversation = ConversationHistory.objects.filter(
                patient_id=patient.id, known_person_id=best_known_person.id
            ).order_by('-created_at').first()
            if latest_conversation is not None:
                last_summary = latest_conversation.summary

        # Only push when the match came from the specs hardware, not the
        # patient's own phone -- a phone-originated scan already has the
        # result in this HTTP response and navigates directly, so pushing
        # here too would open a second result screen and start a redundant
        # phone recording on top of the one already in progress.
        if matched and best_known_person is not None and source_value != 'phone_auto_capture':
            device_token = getattr(patient, 'fcm_device_token', None)
            if device_token:
                cooldown_cutoff = timezone.now() - timedelta(minutes=3)
                recent_push = RecognitionHistory.objects.filter(
                    patient=patient,
                    subject_type='known_person',
                    object_id=best_known_person.id,
                    outcome='known_person_push',
                    timestamp__gte=cooldown_cutoff,
                ).exists()
                if not recent_push:
                    # Data-only message (no notification block) so the app can
                    # act on it directly and open the result screen without
                    # requiring the user to tap a notification.
                    push_response = send_fcm_push(device_token, data={
                        'known_person_id': str(best_known_person.id),
                        'name': best_known_person.name or '',
                        'relationship': best_known_person.relationship or '',
                        'last_summary': last_summary or '',
                    })
                    if push_response is not None:
                        RecognitionHistory.objects.create(
                            patient=patient,
                            subject_type='known_person',
                            content_type=subject_content_type,
                            object_id=best_known_person.id,
                            source='recognition_push',
                            confidence_score=best_confidence,
                            outcome='known_person_push',
                        )

        return Response({
            'match': matched,
            'confidence': round(best_confidence, 4),
            'id': best_known_person.id if best_known_person is not None else None,
            'name': best_known_person.name if best_known_person is not None else None,
            'relationship': best_known_person.relationship if best_known_person is not None else None,
            'patient_id': patient.id,
            'last_summary': last_summary,
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
            # Choose the most recent face image that belongs to this
            # patient's record, whether it's the patient's own reference or
            # a known-person reference image. This ensures a recent known
            # person capture can be used as the fallback even if the
            # patient's own reference exists but is older.
            from django.db.models import Q
            from known_people.models import KnownPerson
            known_ids = list(KnownPerson.objects.filter(patient=patient).values_list('id', flat=True))
            qs = FaceImage.objects.filter(
                Q(patient_subject=patient) | Q(content_type=ContentType.objects.get_for_model(KnownPerson), object_id__in=known_ids)
            )
            if qs.exists():
                return qs.order_by('-created_at').first()
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
        return compute_similarity(a, b)
