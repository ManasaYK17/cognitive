from django.db import migrations


def clear_face_encodings(apps, schema_editor):
    # Swapped the primary face encoder from dlib (128-d) to InsightFace's
    # ArcFace model (512-d, and on a different similarity scale -- see
    # compute_similarity's docstring in recognition/services.py). Existing
    # encodings are the wrong length for the new comparisons and would never
    # match anything; they regenerate lazily on the next identify/register
    # call, so just drop them here.
    FaceEncoding = apps.get_model('recognition', 'FaceEncoding')
    FaceEncoding.objects.all().delete()


class Migration(migrations.Migration):

    dependencies = [
        ('recognition', '0002_clear_stale_face_encodings'),
    ]

    operations = [
        migrations.RunPython(clear_face_encodings, migrations.RunPython.noop),
    ]
