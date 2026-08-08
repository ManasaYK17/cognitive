import sys

from django.apps import AppConfig

# manage.py commands that never serve requests -- skip the InsightFace warmup
# for these so e.g. the Docker build's collectstatic step doesn't pay to load
# a 326MB model it'll never use. Anything else (runserver, or gunicorn
# importing the WSGI app directly with no matching argv[1]) gets warmed.
_SKIP_WARMUP_COMMANDS = {
    'migrate', 'makemigrations', 'collectstatic', 'test', 'shell',
    'dbshell', 'createsuperuser', 'register_device', 'check',
}


class RecognitionConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'recognition'

    def ready(self):
        import recognition.signals  # noqa: F401

        if len(sys.argv) > 1 and sys.argv[1] in _SKIP_WARMUP_COMMANDS:
            return

        # Load the model synchronously here (rather than in a background
        # thread) so the server never accepts a request before it's ready --
        # a request arriving mid-load would otherwise see the module's
        # "already attempted" flag and be told no model is available.
        from recognition.services import _get_insightface_app
        _get_insightface_app()
