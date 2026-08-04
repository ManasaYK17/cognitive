from django.urls import path
from .views import SafeZoneView, LocationPingView, PatientLatestLocationView

urlpatterns = [
    path('<int:pk>/safe-zone/', SafeZoneView.as_view(), name='patient-safe-zone'),
    path('<int:pk>/location/', LocationPingView.as_view(), name='patient-location-ping'),
    path('<int:pk>/location/latest/', PatientLatestLocationView.as_view(), name='patient-location-latest'),
]
