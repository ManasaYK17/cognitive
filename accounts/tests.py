from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from .models import Caregiver


class AccountsTests(APITestCase):
    def test_register_caregiver(self):
        url = reverse('caregiver-register')
        payload = {
            'email': 'caregiver@example.com',
            'first_name': 'Jane',
            'last_name': 'Doe',
            'password': 'StrongPassword123',
            'password_confirm': 'StrongPassword123',
        }
        response = self.client.post(url, payload, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(Caregiver.objects.filter(email='caregiver@example.com').exists())

    def test_login_and_refresh(self):
        caregiver = Caregiver.objects.create_user(
            email='caregiver2@example.com',
            first_name='John',
            password='AnotherPassword123',
        )
        login_url = reverse('caregiver-login')
        response = self.client.post(login_url, {
            'email': 'caregiver2@example.com',
            'password': 'AnotherPassword123',
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)
        self.assertIn('refresh', response.data)

        refresh_url = reverse('token_refresh')
        refresh_response = self.client.post(refresh_url, {
            'refresh': response.data['refresh'],
        }, format='json')
        self.assertEqual(refresh_response.status_code, status.HTTP_200_OK)
        self.assertIn('access', refresh_response.data)

    def test_full_auth_flow_register_login_and_me(self):
        register_url = reverse('caregiver-register')
        register_payload = {
            'email': 'fullflow@example.com',
            'first_name': 'Full',
            'last_name': 'Flow',
            'password': 'FullFlowPassword123',
            'password_confirm': 'FullFlowPassword123',
        }
        register_response = self.client.post(register_url, register_payload, format='json')
        self.assertEqual(register_response.status_code, status.HTTP_201_CREATED)

        caregiver = Caregiver.objects.get(email='fullflow@example.com')
        login_url = reverse('caregiver-login')
        login_response = self.client.post(login_url, {
            'email': 'fullflow@example.com',
            'password': 'FullFlowPassword123',
        }, format='json')
        self.assertEqual(login_response.status_code, status.HTTP_200_OK)
        self.assertIn('access', login_response.data)

        access_token = login_response.data['access']
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {access_token}')
        me_url = reverse('caregiver-me')
        me_response = self.client.get(me_url)
        self.assertEqual(me_response.status_code, status.HTTP_200_OK)
        self.assertEqual(me_response.data['email'], caregiver.email)
        self.assertEqual(me_response.data['first_name'], caregiver.first_name)
    def test_register_device_token(self):
        caregiver = Caregiver.objects.create_user(
            email='caregiver2@example.com',
            first_name='Token',
            password='AnotherPassword123',
        )
        login_url = reverse('caregiver-login')
        response = self.client.post(login_url, {
            'email': caregiver.email,
            'password': 'AnotherPassword123',
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        access_token = response.data['access']

        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {access_token}')
        token_url = reverse('register-device-token')
        token_response = self.client.post(token_url, {'device_token': 'fake-token-123'}, format='json')
        self.assertEqual(token_response.status_code, status.HTTP_200_OK)
        self.assertEqual(token_response.data['detail'], 'Device token registered.')
        caregiver.refresh_from_db()
        self.assertEqual(caregiver.fcm_device_token, 'fake-token-123')
    def test_me_requires_authentication(self):
        url = reverse('caregiver-me')
        response = self.client.get(url)
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
