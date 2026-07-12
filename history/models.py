from django.db import models
from django.contrib.contenttypes.fields import GenericForeignKey
from django.contrib.contenttypes.models import ContentType
from patients.models import Patient
from known_people.models import KnownPerson


class RecognitionHistoryQuerySet(models.QuerySet):
    def _normalize_subject_kwargs(self, kwargs):
        if 'subject' in kwargs:
            subject = kwargs.pop('subject')
            if subject is not None:
                kwargs['content_type'] = ContentType.objects.get_for_model(subject)
                kwargs['object_id'] = subject.pk
        return kwargs

    def filter(self, *args, **kwargs):
        kwargs = self._normalize_subject_kwargs(kwargs)
        return super().filter(*args, **kwargs)

    def exclude(self, *args, **kwargs):
        kwargs = self._normalize_subject_kwargs(kwargs)
        return super().exclude(*args, **kwargs)


class RecognitionHistoryManager(models.Manager):
    def get_queryset(self):
        return RecognitionHistoryQuerySet(self.model, using=self._db)

    def filter(self, *args, **kwargs):
        return self.get_queryset().filter(*args, **kwargs)

    def exclude(self, *args, **kwargs):
        return self.get_queryset().exclude(*args, **kwargs)


class RecognitionHistory(models.Model):
    objects = RecognitionHistoryManager()
    patient = models.ForeignKey(Patient, related_name='recognition_history', on_delete=models.CASCADE)
    subject_type = models.CharField(
        max_length=20,
        choices=[('patient', 'Patient'), ('known_person', 'Known Person')],
        blank=True,
        null=True,
    )
    content_type = models.ForeignKey(ContentType, on_delete=models.CASCADE, null=True, blank=True)
    object_id = models.PositiveIntegerField(null=True, blank=True)
    subject = GenericForeignKey('content_type', 'object_id')
    timestamp = models.DateTimeField(auto_now_add=True)
    confidence_score = models.FloatField(default=0.0)
    source = models.CharField(max_length=50)
    outcome = models.CharField(
        max_length=20,
        choices=[
            ('matched', 'Matched'),
            ('not_matched', 'Not Matched'),
            ('breach_alert', 'Breach Alert'),
        ],
    )

    class Meta:
        ordering = ['-timestamp']

    def __str__(self):
        return f'{self.patient.name} - {self.outcome}'
