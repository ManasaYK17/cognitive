from PIL import Image, ImageDraw
import numpy as np

def make_image(size=(120, 120), color=(255, 0, 0), with_face=True):
    image = Image.new('RGB', size, color)
    if with_face:
        draw = ImageDraw.Draw(image)
        draw.rectangle((20, 20, 100, 100), fill=(0, 0, 255))
    return image


def make_textured_image(size=(120, 120)):
    image = Image.new('RGB', size, (255, 255, 255))
    draw = ImageDraw.Draw(image)
    for x in range(0, size[0], 10):
        draw.line((x, 0, x + 20, size[1]), fill=(30, 60, 120))
    for y in range(0, size[1], 10):
        draw.line((0, y, size[0], y + 20), fill=(200, 80, 40))
    return image

for name, img in [('face', make_image()), ('blank', make_image(with_face=False)), ('textured', make_textured_image())]:
    arr = np.array(img.convert('RGB'))
    grayscale = np.mean(arr, axis=2)
    var = float(np.var(grayscale))
    mean = float(np.mean(grayscale))
    unique = np.unique(grayscale)
    print('===', name, '===')
    print('var', var)
    print('mean', mean)
    print('min', float(grayscale.min()), 'max', float(grayscale.max()))
    print('unique count', len(unique))
    print('unique sample', unique[:20])
    print()
