from rest_framework.permissions import BasePermission


class IsCaregiverOwner(BasePermission):
    def has_object_permission(self, request, view, obj):
        return obj.caregiver_id == request.user.id
