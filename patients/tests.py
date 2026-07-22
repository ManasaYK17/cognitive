from django.core.files.uploadedfile import SimpleUploadedFile
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase
from .models import Patient, FaceImage
from accounts.models import Caregiver
from conversations.models import ConversationHistory
from geofencing.models import LocationPing, SafeZone
from history.models import RecognitionHistory
from known_people.models import KnownPerson


class PatientTests(APITestCase):
    def setUp(self):
        self.caregiver = Caregiver.objects.create_user(email='patientcaregiver@example.com', first_name='Care', password='StrongPass123')
        self.other_caregiver = Caregiver.objects.create_user(email='othercaregiver@example.com', first_name='Other', password='StrongPass123')
        self.client.force_authenticate(user=self.caregiver)

    def test_caregiver_can_crud_and_scope_patients(self):
        endpoint = reverse('caregiver-patient')
        response = self.client.post(endpoint, {
            'name': 'Alice',
            'date_of_birth': '1990-01-01',
            'medical_notes': 'Needs reminders',
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        patient_id = response.data['id']

        get_response = self.client.get(endpoint)
        self.assertEqual(get_response.status_code, status.HTTP_200_OK)
        self.assertEqual(get_response.data['name'], 'Alice')

        update_response = self.client.put(endpoint, {
            'name': 'Alice',
            'date_of_birth': '1990-01-01',
            'medical_notes': 'Updated note',
        }, format='json')
        self.assertEqual(update_response.status_code, status.HTTP_200_OK)
        self.assertEqual(update_response.data['medical_notes'], 'Updated note')

        self.client.force_authenticate(user=self.other_caregiver)
        forbidden_response = self.client.get(endpoint)
        self.assertEqual(forbidden_response.status_code, status.HTTP_404_NOT_FOUND)

        self.client.force_authenticate(user=self.caregiver)
        delete_response = self.client.delete(endpoint)
        self.assertEqual(delete_response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(Patient.objects.filter(id=patient_id).exists())

    def test_patient_face_images_upload_replaces_previous_patient_reference(self):
        patient = Patient.objects.create(caregiver=self.caregiver, name='Bob', age=78, medical_notes='Test')
        upload_url = reverse('patient-face-images', kwargs={'pk': patient.id})
        image_one = SimpleUploadedFile('face1.jpg', b'fake-image-bytes', content_type='image/jpeg')
        response = self.client.post(upload_url, {'files': [image_one]}, format='multipart')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(FaceImage.objects.filter(patient_subject=patient).count(), 1)

        image_two = SimpleUploadedFile('face2.jpg', b'fake-image-bytes-2', content_type='image/jpeg')
        replacement_response = self.client.post(upload_url, {'files': [image_two]}, format='multipart')
        self.assertEqual(replacement_response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(FaceImage.objects.filter(patient_subject=patient).count(), 1)

    def test_dashboard_summary_includes_aggregated_metrics(self):
        patient = Patient.objects.create(caregiver=self.caregiver, name='Dana', age=72, medical_notes='Summary test')
        known_person = KnownPerson.objects.create(patient=patient, name='Mina', relationship='Daughter')
        RecognitionHistory.objects.create(
            patient=patient,
            subject_type='known_person',
            content_type=None,
            object_id=known_person.id,
            confidence_score=0.82,
            source='phone_camera',
            outcome='matched',
            timestamp=timezone.now(),
        )
        RecognitionHistory.objects.create(
            patient=patient,
            subject_type='patient',
            content_type=None,
            object_id=patient.id,
            confidence_score=0.61,
            source='phone_camera',
            outcome='not_matched',
            timestamp=timezone.now(),
        )
        ConversationHistory.objects.create(patient=patient, known_person=known_person, summary='Saved summary', transcript='hi')
        SafeZone.objects.create(patient=patient, name='Home', center_latitude=1.0, center_longitude=2.0, radius_meters=100)
        LocationPing.objects.create(patient=patient, latitude=1.0, longitude=2.0, distance_from_center_meters=25)

        response = self.client.get(reverse('patient-dashboard-summary', kwargs={'pk': patient.id}))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['today']['known_detections'], 1)
        self.assertEqual(response.data['today']['unknown_detections'], 1)
        self.assertEqual(response.data['conversations_saved'], 1)
        self.assertTrue(response.data['safe_zone']['inside'])
        self.assertGreaterEqual(len(response.data['recent_activity']), 1)
