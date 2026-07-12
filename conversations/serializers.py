from rest_framework import serializers
from .models import ConversationHistory


class ConversationHistorySerializer(serializers.ModelSerializer):
    class Meta:
        model = ConversationHistory
        fields = ['id', 'patient', 'known_person', 'transcript', 'summary', 'error_message', 'created_at']
        read_only_fields = ['id', 'transcript', 'summary', 'error_message', 'created_at']
