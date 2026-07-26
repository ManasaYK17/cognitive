import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'cognitive_assist.settings')
import django
django.setup()

import io
from PIL import Image, ImageDraw
from django.core.files.base import ContentFile
from recognition.services import _image_variance, detect_face
from recognition.views import IdentifyKnownPersonView

size = (120, 120)
image = Image.new('RGB', size, (255, 255, 255))
draw = ImageDraw.Draw(image)
for x in range(0, size[0], 10):
    draw.line((x, 0, x + 20, size[1]), fill=(30, 60, 120))
for y in range(0, size[1], 10):
    draw.line((0, y, size[0], y + 20), fill=(200, 80, 40))

buf = io.BytesIO()
image.save(buf, format='JPEG')
textured_bytes = buf.getvalue()
textured = ContentFile(textured_bytes, name='textured.jpg')
print('textured variance:', _image_variance(textured))
print('textured blank:', IdentifyKnownPersonView._is_blank_image(textured))
try:
    print('detect textured:', detect_face(textured))
except Exception as exc:
    print('detect textured failed:', type(exc).__name__, exc)

solid = Image.new('RGB', size, (255, 0, 0))
buf2 = io.BytesIO()
solid.save(buf2, format='JPEG')
solid_bytes = buf2.getvalue()
solid_cf = ContentFile(solid_bytes, name='solid.jpg')
print('solid variance:', _image_variance(solid_cf))
print('solid blank:', IdentifyKnownPersonView._is_blank_image(solid_cf))
try:
    print('detect solid:', detect_face(solid_cf))
except Exception as exc:
    print('detect solid failed:', type(exc).__name__, exc)

from django.test import Client
client = Client()

# create user / patient / known person with a known-person face image encoded
from django.contrib.auth import get_user_model
from accounts.models import Caregiver
from patients.models import Patient, FaceImage
from known_people.models import KnownPerson
from django.contrib.contenttypes.models import ContentType

caregiver = Caregiver.objects.create_user(email='debug@example.com', first_name='Debug', password='DebugPass123')
patient = Patient.objects.create(caregiver=caregiver, name='Rina', age=60, medical_notes='Needs recognition')
known_person = KnownPerson.objects.create(patient=patient, name='Mina', relationship='Daughter')

# make known person face image use textured image
known_face = FaceImage.objects.create(subject_type='known_person', image=textured, object_id=known_person.id, content_type=ContentType.objects.get_for_model(known_person))

# issue token
from django.core.signing import dumps
session_token = dumps({'patient_id': patient.id, 'device_id': 'device-123'})

response = client.post('/api/recognition/identify-known-person/', {'image': textured, 'source': 'phone_camera'}, HTTP_AUTHORIZATION=f'Bearer {session_token}')
print('client response status', response.status_code)
print('client response content', response.content.decode())
