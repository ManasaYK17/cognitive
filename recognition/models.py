from django.db import models
from django.contrib.contenttypes.fields import GenericForeignKey
from django.contrib.contenttypes.models import ContentType


class FaceEncoding(models.Model):
    subject_type = models.CharField(max_length=20, choices=[('patient', 'Patient'), ('known_person', 'Known Person')])
    content_type = models.ForeignKey(ContentType, on_delete=models.CASCADE, null=True, blank=True)
    object_id = models.PositiveIntegerField(null=True, blank=True)
    subject = GenericForeignKey('content_type', 'object_id')
    face_image = models.OneToOneField('patients.FaceImage', related_name='encoding', on_delete=models.CASCADE)
    encoding = models.JSONField()
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f'{self.subject_type} encoding'
