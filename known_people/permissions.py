from rest_framework.permissions import BasePermission


class IsCaregiverForKnownPerson(BasePermission):
    def has_object_permission(self, request, view, obj):
        return obj.patient.caregiver_id == request.user.id
