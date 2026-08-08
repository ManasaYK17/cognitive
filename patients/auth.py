from django.core.signing import loads

from .models import Patient, PatientDevice


def resolve_patient_from_token(token):
    """Resolves the acting Patient from a bearer token, which may be either:
    - a signed session token, dynamically issued per app session after a
      face-login (short-lived, tied to whatever the patient's id happened
      to be at issue time), or
    - a stable per-device id registered once via PatientDevice -- for
      hardware like the specs firmware that can't do a face-login handshake
      on every boot and needs something that survives a data reset.
    Returns None if the token doesn't resolve to any patient.
    """
    if not token:
        return None

    try:
        payload = loads(token)
        patient_id = payload.get('patient_id') if isinstance(payload, dict) else None
        if patient_id is not None:
            patient = Patient.objects.filter(id=patient_id).first()
            if patient is not None:
                return patient
    except Exception:
        pass

    device = PatientDevice.objects.filter(device_id=token).select_related('patient').first()
    return device.patient if device is not None else None
