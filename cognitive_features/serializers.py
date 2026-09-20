from rest_framework import serializers
from .models import GameResult, Reminder


class GameResultSerializer(serializers.ModelSerializer):
    accuracy = serializers.FloatField(read_only=True)
    date = serializers.DateField(source='played_at', read_only=True)
    time = serializers.TimeField(source='played_at', read_only=True)

    class Meta:
        model = GameResult
        fields = ['id', 'patient', 'game_name', 'score', 'correct_answers', 'total_questions', 'accuracy', 'played_at', 'date', 'time']
        read_only_fields = fields


class GameResultCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = GameResult
        fields = ['game_name', 'score', 'correct_answers', 'total_questions']

    def validate(self, attrs):
        if not attrs['game_name'].strip() or attrs['total_questions'] <= 0:
            raise serializers.ValidationError('A game name and at least one question are required.')
        if attrs['correct_answers'] > attrs['total_questions'] or attrs['score'] > 100:
            raise serializers.ValidationError('Game score values are invalid.')
        return attrs


class ReminderSerializer(serializers.ModelSerializer):
    type = serializers.CharField(source='reminder_type', read_only=True)
    date = serializers.SerializerMethodField()
    time = serializers.SerializerMethodField()

    class Meta:
        model = Reminder
        fields = ['id', 'patient', 'caregiver', 'type', 'reminder_type', 'medicine_name', 'message', 'scheduled_for', 'date', 'time', 'status', 'triggered_at', 'completed_at', 'missed_at', 'created_at']
        read_only_fields = ['id', 'patient', 'caregiver', 'type', 'date', 'time', 'status', 'triggered_at', 'completed_at', 'missed_at', 'created_at']

    def get_date(self, obj):
        return obj.scheduled_for.date()

    def get_time(self, obj):
        return obj.scheduled_for.time()

    def validate(self, attrs):
        reminder_type = attrs.get('reminder_type', self.instance.reminder_type if self.instance else None)
        medicine_name = attrs.get('medicine_name', '').strip()
        message = attrs.get('message', '').strip()
        if reminder_type == Reminder.MEDICINE and not medicine_name:
            raise serializers.ValidationError({'medicine_name': 'Medicine name is required.'})
        if reminder_type in (Reminder.FOOD, Reminder.OTHER) and not message:
            raise serializers.ValidationError({'message': 'A reminder message is required.'})
        return attrs
