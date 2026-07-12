from rest_framework import serializers
from .models import KnownPerson


class KnownPersonSerializer(serializers.ModelSerializer):
    class Meta:
        model = KnownPerson
        fields = ['id', 'patient', 'name', 'relationship', 'occupation', 'phone_number', 'address', 'notes', 'created_at', 'updated_at']
        read_only_fields = ['id', 'created_at', 'updated_at']
