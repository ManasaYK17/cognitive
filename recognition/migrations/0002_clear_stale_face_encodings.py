from django.db import migrations


def clear_face_encodings(apps, schema_editor):
    # The encoding algorithm changed (it now crops to the detected face
    # region and uses an LBP histogram instead of a whole-photo pixel
    # thumbnail), so any previously stored encodings are in the old format
    # and would either mismatch on length or compare meaninglessly against
    # new ones. They're cheap to regenerate lazily on the next
    # identify/register call, so just drop them here.
    FaceEncoding = apps.get_model('recognition', 'FaceEncoding')
    FaceEncoding.objects.all().delete()


class Migration(migrations.Migration):

    dependencies = [
        ('recognition', '0001_initial'),
    ]

    operations = [
        migrations.RunPython(clear_face_encodings, migrations.RunPython.noop),
    ]
