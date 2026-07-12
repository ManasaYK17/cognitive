from django.urls import path
from .views import CaregiverPatientView, PatientFaceImageView

urlpatterns = [
    path('', CaregiverPatientView.as_view(), name='caregiver-patient'),
    path('<int:pk>/face-images/', PatientFaceImageView.as_view(), name='patient-face-images'),
]
