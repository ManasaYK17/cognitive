from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/accounts/', include('accounts.urls')),
    path('api/patients/', include('patients.urls')),
    path('api/known-people/', include('known_people.urls')),
    path('api/recognition/', include('recognition.urls')),
    path('api/conversations/', include('conversations.urls')),
    path('api/history/', include('history.urls')),
    path('api/patients/', include('geofencing.urls')),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
