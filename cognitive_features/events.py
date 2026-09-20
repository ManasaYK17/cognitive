import logging
import uuid
from django.utils import timezone
from geofencing.services import send_fcm_push

logger = logging.getLogger(__name__)

PATIENT_UPDATED = 'PATIENT_UPDATED'
LOCATION_UPDATED = 'LOCATION_UPDATED'
REMINDER_CREATED = 'REMINDER_CREATED'
REMINDER_UPDATED = 'REMINDER_UPDATED'
REMINDER_TRIGGERED = 'REMINDER_TRIGGERED'
REMINDER_COMPLETED = 'REMINDER_COMPLETED'
REMINDER_MISSED = 'REMINDER_MISSED'
GAME_SCORE_UPDATED = 'GAME_SCORE_UPDATED'
CONVERSATION_UPDATED = 'CONVERSATION_UPDATED'


def publish_patient_event(patient, event_type, recipient_role, object_id=None, data=None):
    """Send a minimal, relationship-scoped event to the correct device."""
    data = data or {}
    if recipient_role == 'patient':
        token = patient.fcm_device_token
    elif recipient_role == 'caregiver':
        token = patient.caregiver.fcm_device_token
    else:
        raise ValueError(f'Unsupported realtime recipient role: {recipient_role}')
    if not token:
        logger.info('realtime_event_skipped type=%s patient_id=%s target_role=%s reason=no_token', event_type, patient.id, recipient_role)
        return None

    event_id = str(uuid.uuid4())
    payload = {
        'event_id': event_id,
        'type': event_type,
        'target_role': recipient_role,
        'patient_id': str(patient.id),
        'object_id': str(object_id) if object_id is not None else '',
        'timestamp': timezone.now().isoformat(),
        **{key: str(value) for key, value in data.items() if value is not None},
    }
    title = 'Cognitive Assist update'
    body = event_type.replace('_', ' ').title()
    if event_type == LOCATION_UPDATED:
        title = f'{patient.name} location updated'
        body = 'Open Cognitive Assist to view the latest location.'
    elif event_type == REMINDER_CREATED:
        title = 'New reminder'
        body = data.get('message') or data.get('medicine_name') or body
    logger.info('realtime_event_sent event_id=%s type=%s patient_id=%s target_role=%s', event_id, event_type, patient.id, recipient_role)
    return send_fcm_push(token, title=title, body=body, data=payload)
