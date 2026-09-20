from django.contrib.contenttypes.models import ContentType
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from patients.models import Patient, FaceImage
from accounts.models import Caregiver
from known_people.models import KnownPerson
from history.models import RecognitionHistory
from . import services
from .services import (
    detect_face,
    generate_encoding,
    NoFaceDetectedError,
    MultipleFacesDetectedError,
    LowQualityImageError,
    _LBP_GRID,
    _LBP_BINS,
)
from .models import FaceEncoding
from PIL import Image, ImageDraw
import io
import numpy as np
from unittest.mock import patch


class RecognitionServiceTests(TestCase):
    def setUp(self):
        self.caregiver = Caregiver.objects.create_user(email='recognitioncaregiver@example.com', first_name='Rec', password='StrongPass123')
        self.patient = Patient.objects.create(caregiver=self.caregiver, name='Rina', age=60, medical_notes='Needs recognition')

    def _make_image(self, size=(120, 120), color=(255, 0, 0), with_face=True):
        image = Image.new('RGB', size, color)
        if with_face:
            draw = ImageDraw.Draw(image)
            draw.ellipse((20, 20, 100, 100), fill=(0, 0, 255))
        buffer = io.BytesIO()
        image.save(buffer, format='JPEG')
        return SimpleUploadedFile('face.jpg', buffer.getvalue(), content_type='image/jpeg')

    def test_detect_face_and_generate_encoding_for_valid_image(self):
        image = self._make_image()
        face_location = detect_face(image)
        self.assertIsNotNone(face_location)
        encoding = generate_encoding(image, face_location)
        # dlib's real face encoder (128-d) is used when face-recognition is
        # installed; otherwise this falls back to the LBP grid histogram.
        expected_length = 128 if services.face_recognition is not None else _LBP_GRID[0] * _LBP_GRID[1] * _LBP_BINS
        self.assertEqual(len(encoding), expected_length)

    def test_no_face_detected_raises_clear_error(self):
        image = self._make_image(with_face=False)
        with self.assertRaises(NoFaceDetectedError):
            detect_face(image)

    def test_multiple_faces_detected_raises_clear_error(self):
        image = Image.new('RGB', (220, 220), 'white')
        image.paste(Image.new('RGB', (60, 60), 'red'), (20, 20))
        image.paste(Image.new('RGB', (60, 60), 'blue'), (120, 120))
        buffer = io.BytesIO()
        image.save(buffer, format='JPEG')
        uploaded = SimpleUploadedFile('two_faces.jpg', buffer.getvalue(), content_type='image/jpeg')
        with self.assertRaises(MultipleFacesDetectedError):
            detect_face(uploaded)

    def test_detect_face_ignores_tiny_secondary_detection(self):
        image = self._make_image()

        class FakeFace:
            def __init__(self, bbox):
                self.bbox = bbox

        with patch('recognition.services._image_variance', return_value=100.0), \
             patch('recognition.services.cv2.imdecode', return_value=np.zeros((240, 240, 3), dtype=np.uint8)), \
             patch('recognition.services._insightface_get_faces', return_value=[
                 FakeFace((10, 10, 150, 150)),
                 FakeFace((160, 160, 170, 170)),
             ]), \
             patch('recognition.services._yunet_detect', return_value=[]):
            location = detect_face(image)

        self.assertEqual(location, (10, 10, 150, 150))

    def test_detect_face_handles_numpy_bbox_arrays_from_insightface(self):
        image = self._make_image()

        class FakeFace:
            def __init__(self, bbox):
                self.bbox = np.array(bbox, dtype=float)

        with patch('recognition.services._image_variance', return_value=100.0), \
             patch('recognition.services.cv2.imdecode', return_value=np.zeros((240, 240, 3), dtype=np.uint8)), \
             patch('recognition.services._insightface_get_faces', return_value=[
                 FakeFace((10, 10, 150, 150)),
                 FakeFace((160, 160, 170, 170)),
             ]), \
             patch('recognition.services._yunet_detect', return_value=[]):
            location = detect_face(image)

        self.assertEqual(location, (10, 10, 150, 150))

    def test_signal_creates_encoding_for_face_image(self):
        image = self._make_image()
        face_image = FaceImage.objects.create(subject_type='patient', patient_subject=self.patient, image=image)
        self.assertTrue(FaceEncoding.objects.filter(face_image=face_image).exists())


class RecognitionEndpointTests(APITestCase):
    def setUp(self):
        self.caregiver = Caregiver.objects.create_user(email='recognitionendpoint@example.com', first_name='Rec', password='StrongPass123')
        self.patient = Patient.objects.create(caregiver=self.caregiver, name='Rina', age=60, medical_notes='Needs recognition')
        self.known_person = KnownPerson.objects.create(patient=self.patient, name='Mina', relationship='Daughter')
        self.device_id = 'device-123'
        self.patient_image = self._make_image()
        self.known_person_image = self._make_image(color=(0, 255, 0))
        self.patient_face_image = FaceImage.objects.create(subject_type='patient', patient_subject=self.patient, image=self.patient_image)
        self.known_person_face_image = FaceImage.objects.create(
            subject_type='known_person',
            image=self.known_person_image,
            object_id=self.known_person.id,
            content_type=ContentType.objects.get_for_model(self.known_person),
        )
        self.image = self._make_image()

    def _make_image(self, size=(120, 120), color=(255, 0, 0), with_face=True):
        image = Image.new('RGB', size, color)
        if with_face:
            draw = ImageDraw.Draw(image)
            draw.rectangle((20, 20, 100, 100), fill=(0, 0, 255))
        buffer = io.BytesIO()
        image.save(buffer, format='JPEG')
        return SimpleUploadedFile('face.jpg', buffer.getvalue(), content_type='image/jpeg')

    def _make_textured_image(self, size=(120, 120)):
        image = Image.new('RGB', size, (255, 255, 255))
        draw = ImageDraw.Draw(image)
        for x in range(0, size[0], 10):
            draw.line((x, 0, x + 20, size[1]), fill=(30, 60, 120))
        for y in range(0, size[1], 10):
            draw.line((0, y, size[0], y + 20), fill=(200, 80, 40))
        buffer = io.BytesIO()
        image.save(buffer, format='JPEG')
        return SimpleUploadedFile('textured.jpg', buffer.getvalue(), content_type='image/jpeg')

    def test_identify_patient_returns_session_token_and_logs_history(self):
        response = self.client.post(reverse('identify-patient'), {'device_id': self.device_id, 'image': self._make_image()}, format='multipart')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['match'])
        self.assertEqual(response.data['patient_id'], self.patient.id)
        self.assertIn('patient_session_token', response.data)
        self.assertTrue(RecognitionHistory.objects.filter(patient=self.patient, outcome='matched').exists())

    def test_identify_patient_does_not_match_known_person_image(self):
        response = self.client.post(
            reverse('identify-patient'),
            {
                'device_id': self.device_id,
                'source': 'phone_auto_capture',
                'image': self._make_image(color=(0, 255, 0)),
            },
            format='multipart',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data['match'])
        self.assertIsNone(response.data['patient_id'])
        self.assertIsNone(response.data['patient_session_token'])
        self.assertFalse(
            RecognitionHistory.objects.filter(
                patient=self.patient,
                subject_type='patient',
                outcome='matched',
            ).exists(),
        )

    def test_identify_patient_prefers_actual_patient_when_known_person_is_close_but_not_stronger(self):
        similar_person = KnownPerson.objects.create(patient=self.patient, name='Close Relative')
        FaceImage.objects.create(
            subject_type='known_person',
            image=self.patient_image,
            object_id=similar_person.id,
            content_type=ContentType.objects.get_for_model(similar_person),
        )

        response = self.client.post(
            reverse('identify-patient'),
            {'device_id': self.device_id, 'image': self._make_image()},
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['match'])
        self.assertEqual(response.data['patient_id'], self.patient.id)
        self.assertIsNotNone(response.data['patient_session_token'])

    @patch('recognition.views.compute_similarity', return_value=0.72)
    def test_identify_patient_ignores_same_patient_known_person_when_deciding_patient_match(self, _mock_similarity):
        similar_person = KnownPerson.objects.create(patient=self.patient, name='Close Relative')
        FaceImage.objects.create(
            subject_type='known_person',
            image=self.patient_image,
            object_id=similar_person.id,
            content_type=ContentType.objects.get_for_model(similar_person),
        )

        response = self.client.post(
            reverse('identify-patient'),
            {'device_id': self.device_id, 'source': 'phone_auto_capture', 'image': self._make_image()},
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['match'])
        self.assertEqual(response.data['patient_id'], self.patient.id)
        self.assertIsNotNone(response.data['patient_session_token'])

    def test_identify_patient_does_not_confuse_known_people_from_other_patients(self):
        other_caregiver = Caregiver.objects.create_user(
            email='othercaregiver@example.com',
            first_name='Other',
            password='StrongPass123',
        )
        other_patient = Patient.objects.create(caregiver=other_caregiver, name='Other Patient', age=50, medical_notes='Other')
        other_known = KnownPerson.objects.create(patient=other_patient, name='Lookalike Relative', relationship='Sibling')
        FaceImage.objects.create(
            subject_type='known_person',
            image=self.patient_image,
            object_id=other_known.id,
            content_type=ContentType.objects.get_for_model(other_known),
        )

        response = self.client.post(
            reverse('identify-patient'),
            {'device_id': self.device_id, 'image': self._make_image()},
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['match'])
        self.assertEqual(response.data['patient_id'], self.patient.id)
        self.assertIsNotNone(response.data['patient_session_token'])

    def test_issue_patient_session_token_returns_signed_token(self):
        response = self.client.post(
            reverse('issue-patient-session-token'),
            {'patient_id': self.patient.id, 'device_id': self.device_id},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['patient_id'], self.patient.id)
        self.assertIn('patient_session_token', response.data)

    def test_identify_known_person_requires_patient_session_token(self):
        identify_response = self.client.post(reverse('identify-patient'), {'device_id': self.device_id, 'image': self._make_image()}, format='multipart')
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {identify_response.data['patient_session_token']}")
        response = self.client.post(
            reverse('identify-known-person'),
            {'image': self._make_image(), 'patient_id': self.patient.id, 'source': 'phone_camera'},
            format='multipart',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['match'])
        self.assertEqual(response.data['id'], self.known_person.id)
        self.assertEqual(response.data.get('relationship'), self.known_person.relationship)
        self.assertTrue(RecognitionHistory.objects.filter(patient=self.patient, subject=self.known_person, outcome='matched').exists())

    def test_identify_known_person_returns_no_match_when_no_known_people(self):
        self.known_person.delete()
        identify_response = self.client.post(reverse('identify-patient'), {'device_id': self.device_id, 'image': self._make_image()}, format='multipart')
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {identify_response.data['patient_session_token']}")
        response = self.client.post(
            reverse('identify-known-person'),
            {'image': self._make_image(), 'source': 'phone_camera'},
            format='multipart',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data['match'])
        self.assertIsNone(response.data.get('id'))
        self.assertIsNone(response.data.get('name'))

    def test_identify_known_person_rebuilds_missing_encodings_for_known_person_images(self):
        FaceEncoding.objects.filter(face_image=self.known_person_face_image).delete()
        identify_response = self.client.post(reverse('identify-patient'), {'device_id': self.device_id, 'image': self._make_image()}, format='multipart')
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {identify_response.data['patient_session_token']}")
        response = self.client.post(
            reverse('identify-known-person'),
            {'image': self._make_image(), 'source': 'phone_camera'},
            format='multipart',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['match'])
        self.assertEqual(response.data['id'], self.known_person.id)
        self.assertTrue(FaceEncoding.objects.filter(face_image=self.known_person_face_image).exists())

    def test_identify_known_person_falls_back_when_the_live_image_has_no_clear_face(self):
        textured_image = self._make_textured_image()
        FaceImage.objects.filter(pk=self.known_person_face_image.pk).delete()
        FaceImage.objects.create(
            subject_type='known_person',
            image=textured_image,
            object_id=self.known_person.id,
            content_type=ContentType.objects.get_for_model(self.known_person),
        )

        issue_token_response = self.client.post(
            reverse('issue-patient-session-token'),
            {'patient_id': self.patient.id, 'device_id': self.device_id},
            format='json',
        )
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_token_response.data['patient_session_token']}")
        response = self.client.post(
            reverse('identify-known-person'),
            {'image': textured_image, 'source': 'phone_camera'},
            format='multipart',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['match'])
        self.assertEqual(response.data['id'], self.known_person.id)

    def test_identify_known_person_returns_bad_request_for_non_face_image(self):
        identify_response = self.client.post(reverse('identify-patient'), {'device_id': self.device_id, 'image': self.image}, format='multipart')
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {identify_response.data['patient_session_token']}")
        bad_image = self._make_image(with_face=False)
        response = self.client.post(
            reverse('identify-known-person'),
            {'image': bad_image, 'source': 'phone_camera'},
            format='multipart',
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('detail', response.data)

    @patch('recognition.views.compute_similarity', return_value=0.84)
    def test_phone_auto_capture_accepts_realistic_same_person_similarity(self, _mock_similarity):
        identify_response = self.client.post(reverse('identify-patient'), {'device_id': self.device_id, 'image': self._make_image()}, format='multipart')
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {identify_response.data['patient_session_token']}")
        response = self.client.post(
            reverse('identify-known-person'),
            {'image': self._make_image(), 'source': 'phone_auto_capture'},
            format='multipart',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['match'])
        self.assertEqual(response.data['id'], self.known_person.id)

    @patch('recognition.views.compute_similarity', return_value=0.6)
    def test_phone_auto_capture_rejects_low_confidence_unknown_person(self, _mock_similarity):
        identify_response = self.client.post(reverse('identify-patient'), {'device_id': self.device_id, 'image': self._make_image()}, format='multipart')
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {identify_response.data['patient_session_token']}")
        response = self.client.post(
            reverse('identify-known-person'),
            {'image': self._make_image(), 'source': 'phone_auto_capture'},
            format='multipart',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data['match'])
        self.assertIsNone(response.data['id'])

    @patch('recognition.views.compute_similarity', return_value=0.6)
    def test_phone_auto_capture_records_unknown_detection_event(self, _mock_similarity):
        identify_response = self.client.post(reverse('identify-patient'), {'device_id': self.device_id, 'image': self._make_image()}, format='multipart')
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {identify_response.data['patient_session_token']}")

        response = self.client.post(
            reverse('identify-known-person'),
            {'image': self._make_image(), 'source': 'phone_auto_capture'},
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data['match'])
        self.assertTrue(
            RecognitionHistory.objects.filter(
                patient=self.patient,
                subject_type='known_person',
                outcome='not_matched',
            ).exists(),
        )

    @patch('recognition.views.compute_similarity', return_value=0.2)
    def test_unknown_person_uses_single_shared_unknown_identity(self, _mock_similarity):
        token_response = self.client.post(
            reverse('issue-patient-session-token'),
            {'patient_id': self.patient.id, 'device_id': self.device_id},
            format='json',
        )
        self.assertEqual(token_response.status_code, status.HTTP_200_OK)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token_response.data['patient_session_token']}")

        first = self.client.post(
            reverse('identify-known-person'),
            {'image': self._make_image(), 'source': 'specs_hardware'},
            format='multipart',
        )
        second = self.client.post(
            reverse('identify-known-person'),
            {'image': self._make_image(color=(10, 20, 30)), 'source': 'specs_hardware'},
            format='multipart',
        )

        self.assertEqual(first.status_code, status.HTTP_200_OK)
        self.assertEqual(second.status_code, status.HTTP_200_OK)
        self.assertFalse(first.data['match'])
        self.assertFalse(second.data['match'])
        self.assertEqual(first.data['name'], 'Unknown')
        self.assertEqual(second.data['name'], 'Unknown')
        self.assertEqual(first.data['id'], second.data['id'])
        self.assertEqual(KnownPerson.objects.filter(patient=self.patient, name='Unknown').count(), 1)

    @patch('recognition.views.compute_similarity', return_value=0.84)
    def test_phone_auto_capture_detects_known_person(self, _mock_similarity):
        identify_response = self.client.post(reverse('identify-patient'), {'device_id': self.device_id, 'image': self._make_image()}, format='multipart')
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {identify_response.data['patient_session_token']}")
        response = self.client.post(
            reverse('identify-known-person'),
            {'image': self._make_image(), 'source': 'phone_auto_capture'},
            format='multipart',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['match'])
        self.assertEqual(response.data['id'], self.known_person.id)

    def test_phone_auto_capture_does_not_fallback_to_known_person_reference(self):
        identify_response = self.client.post(reverse('identify-patient'), {'device_id': self.device_id, 'image': self._make_image()}, format='multipart')
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {identify_response.data['patient_session_token']}")
        with patch('recognition.views.detect_face', side_effect=NoFaceDetectedError('No face detected')):
            response = self.client.post(
                reverse('identify-known-person'),
                {'image': self._make_image(color=(255, 255, 0)), 'source': 'phone_auto_capture'},
                format='multipart',
            )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('detail', response.data)
