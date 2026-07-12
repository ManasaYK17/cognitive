from rest_framework import serializers
from .models import RecognitionHistory


class RecognitionHistorySerializer(serializers.ModelSerializer):
    subject_name = serializers.SerializerMethodField()

    class Meta:
        model = RecognitionHistory
        fields = ['id', 'patient', 'subject_type', 'subject_name', 'timestamp', 'confidence_score', 'source', 'outcome']
        read_only_fields = fields

    def get_subject_name(self, obj):
        if obj.subject is None:
            return None
        return getattr(obj.subject, 'name', None)


class HistoryFeedSerializer(serializers.Serializer):
    id = serializers.IntegerField(read_only=True)
    event_type = serializers.CharField(read_only=True)
    patient_id = serializers.IntegerField(read_only=True)
    known_person_id = serializers.IntegerField(read_only=True, allow_null=True)
    known_person_name = serializers.CharField(read_only=True, allow_null=True)
    timestamp = serializers.DateTimeField(read_only=True)
    confidence_score = serializers.FloatField(read_only=True, allow_null=True)
    source = serializers.CharField(read_only=True, allow_null=True)
    outcome = serializers.CharField(read_only=True, allow_null=True)
    summary = serializers.CharField(read_only=True, allow_null=True)
    transcript = serializers.CharField(read_only=True, allow_null=True)
    error_message = serializers.CharField(read_only=True, allow_null=True)


class PatientHistorySummarySerializer(serializers.Serializer):
    known_person_id = serializers.IntegerField(read_only=True)
    known_person_name = serializers.CharField(read_only=True)
    last_summary = serializers.CharField(read_only=True, allow_null=True)
    last_summary_at = serializers.DateTimeField(read_only=True, allow_null=True)
