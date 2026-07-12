from django.db.models.signals import post_save
from django.dispatch import receiver
from patients.models import FaceImage
from .models import FaceEncoding
from .services import detect_face, generate_encoding, NoFaceDetectedError, MultipleFacesDetectedError, LowQualityImageError
from PIL import UnidentifiedImageError


@receiver(post_save, sender=FaceImage)
def create_face_encoding(sender, instance, created, **kwargs):
    if not created:
        return
    try:
        face_location = detect_face(instance.image)
        encoding = generate_encoding(instance.image, face_location)
    except Exception:
        return
    FaceEncoding.objects.create(
        subject_type=instance.subject_type,
        content_type=instance.content_type,
        object_id=instance.object_id,
        face_image=instance,
        encoding=encoding,
    )
