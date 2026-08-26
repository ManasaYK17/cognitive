import os
import django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'cognitive_assist.settings')
django.setup()

from django.test import Client
from patients.models import Patient
from django.core.signing import dumps

p = Patient.objects.first()
token = dumps({'patient_id': p.id, 'device_id': 'debug'}) if p else None
print('patient', p.id if p else None)
print('token', token)

c = Client()
with open('media/debug_captures/20260810_055512_926674.jpg', 'rb') as f:
    resp = c.post(
        '/api/conversations/summarize/',
        {'patient_id': str(p.id) if p else '1', 'known_person_id': '1', 'audio': f},
        HTTP_AUTHORIZATION=f'Bearer {token}' if token else None,
    )
    print('status', resp.status_code)
    print(resp.content.decode('utf-8', errors='replace'))
