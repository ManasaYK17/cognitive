from django.db import models
from patients.models import Patient
from known_people.models import KnownPerson


class ConversationHistory(models.Model):
    patient = models.ForeignKey(Patient, related_name='conversation_history', on_delete=models.CASCADE)
    known_person = models.ForeignKey(KnownPerson, related_name='conversation_history', on_delete=models.CASCADE)
    transcript = models.TextField()
    summary = models.TextField(blank=True, null=True)
    error_message = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'Conversation summary for {self.known_person.name} and {self.patient.name} at {self.created_at}'
