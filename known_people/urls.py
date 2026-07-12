from django.urls import path
from .views import KnownPersonListCreateView, KnownPersonDetailView, KnownPersonFaceImageView

urlpatterns = [
    path('', KnownPersonListCreateView.as_view(), name='known-person-list-create'),
    path('<int:pk>/', KnownPersonDetailView.as_view(), name='known-person-detail'),
    path('<int:pk>/face-images/', KnownPersonFaceImageView.as_view(), name='known-person-face-images'),
]
