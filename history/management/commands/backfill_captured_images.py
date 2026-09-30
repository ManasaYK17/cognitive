import re
from datetime import datetime, timedelta, timezone
from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand
from django.db import transaction

from conversations.models import ConversationHistory
from history.models import RecognitionHistory


_CAPTURE_NAME = re.compile(r'^patient_(\d+)_(\d{8})_(\d{6})_(\d{6})_\d+\.jpg$')
_MAX_RECOGNITION_AGE = timedelta(seconds=60)
_MAX_CAPTURE_OFFSET_SECONDS = 10
_MIN_NEAREST_CAPTURE_GAP_SECONDS = 1


class Command(BaseCommand):
    help = 'Backfill blank conversations from uniquely timestamp-matched hardware captures.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--apply',
            action='store_true',
            help='Save image links. Without this flag, only report safe matches.',
        )

    def handle(self, *args, **options):
        capture_root = Path(settings.MEDIA_ROOT) / 'debug_captures'
        captures_by_patient = self._load_captures(capture_root)
        candidates = []
        skipped_ambiguous = 0

        conversations = ConversationHistory.objects.filter(
            captured_image__isnull=True,
        ).select_related('known_person').order_by('created_at')

        for conversation in conversations.iterator():
            event = RecognitionHistory.objects.filter(
                patient_id=conversation.patient_id,
                subject_type='known_person',
                object_id=conversation.known_person_id,
                source='specs_hardware',
                outcome='matched',
                timestamp__lte=conversation.created_at,
                timestamp__gte=conversation.created_at - _MAX_RECOGNITION_AGE,
            ).order_by('-timestamp').first()
            if event is None:
                continue

            intervening_event = RecognitionHistory.objects.filter(
                patient_id=conversation.patient_id,
                timestamp__gt=event.timestamp,
                timestamp__lte=conversation.created_at,
            ).exists()
            if intervening_event:
                continue

            matching_captures = [
                (abs((event.timestamp - captured_at).total_seconds()), image_path)
                for image_path, captured_at in captures_by_patient.get(conversation.patient_id, [])
                if captured_at <= event.timestamp
                and (event.timestamp - captured_at).total_seconds() <= _MAX_CAPTURE_OFFSET_SECONDS
            ]
            matching_captures.sort(key=lambda item: item[0])
            if not matching_captures:
                continue
            if (
                len(matching_captures) > 1
                and matching_captures[1][0] - matching_captures[0][0] < _MIN_NEAREST_CAPTURE_GAP_SECONDS
            ):
                skipped_ambiguous += 1
                continue

            candidates.append((conversation, event, matching_captures[0][1]))

        mode = 'Applying' if options['apply'] else 'Dry run; no database changes.'
        self.stdout.write(f'{mode} Safe conversation-image matches: {len(candidates)}')
        self.stdout.write(f'Skipped ambiguous image matches: {skipped_ambiguous}')
        for conversation, event, image_path in candidates:
            age = (conversation.created_at - event.timestamp).total_seconds()
            self.stdout.write(
                f'conversation={conversation.id} person={conversation.known_person.name} '
                f'recognition={event.id} age_seconds={age:.1f} image={image_path}'
            )

        if not options['apply']:
            return

        with transaction.atomic():
            for conversation, event, image_path in candidates:
                conversation.captured_image.name = image_path
                conversation.save(update_fields=['captured_image'])
                if not event.captured_image:
                    event.captured_image.name = image_path
                    event.save(update_fields=['captured_image'])

    @staticmethod
    def _load_captures(capture_root):
        captures_by_patient = {}
        if not capture_root.exists():
            return captures_by_patient

        for image_path in capture_root.glob('patient_*.jpg'):
            match = _CAPTURE_NAME.match(image_path.name)
            if match is None or image_path.stat().st_size < 4000:
                continue
            patient_id = int(match.group(1))
            captured_at = datetime.strptime(
                ''.join(match.groups()[1:]),
                '%Y%m%d%H%M%S%f',
            ).replace(tzinfo=timezone.utc)
            relative_path = image_path.relative_to(settings.MEDIA_ROOT).as_posix()
            captures_by_patient.setdefault(patient_id, []).append((relative_path, captured_at))
        return captures_by_patient