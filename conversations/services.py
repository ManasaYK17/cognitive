import io
import logging
import wave

import numpy as np
import requests
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
