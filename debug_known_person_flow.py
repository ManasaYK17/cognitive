import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'cognitive_assist.settings')
import django
django.setup()

from PIL import Image, ImageDraw
import io
from django.core.files.uploadedfile import SimpleUploadedFile
from django.contrib.contenttypes.models import ContentType
from rest_framework.test import APIClient
from accounts.models import Caregiver
import uuid
from patients.models import Patient, FaceImage
from known_people.models import KnownPerson
from recognition.models import FaceEncoding
from django.core import signing

# create data
caregiver = Caregiver.objects.create_user(email=f'debug+{uuid.uuid4().hex}@example.com', first_name='Dbg', password='pw')
patient = Patient.objects.create(caregiver=caregiver, name='P', age=50)
known_person = KnownPerson.objects.create(patient=patient, name='K', relationship='Friend')

# make textured image
size=(120,120)
image = Image.new('RGB', size, (255,255,255))
draw = ImageDraw.Draw(image)
for x in range(0, size[0], 10):
    draw.line((x,0,x+20,size[1]), fill=(30,60,120))
for y in range(0, size[1], 10):
    draw.line((0,y,size[0],y+20), fill=(200,80,40))
buf = io.BytesIO()
image.save(buf, format='JPEG')
textured = SimpleUploadedFile('textured.jpg', buf.getvalue(), content_type='image/jpeg')

# create known person's face image record
FaceImage.objects.filter(pk__isnull=False).delete()
fi = FaceImage.objects.create(subject_type='known_person', image=textured, object_id=known_person.id, content_type=ContentType.objects.get_for_model(known_person))
print('Created FaceImage id', fi.pk)
print('FaceEncoding exists?', FaceEncoding.objects.filter(face_image=fi).exists())

# issue patient session token
token = signing.dumps({'patient_id': patient.id, 'device_id': 'dev'})
print('Token:', token)

# call API
client = APIClient()
client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')

from recognition.views import IdentifyKnownPersonView
coerced = IdentifyKnownPersonView()._coerce_image(textured)
print('Coerced type:', type(coerced), 'hasattr getvalue', hasattr(coerced, 'getvalue'))
print('Is blank (pre):', IdentifyKnownPersonView._is_blank_image(coerced))

resp = client.post('/api/recognition/identify-known-person/', {'image': textured, 'source': 'phone_camera'}, format='multipart')
print('Response status:', resp.status_code)
try:
    print('Response data:', resp.data)
except Exception:
    print('Response content:', getattr(resp, 'content', resp))

# fallback face
fallback = IdentifyKnownPersonView._get_fallback_image(patient)
print('Fallback face id:', getattr(fallback, 'pk', None))
if fallback:
    enc = FaceEncoding.objects.filter(face_image=fallback).first()
    print('Fallback encoding exists:', bool(enc))
    if enc:
        print('Encoding length:', len(enc.encoding))
