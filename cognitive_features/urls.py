from django.urls import path
from .views import GameResultListCreateView, ReminderListCreateView, ReminderStatusView

urlpatterns = [
    path('games/', GameResultListCreateView.as_view(), name='game-results'),
    path('reminders/', ReminderListCreateView.as_view(), name='reminders'),
    path('reminders/<int:pk>/status/', ReminderStatusView.as_view(), name='reminder-status'),
]
