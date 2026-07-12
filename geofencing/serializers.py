from rest_framework import serializers
from .models import SafeZone, LocationPing


class SafeZoneSerializer(serializers.ModelSerializer):
    class Meta:
        model = SafeZone
        fields = ['patient', 'name', 'center_latitude', 'center_longitude', 'radius_meters']
        read_only_fields = ['patient']


class LocationPingSerializer(serializers.ModelSerializer):
    class Meta:
        model = LocationPing
        fields = ['id', 'patient', 'latitude', 'longitude', 'timestamp', 'distance_from_center_meters']
        read_only_fields = ['id', 'patient', 'timestamp', 'distance_from_center_meters']
