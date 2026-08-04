from django.urls import path
from .views import ConversationSummarizeView, ConversationTranscribeView

urlpatterns = [
    path('summarize/', ConversationSummarizeView.as_view(), name='conversation-summarize'),
    path('transcribe/', ConversationTranscribeView.as_view(), name='conversation-transcribe'),
]
