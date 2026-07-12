from django.urls import path
from .views import (
    CaregiverRegisterView,
    CaregiverLoginView,
    CaregiverTokenRefreshView,
    CaregiverMeView,
    RegisterDeviceTokenView,
)

urlpatterns = [
    path('register/', CaregiverRegisterView.as_view(), name='caregiver-register'),
    path('login/', CaregiverLoginView.as_view(), name='caregiver-login'),
    path('token/refresh/', CaregiverTokenRefreshView.as_view(), name='token_refresh'),
    path('me/', CaregiverMeView.as_view(), name='caregiver-me'),
    path('register-device-token/', RegisterDeviceTokenView.as_view(), name='register-device-token'),
]
