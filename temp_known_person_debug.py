import os
import uuid
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'cognitive_assist.settings')
import django
django.setup()
from django.test import Client
from accounts.models import Caregiver
from patients.models import Patient
from known_people.models import KnownPerson
from django.core.signing import dumps
from PIL import Image, ImageDraw
import io

email = f'debug_{uuid.uuid4().hex}@example.com'
caregiver = Caregiver.objects.create_user(email=email, first_name='Debug', password='DebugPass123')
patient = Patient.objects.create(caregiver=caregiver, name='Rina', age=60, medical_notes='Needs recognition')
KnownPerson.objects.create(patient=patient, name='Mina', relationship='Daughter')

session_token = dumps({'patient_id': patient.id, 'device_id': 'device-123'})

# textured image
image = Image.new('RGB', (120, 120), (255, 255, 255))
draw = ImageDraw.Draw(image)
for x in range(0, 120, 10):
    draw.line((x, 0, x + 20, 120), fill=(30, 60, 120))
for y in range(0, 120, 10):
    draw.line((0, y, 120, y + 20), fill=(200, 80, 40))
buf = io.BytesIO()
image.save(buf, format='JPEG')
buf.seek(0)

client = Client()
response = client.post('/api/recognition/identify-known-person/', {'image': buf, 'source': 'phone_camera'}, content_type='multipart/form-data', HTTP_AUTHORIZATION=f'Bearer {session_token}')
print('status', response.status_code)
print(response.content.decode('utf-8'))
