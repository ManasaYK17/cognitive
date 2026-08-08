from django.core.management.base import BaseCommand, CommandError

from patients.models import Patient, PatientDevice


class Command(BaseCommand):
    help = 'Links a physical device (e.g. specs firmware, identified by its WiFi MAC address) to a patient.'

    def add_arguments(self, parser):
        parser.add_argument('device_id', help="The device's stable hardware id, e.g. its WiFi MAC address.")
        parser.add_argument('patient_id', type=int, help='The patient this device should act on behalf of.')
        parser.add_argument('--label', default='', help='Optional friendly name for the device.')

    def handle(self, *args, **options):
        device_id = options['device_id'].strip()
        try:
            patient = Patient.objects.get(id=options['patient_id'])
        except Patient.DoesNotExist:
            raise CommandError(f"No patient with id {options['patient_id']}.")

        device, created = PatientDevice.objects.update_or_create(
            device_id=device_id,
            defaults={'patient': patient, 'label': options['label']},
        )
        verb = 'Registered' if created else 'Re-pointed'
        self.stdout.write(self.style.SUCCESS(f'{verb} device {device_id!r} -> patient {patient.id} ({patient.name})'))
