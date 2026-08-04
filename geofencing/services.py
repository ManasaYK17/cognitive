import logging
from datetime import timedelta
from django.conf import settings
from django.utils import timezone
from .models import LocationPing
from history.models import RecognitionHistory

logger = logging.getLogger(__name__)

_firebase_app = None
_messaging = None


def _get_firebase_app():
    global _firebase_app, _messaging
    if _firebase_app is not None and _messaging is not None:
        return _firebase_app, _messaging

    try:
        from firebase_admin import credentials, initialize_app, messaging
    except ModuleNotFoundError:
        raise RuntimeError('firebase_admin is not installed; push notifications are disabled.')

    fcm_key_path = getattr(settings, 'FCM_SERVICE_ACCOUNT_JSON', None)
    if not fcm_key_path:
        raise RuntimeError('FCM_SERVICE_ACCOUNT_JSON must be configured for push notifications.')

    cred = credentials.Certificate(fcm_key_path)
    _firebase_app = initialize_app(cred)
    _messaging = messaging
    return _firebase_app, _messaging


def send_fcm_push(device_token, title=None, body=None, data=None):
    """Send an FCM push to a single device token. Reused by any flow that
    needs to notify a device (geofence breach alerts, recognition matches,
    etc.) so the send/error-handling logic lives in one place.
    Returns the FCM message id on success, or None if push is disabled,
    misconfigured, or the send failed."""
    try:
        app, messaging_client = _get_firebase_app()
    except RuntimeError as exc:
        logger.warning('FCM disabled or misconfigured: %s', exc)
        return None

    notification = None
    if title or body:
        notification = messaging_client.Notification(title=title, body=body)

    message = messaging_client.Message(
        notification=notification,
        data=data or {},
        token=device_token,
    )
    try:
        response = messaging_client.send(message, app=app)
        logger.info('Sent FCM message %s to token %s', response, device_token)
        return response
    except Exception as exc:
        logger.exception('Failed to send FCM message: %s', exc)
        return None


def check_and_alert(patient, location_ping):
    try:
        safe_zone = getattr(patient, 'safe_zone', None)
        if safe_zone is None:
            return

        previous_ping = (
            LocationPing.objects.filter(patient=patient)
            .exclude(id=location_ping.id)
            .order_by('-timestamp')
            .first()
        )
        was_inside = previous_ping and previous_ping.distance_from_center_meters is not None and previous_ping.distance_from_center_meters <= safe_zone.radius_meters
        is_outside = location_ping.distance_from_center_meters is not None and location_ping.distance_from_center_meters > safe_zone.radius_meters

        if is_outside and was_inside:
            cooldown_cutoff = timezone.now() - timedelta(minutes=10)
            last_alert = RecognitionHistory.objects.filter(
                patient=patient,
                outcome='breach_alert',
                timestamp__gte=cooldown_cutoff,
            ).order_by('-timestamp').first()
            if last_alert is not None:
                return

            caregiver = patient.caregiver
            device_token = getattr(caregiver, 'fcm_device_token', None)
            if not device_token:
                logger.warning('No FCM device token registered for caregiver %s', caregiver.email)
                return

            response = send_fcm_push(
                device_token,
                title=f'Patient {patient.name} is out of range',
                body=f'Location: {location_ping.latitude}, {location_ping.longitude}',
            )
            if response is None:
                return

            RecognitionHistory.objects.create(
                patient=patient,
                subject_type='patient',
                content_type=None,
                object_id=None,
                confidence_score=0.0,
                source='geofence',
                outcome='breach_alert',
            )
    except Exception:
        logger.exception('Error in check_and_alert')
