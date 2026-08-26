from django.conf import settings
from django.db import models
from patients.models import Patient


class GameResult(models.Model):
    patient = models.ForeignKey(Patient, related_name='game_results', on_delete=models.CASCADE)
    game_name = models.CharField(max_length=80)
    score = models.PositiveIntegerField()
    correct_answers = models.PositiveIntegerField()
    total_questions = models.PositiveIntegerField()
    played_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-played_at']

    @property
    def accuracy(self):
        return round(self.correct_answers / self.total_questions * 100, 1) if self.total_questions else 0


class Reminder(models.Model):
    MEDICINE = 'medicine'
    FOOD = 'food'
    OTHER = 'other'
    TYPES = [(MEDICINE, 'Medicine'), (FOOD, 'Food'), (OTHER, 'Other')]
    PENDING = 'pending'
    TRIGGERED = 'triggered'
    COMPLETED = 'completed'
    MISSED = 'missed'
    STATUSES = [(PENDING, 'Pending'), (TRIGGERED, 'Alarm triggered'), (COMPLETED, 'Completed'), (MISSED, 'Missed')]

    patient = models.ForeignKey(Patient, related_name='reminders', on_delete=models.CASCADE)
    caregiver = models.ForeignKey(settings.AUTH_USER_MODEL, related_name='reminders', on_delete=models.CASCADE)
    reminder_type = models.CharField(max_length=20, choices=TYPES)
    medicine_name = models.CharField(max_length=255, blank=True)
    message = models.CharField(max_length=500, blank=True)
    scheduled_for = models.DateTimeField()
    status = models.CharField(max_length=20, choices=STATUSES, default=PENDING)
    triggered_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    missed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['scheduled_for']
        constraints = [models.UniqueConstraint(fields=['patient', 'reminder_type', 'scheduled_for', 'medicine_name', 'message'], name='unique_reminder_submission')]
