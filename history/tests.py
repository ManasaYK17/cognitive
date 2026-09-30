from datetime import timedelta
from django.urls import reverse
from django.contrib.contenttypes.models import ContentType
from django.core.signing import dumps
from django.core.files.uploadedfile import SimpleUploadedFile
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase
from unittest.mock import patch
from accounts.models import Caregiver
from patients.models import FaceImage, Patient
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

    def test_history_feed_serves_the_capture_attached_to_an_unknown_conversation(self):
        unknown_person = KnownPerson.objects.create(patient=self.patient, name='Unknown', relationship='None')
        conversation = ConversationHistory.objects.create(
            patient=self.patient,
            known_person=unknown_person,
            transcript='Unknown conversation',
            summary='Conversation with an unknown person',
            captured_image=SimpleUploadedFile('unknown-capture.jpg', b'unknown-capture-bytes', content_type='image/jpeg'),
        )
        self._authenticate_caregiver()

        response = self.client.get(reverse('history-feed'))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        item = next(row for row in response.data if row['event_type'] == 'conversation' and row['id'] == conversation.id)
        self.assertIn(f'/api/history/images/conversation/{conversation.id}/', item['captured_image'])
        image_response = self.client.get(item['captured_image'])
        self.assertEqual(image_response.status_code, status.HTTP_200_OK)
        self.assertEqual(b''.join(image_response.streaming_content), b'unknown-capture-bytes')

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

    def test_patient_history_returns_known_photo_and_unknown_conversation_capture(self):
        unknown_person = KnownPerson.objects.create(patient=self.patient, name='Unknown', relationship='None')
        unknown_capture = b'patient-unknown-capture'
        unknown_conversation = ConversationHistory.objects.create(
            patient=self.patient,
            known_person=unknown_person,
            transcript='Unknown conversation',
            summary='Unknown conversation summary',
            captured_image=SimpleUploadedFile('capture.jpg', unknown_capture, content_type='image/jpeg'),
        )
        known_photo = b'known-enrollment-photo'
        FaceImage.objects.create(
            subject_type='known_person',
            content_type=ContentType.objects.get_for_model(KnownPerson),
            object_id=self.known_person.id,
            image=SimpleUploadedFile('known.jpg', known_photo, content_type='image/jpeg'),
        )
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.patient_token}')

        people_response = self.client.get(reverse('history-patient-view'))

        self.assertEqual(people_response.status_code, status.HTTP_200_OK)
        people = {item['known_person_name']: item for item in people_response.data}
        self.assertTrue(people['Mina']['known_person_image'].endswith(f'/patient-images/known-person/{self.known_person.id}/'))
        self.assertIsNone(people['Unknown']['known_person_image'])

        conversations_response = self.client.get(
            reverse('history-patient-view'),
            {'known_person_id': unknown_person.id},
        )
        self.assertEqual(conversations_response.status_code, status.HTTP_200_OK)
        capture_url = conversations_response.data[0]['captured_image']
        self.assertTrue(capture_url.endswith(f'/patient-images/conversation/{unknown_conversation.id}/'))
        image_response = self.client.get(capture_url)
        self.assertEqual(image_response.status_code, status.HTTP_200_OK)
        self.assertEqual(b''.join(image_response.streaming_content), unknown_capture)

        other_patient_token = dumps({'patient_id': self.other_patient.id, 'device_id': 'other-device'})
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {other_patient_token}')
        forbidden_image = self.client.get(capture_url)
        self.assertEqual(forbidden_image.status_code, status.HTTP_404_NOT_FOUND)

    def test_patient_recognition_ignores_older_match_after_latest_hardware_non_match(self):
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.patient_token}')
        known_person_type = ContentType.objects.get_for_model(KnownPerson)
        RecognitionHistory.objects.create(
            patient=self.patient,
            subject_type='known_person',
            content_type=known_person_type,
            object_id=self.known_person.id,
            confidence_score=0.9,
            source='specs_hardware',
            outcome='matched',
        )
        RecognitionHistory.objects.create(
            patient=self.patient,
            subject_type='known_person',
            content_type=known_person_type,
            object_id=self.known_person.id,
            confidence_score=0.4,
            source='specs_hardware',
            outcome='not_matched',
        )

        response = self.client.get(reverse('patient-recognition'))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data['match'])
        self.assertIn('timestamp', response.data)

        next_response = self.client.get(reverse('patient-recognition'), {'after': response.data['timestamp']})
        self.assertEqual(next_response.status_code, status.HTTP_200_OK)
        self.assertFalse(next_response.data['match'])
        self.assertNotIn('timestamp', next_response.data)

    def test_patient_recognition_ignores_stale_hardware_match_from_previous_session(self):
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.patient_token}')
        stale_time = timezone.now() - timedelta(minutes=3)
        stale_event = RecognitionHistory.objects.create(
            patient=self.patient,
            subject_type='known_person',
            content_type=ContentType.objects.get_for_model(KnownPerson),
            object_id=self.known_person.id,
            confidence_score=0.9,
            source='specs_hardware',
            outcome='matched',
        )
        stale_event.timestamp = stale_time
        stale_event.save(update_fields=['timestamp'])

        response = self.client.get(reverse('patient-recognition'))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data['match'])

    def test_patient_recognition_returns_latest_matching_hardware_person(self):
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.patient_token}')
        RecognitionHistory.objects.create(
            patient=self.patient,
            subject_type='known_person',
            content_type=ContentType.objects.get_for_model(KnownPerson),
            object_id=self.known_person.id,
            confidence_score=0.9,
            source='specs_hardware',
            outcome='matched',
        )

        response = self.client.get(reverse('patient-recognition'))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['match'])
        self.assertEqual(response.data['known_person_id'], self.known_person.id)
        self.assertEqual(response.data['name'], self.known_person.name)

    @patch('conversations.services.translate_conversation_text')
    def test_patient_history_view_translates_and_caches_stored_conversation(self, mock_translate):
        mock_translate.side_effect = lambda text, language: f'{language}: {text}'
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.patient_token}')
        params = {
            'known_person_id': str(self.known_person.id),
            'language': 'Kannada',
        }

        first_response = self.client.get(reverse('history-patient-view'), params)

        self.assertEqual(first_response.status_code, status.HTTP_200_OK)
        self.assertEqual(first_response.data[0]['summary'], 'Kannada: Brief summary')
        self.assertEqual(first_response.data[0]['transcript'], 'Kannada: Hello, this is a conversation.')
        self.conversation.refresh_from_db()
        self.assertEqual(self.conversation.summary, 'Brief summary')
        self.assertEqual(self.conversation.transcript, 'Hello, this is a conversation.')

        second_response = self.client.get(reverse('history-patient-view'), params)

        self.assertEqual(second_response.data[0]['summary'], 'Kannada: Brief summary')
        self.assertEqual(mock_translate.call_count, 2)
