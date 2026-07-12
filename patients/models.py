from django.db import models
from django.conf import settings
from django.contrib.contenttypes.fields import GenericForeignKey
from django.contrib.contenttypes.models import ContentType


class Patient(models.Model):
    caregiver = models.OneToOneField(settings.AUTH_USER_MODEL, related_name='patient', on_delete=models.CASCADE)
    name = models.CharField(max_length=255)
    date_of_birth = models.DateField(null=True, blank=True)
    age = models.PositiveIntegerField(null=True, blank=True)
    caregiver_photo = models.ImageField(upload_to='patient_photos/', blank=True, null=True)
    medical_notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def clean(self):
        from django.core.exceptions import ValidationError
        if self.date_of_birth is None and self.age is None:
            raise ValidationError('Provide either date of birth or age.')

    def __str__(self):
        return self.name


class FaceImage(models.Model):
    subject_type = models.CharField(max_length=20, choices=[('patient', 'Patient'), ('known_person', 'Known Person')])
    patient_subject = models.ForeignKey(Patient, null=True, blank=True, related_name='face_images', on_delete=models.CASCADE)
    content_type = models.ForeignKey(ContentType, on_delete=models.CASCADE, null=True, blank=True)
    object_id = models.PositiveIntegerField(null=True, blank=True)
    subject = GenericForeignKey('content_type', 'object_id')
    image = models.ImageField(upload_to='face_images/')
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f'{self.subject_type} face image'
