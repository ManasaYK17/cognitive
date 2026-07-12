from django.contrib.auth import authenticate
from rest_framework import serializers
from .models import Caregiver


class CaregiverRegistrationSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)
    password_confirm = serializers.CharField(write_only=True, min_length=8)

    class Meta:
        model = Caregiver
        fields = ['email', 'first_name', 'last_name', 'password', 'password_confirm']

    def validate(self, attrs):
        if attrs['password'] != attrs['password_confirm']:
            raise serializers.ValidationError({'password_confirm': 'Password confirmation does not match.'})
        return attrs

    def create(self, validated_data):
        validated_data.pop('password_confirm', None)
        password = validated_data.pop('password')
        return Caregiver.objects.create_user(password=password, **validated_data)


class CaregiverProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = Caregiver
        fields = ['id', 'email', 'first_name', 'last_name', 'date_joined']


class DeviceTokenRegistrationSerializer(serializers.Serializer):
    device_token = serializers.CharField(max_length=255)


class CaregiverLoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)

    def validate(self, attrs):
        email = attrs.get('email')
        password = attrs.get('password')
        caregiver = authenticate(request=self.context.get('request'), email=email, password=password)
        if not caregiver:
            raise serializers.ValidationError('Unable to log in with provided credentials.', code='authorization')
        attrs['user'] = caregiver
        return attrs
