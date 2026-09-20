import io
import logging
import os
import shutil
import subprocess
import tempfile
import wave

import numpy as np
import requests
from django.conf import settings
from scipy.signal import butter, filtfilt
try:
    import speech_recognition as sr
except ImportError:  # pragma: no cover
    sr = None

logger = logging.getLogger(__name__)


class SpeechToTextError(Exception):
    pass


class SummarizationError(Exception):
    pass


# recognize_google's free/unofficial endpoint (no api_key -- see below) is
# unreliable on long continuous clips sent as a single request: confirmed
# directly against a real 60s device recording where the whole file came
# back UnknownValueError, but splitting it into 10s chunks transcribed 5 of
# 6 correctly. transcribe_audio() below chunks for this reason -- a bad or
# silent chunk then just contributes nothing, instead of blanking out an
# otherwise-good recording.
_TRANSCRIBE_CHUNK_SECONDS = 10


def _recognize_chunk(recognizer, audio_data, language='en-IN'):
    # Prefer local offline recognition if available, otherwise fall back.
    if hasattr(recognizer, 'recognize_sphinx'):
        try:
            return recognizer.recognize_sphinx(audio_data)
        except sr.RequestError:
            pass
        except sr.UnknownValueError:
            return None

    try:
        return recognizer.recognize_google(audio_data, language=language)
    except sr.RequestError as exc:
        raise SpeechToTextError(f'Speech recognition service error: {exc}') from exc
    except sr.UnknownValueError:
        return None


def _normalize_audio_bytes(raw_bytes, source_name='audio'):
    """Convert common mobile audio formats (notably .m4a) into PCM WAV bytes.

    This keeps the rest of the transcription pipeline unchanged while allowing
    the app's recorder output to be processed by SpeechRecognition.
    """
    if not raw_bytes:
        return None

    # Fast path: already a WAV/PCM payload.
    if source_name.lower().endswith('.wav') or source_name.lower().endswith('.wave'):
        try:
            with wave.open(io.BytesIO(raw_bytes), 'rb') as wav:
                wav.getnframes()
            return raw_bytes
        except Exception:
            pass

    ffmpeg_path = shutil.which('ffmpeg')
    if ffmpeg_path is None:
        winget_root = os.path.expandvars(r'%LOCALAPPDATA%\Microsoft\WinGet\Packages')
        for root, _, files in os.walk(winget_root):
            if 'ffmpeg.exe' in files:
                ffmpeg_path = os.path.join(root, 'ffmpeg.exe')
                break
    if ffmpeg_path is None:
        return None

    with tempfile.TemporaryDirectory() as tmpdir:
        input_name = os.path.basename(source_name or 'audio_input')
        input_path = os.path.join(tmpdir, input_name)
        output_path = os.path.join(tmpdir, 'normalized.wav')
        with open(input_path, 'wb') as handle:
            handle.write(raw_bytes)

        try:
            subprocess.run(
                [ffmpeg_path, '-y', '-i', input_path, '-vn', '-acodec', 'pcm_s16le', '-ar', '16000', output_path],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
        except (OSError, subprocess.CalledProcessError):
            return None

        try:
            with open(output_path, 'rb') as handle:
                return handle.read()
        except Exception:
            return None


def transcribe_audio(audio_file, language='en-IN'):
    if sr is None:
        raise SpeechToTextError('SpeechRecognition library is not installed.')

    recognizer = sr.Recognizer()
    raw_bytes = _read_audio_bytes(audio_file)
    if raw_bytes is None:
        raise SpeechToTextError('Unable to read audio data.')

    normalized_bytes = _normalize_audio_bytes(raw_bytes, getattr(audio_file, 'name', 'audio'))
    if normalized_bytes is None:
        raise SpeechToTextError('Unable to process audio file: Audio file could not be read as PCM WAV, AIFF/AIFF-C, or Native FLAC; check if file is corrupted or in another format')

    try:
        chunks = []
        with sr.AudioFile(io.BytesIO(normalized_bytes)) as source:
            while True:
                audio_data = recognizer.record(source, duration=_TRANSCRIBE_CHUNK_SECONDS)
                if len(audio_data.frame_data) == 0:
                    break
                chunks.append(audio_data)
    except Exception as exc:
        raise SpeechToTextError(f'Unable to process audio file: {exc}') from exc

    transcripts = [text for text in (_recognize_chunk(recognizer, chunk, language=language) for chunk in chunks) if text]
    if not transcripts:
        raise SpeechToTextError('Speech could not be understood.')
    return ' '.join(transcripts)


def _high_pass_filter_wav_bytes(raw_bytes, cutoff_hz=300.0, order=4):
    """Applies a zero-phase Butterworth high-pass filter to raw PCM WAV
    bytes, returning new WAV bytes with the same header fields (channels,
    sample width, frame rate) but filtered sample data. Validated separately
    against a real gain-corrected device recording (zero clipping, speech-
    band spectral energy 37% -> 70%) before being wired in here."""
    src = wave.open(io.BytesIO(raw_bytes), 'rb')
    nchannels = src.getnchannels()
    sampwidth = src.getsampwidth()
    framerate = src.getframerate()
    nframes = src.getnframes()
    frames = src.readframes(nframes)
    src.close()

    if sampwidth != 2:
        # Only 16-bit PCM has been validated; leave anything else unfiltered.
        return raw_bytes

    samples = np.frombuffer(frames, dtype=np.int16).astype(np.float64)
    nyquist = framerate / 2.0
    if cutoff_hz >= nyquist:
        return raw_bytes

    b, a = butter(order, cutoff_hz / nyquist, btype='high')
    filtered = filtfilt(b, a, samples)
    filtered_clipped = np.clip(filtered, -32768, 32767).astype(np.int16)

    out_buffer = io.BytesIO()
    dst = wave.open(out_buffer, 'wb')
    dst.setnchannels(nchannels)
    dst.setsampwidth(sampwidth)
    dst.setframerate(framerate)
    dst.writeframes(filtered_clipped.tobytes())
    dst.close()
    return out_buffer.getvalue()


def transcribe_audio_high_pass(audio_file):
    """Same as transcribe_audio(), but applies a validated 300Hz 4th-order
    Butterworth high-pass filter to the audio first. A separate entry point
    used only by ConversationTranscribeView's live-test path -- transcribe_audio()
    itself (also used by ConversationSummarizeView) is left untouched."""
    raw_bytes = _read_audio_bytes(audio_file)
    if raw_bytes is None:
        raise SpeechToTextError('Unable to read audio data.')

    try:
        filtered_bytes = _high_pass_filter_wav_bytes(raw_bytes)
    except Exception as exc:
        raise SpeechToTextError(f'Unable to filter audio: {exc}') from exc

    return transcribe_audio(io.BytesIO(filtered_bytes))


def summarize_transcript(transcript, api_url, model_name, api_key=None, timeout_seconds=60, target_language='English'):
    target_language_label = (target_language or 'English').strip() or 'English'
    prompt = (
        f'Please provide a concise 2-3 sentence summary of the following conversation transcript in {target_language_label}. '
        'Keep the output only in that language and do not include English explanation.\n\n'
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

    # Ollama's /api/generate streams NDJSON by default (one JSON object per
    # token) unless stream is explicitly disabled -- confirmed directly
    # against a local Ollama instance: without stream=False, response.json()
    # fails to parse the multi-line body as a single document.
    # temperature/max_tokens aren't top-level fields on this endpoint either
    # (silently ignored there); Ollama takes them under "options" as
    # temperature/num_predict.
    payload = {
        'model': model_name,
        'prompt': prompt,
        'stream': False,
        'options': {
            'temperature': 0.2,
            'num_predict': 200,
        },
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

    # Ollama's actual /api/generate response shape is a flat {"response":
    # "...", "done": true, ...} -- not the OpenAI Responses API's nested
    # results[].output[].text shape this used to look for, which no real
    # Ollama response would ever have.
    text = body.get('response')
    if not text or not isinstance(text, str):
        raise SummarizationError('Ollama response did not contain text output.')

    return text.strip()


def process_saved_conversation(conversation_id, transcriber=None, summarizer=None, target_language='English'):
    """Transcribe and summarize a saved audio conversation in the background.

    This keeps the worker API compatible with the older code path that was still
    invoking it from the view layer after the row had been created.
    """
    from .models import ConversationHistory

    transcriber = transcriber or transcribe_audio
    summarizer = summarizer or summarize_transcript

    try:
        conversation = ConversationHistory.objects.select_related('patient', 'known_person').get(pk=conversation_id)
    except ConversationHistory.DoesNotExist:
        logger.warning('Conversation processing skipped for missing record %s', conversation_id)
        return

    audio = conversation.audio_file
    if audio is None or not getattr(audio, 'name', None):
        conversation.error_message = 'No audio file attached to this conversation.'
        conversation.save(update_fields=['error_message'])
        return

    transcript = ''
    try:
        transcript = transcriber(audio, language=_language_to_code(target_language))
        conversation.transcript = transcript
        conversation.summary = ''
        conversation.error_message = None
        conversation.save(update_fields=['transcript', 'summary', 'error_message'])
    except SpeechToTextError as exc:
        conversation.transcript = ''
        conversation.summary = ''
        conversation.error_message = str(exc)
        conversation.save(update_fields=['transcript', 'summary', 'error_message'])
        return

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
        summary = summarizer(transcript, api_url, model_name, api_key=api_key, target_language=target_language)
        conversation.summary = summary
        conversation.error_message = None
    except SummarizationError as exc:
        conversation.summary = ''
        conversation.error_message = str(exc)

    conversation.save(update_fields=['summary', 'error_message'])


def _language_to_code(language_name):
    mapping = {
        'English': 'en-IN',
        'Kannada': 'kn-IN',
        'Telugu': 'te-IN',
        'Tamil': 'ta-IN',
        'Hindi': 'hi-IN',
    }
    return mapping.get((language_name or 'English').strip(), 'en-IN')


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
