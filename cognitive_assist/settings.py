import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = 'replace-this-with-a-secure-secret'
DEBUG = True
ALLOWED_HOSTS = ['*']

INSTALLED_APPS = [
    'corsheaders',
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework',
    'rest_framework_simplejwt',
    'accounts',
    'patients',
    'known_people',
    'recognition',
    'history',
    'conversations',
    'geofencing',
]

MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'cognitive_assist.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'cognitive_assist.wsgi.application'

MONGO_HOST = os.environ.get('MONGO_HOST', 'localhost')

USE_MONGODB = os.environ.get('USE_MONGODB', 'false').lower() == 'true'

if USE_MONGODB:
    DATABASES = {
        'default': {
            'ENGINE': 'djongo',
            'NAME': 'cognitive_assist_db',
            'CLIENT': {
                'host': f'mongodb://{MONGO_HOST}:27017',
            },
        }
    }
else:
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME': BASE_DIR / 'db.sqlite3',
        }
    }

AUTH_USER_MODEL = 'accounts.Caregiver'

MIGRATION_MODULES = {
    'admin': None,
    'auth': None,
    'contenttypes': None,
    'sessions': None,
    'messages': None,
    'staticfiles': None,
    # 'accounts': None,  # allow migrations for accounts during local development
}

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticated',
    ),
}

from datetime import timedelta

SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=15),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=7),
    'AUTH_HEADER_TYPES': ('Bearer',),
}

RECOGNITION_CONFIDENCE_THRESHOLD = 0.7
OLLAMA_API_URL = os.environ.get('OLLAMA_API_URL', 'http://localhost:11434/api/generate')
OLLAMA_MODEL_NAME = os.environ.get('OLLAMA_MODEL_NAME', 'qwen2.5:7b')
OPENROUTER_API_URL = os.environ.get('OPENROUTER_API_URL', 'https://openrouter.ai/api/v1/chat/completions')
OPENROUTER_API_KEY = os.environ.get('OPENROUTER_API_KEY', '')
OPENROUTER_MODEL_NAME = os.environ.get('OPENROUTER_MODEL_NAME', 'qwen-2.5-mini')
FCM_SERVICE_ACCOUNT_JSON = os.environ.get('FCM_SERVICE_ACCOUNT_JSON')

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticated',
    ),
    'DEFAULT_THROTTLE_RATES': {
        'recognition': '20/min',
    },
}

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_L10N = True
USE_TZ = True
STATIC_URL = '/static/'

# Allow local dev origins
CORS_ALLOW_ALL_ORIGINS = True

# Media files (uploaded face images)
MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'
