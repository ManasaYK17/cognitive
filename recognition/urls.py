from django.urls import path
from .views import IdentifyPatientView, IdentifyKnownPersonView

urlpatterns = [
    path('identify-patient/', IdentifyPatientView.as_view(), name='identify-patient'),
    path('identify-known-person/', IdentifyKnownPersonView.as_view(), name='identify-known-person'),
]
