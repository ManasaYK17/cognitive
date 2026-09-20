class RealtimeEvent {
  final String id;
  final String type;
  final String targetRole;
  final int? patientId;
  final int? objectId;
  final Map<String, dynamic> data;

  const RealtimeEvent({required this.id, required this.type, required this.targetRole, this.patientId, this.objectId, required this.data});

  factory RealtimeEvent.fromMap(Map<String, dynamic> map) => RealtimeEvent(
    id: map['event_id']?.toString() ?? '',
    type: map['type']?.toString() ?? '',
    targetRole: map['target_role']?.toString() ?? '',
    patientId: int.tryParse(map['patient_id']?.toString() ?? ''),
    objectId: int.tryParse(map['object_id']?.toString() ?? ''),
    data: map,
  );
}
