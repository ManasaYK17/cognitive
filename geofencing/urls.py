from django.urls import path
from .views import SafeZoneView, LocationPingView

urlpatterns = [
    path('<int:pk>/safe-zone/', SafeZoneView.as_view(), name='patient-safe-zone'),
    path('<int:pk>/location/', LocationPingView.as_view(), name='patient-location-ping'),
]
