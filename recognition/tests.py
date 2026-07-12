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
from .services import detect_face, generate_encoding, NoFaceDetectedError, MultipleFacesDetectedError, LowQualityImageError
from .models import FaceEncoding
from PIL import Image
import io
import numpy as np


class RecognitionServiceTests(TestCase):
    def setUp(self):
        self.caregiver = Caregiver.objects.create_user(email='recognitioncaregiver@example.com', first_name='Rec', password='StrongPass123')
        self.patient = Patient.objects.create(caregiver=self.caregiver, name='Rina', age=60, medical_notes='Needs recognition')

    def _make_image(self, size=(120, 120), color=(255, 0, 0), with_face=True):
        image = Image.new('RGB', size, color)
        if with_face:
            image = image.crop((20, 20, 100, 100))
        buffer = io.BytesIO()
        image.save(buffer, format='JPEG')
        return SimpleUploadedFile('face.jpg', buffer.getvalue(), content_type='image/jpeg')

    def test_detect_face_and_generate_encoding_for_valid_image(self):
        image = self._make_image()
        face_location = detect_face(image)
        self.assertIsNotNone(face_location)
        encoding = generate_encoding(image, face_location)
        self.assertEqual(len(encoding), 128)

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
        self.image = self._make_image()
        self.patient_face_image = FaceImage.objects.create(subject_type='patient', patient_subject=self.patient, image=self.image)
        self.known_person_face_image = FaceImage.objects.create(
            subject_type='known_person',
            image=self.image,
            object_id=self.known_person.id,
            content_type=ContentType.objects.get_for_model(self.known_person),
        )

    def _make_image(self, size=(120, 120), color=(255, 0, 0), with_face=True):
        image = Image.new('RGB', size, color)
        if with_face:
            image = image.crop((20, 20, 100, 100))
        buffer = io.BytesIO()
        image.save(buffer, format='JPEG')
        return SimpleUploadedFile('face.jpg', buffer.getvalue(), content_type='image/jpeg')

    def test_identify_patient_returns_session_token_and_logs_history(self):
        response = self.client.post(reverse('identify-patient'), {'device_id': self.device_id, 'image': self.image}, format='multipart')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['match'])
        self.assertEqual(response.data['patient_id'], self.patient.id)
        self.assertIn('patient_session_token', response.data)
        self.assertTrue(RecognitionHistory.objects.filter(patient=self.patient, outcome='matched').exists())

    def test_identify_known_person_requires_patient_session_token(self):
        identify_response = self.client.post(reverse('identify-patient'), {'device_id': self.device_id, 'image': self.image}, format='multipart')
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {identify_response.data['patient_session_token']}")
        response = self.client.post(
            reverse('identify-known-person'),
            {'image': self.image, 'patient_id': self.patient.id, 'source': 'phone_camera'},
            format='multipart',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['match'])
        self.assertEqual(response.data['id'], self.known_person.id)
        self.assertTrue(RecognitionHistory.objects.filter(patient=self.patient, subject=self.known_person, outcome='matched').exists())
