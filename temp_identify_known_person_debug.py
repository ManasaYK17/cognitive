import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'cognitive_assist.settings')
import django
django.setup()

from django.core.signing import dumps
from django.test.client import RequestFactory
from accounts.models import Caregiver
from patients.models import Patient
from known_people.models import KnownPerson
from recognition.views import IdentifyKnownPersonView
from PIL import Image, ImageDraw
import io

# build test data
caregiver = Caregiver.objects.create_user(email='debug@example.com', first_name='Debug', password='DebugPass123')
patient = Patient.objects.create(caregiver=caregiver, name='Rina', age=60, medical_notes='Needs recognition')
KnownPerson.objects.create(patient=patient, name='Mina', relationship='Daughter')

session_token = dumps({'patient_id': patient.id, 'device_id': 'device-123'})

# helper images

def make_textured_image(size=(120, 120)):
    image = Image.new('RGB', size, (255, 255, 255))
    draw = ImageDraw.Draw(image)
    for x in range(0, size[0], 10):
        draw.line((x, 0, x + 20, size[1]), fill=(30, 60, 120))
    for y in range(0, size[1], 10):
        draw.line((0, y, size[0], y + 20), fill=(200, 80, 40))
    buf = io.BytesIO()
    image.save(buf, format='JPEG')
    buf.seek(0)
    return buf

rf = RequestFactory()
body = {'source': 'phone_camera'}
image_buf = make_textured_image()
request = rf.post('/recognition/identify-known-person/', body, format='multipart', HTTP_AUTHORIZATION=f'Bearer {session_token}')
request.FILES['image'] = image_buf

response = IdentifyKnownPersonView.as_view()(request)
print('status', response.status_code)
print('body', response.content.decode())
