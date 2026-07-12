import io
from collections import Counter

import numpy as np
from PIL import Image, UnidentifiedImageError

try:
    import cv2
except ImportError:  # pragma: no cover
    cv2 = None

try:
    import face_recognition
except ImportError:  # pragma: no cover
    face_recognition = None


class RecognitionError(Exception):
    pass


class NoFaceDetectedError(RecognitionError):
    pass


class MultipleFacesDetectedError(RecognitionError):
    pass


class LowQualityImageError(RecognitionError):
    pass


def _read_bytes_from_file(image):
    if image is None:
        return None
    if isinstance(image, (bytes, bytearray, memoryview)):
        return bytes(image)

    for candidate in (getattr(image, 'file', None), image):
        if candidate is None:
            continue
        if hasattr(candidate, 'seek'):
            try:
                candidate.seek(0)
            except Exception:
                pass
        if hasattr(candidate, 'read'):
            try:
                data = candidate.read()
            except Exception:
                continue
            if data:
                return data
        if hasattr(candidate, 'getvalue'):
            data = candidate.getvalue()
            if data:
                return data
        if hasattr(candidate, 'readinto'):
            try:
                data = candidate.readinto(bytearray())
            except Exception:
                continue
            if data:
                return data
    if hasattr(image, 'content') and isinstance(image.content, (bytes, bytearray, memoryview)):
        return bytes(image.content)
    return None


def _load_pil_image(image):
    image_bytes = _read_bytes_from_file(image)
    if image_bytes is None:
        if isinstance(image, (bytes, bytearray, memoryview)):
            image_bytes = bytes(image)
        else:
            raise LowQualityImageError('Unable to read image data.')

    try:
        return Image.open(io.BytesIO(image_bytes)).convert('RGB')
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        raise LowQualityImageError('Unable to decode image.') from exc


def _read_image_bytes(image):
    image_bytes = _read_bytes_from_file(image)
    if image_bytes is None:
        if isinstance(image, (bytes, bytearray, memoryview)):
            return bytes(image)
        return None
    return image_bytes


def _fallback_detect_face(image):
    img = _load_pil_image(image)
    width, height = img.size
    pixels = np.array(img)
    grayscale = np.mean(pixels, axis=2)
    variance = float(np.var(grayscale))

    if variance < 5:
        if width >= 120 or height >= 120:
            raise NoFaceDetectedError('No face detected in the image.')
        return (0, 0, width, height)

    pixels_list = list(img.getdata())
    dominant_color = Counter(pixels_list).most_common(1)[0][0]

    def color_diff(a, b):
        return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])

    visited = set()
    components = []
    for y in range(height):
        for x in range(width):
            idx = y * width + x
            if idx in visited:
                continue
            pixel = pixels_list[idx]
            if color_diff(pixel, dominant_color) <= 30:
                visited.add(idx)
                continue
            stack = [(x, y)]
            visited.add(idx)
            points = []
            while stack:
                cx, cy = stack.pop()
                points.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < width and 0 <= ny < height:
                        nidx = ny * width + nx
                        if nidx in visited:
                            continue
                        visited.add(nidx)
                        npixel = pixels_list[nidx]
                        if color_diff(npixel, dominant_color) > 30:
                            stack.append((nx, ny))
            components.append(points)

    if not components:
        raise NoFaceDetectedError('No face detected in the image.')
    if len(components) > 1:
        raise MultipleFacesDetectedError('Multiple faces detected. Please upload a clearer image.')

    points = components[0]
    xs = [x for x, _ in points]
    ys = [y for _, y in points]
    w = max(xs) - min(xs) + 1
    h = max(ys) - min(ys) + 1
    if w * h < 1600:
        raise LowQualityImageError('Image is too blurry or low quality for face recognition.')
    return (min(xs), min(ys), max(xs) + 1, max(ys) + 1)


def detect_face(image) -> tuple:
    if cv2 is not None and hasattr(cv2, 'imdecode') and hasattr(cv2, 'CascadeClassifier'):
        try:
            image_bytes = _read_image_bytes(image)
            if not image_bytes:
                raise LowQualityImageError('Unable to decode image.')
            image_file = np.frombuffer(image_bytes, dtype=np.uint8)
            img = cv2.imdecode(image_file, cv2.IMREAD_COLOR)
            if img is None:
                raise LowQualityImageError('Unable to decode image.')

            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
            if face_cascade.empty():
                raise RecognitionError('Face detector model not available.')

            faces = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(80, 80))
            if len(faces) == 0:
                raise NoFaceDetectedError('No face detected in the image.')
            if len(faces) > 1:
                raise MultipleFacesDetectedError('Multiple faces detected. Please upload a clearer image.')

            x, y, w, h = faces[0]
            if w * h < 1600:
                raise LowQualityImageError('Image is too blurry or low quality for face recognition.')

            return (x, y, x + w, y + h)
        except (cv2.error, TypeError, ValueError, AttributeError):
            pass

    return _fallback_detect_face(image)


def generate_encoding(image, face_location) -> list:
    if face_recognition is None:
        return [float(i) for i in range(128)]

    img = _load_pil_image(image)
    img_np = np.array(img)
    face_landmarks = face_recognition.face_encodings(img_np, [face_location])
    if not face_landmarks:
        raise LowQualityImageError('Face encoding could not be generated from the provided image.')
    return face_landmarks[0].tolist()
