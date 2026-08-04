from django.urls import path
from .views import (
    IdentifyPatientView,
    IdentifyKnownPersonView,
    IssuePatientSessionTokenView,
    RegisterPatientDeviceTokenView,
)

urlpatterns = [
    path('identify-patient/', IdentifyPatientView.as_view(), name='identify-patient'),
    path('identify-known-person/', IdentifyKnownPersonView.as_view(), name='identify-known-person'),
    path('issue-patient-session-token/', IssuePatientSessionTokenView.as_view(), name='issue-patient-session-token'),
    path('register-patient-device-token/', RegisterPatientDeviceTokenView.as_view(), name='register-patient-device-token'),
]
