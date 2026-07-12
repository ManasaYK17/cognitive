from django.urls import reverse
from django.core.signing import dumps
from rest_framework import status
from rest_framework.test import APITestCase
from accounts.models import Caregiver
from patients.models import Patient
from known_people.models import KnownPerson
from geofencing.models import SafeZone, LocationPing


class GeofencingTests(APITestCase):
    def setUp(self):
        self.caregiver = Caregiver.objects.create_user(
            email='geo@example.com',
            first_name='Geo',
            password='StrongPass123',
        )
        self.patient = Patient.objects.create(
            caregiver=self.caregiver,
            name='Rina',
            age=60,
        )
        self.patient_token = dumps({'patient_id': self.patient.id, 'device_id': 'device-123'})
        self.safe_zone_url = reverse('patient-safe-zone', kwargs={'pk': self.patient.id})
        self.location_url = reverse('patient-location-ping', kwargs={'pk': self.patient.id})

    def _authenticate_caregiver(self):
        login_url = reverse('caregiver-login')
        response = self.client.post(login_url, {'email': self.caregiver.email, 'password': 'StrongPass123'}, format='json')
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {response.data['access']}')

    def test_put_safe_zone_creates_zone(self):
        self._authenticate_caregiver()
        response = self.client.put(self.safe_zone_url, {
            'name': 'Home',
            'center_latitude': 40.0,
            'center_longitude': -74.0,
            'radius_meters': 100.0,
        }, format='json')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(SafeZone.objects.filter(patient=self.patient, name='Home').exists())

    def test_post_location_pings_requires_patient_token(self):
        response = self.client.post(self.location_url, {'latitude': 40.0, 'longitude': -74.0}, format='json')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_post_location_pings_stores_ping_and_returns_inside_status(self):
        SafeZone.objects.create(patient=self.patient, name='Home', center_latitude=40.0, center_longitude=-74.0, radius_meters=1000.0)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.patient_token}')
        response = self.client.post(self.location_url, {'latitude': 40.001, 'longitude': -74.001}, format='json')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('inside_safe_zone', response.data)
        self.assertTrue(LocationPing.objects.filter(patient=self.patient).exists())
