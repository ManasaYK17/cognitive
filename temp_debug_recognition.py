import os
import io
from PIL import Image, ImageDraw
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import RequestFactory
from rest_framework.test import APIRequestFactory

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'cognitive_assist.settings')
import django
django.setup()

from recognition.services import _read_bytes_from_file, _load_pil_image, detect_face
from recognition.views import IdentifyPatientView

image = Image.new('RGB', (120, 120), (255, 0, 0))
draw = ImageDraw.Draw(image)
draw.rectangle((20, 20, 100, 100), fill=(0, 0, 255))
buffer = io.BytesIO()
image.save(buffer, format='JPEG')
img = SimpleUploadedFile('face.jpg', buffer.getvalue(), content_type='image/jpeg')
print('SimpleUploadedFile type', type(img))
print('name', img.name)
print('size', img.size)
print('ready read len', len(img.read()))
img.seek(0)
print('_read_bytes_from_file', len(_read_bytes_from_file(img)))
img.seek(0)
print('_load_pil_image size', _load_pil_image(img).size)

factory = APIRequestFactory()
request = factory.post('/api/recognition/identify-patient/', {'device_id': 'device-123', 'image': img}, format='multipart')
print('request FILES keys', request.FILES.keys())
if 'image' in request.FILES:
    file_obj = request.FILES['image']
    print('file type', type(file_obj))
    print('file name', file_obj.name)
    print('file size', file_obj.size)
    print('has read', hasattr(file_obj, 'read'), 'has seek', hasattr(file_obj, 'seek'))
    print('file tell before', file_obj.tell())
    data = file_obj.read()
    print('read len', len(data), 'tell after', file_obj.tell())
    file_obj.seek(0)
    print('_read_bytes_from_file request file len', len(_read_bytes_from_file(file_obj)))
    file_obj.seek(0)
    print('_load_pil_image request file size', _load_pil_image(file_obj).size)

view = IdentifyPatientView.as_view()
response = view(request)
print('response status', response.status_code)
print('response data', response.data)
