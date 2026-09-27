from django.contrib.auth import get_user_model
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from patients.models import Patient


class CaregiverGameResultsTests(TestCase):
    def setUp(self):
        caregiver_model = get_user_model()
        self.caregiver = caregiver_model.objects.create_user(
            email='game-results-caregiver@example.com',
            first_name='Caregiver',
            password='StrongPass123',
        )
        self.patient = Patient.objects.create(
            caregiver=self.caregiver,
            name='Game Results Patient',
            age=60,
            medical_notes='Game results visibility test',
        )
        self.client = APIClient()

    def test_caregiver_can_read_result_saved_with_patient_session(self):
        token_response = self.client.post(
            reverse('issue-patient-session-token'),
            {'patient_id': self.patient.id, 'device_id': 'game-results-device'},
            format='json',
        )
        self.assertEqual(token_response.status_code, 200)

        self.client.credentials(
            HTTP_AUTHORIZATION=f"Bearer {token_response.data['patient_session_token']}"
        )
        save_response = self.client.post(
            reverse('game-results'),
            {
                'game_name': 'Sequence Memory',
                'score': 60,
                'correct_answers': 3,
                'total_questions': 5,
            },
            format='json',
        )
        self.assertEqual(save_response.status_code, 201)

        caregiver_token = str(RefreshToken.for_user(self.caregiver).access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {caregiver_token}')
        read_response = self.client.get(
            reverse('game-results'),
            {'patient': self.patient.id},
        )

        self.assertEqual(read_response.status_code, 200)
        self.assertEqual(len(read_response.data), 1)
        self.assertEqual(read_response.data[0]['score'], 60)
        self.assertEqual(read_response.data[0]['correct_answers'], 3)
        self.assertEqual(read_response.data[0]['total_questions'], 5)