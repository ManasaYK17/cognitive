from django.core.files.uploadedfile import SimpleUploadedFile
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from accounts.models import Caregiver
from patients.models import Patient
from .models import KnownPerson
from patients.models import FaceImage


class KnownPersonTests(APITestCase):
    def setUp(self):
        self.caregiver = Caregiver.objects.create_user(email='knowncaregiver@example.com', first_name='Care', password='StrongPass123')
        self.other_caregiver = Caregiver.objects.create_user(email='otherknowncaregiver@example.com', first_name='Other', password='StrongPass123')
        self.patient = Patient.objects.create(caregiver=self.caregiver, name='Charlie', age=70, medical_notes='Test patient')
        self.client.force_authenticate(user=self.caregiver)

    def test_caregiver_can_manage_known_people_for_their_patients(self):
        url = reverse('known-person-list-create')
        create_response = self.client.post(url, {
            'patient': self.patient.id,
            'name': 'Diana',
            'relationship': 'Daughter',
            'occupation': 'Teacher',
            'phone_number': '555-1234',
            'address': '123 Main St',
            'notes': 'Likes tea',
        }, format='json')
        self.assertEqual(create_response.status_code, status.HTTP_201_CREATED)
        known_person_id = create_response.data['id']

        list_response = self.client.get(url)
        self.assertEqual(list_response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(list_response.data), 1)

        detail_url = reverse('known-person-detail', kwargs={'pk': known_person_id})
        detail_response = self.client.get(detail_url)
        self.assertEqual(detail_response.status_code, status.HTTP_200_OK)
        self.assertEqual(detail_response.data['name'], 'Diana')

        update_response = self.client.patch(detail_url, {'notes': 'Updated note'}, format='json')
        self.assertEqual(update_response.status_code, status.HTTP_200_OK)
        self.assertEqual(update_response.data['notes'], 'Updated note')

        self.client.force_authenticate(user=self.other_caregiver)
        forbidden_response = self.client.get(detail_url)
        self.assertEqual(forbidden_response.status_code, status.HTTP_404_NOT_FOUND)

        self.client.force_authenticate(user=self.caregiver)
        delete_response = self.client.delete(detail_url)
        self.assertEqual(delete_response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(KnownPerson.objects.filter(id=known_person_id).exists())

    def test_known_person_face_images_upload(self):
        known_person = KnownPerson.objects.create(patient=self.patient, name='Eve', relationship='Friend')
        upload_url = reverse('known-person-face-images', kwargs={'pk': known_person.id})
        image = SimpleUploadedFile('face1.jpg', b'fake-image-bytes', content_type='image/jpeg')
        response = self.client.post(upload_url, {'files': [image, image]}, format='multipart')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(FaceImage.objects.filter(subject_type='known_person', object_id=known_person.id).count(), 2)
