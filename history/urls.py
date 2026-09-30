from django.urls import path
from .views import HistoryCaptureImageView, HistoryFeedView, PatientHistoryImageView, PatientHistoryView, PatientRecognitionView

urlpatterns = [
    path('', HistoryFeedView.as_view(), name='history-feed'),
    path('patient-view/', PatientHistoryView.as_view(), name='history-patient-view'),
    path('patient-recognition/', PatientRecognitionView.as_view(), name='patient-recognition'),
    path('patient-images/<str:image_type>/<int:pk>/', PatientHistoryImageView.as_view(), name='patient-history-image'),
    path('images/<str:event_type>/<int:pk>/', HistoryCaptureImageView.as_view(), name='history-capture-image'),
]
