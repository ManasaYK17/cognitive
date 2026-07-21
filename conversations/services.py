import io
import logging

import requests
try:
    import speech_recognition as sr
except ImportError:  # pragma: no cover
    sr = None

logger = logging.getLogger(__name__)


class SpeechToTextError(Exception):
    pass


class SummarizationError(Exception):
    pass


def transcribe_audio(audio_file):
    if sr is None:
        raise SpeechToTextError('SpeechRecognition library is not installed.')

    recognizer = sr.Recognizer()
    raw_bytes = _read_audio_bytes(audio_file)
    if raw_bytes is None:
        raise SpeechToTextError('Unable to read audio data.')

    audio_source = io.BytesIO(raw_bytes)
    try:
        with sr.AudioFile(audio_source) as source:
            audio_data = recognizer.record(source)
    except Exception as exc:
        raise SpeechToTextError(f'Unable to process audio file: {exc}') from exc

    # Prefer local offline recognition if available, otherwise fall back.
    if hasattr(recognizer, 'recognize_sphinx'):
        try:
            return recognizer.recognize_sphinx(audio_data)
        except sr.RequestError:
            pass
        except sr.UnknownValueError:
            raise SpeechToTextError('Speech could not be understood.')

    try:
        return recognizer.recognize_google(audio_data)
    except sr.RequestError as exc:
        raise SpeechToTextError(f'Speech recognition service error: {exc}') from exc
    except sr.UnknownValueError:
        raise SpeechToTextError('Speech could not be understood.')


def summarize_transcript(transcript, api_url, model_name, api_key=None, timeout_seconds=10):
    prompt = (
        'Please provide a concise 2-3 sentence summary of the following conversation transcript:\n\n'
        f'{transcript}\n\n'
        'Summary:'
    )

    if api_key or 'openrouter.ai' in api_url.lower() or api_url.endswith('/chat/completions'):
        payload = {
            'model': model_name,
            'messages': [
                {
                    'role': 'user',
                    'content': prompt,
                }
            ],
            'temperature': 0.2,
            'max_tokens': 200,
        }
        headers = {'Content-Type': 'application/json'}
        if api_key:
            headers['Authorization'] = f'Bearer {api_key}'

        try:
            response = requests.post(api_url, json=payload, headers=headers, timeout=timeout_seconds)
            response.raise_for_status()
        except requests.RequestException as exc:
            logger.exception('OpenRouter summarization request failed')
            raise SummarizationError(f'Summarization service unavailable: {exc}') from exc

        try:
            body = response.json()
        except ValueError as exc:
            raise SummarizationError('Invalid response from summarization service.') from exc

        choices = body.get('choices')
        if not choices or not isinstance(choices, list):
            raise SummarizationError('Summarization response did not contain choices.')

        first_choice = choices[0]
        message = first_choice.get('message') or {}
        content = message.get('content') if isinstance(message, dict) else None
        if not content:
            raise SummarizationError('Summarization response did not contain content.')

        if isinstance(content, dict):
            content = content.get('text')
        return content.strip()

    payload = {
        'model': model_name,
        'prompt': prompt,
        'temperature': 0.2,
        'max_tokens': 200,
    }

    try:
        response = requests.post(api_url, json=payload, timeout=timeout_seconds)
        response.raise_for_status()
    except requests.RequestException as exc:
        logger.exception('Ollama summarization request failed')
        raise SummarizationError(f'Ollama service unavailable: {exc}') from exc

    try:
        body = response.json()
    except ValueError as exc:
        raise SummarizationError('Invalid response from Ollama service.') from exc

    results = body.get('results')
    if not results or not isinstance(results, list):
        raise SummarizationError('Ollama response did not contain summarization results.')

    first_result = results[0]
    output = first_result.get('output') or []
    if not output or not isinstance(output, list):
        raise SummarizationError('Ollama response output is missing.')

    text_parts = [item.get('text') for item in output if isinstance(item, dict) and item.get('type') == 'output_text']
    if not text_parts:
        text_parts = [item.get('text') for item in output if isinstance(item, dict) and item.get('text')]

    if not text_parts:
        raise SummarizationError('Ollama response did not contain text output.')

    return ' '.join(text_parts).strip()


def _read_audio_bytes(audio_file):
    if audio_file is None:
        return None

    try:
        if hasattr(audio_file, 'seek'):
            audio_file.seek(0)
        if hasattr(audio_file, 'read'):
            data = audio_file.read()
            if data:
                return data
    except Exception:
        pass

    underlying = getattr(audio_file, 'file', None)
    if underlying is not None:
        try:
            if hasattr(underlying, 'seek'):
                underlying.seek(0)
            if hasattr(underlying, 'read'):
                data = underlying.read()
                if data:
                    return data
        except Exception:
            pass

    if isinstance(audio_file, (bytes, bytearray)):
        return bytes(audio_file)

    return None
