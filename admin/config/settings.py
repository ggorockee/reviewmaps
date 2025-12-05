"""
Django settings for ReviewMaps Admin
GORM이 관리하는 테이블에 대한 Admin CRUD 전용
"""
import os
from pathlib import Path
from dotenv import load_dotenv
import dj_database_url

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = os.getenv('SECRET_KEY', 'django-insecure-dev-key-change-in-production')
DEBUG = os.getenv('DEBUG', 'True').lower() == 'true'
ALLOWED_HOSTS = os.getenv('ALLOWED_HOSTS', 'localhost,127.0.0.1').split(',')

# Application definition
INSTALLED_APPS = [
    # Unfold must be before django.contrib.admin
    "unfold",
    "unfold.contrib.filters",
    "unfold.contrib.forms",

    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',

    # Local apps
    'users',
    'campaigns',
    'keyword_alerts',
    'app_config',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'config.urls'

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

WSGI_APPLICATION = 'config.wsgi.application'

# Database - Same PostgreSQL as Go Fiber API
DATABASES = {
    'default': dj_database_url.config(
        default=os.getenv('DATABASE_URL', 'postgres://postgres:postgres@localhost:5432/reviewmaps'),
        conn_max_age=600,
    )
}

# Custom User Model
AUTH_USER_MODEL = 'users.User'

# Password validation
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

# Internationalization
LANGUAGE_CODE = 'ko-kr'
TIME_ZONE = 'Asia/Seoul'
USE_I18N = True
USE_TZ = True

# Static files
STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

# Default primary key field type
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# Unfold Admin Configuration
UNFOLD = {
    "SITE_TITLE": "ReviewMaps Admin",
    "SITE_HEADER": "ReviewMaps",
    "SITE_URL": "/",
    "SITE_SYMBOL": "campaign",
    "SHOW_HISTORY": True,
    "SHOW_VIEW_ON_SITE": False,
    "COLORS": {
        "primary": {
            "50": "250 245 255",
            "100": "243 232 255",
            "200": "233 213 255",
            "300": "216 180 254",
            "400": "192 132 252",
            "500": "168 85 247",
            "600": "147 51 234",
            "700": "126 34 206",
            "800": "107 33 168",
            "900": "88 28 135",
            "950": "59 7 100",
        },
    },
    "SIDEBAR": {
        "show_search": True,
        "show_all_applications": True,
        "navigation": [
            {
                "title": "사용자 관리",
                "separator": True,
                "items": [
                    {
                        "title": "사용자",
                        "icon": "person",
                        "link": "/admin/users/user/",
                    },
                    {
                        "title": "SNS 계정",
                        "icon": "link",
                        "link": "/admin/users/socialaccount/",
                    },
                ],
            },
            {
                "title": "캠페인 관리",
                "separator": True,
                "items": [
                    {
                        "title": "캠페인",
                        "icon": "campaign",
                        "link": "/admin/campaigns/campaign/",
                    },
                    {
                        "title": "카테고리",
                        "icon": "category",
                        "link": "/admin/campaigns/category/",
                    },
                ],
            },
            {
                "title": "키워드 알림",
                "separator": True,
                "items": [
                    {
                        "title": "키워드",
                        "icon": "search",
                        "link": "/admin/keyword_alerts/keyword/",
                    },
                    {
                        "title": "알림 기록",
                        "icon": "notifications",
                        "link": "/admin/keyword_alerts/keywordalert/",
                    },
                    {
                        "title": "FCM 디바이스",
                        "icon": "smartphone",
                        "link": "/admin/keyword_alerts/fcmdevice/",
                    },
                ],
            },
            {
                "title": "앱 설정",
                "separator": True,
                "items": [
                    {
                        "title": "광고 설정",
                        "icon": "ads_click",
                        "link": "/admin/app_config/adconfig/",
                    },
                    {
                        "title": "앱 버전",
                        "icon": "update",
                        "link": "/admin/app_config/appversion/",
                    },
                    {
                        "title": "앱 설정",
                        "icon": "settings",
                        "link": "/admin/app_config/appsetting/",
                    },
                    {
                        "title": "Rate Limit",
                        "icon": "speed",
                        "link": "/admin/app_config/ratelimitconfig/",
                    },
                ],
            },
        ],
    },
}
