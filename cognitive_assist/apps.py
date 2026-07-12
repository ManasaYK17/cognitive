from django.apps import AppConfig


class CognitiveAssistConfig(AppConfig):
    name = 'cognitive_assist'

    def ready(self):
        import recognition.signals  # noqa: F401
