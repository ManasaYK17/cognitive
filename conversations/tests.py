from django.contrib.contenttypes.models import ContentType
from django.core.signing import dumps
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from unittest.mock import patch
from django.core.files.uploadedfile import SimpleUploadedFile
from accounts.models import Caregiver
from conversations.services import SummarizationError
from patients.models import Patient, FaceImage
from known_people.models import KnownPerson
from conversations.models import ConversationHistory


class ConversationSummarizeTests(APITestCase):
    def setUp(self):
        self.caregiver = Caregiver.objects.create_user(email='convcaregiver@example.com', first_name='Conv', password='StrongPass123')
        self.patient = Patient.objects.create(caregiver=self.caregiver, name='Rina', age=60, medical_notes='Needs recognition')
        self.known_person = KnownPerson.objects.create(patient=self.patient, name='Mina', relationship='Daughter')
        self.device_id = 'device-123'
        self.patient_token = dumps({'patient_id': self.patient.id, 'device_id': self.device_id})
        self.patient_face_image = FaceImage.objects.create(subject_type='patient', patient_subject=self.patient, image=SimpleUploadedFile('audio.wav', b'dummyaudio', content_type='audio/wav'))

    def _make_audio(self):
        return SimpleUploadedFile('audio.wav', b'dummyaudio', content_type='audio/wav')

    @patch('conversations.views.summarize_transcript')
    @patch('conversations.views.transcribe_audio')
    def test_summarize_conversation_stores_summary(self, mock_transcribe, mock_summarize):
        mock_transcribe.return_value = 'Hello, this is a test conversation.'
        mock_summarize.return_value = 'A brief summary of the conversation.'
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.patient_token}')

        response = self.client.post(
            reverse('conversation-summarize'),
            {
                'audio': self._make_audio(),
                'patient_id': self.patient.id,
                'known_person_id': self.known_person.id,
                'device_id': self.device_id,
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['summary'], 'A brief summary of the conversation.')
        self.assertTrue(ConversationHistory.objects.filter(patient=self.patient, known_person=self.known_person, summary__icontains='brief summary').exists())

    @patch('conversations.views.summarize_transcript')
    @patch('conversations.views.transcribe_audio')
    def test_summarize_conversation_fallback_records_transcript_on_summary_failure(self, mock_transcribe, mock_summarize):
        mock_transcribe.return_value = 'Fallback transcript.'
        mock_summarize.side_effect = SummarizationError('Ollama unreachable')
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.patient_token}')

        response = self.client.post(
            reverse('conversation-summarize'),
            {
                'audio': self._make_audio(),
                'patient_id': self.patient.id,
                'known_person_id': self.known_person.id,
                'device_id': self.device_id,
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_207_MULTI_STATUS)
        self.assertEqual(response.data['transcript'], 'Fallback transcript.')
        self.assertIsNotNone(response.data['error_message'])
        self.assertTrue(ConversationHistory.objects.filter(patient=self.patient, known_person=self.known_person, transcript='Fallback transcript.').exists())
