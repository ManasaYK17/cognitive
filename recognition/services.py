import io
from collections import Counter
from pathlib import Path

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

try:
    from insightface.app import FaceAnalysis
except ImportError:  # pragma: no cover
    FaceAnalysis = None


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
                if hasattr(candidate, 'seek'):
                    try:
                        candidate.seek(0)
                    except Exception:
                        pass
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
    if isinstance(image, Image.Image):
        return image.convert('RGB')

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


def _image_variance(image) -> float:
    img = _load_pil_image(image)
    pixels = np.array(img)
    if pixels.size == 0:
        return 0.0
    grayscale = np.mean(pixels, axis=2)
    return float(np.var(grayscale))


def _fallback_detect_face(image):
    img = _load_pil_image(image)
    width, height = img.size
    variance = _image_variance(image)

    if variance < 2.0:
        raise NoFaceDetectedError('No face detected in the image.')

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
            if color_diff(pixel, dominant_color) <= 60:
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
                        if color_diff(npixel, dominant_color) > 60:
                            stack.append((nx, ny))
            components.append(points)

    if not components:
        raise NoFaceDetectedError('No face detected in the image.')

    components.sort(key=len, reverse=True)
    largest = components[0]
    largest_size = len(largest)
    if len(components) > 1:
        second_size = len(components[1])
        if second_size > max(80, largest_size // 3) and largest_size > 400:
            raise MultipleFacesDetectedError('Multiple faces detected. Please upload a clearer image.')

    points = largest
    xs = [x for x, _ in points]
    ys = [y for _, y in points]
    w = max(xs) - min(xs) + 1
    h = max(ys) - min(ys) + 1
    if w * h < 1600:
        raise LowQualityImageError('Image is too blurry or low quality for face recognition.')
    return (min(xs), min(ys), max(xs) + 1, max(ys) + 1)


_insightface_app = None
_insightface_load_attempted = False


def _get_insightface_app():
    """Lazily loads InsightFace's buffalo_l pack (SCRFD detector + ArcFace
    recognition model, ~326MB, cached under ~/.insightface/models after
    first download). This is the primary detector+encoder now -- benchmarked
    directly against dlib's face_recognition on real captured photos from
    this app and gave dramatically better same-person/different-person
    separation (dlib clustered every candidate at ~0.90-0.93 regardless of
    identity; InsightFace separated same-person ~0.88-0.96 from
    different-person ~0.18-0.24 on the same photos)."""
    global _insightface_app, _insightface_load_attempted
    if _insightface_load_attempted:
        return _insightface_app
    _insightface_load_attempted = True
    if FaceAnalysis is None:
        return None
    try:
        app = FaceAnalysis(name='buffalo_l', providers=['CPUExecutionProvider'])
        app.prepare(ctx_id=0, det_size=(640, 640))
        _insightface_app = app
    except Exception:
        _insightface_app = None
    return _insightface_app


def _insightface_get_faces(img_bgr):
    app = _get_insightface_app()
    if app is None:
        return []
    try:
        return app.get(img_bgr)
    except Exception:
        return []


_YUNET_MODEL_PATH = Path(__file__).resolve().parent / 'detection_models' / 'face_detection_yunet_2023mar.onnx'
_yunet_detector = None
_yunet_load_attempted = False


def _get_yunet_detector():
    """Lazily loads OpenCV's YuNet DNN face detector. Much more robust than
    the Haar cascade below to blur, tilt, and poor lighting -- important for
    specs/phone captures, which the Haar cascade regularly failed on (it
    would fall through to a crude whole-frame fallback instead of a tight
    face box)."""
    global _yunet_detector, _yunet_load_attempted
    if _yunet_load_attempted:
        return _yunet_detector
    _yunet_load_attempted = True
    if cv2 is None or not hasattr(cv2, 'FaceDetectorYN_create'):
        return None
    if not _YUNET_MODEL_PATH.exists():
        return None
    try:
        _yunet_detector = cv2.FaceDetectorYN_create(
            str(_YUNET_MODEL_PATH), '', (320, 320), score_threshold=0.7, nms_threshold=0.3, top_k=5000,
        )
    except Exception:
        _yunet_detector = None
    return _yunet_detector


def _yunet_detect(img) -> list:
    detector = _get_yunet_detector()
    if detector is None:
        return []
    h, w = img.shape[:2]
    if h <= 0 or w <= 0:
        return []
    detector.setInputSize((w, h))
    try:
        _, faces = detector.detect(img)
    except Exception:
        return []
    if faces is None:
        return []

    boxes = []
    for row in faces:
        x, y, box_w, box_h = row[:4]
        x1 = max(0, int(round(x)))
        y1 = max(0, int(round(y)))
        x2 = min(w, int(round(x + box_w)))
        y2 = min(h, int(round(y + box_h)))
        if x2 > x1 and y2 > y1:
            boxes.append((x1, y1, x2, y2))
    return boxes


def detect_face(image) -> tuple:
    if _image_variance(image) < 2.0:
        raise NoFaceDetectedError('No face detected in the image.')

    img = None
    if cv2 is not None:
        try:
            image_bytes = _read_image_bytes(image)
            if image_bytes:
                image_file = np.frombuffer(image_bytes, dtype=np.uint8)
                img = cv2.imdecode(image_file, cv2.IMREAD_COLOR)
        except Exception:
            img = None

    if img is not None:
        insightface_faces = _insightface_get_faces(img)
        if len(insightface_faces) > 1:
            raise MultipleFacesDetectedError('Multiple faces detected. Please upload a clearer image.')
        if len(insightface_faces) == 1:
            h, w = img.shape[:2]
            x1, y1, x2, y2 = insightface_faces[0].bbox
            x1, y1 = max(0, int(round(x1))), max(0, int(round(y1)))
            x2, y2 = min(w, int(round(x2))), min(h, int(round(y2)))
            if (x2 - x1) * (y2 - y1) < 1600:
                raise LowQualityImageError('Image is too blurry or low quality for face recognition.')
            return (x1, y1, x2, y2)

        # InsightFace found nothing (e.g. not installed) -- try YuNet.
        boxes = _yunet_detect(img)
        if len(boxes) > 1:
            raise MultipleFacesDetectedError('Multiple faces detected. Please upload a clearer image.')
        if len(boxes) == 1:
            x1, y1, x2, y2 = boxes[0]
            if (x2 - x1) * (y2 - y1) < 1600:
                raise LowQualityImageError('Image is too blurry or low quality for face recognition.')
            return boxes[0]

        # Neither found anything -- try the older Haar
        # cascade before giving up on a real detector entirely.
        if hasattr(cv2, 'CascadeClassifier'):
            try:
                gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
                face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
                if not face_cascade.empty():
                    faces = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(80, 80))
                    if len(faces) > 1:
                        raise MultipleFacesDetectedError('Multiple faces detected. Please upload a clearer image.')
                    if len(faces) == 1:
                        x, y, w, h = faces[0]
                        if w * h < 1600:
                            raise LowQualityImageError('Image is too blurry or low quality for face recognition.')
                        return (x, y, x + w, y + h)
            except (MultipleFacesDetectedError, LowQualityImageError):
                raise
            except (cv2.error, TypeError, ValueError, AttributeError):
                pass

    # Last resort: crude flood-fill blob detector for when no cv2 detector
    # is available at all.
    return _fallback_detect_face(image)


_MIN_FACE_BOX_AREA = 24 * 24
_LBP_FACE_SIZE = 96
_LBP_GRID = (8, 8)
_LBP_BINS = 59  # 58 uniform patterns (P=8) + 1 bin for all non-uniform codes


def _build_uniform_lbp_table() -> np.ndarray:
    """Maps each of the 256 possible 8-bit LBP codes to its uniform-pattern
    bin (0-57), or to bin 58 if the code has more than 2 bitwise transitions
    around the circle (i.e. isn't a 'uniform' pattern)."""
    table = np.zeros(256, dtype=np.uint8)
    next_label = 0
    for code in range(256):
        bits = [(code >> i) & 1 for i in range(8)]
        transitions = sum(bits[i] != bits[(i + 1) % 8] for i in range(8))
        if transitions <= 2:
            table[code] = next_label
            next_label += 1
        else:
            table[code] = _LBP_BINS - 1
    return table


_UNIFORM_LBP_TABLE = _build_uniform_lbp_table()


def _crop_to_face(img: Image.Image, face_location, padding_ratio: float = 0.2) -> Image.Image:
    if not face_location or len(face_location) != 4:
        return img
    width, height = img.size
    left, top, right, bottom = face_location
    box_w = right - left
    box_h = bottom - top
    if box_w * box_h < _MIN_FACE_BOX_AREA:
        # Degenerate/unknown box (e.g. the (0, 0, 1, 1) sentinel used when
        # detection failed) -- cropping to it would discard the whole face,
        # so fall back to the full frame instead.
        return img
    pad_x = int(box_w * padding_ratio)
    pad_y = int(box_h * padding_ratio)
    left = max(0, left - pad_x)
    top = max(0, top - pad_y)
    right = min(width, right + pad_x)
    bottom = min(height, bottom + pad_y)
    if right <= left or bottom <= top:
        return img
    return img.crop((left, top, right, bottom))


def _to_css_location(face_location, image_size) -> tuple:
    """face_recognition.face_encodings expects known_face_locations in
    (top, right, bottom, left) 'css' order -- detect_face returns
    (left, top, right, bottom), so this must be reordered before calling it."""
    width, height = image_size
    left, top, right, bottom = face_location
    left = max(0, min(int(left), width))
    right = max(0, min(int(right), width))
    top = max(0, min(int(top), height))
    bottom = max(0, min(int(bottom), height))
    return (top, right, bottom, left)


def _lbp_codes(gray: np.ndarray) -> np.ndarray:
    h, w = gray.shape
    center = gray[1:h - 1, 1:w - 1]
    neighbors = (
        gray[0:h - 2, 0:w - 2], gray[0:h - 2, 1:w - 1], gray[0:h - 2, 2:w],
        gray[1:h - 1, 2:w],
        gray[2:h, 2:w], gray[2:h, 1:w - 1], gray[2:h, 0:w - 2],
        gray[1:h - 1, 0:w - 2],
    )
    code = np.zeros(center.shape, dtype=np.uint8)
    for bit, neighbor in enumerate(neighbors):
        code |= (neighbor >= center).astype(np.uint8) << bit
    return code


def _grid_histogram(uniform_codes: np.ndarray, grid=_LBP_GRID, bins: int = _LBP_BINS) -> np.ndarray:
    h, w = uniform_codes.shape
    row_groups = [g for g in np.array_split(np.arange(h), grid[0]) if g.size]
    col_groups = [g for g in np.array_split(np.arange(w), grid[1]) if g.size]
    cells = []
    for rows in row_groups:
        for cols in col_groups:
            cell = uniform_codes[rows[0]:rows[-1] + 1, cols[0]:cols[-1] + 1]
            hist, _ = np.histogram(cell, bins=bins, range=(0, bins))
            total = hist.sum()
            cells.append(hist / total if total > 0 else hist.astype(np.float64))
    return np.concatenate(cells) if cells else np.zeros(bins, dtype=np.float64)


def _face_descriptor(face_img: Image.Image) -> list:
    """Local Binary Pattern histogram descriptor computed over a face crop.
    Per-cell histograms (rather than raw pixel values) make this robust to
    lighting/background and don't require dlib, which needs a C++ toolchain
    that isn't available in every deployment environment."""
    gray = face_img.convert('L').resize((_LBP_FACE_SIZE, _LBP_FACE_SIZE), Image.Resampling.LANCZOS)
    arr = np.array(gray, dtype=np.uint8)
    if cv2 is not None and hasattr(cv2, 'equalizeHist'):
        arr = cv2.equalizeHist(arr)
    uniform_codes = _UNIFORM_LBP_TABLE[_lbp_codes(arr)]
    return _grid_histogram(uniform_codes).astype(np.float64).tolist()


def _fallback_encoding(face_img) -> list:
    return _face_descriptor(_load_pil_image(face_img))


def compute_similarity(a, b) -> float:
    """Raw cosine similarity, clamped to [0, 1] (negative cosine has no
    meaningful "match" interpretation here, so it's floored at 0 rather than
    rescaled). Deliberately NOT remapped via (cosine+1)/2 -- that distorted
    InsightFace's embeddings specifically: benchmarked directly against real
    photos from this app, different people scored ~0.18-0.24 raw cosine and
    the same person ~0.88-0.96, a clean gap either side of ~0.5. Rescaling
    would have compressed the different-person cluster up to ~0.6, above the
    confidence threshold, on cosine similarity alone -- rescaling was a
    leftover from calibrating against dlib/LBP fallback encodings, which
    have different (and, on this app's actual photos, much less reliable)
    distributions. Works for any real-valued equal-length vectors regardless
    of sign, so it's safe for the dlib/LBP fallbacks too."""
    if not a or not b or len(a) != len(b):
        return 0.0
    a_arr = np.asarray(a, dtype=np.float64)
    b_arr = np.asarray(b, dtype=np.float64)
    a_norm = np.linalg.norm(a_arr)
    b_norm = np.linalg.norm(b_arr)
    if a_norm <= 0 or b_norm <= 0:
        return 0.0
    cosine = float(np.dot(a_arr, b_arr) / (a_norm * b_norm))
    return max(0.0, min(1.0, cosine))


def _enhance_low_light(img: Image.Image) -> Image.Image:
    """CLAHE (contrast-limited adaptive histogram equalization) on the L
    channel of LAB -- boosts local contrast in dark/underexposed captures
    without blowing out color, unlike a flat brightness/gamma adjustment.
    This is the actual limiting factor observed in misidentifications: a
    dark, noisy face crop doesn't carry enough clean detail for any
    face-recognition model to discriminate reliably, regardless of how
    tightly it's cropped."""
    if cv2 is None or not hasattr(cv2, 'createCLAHE'):
        return img
    try:
        arr = np.array(img)
        lab = cv2.cvtColor(arr, cv2.COLOR_RGB2LAB)
        l_channel, a_channel, b_channel = cv2.split(lab)
        clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
        l_channel = clahe.apply(l_channel)
        enhanced = cv2.cvtColor(cv2.merge((l_channel, a_channel, b_channel)), cv2.COLOR_LAB2RGB)
        return Image.fromarray(enhanced)
    except Exception:
        return img


def generate_encoding(image, face_location) -> list:
    img = _enhance_low_light(_load_pil_image(image))
    face_img = _crop_to_face(img, face_location)

    if FaceAnalysis is not None:
        try:
            img_bgr = cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)
            faces = _insightface_get_faces(img_bgr)
            if faces:
                # Multiple detections can happen here even though detect_face()
                # already rejected multi-face frames earlier in the request --
                # this is a fresh, independent detection pass. Picking the
                # largest face is the same "main subject" heuristic detect_face()
                # effectively applies via its own single-face requirement.
                faces.sort(key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]), reverse=True)
                return faces[0].normed_embedding.tolist()
        except Exception:
            pass

    if face_recognition is not None:
        try:
            img_np = np.array(img)
            css_location = _to_css_location(face_location, img.size)
            face_landmarks = face_recognition.face_encodings(img_np, [css_location])
            if face_landmarks:
                return face_landmarks[0].tolist()
        except Exception:
            pass

    return _face_descriptor(face_img)
