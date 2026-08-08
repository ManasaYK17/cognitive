from django.conf import settings
from django.contrib.contenttypes.models import ContentType
from rest_framework import status, views
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import SimpleRateThrottle

from patients.auth import resolve_patient_from_token
from known_people.models import KnownPerson
from .models import ConversationHistory
from .services import SpeechToTextError, SummarizationError, transcribe_audio, transcribe_audio_high_pass, summarize_transcript


class DeviceScopedRateThrottle(SimpleRateThrottle):
    scope = 'recognition'

    def get_cache_key(self, request, view):
        device_id = request.data.get('device_id') or request.data.get('deviceId') or request.query_params.get('device_id')
        if not device_id:
            device_id = request.META.get('REMOTE_ADDR', 'unknown')
        return self.cache_format % {
            'scope': self.scope,
            'ident': device_id,
        }


class ConversationSummarizeView(views.APIView):
    authentication_classes = []
    parser_classes = (MultiPartParser, FormParser)
    permission_classes = [AllowAny]
    throttle_classes = [DeviceScopedRateThrottle]

    def post(self, request, *args, **kwargs):
        audio = request.FILES.get('audio')
        patient_id = request.data.get('patient_id')
        known_person_id = request.data.get('known_person_id')

        if not audio:
            return Response({'detail': 'An audio file is required.'}, status=status.HTTP_400_BAD_REQUEST)
        if not patient_id or not known_person_id:
            return Response({'detail': 'patient_id and known_person_id are required.'}, status=status.HTTP_400_BAD_REQUEST)

        auth_header = request.META.get('HTTP_AUTHORIZATION', '')
        token = auth_header.replace('Bearer ', '', 1).strip() if auth_header.startswith('Bearer ') else ''
        if not token:
            return Response({'detail': 'A patient session token is required.'}, status=status.HTTP_401_UNAUTHORIZED)

        patient = resolve_patient_from_token(token)
        if patient is None or str(patient.id) != str(patient_id):
            return Response({'detail': 'Token patient_id does not match request patient_id.'}, status=status.HTTP_401_UNAUTHORIZED)

        known_person = KnownPerson.objects.filter(id=known_person_id, patient=patient).first()
        if known_person is None:
            return Response({'detail': 'Known person not found for the patient.'}, status=status.HTTP_404_NOT_FOUND)

        transcript = ''
        summary = ''
        error_message = None

        try:
            transcript = transcribe_audio(audio)
        except SpeechToTextError as exc:
            error_message = str(exc)
            conversation = ConversationHistory.objects.create(
                patient=patient,
                known_person=known_person,
                transcript=transcript,
                summary=summary,
                error_message=error_message,
            )
            return Response({'detail': error_message}, status=status.HTTP_400_BAD_REQUEST)

        openrouter_url = getattr(settings, 'OPENROUTER_API_URL', '')
        openrouter_api_key = getattr(settings, 'OPENROUTER_API_KEY', '')
        openrouter_model_name = getattr(settings, 'OPENROUTER_MODEL_NAME', 'qwen-2.5-mini')
        ollama_url = getattr(settings, 'OLLAMA_API_URL', 'http://localhost:11434/api/generate')
        ollama_model_name = getattr(settings, 'OLLAMA_MODEL_NAME', 'qwen2.5:7b')

        if openrouter_api_key:
            api_url = openrouter_url
            model_name = openrouter_model_name
            api_key = openrouter_api_key
        else:
            api_url = ollama_url
            model_name = ollama_model_name
            api_key = None

        try:
            summary = summarize_transcript(transcript, api_url, model_name, api_key=api_key)
        except SummarizationError as exc:
            error_message = str(exc)

        conversation = ConversationHistory.objects.create(
            patient=patient,
            known_person=known_person,
            transcript=transcript,
            summary=summary,
            error_message=error_message,
        )

        response_data = {
            'id': conversation.id,
            'patient_id': patient.id,
            'known_person_id': known_person.id,
            'transcript': transcript,
            'summary': summary,
            'error_message': error_message,
            'created_at': conversation.created_at,
        }
        status_code = status.HTTP_200_OK if not error_message else status.HTTP_207_MULTI_STATUS
        return Response(response_data, status=status_code)


class ConversationTranscribeView(views.APIView):
    """Transcribes and summarizes a raw audio recording without attaching it
    to a known_person or creating a ConversationHistory row. For use before a
    known_person exists yet -- e.g. the create-from-encounter flow, where the
    caller needs a summary string to submit alongside newly captured face
    images. Same Bearer patient-session-token auth pattern as
    ConversationSummarizeView and recognition.views.IdentifyKnownPersonView."""
    authentication_classes = []
    parser_classes = (MultiPartParser, FormParser)
    permission_classes = [AllowAny]
    throttle_classes = [DeviceScopedRateThrottle]

    def post(self, request, *args, **kwargs):
        audio = request.FILES.get('audio')
        patient_id = request.data.get('patient_id')

        if not audio:
            return Response({'detail': 'An audio file is required.'}, status=status.HTTP_400_BAD_REQUEST)
        if not patient_id:
            return Response({'detail': 'patient_id is required.'}, status=status.HTTP_400_BAD_REQUEST)

        auth_header = request.META.get('HTTP_AUTHORIZATION', '')
        token = auth_header.replace('Bearer ', '', 1).strip() if auth_header.startswith('Bearer ') else ''
        if not token:
            return Response({'detail': 'A patient session token is required.'}, status=status.HTTP_401_UNAUTHORIZED)

        patient = resolve_patient_from_token(token)
        if patient is None or str(patient.id) != str(patient_id):
            return Response({'detail': 'Token patient_id does not match request patient_id.'}, status=status.HTTP_401_UNAUTHORIZED)

        transcript = ''
        summary = ''
        error_message = None

        try:
            # High-pass-filtered variant, not the plain transcribe_audio()
            # ConversationSummarizeView uses -- see transcribe_audio_high_pass()
            # docstring in services.py.
            transcript = transcribe_audio_high_pass(audio)
        except SpeechToTextError as exc:
            error_message = str(exc)
            return Response(
                {'transcript': transcript, 'summary': summary, 'error_message': error_message},
                status=status.HTTP_400_BAD_REQUEST,
            )

        openrouter_url = getattr(settings, 'OPENROUTER_API_URL', '')
        openrouter_api_key = getattr(settings, 'OPENROUTER_API_KEY', '')
        openrouter_model_name = getattr(settings, 'OPENROUTER_MODEL_NAME', 'qwen-2.5-mini')
        ollama_url = getattr(settings, 'OLLAMA_API_URL', 'http://localhost:11434/api/generate')
        ollama_model_name = getattr(settings, 'OLLAMA_MODEL_NAME', 'qwen2.5:7b')

        if openrouter_api_key:
            api_url = openrouter_url
            model_name = openrouter_model_name
            api_key = openrouter_api_key
        else:
            api_url = ollama_url
            model_name = ollama_model_name
            api_key = None

        try:
            summary = summarize_transcript(transcript, api_url, model_name, api_key=api_key)
        except SummarizationError as exc:
            error_message = str(exc)

        status_code = status.HTTP_200_OK if not error_message else status.HTTP_207_MULTI_STATUS
        return Response(
            {'transcript': transcript, 'summary': summary, 'error_message': error_message},
            status=status_code,
        )
