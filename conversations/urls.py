from django.urls import path
from .views import ConversationSummarizeView

urlpatterns = [
    path('summarize/', ConversationSummarizeView.as_view(), name='conversation-summarize'),
]
