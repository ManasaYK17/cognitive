from django.urls import path
from .views import CaregiverPatientView, PatientDashboardSummaryView, PatientDeviceListCreateView, PatientFaceImageView

urlpatterns = [
    path('', CaregiverPatientView.as_view(), name='caregiver-patient'),
    path('<int:pk>/dashboard-summary/', PatientDashboardSummaryView.as_view(), name='patient-dashboard-summary'),
    path('<int:pk>/face-images/', PatientFaceImageView.as_view(), name='patient-face-images'),
    path('devices/', PatientDeviceListCreateView.as_view(), name='patient-devices'),
]
