from rest_framework import serializers
from .models import KnownPerson
from django.contrib.contenttypes.models import ContentType
from patients.models import FaceImage


def _latest_face_image_url(obj, request=None):
    content_type = ContentType.objects.get_for_model(obj.__class__)
    face = FaceImage.objects.filter(content_type=content_type, object_id=obj.id).order_by('-created_at').first()
    if not face:
        return None
    try:
        url = face.image.url
    except Exception:
        return None
    if request is not None:
        return request.build_absolute_uri(url)
    return url


class KnownPersonSerializer(serializers.ModelSerializer):
    face_image = serializers.SerializerMethodField()

    def get_face_image(self, obj):
        request = self.context.get('request') if hasattr(self, 'context') else None
        return _latest_face_image_url(obj, request=request)
    class Meta:
        model = KnownPerson
        fields = ['id', 'patient', 'name', 'relationship', 'occupation', 'phone_number', 'address', 'notes', 'face_image', 'created_at', 'updated_at']
        read_only_fields = ['id', 'created_at', 'updated_at']
