from django.db import models
from django.contrib.contenttypes.fields import GenericRelation
from patients.models import Patient


class KnownPerson(models.Model):
    recognition_history = GenericRelation(
        'history.RecognitionHistory',
        content_type_field='content_type',
        object_id_field='object_id',
    )
    patient = models.ForeignKey(Patient, related_name='known_people', on_delete=models.CASCADE)
    name = models.CharField(max_length=255)
    relationship = models.CharField(max_length=255, blank=True)
    occupation = models.CharField(max_length=255, blank=True)
    phone_number = models.CharField(max_length=50, blank=True)
    address = models.TextField(blank=True)
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.name
