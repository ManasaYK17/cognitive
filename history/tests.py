from django.urls import reverse
from django.core.signing import dumps
from rest_framework import status
from rest_framework.test import APITestCase
from accounts.models import Caregiver
from patients.models import Patient
from known_people.models import KnownPerson
from history.models import RecognitionHistory
from conversations.models import ConversationHistory


class HistoryEndpointsTests(APITestCase):
    def setUp(self):
        self.caregiver = Caregiver.objects.create_user(
            email='historycaregiver@example.com',
            first_name='History',
            password='StrongPass123',
        )
        self.patient = Patient.objects.create(
            caregiver=self.caregiver,
            name='Rina',
            age=60,
            medical_notes='Needs recognition',
        )
        self.other_caregiver = Caregiver.objects.create_user(
            email='historyothercaregiver@example.com',
            first_name='HistoryOther',
            password='StrongPass123',
        )
        self.other_patient = Patient.objects.create(
            caregiver=self.other_caregiver,
            name='Lina',
            age=70,
            medical_notes='Another patient',
        )
        self.known_person = KnownPerson.objects.create(
            patient=self.patient,
            name='Mina',
            relationship='Daughter',
        )
        self.other_known_person = KnownPerson.objects.create(
            patient=self.other_patient,
            name='Tina',
            relationship='Daughter',
        )
        self.history_event = RecognitionHistory.objects.create(
            patient=self.patient,
            subject_type='known_person',
            content_type=None,
            object_id=self.known_person.id,
            confidence_score=0.85,
            source='phone_camera',
            outcome='matched',
        )
        self.conversation = ConversationHistory.objects.create(
            patient=self.patient,
            known_person=self.known_person,
            transcript='Hello, this is a conversation.',
            summary='Brief summary',
        )
        self.patient_token = dumps({'patient_id': self.patient.id, 'device_id': 'device-123'})

    def _authenticate_caregiver(self):
        login_url = reverse('caregiver-login')
        response = self.client.post(login_url, {
            'email': self.caregiver.email,
            'password': 'StrongPass123',
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {response.data["access"]}')

    def test_history_feed_returns_combined_history_for_caregiver(self):
        self._authenticate_caregiver()
        response = self.client.get(reverse('history-feed'))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 2)
        self.assertEqual({item['event_type'] for item in response.data}, {'recognition', 'conversation'})

    def test_history_feed_filters_by_patient_and_search(self):
        self._authenticate_caregiver()
        response = self.client.get(reverse('history-feed'), {
            'patient_id': self.patient.id,
            'search': 'Brief',
        })

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]['event_type'], 'conversation')
        self.assertEqual(response.data[0]['summary'], 'Brief summary')

    def test_patient_history_view_requires_session_token(self):
        response = self.client.get(reverse('history-patient-view'))
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_patient_history_view_returns_latest_conversation_summaries(self):
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.patient_token}')
        response = self.client.get(reverse('history-patient-view'))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]['known_person_name'], 'Mina')
        self.assertEqual(response.data[0]['last_summary'], 'Brief summary')
