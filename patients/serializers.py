from rest_framework import serializers
from .models import Patient, FaceImage


class PatientSerializer(serializers.ModelSerializer):
    class Meta:
        model = Patient
        fields = ['id', 'name', 'date_of_birth', 'age', 'caregiver_photo', 'medical_notes', 'created_at', 'updated_at']
        read_only_fields = ['id', 'created_at', 'updated_at']

    def validate(self, attrs):
        date_of_birth = attrs.get('date_of_birth')
        age = attrs.get('age')
        existing = getattr(self.instance, 'date_of_birth', None) if self.instance else None
        existing_age = getattr(self.instance, 'age', None) if self.instance else None

        if date_of_birth is None and age is None:
            if existing is None and existing_age is None:
                raise serializers.ValidationError({'non_field_errors': 'Provide either date of birth or age.'})
        return attrs


class FaceImageSerializer(serializers.ModelSerializer):
    class Meta:
        model = FaceImage
        fields = ['id', 'image', 'created_at']
        read_only_fields = ['id', 'created_at']
