from django.db import models
from django.conf import settings
from django.core.exceptions import ValidationError
from math import radians, cos, sin, asin, sqrt
from patients.models import Patient


class SafeZone(models.Model):
    patient = models.OneToOneField(Patient, related_name='safe_zone', on_delete=models.CASCADE)
    name = models.CharField(max_length=100)
    center_latitude = models.FloatField()
    center_longitude = models.FloatField()
    radius_meters = models.FloatField()

    def clean(self):
        if self.radius_meters <= 0:
            raise ValidationError('radius_meters must be positive.')

    def __str__(self):
        return f'{self.patient.name} safe zone: {self.name}'


class LocationPing(models.Model):
    patient = models.ForeignKey(Patient, related_name='location_pings', on_delete=models.CASCADE)
    latitude = models.FloatField()
    longitude = models.FloatField()
    timestamp = models.DateTimeField(auto_now_add=True)
    distance_from_center_meters = models.FloatField()

    def save(self, *args, **kwargs):
        safe_zone = getattr(self.patient, 'safe_zone', None)
        if safe_zone is None:
            self.distance_from_center_meters = None
        else:
            self.distance_from_center_meters = self._haversine_distance(
                safe_zone.center_latitude,
                safe_zone.center_longitude,
                self.latitude,
                self.longitude,
            )
        super().save(*args, **kwargs)

    @staticmethod
    def _haversine_distance(lat1, lon1, lat2, lon2):
        dlat = radians(lat2 - lat1)
        dlon = radians(lon2 - lon1)
        lat1 = radians(lat1)
        lat2 = radians(lat2)
        a = sin(dlat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(dlon / 2) ** 2
        c = 2 * asin(sqrt(a))
        earth_radius = 6371000
        return earth_radius * c

    def __str__(self):
        return f'LocationPing {self.patient.name} at {self.timestamp}'
