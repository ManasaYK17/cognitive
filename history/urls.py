from django.urls import path
from .views import HistoryFeedView, PatientHistoryView

urlpatterns = [
    path('', HistoryFeedView.as_view(), name='history-feed'),
    path('patient-view/', PatientHistoryView.as_view(), name='history-patient-view'),
]
