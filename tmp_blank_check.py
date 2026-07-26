from recognition.views import IdentifyKnownPersonView
from PIL import Image, ImageDraw
import io
import numpy as np
from django.core.files.uploadedfile import SimpleUploadedFile


def make_image(size=(120, 120), color=(255, 0, 0), with_face=True):
    image = Image.new('RGB', size, color)
    if with_face:
        draw = ImageDraw.Draw(image)
        draw.rectangle((20, 20, 100, 100), fill=(0, 0, 255))
    buffer = io.BytesIO()
    image.save(buffer, format='JPEG')
    return SimpleUploadedFile('face.jpg', buffer.getvalue(), content_type='image/jpeg')


def make_textured_image(size=(120, 120)):
    image = Image.new('RGB', size, (255, 255, 255))
    draw = ImageDraw.Draw(image)
    for x in range(0, size[0], 10):
        draw.line((x, 0, x + 20, size[1]), fill=(30, 60, 120))
    for y in range(0, size[1], 10):
        draw.line((0, y, size[0], y + 20), fill=(200, 80, 40))
    buffer = io.BytesIO()
    image.save(buffer, format='JPEG')
    return SimpleUploadedFile('textured.jpg', buffer.getvalue(), content_type='image/jpeg')

for name, img in [('solid', make_image(with_face=False)), ('textured', make_textured_image()), ('face', make_image())]:
    pil_img = Image.open(io.BytesIO(img.read())).convert('RGB')
    pixels = np.array(pil_img)
    grayscale = np.mean(pixels, axis=2)
    flat = pixels.reshape(-1, 3)
    print(name, 'var', float(np.var(grayscale)), 'channel_var', np.var(flat, axis=0), 'mean_abs', float(np.mean(np.abs(flat - flat.mean(axis=0)))))
    print(name, 'blank', IdentifyKnownPersonView._is_blank_image(img))
