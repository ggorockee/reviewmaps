# SNS 로그인 및 설정 관리 API 구현 계획

**작성일**: 2025-11-19
**상태**: 계획 단계 - 사용자 확인 대기
**목표**: Kakao, Google, Apple SNS 로그인 + 광고 설정 + 키워드 관리 API 구현

---

## 📋 요구사항 분석

### 1. SNS 로그인 API (Kakao, Google, Apple)
- **목적**: 소셜 로그인을 통한 사용자 인증
- **플랫폼**: Kakao, Google, Apple
- **인증 방식**: OAuth 2.0 기반 토큰 검증
- **환경변수 관리**: .env 파일에 각 플랫폼별 시크릿 키 추가

### 2. Flutter 앱에서 시크릿 키 API 요청 설계
**사용자 질문**: "Flutter 앱에서 API를 요청해서 시크릿 키를 받아오는 것이 관리적으로 편할 것 같은데 의견은?"

**분석 및 제안**:

#### ❌ 권장하지 않는 방식 (시크릿 키를 API로 전달)
```
이유:
1. 보안 취약점: 클라이언트에 시크릿 키가 노출되면 악의적 사용 가능
2. OAuth 2.0 표준 위반: 시크릿 키는 서버에서만 관리되어야 함
3. 앱 탈취 시 모든 사용자 인증 시스템 해킹 가능
```

#### ✅ 권장 방식 (서버 사이드 검증)
```
Flutter App → Backend API → SNS Provider
1. 앱: SNS SDK로 Access Token 획득
2. 앱: Token을 백엔드 API로 전송
3. 백엔드: 시크릿 키로 Token 검증
4. 백엔드: 검증 성공 시 JWT 토큰 발급
```

**장점**:
- 시크릿 키가 서버에만 존재 (보안 강화)
- OAuth 2.0 표준 준수
- 클라이언트 코드 탈취되어도 시크릿 키는 안전

**구현 방식**:
```python
# Flutter 앱
kakao_token = await KakaoLogin.login()
response = await http.post('/api/v1/auth/kakao', {
    'access_token': kakao_token
})

# Django 백엔드
async def kakao_login(access_token: str):
    # 백엔드에서 Kakao API로 토큰 검증
    user_info = await verify_kakao_token(access_token, KAKAO_SECRET_KEY)
    # JWT 발급
    return create_jwt_token(user_info)
```

### 3. 광고 ID 관리 - 플랫폼별 불일치 문제 해결

**문제**: 플랫폼마다 광고 타입이 다름 (예: AdMob에는 전면광고가 있지만 Kakao AdFit에는 없음)

**해결 방안**: **유연한 JSON 스키마 + 타입 정의**

#### 데이터베이스 스키마
```python
class AdConfiguration(models.Model):
    platform = models.CharField(max_length=50)  # 'admob', 'kakao_adfit', 'apple_search_ads'
    ad_type = models.CharField(max_length=50)   # 'banner', 'interstitial', 'rewarded', 'native'
    ad_unit_id = models.CharField(max_length=255)
    is_active = models.BooleanField(default=True)
    platform_specific_config = models.JSONField(default=dict)  # 플랫폼별 추가 설정

    class Meta:
        unique_together = ('platform', 'ad_type')
        indexes = [
            models.Index(fields=['platform', 'is_active']),
        ]
```

#### API 응답 예시 (플랫폼별 구분)
```json
{
  "ad_configurations": {
    "admob": {
      "android": {
        "banner": {
          "ad_unit_id": "ca-app-pub-xxx/aos-banner",
          "is_active": true,
          "config": {"size": "SMART_BANNER"}
        },
        "interstitial": {
          "ad_unit_id": "ca-app-pub-xxx/aos-interstitial",
          "is_active": true,
          "config": {"load_on_startup": true}
        },
        "rewarded": {
          "ad_unit_id": "ca-app-pub-xxx/aos-rewarded",
          "is_active": true,
          "config": {"reward_amount": 10}
        }
      },
      "ios": {
        "banner": {
          "ad_unit_id": "ca-app-pub-xxx/ios-banner",
          "is_active": true,
          "config": {"size": "SMART_BANNER"}
        },
        "interstitial": {
          "ad_unit_id": "ca-app-pub-xxx/ios-interstitial",
          "is_active": true,
          "config": {"load_on_startup": true}
        },
        "rewarded": {
          "ad_unit_id": "ca-app-pub-xxx/ios-rewarded",
          "is_active": true,
          "config": {"reward_amount": 10}
        }
      }
    },
    "kakao_adfit": {
      "android": {
        "banner": {
          "ad_unit_id": "DAN-xxx-aos-banner",
          "is_active": true,
          "config": {"width": 320, "height": 100}
        },
        "native": {
          "ad_unit_id": "DAN-xxx-aos-native",
          "is_active": true,
          "config": {"template": "small"}
        }
      },
      "ios": {
        "banner": {
          "ad_unit_id": "DAN-xxx-ios-banner",
          "is_active": true,
          "config": {"width": 320, "height": 100}
        },
        "native": {
          "ad_unit_id": "DAN-xxx-ios-native",
          "is_active": true,
          "config": {"template": "small"}
        }
      }
      // 주의: 전면광고는 AdMob에만 있음 (Kakao AdFit 미지원)
    }
  }
}
```

**플랫폼 구분**:
- `android` (또는 `aos`): Android 광고 ID
- `ios`: iOS 광고 ID
- 같은 광고 플랫폼(AdMob, Kakao AdFit)이라도 디바이스 OS별로 다른 광고 단위 ID 사용

**Flutter 앱 처리 방식** (플랫폼 자동 감지):
```dart
import 'dart:io' show Platform;

// 타입 안전성을 위한 모델 클래스
class AdConfig {
  final String platform;  // 'admob', 'kakao_adfit'
  final String deviceOS;  // 'android', 'ios'
  final Map<String, AdUnit> adUnits;

  // 플랫폼별로 지원하는 광고 타입만 파싱
  factory AdConfig.fromJson(Map<String, dynamic> json) {
    // 현재 디바이스 OS 자동 감지
    String currentOS = Platform.isAndroid ? 'android' : 'ios';

    // 해당 OS의 광고 설정만 파싱
    Map<String, AdUnit> units = {};
    if (json[currentOS] != null) {
      json[currentOS].forEach((adType, config) {
        units[adType] = AdUnit.fromJson(config);
      });
    }

    return AdConfig(
      platform: json['platform'],
      deviceOS: currentOS,
      adUnits: units,
    );
  }

  // 특정 광고 타입 존재 여부 확인
  bool hasAdType(String adType) => adUnits.containsKey(adType);
}

// 사용 예시
void initializeAds(Map<String, dynamic> adConfigs) {
  // AdMob 설정 로드 (현재 디바이스 OS에 맞는 광고 ID만 사용)
  final admobConfig = AdConfig.fromJson(adConfigs['admob']);

  if (admobConfig.hasAdType('interstitial')) {
    // Android면 aos-interstitial, iOS면 ios-interstitial 자동 선택
    print('전면광고 ID: ${admobConfig.adUnits['interstitial'].adUnitId}');
  }

  // Kakao AdFit (전면광고 미지원 체크)
  final kakaoBanner = AdConfig.fromJson(adConfigs['kakao_adfit']);
  if (!kakaoBanner.hasAdType('interstitial')) {
    print('Kakao AdFit은 전면광고를 지원하지 않습니다.');
  }
}
```

### 4. 키워드 활성화/비활성화 토글 API

**요구사항**: 등록된 키워드를 활성화 ↔ 비활성화 전환

**API 설계**:
```
PATCH /api/v1/keywords/{keyword_id}/toggle
```

### 5. 키워드 등록 개수 제한 설정 API

**요구사항**:
- 현재: 앱에 20개로 하드코딩
- 변경: API로 설정 가능하게

**API 설계**:
```
GET /api/v1/settings/keyword-limit
PUT /api/v1/settings/keyword-limit
```

### 6. 전체 키워드 수 동적 설정

**요구사항**:
- 활성화 키워드 수 + 비활성화 키워드 수 = 전체 키워드 수
- 기본값 20개 → 동적 설정 가능

**설계**:
```
전체_키워드_수 = max_active_keywords + max_inactive_keywords
예: 활성화 30개 + 비활성화 10개 = 총 40개
```

---

## 🏗️ 시스템 아키텍처

### 새로 생성할 Django 앱
```
users/              # SNS 로그인 및 사용자 관리
├── models.py       # CustomUser, SocialAccount
├── views.py        # SNS 로그인 API
├── serializers.py  # Request/Response 스키마
├── services.py     # OAuth 검증 로직
└── tests/          # TDD 테스트

settings/           # 앱 설정 관리
├── models.py       # AppSettings, AdConfiguration
├── views.py        # 설정 관리 API
├── serializers.py  # 설정 스키마
└── tests/          # TDD 테스트

keywords/           # 키워드 관리
├── models.py       # Keyword, UserKeyword
├── views.py        # 키워드 CRUD API
├── serializers.py  # 키워드 스키마
└── tests/          # TDD 테스트
```

---

## 📊 데이터베이스 스키마 설계

### 1. users.SocialAccount (SNS 로그인)
```python
class SocialAccount(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='social_accounts')
    provider = models.CharField(max_length=20, choices=[
        ('kakao', 'Kakao'),
        ('google', 'Google'),
        ('apple', 'Apple'),
    ])
    provider_user_id = models.CharField(max_length=255)  # SNS 제공자의 사용자 ID
    email = models.EmailField()
    name = models.CharField(max_length=100, blank=True)
    profile_image = models.URLField(blank=True)
    access_token = models.TextField(blank=True)  # 암호화 필요
    refresh_token = models.TextField(blank=True)  # 암호화 필요
    token_expires_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('provider', 'provider_user_id')
        indexes = [
            models.Index(fields=['provider', 'provider_user_id']),
        ]
```

### 2. settings.AppSettings (앱 전역 설정)
```python
class AppSettings(models.Model):
    key = models.CharField(max_length=100, unique=True, primary_key=True)
    value = models.JSONField()
    description = models.TextField(blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    # 설정 키 예시
    # 'keyword_limit': {'max_active': 20, 'max_inactive': 10}
    # 'ad_platforms': ['admob', 'kakao_adfit']
```

### 3. settings.AdConfiguration (광고 설정)
```python
class AdConfiguration(models.Model):
    platform = models.CharField(max_length=50)  # 'admob', 'kakao_adfit', 'apple_search_ads'
    device_platform = models.CharField(max_length=20)  # 'android', 'ios'
    ad_type = models.CharField(max_length=50)   # 'banner', 'interstitial', 'rewarded', 'native'
    ad_unit_id = models.CharField(max_length=255)
    is_active = models.BooleanField(default=True)
    platform_specific_config = models.JSONField(default=dict)  # 추가 설정 (크기, 템플릿 등)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('platform', 'device_platform', 'ad_type')
        indexes = [
            models.Index(fields=['platform', 'device_platform', 'is_active'], name='idx_ad_platform_device'),
        ]
        verbose_name = "광고 설정"
        verbose_name_plural = "광고 설정"

# 예시 데이터:
# AdConfiguration(platform='admob', device_platform='android', ad_type='banner', ad_unit_id='ca-app-pub-xxx/aos-banner')
# AdConfiguration(platform='admob', device_platform='ios', ad_type='banner', ad_unit_id='ca-app-pub-xxx/ios-banner')
# AdConfiguration(platform='kakao_adfit', device_platform='android', ad_type='native', ad_unit_id='DAN-xxx-aos-native')
```

### 4. keywords.Keyword (키워드 마스터)
```python
class Keyword(models.Model):
    name = models.CharField(max_length=100, unique=True)
    category = models.CharField(max_length=50, blank=True)
    is_active = models.BooleanField(default=True)  # 전역 활성화 여부
    created_at = models.DateTimeField(auto_now_add=True)
```

### 5. keywords.UserKeyword (사용자별 키워드)
```python
class UserKeyword(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='keywords')
    keyword = models.ForeignKey(Keyword, on_delete=models.CASCADE)
    is_active = models.BooleanField(default=True)  # 사용자별 활성화 여부
    priority = models.IntegerField(default=0)  # 우선순위
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('user', 'keyword')
        indexes = [
            models.Index(fields=['user', 'is_active']),
        ]
```

---

## 🔒 인증 및 권한 관리 (중요!)

### ⚠️ 필수 보안 요구사항

#### 1. 키워드 API는 **로그인한 사용자만** 접근 가능
```python
# 모든 키워드 API는 JWT 인증 필수
@require_authentication  # 데코레이터로 인증 체크
async def get_my_keywords(request):
    if not request.user.is_authenticated:
        return JsonResponse({'error': 'Authentication required'}, status=401)
    # ...
```

#### 2. 본인의 리소스만 접근 가능 (권한 체크)
```python
# 키워드 토글 시 본인 확인
async def toggle_keyword(request, keyword_id: int):
    keyword = await UserKeyword.objects.aget(id=keyword_id)

    # 🔐 본인 확인: 다른 사용자의 키워드는 수정 불가
    if keyword.user_id != request.user.id:
        return JsonResponse({'error': 'Permission denied'}, status=403)

    # 본인의 키워드만 수정 가능
    keyword.is_active = not keyword.is_active
    await keyword.asave()
```

#### 3. /me API는 로그인한 본인 정보만 반환
```python
# 로그인한 사용자 본인의 정보만 조회 가능
GET /api/v1/users/me
Authorization: Bearer {jwt_token}

# JWT 토큰에서 사용자 ID 추출 → 본인 정보만 반환
# 다른 사용자 정보 조회 불가
```

#### 4. 인증 실패 시 에러 처리
```python
# 401 Unauthorized: 로그인하지 않은 사용자
{
  "error": "Authentication required",
  "detail": "Please login to access this resource"
}

# 403 Forbidden: 로그인했지만 권한 없음 (다른 사용자의 리소스)
{
  "error": "Permission denied",
  "detail": "You don't have permission to access this resource"
}
```

### 🛡️ 인증 미들웨어 구현
```python
# users/middleware.py
from ninja.security import HttpBearer
import jwt
from django.conf import settings

class JWTAuth(HttpBearer):
    async def authenticate(self, request, token):
        try:
            # JWT 토큰 검증
            payload = jwt.decode(
                token,
                settings.JWT_SECRET_KEY,
                algorithms=[settings.JWT_ALGORITHM]
            )
            user_id = payload.get('user_id')

            # 사용자 조회 (비동기)
            user = await User.objects.aget(id=user_id)
            return user
        except jwt.ExpiredSignatureError:
            return None  # 토큰 만료
        except jwt.InvalidTokenError:
            return None  # 유효하지 않은 토큰
        except User.DoesNotExist:
            return None  # 사용자 없음
```

### 📋 인증이 필요한 API 목록
- ✅ `GET /api/v1/users/me` - 본인 정보 조회
- ✅ `GET /api/v1/keywords/my` - 본인 키워드 목록
- ✅ `POST /api/v1/keywords` - 키워드 추가
- ✅ `PATCH /api/v1/keywords/{id}/toggle` - 키워드 토글 (본인 것만)
- ✅ `DELETE /api/v1/keywords/{id}` - 키워드 삭제 (본인 것만)
- ✅ `GET /api/v1/settings/keyword-limit` - 키워드 제한 조회
- ✅ `GET /api/v1/settings/ads` - 광고 설정 조회 (선택적, 공개 가능)

### 📋 인증이 필요 없는 API 목록 (공개 API)
- ✅ `POST /api/v1/auth/kakao` - Kakao 로그인
- ✅ `POST /api/v1/auth/google` - Google 로그인
- ✅ `POST /api/v1/auth/apple` - Apple 로그인

---

## 🔌 API 엔드포인트 명세

### 0. 사용자 정보 API

#### 0.1 내 정보 조회 (/me)
```
GET /api/v1/users/me
Authorization: Bearer {jwt_token}

Response (성공):
{
  "id": 1,
  "email": "user@example.com",
  "name": "홍길동",
  "profile_image": "https://...",
  "created_at": "2025-11-19T12:00:00Z",
  "social_accounts": [
    {
      "provider": "kakao",
      "email": "user@kakao.com",
      "connected_at": "2025-11-19T12:00:00Z"
    }
  ]
}

Response (인증 실패):
{
  "error": "Authentication required",
  "detail": "Please login to access this resource"
}
```

#### 0.2 내 정보 수정
```
PATCH /api/v1/users/me
Authorization: Bearer {jwt_token}
Content-Type: application/json

Request:
{
  "name": "새이름",
  "profile_image": "https://new-image-url"
}

Response:
{
  "id": 1,
  "email": "user@example.com",
  "name": "새이름",
  "profile_image": "https://new-image-url",
  "updated_at": "2025-11-19T13:00:00Z"
}
```

### 1. SNS 로그인 API

#### 1.1 Kakao 로그인
```
POST /api/v1/auth/kakao
Content-Type: application/json

Request:
{
  "access_token": "kakao_access_token_from_flutter_sdk"
}

Response (성공):
{
  "access_token": "jwt_token",
  "refresh_token": "jwt_refresh_token",
  "user": {
    "id": 1,
    "email": "user@example.com",
    "name": "홍길동",
    "profile_image": "https://..."
  }
}

Response (실패):
{
  "error": "Invalid token",
  "detail": "Kakao token verification failed"
}
```

#### 1.2 Google 로그인
```
POST /api/v1/auth/google
Content-Type: application/json

Request:
{
  "access_token": "google_access_token_from_flutter_sdk"
}

Response: (Kakao와 동일 형식)
```

#### 1.3 Apple 로그인
```
POST /api/v1/auth/apple
Content-Type: application/json

Request:
{
  "identity_token": "apple_identity_token_from_flutter_sdk",
  "authorization_code": "apple_authorization_code"
}

Response: (Kakao와 동일 형식)
```

### 2. 광고 설정 API

#### 2.1 광고 설정 조회
```
GET /api/v1/settings/ads
Authorization: Bearer {jwt_token}

Response:
{
  "configurations": {
    "admob": {
      "banner": {
        "ad_unit_id": "ca-app-pub-xxx/banner",
        "is_active": true,
        "config": {"size": "SMART_BANNER"}
      },
      "interstitial": {
        "ad_unit_id": "ca-app-pub-xxx/interstitial",
        "is_active": true,
        "config": {"load_on_startup": true}
      }
    },
    "kakao_adfit": {
      "banner": {
        "ad_unit_id": "DAN-xxx",
        "is_active": true,
        "config": {"width": 320, "height": 100}
      }
    }
  }
}
```

#### 2.2 광고 설정 업데이트 (관리자용)
```
PUT /api/v1/settings/ads
Authorization: Bearer {admin_jwt_token}
Content-Type: application/json

Request:
{
  "platform": "admob",
  "ad_type": "banner",
  "ad_unit_id": "ca-app-pub-xxx/new-banner",
  "is_active": true,
  "config": {"size": "BANNER"}
}

Response:
{
  "success": true,
  "message": "Ad configuration updated"
}
```

### 3. 키워드 관리 API

#### 3.1 사용자 키워드 목록 조회
```
GET /api/v1/keywords/my
Authorization: Bearer {jwt_token}

Response:
{
  "active_keywords": [
    {"id": 1, "name": "맛집", "priority": 1},
    {"id": 2, "name": "카페", "priority": 2}
  ],
  "inactive_keywords": [
    {"id": 3, "name": "헬스장", "priority": 0}
  ],
  "limits": {
    "max_active": 20,
    "max_inactive": 10,
    "current_active": 2,
    "current_inactive": 1
  }
}
```

#### 3.2 키워드 활성화/비활성화 토글
```
PATCH /api/v1/keywords/{keyword_id}/toggle
Authorization: Bearer {jwt_token}

🔐 권한 체크: 본인의 키워드만 토글 가능 (다른 사용자 키워드 접근 시 403 Forbidden)

Response (성공):
{
  "id": 1,
  "name": "맛집",
  "is_active": false,  // 토글 후 상태
  "message": "Keyword deactivated successfully"
}

Error (제한 초과):
{
  "error": "Limit exceeded",
  "detail": "Maximum active keywords limit (20) reached"
}

Error (권한 없음 - 다른 사용자의 키워드):
{
  "error": "Permission denied",
  "detail": "You don't have permission to modify this keyword"
}

Error (인증 안됨):
{
  "error": "Authentication required",
  "detail": "Please login to access this resource"
}
```

#### 3.3 키워드 추가
```
POST /api/v1/keywords
Authorization: Bearer {jwt_token}
Content-Type: application/json

Request:
{
  "name": "영화관",
  "is_active": true
}

Response:
{
  "id": 4,
  "name": "영화관",
  "is_active": true,
  "created_at": "2025-11-19T12:00:00Z"
}
```

#### 3.4 키워드 삭제
```
DELETE /api/v1/keywords/{keyword_id}
Authorization: Bearer {jwt_token}

🔐 권한 체크: 본인의 키워드만 삭제 가능 (다른 사용자 키워드 접근 시 403 Forbidden)

Response (성공):
{
  "success": true,
  "message": "Keyword deleted successfully"
}

Error (권한 없음 - 다른 사용자의 키워드):
{
  "error": "Permission denied",
  "detail": "You don't have permission to delete this keyword"
}

Error (인증 안됨):
{
  "error": "Authentication required",
  "detail": "Please login to access this resource"
}

Error (키워드 없음):
{
  "error": "Not found",
  "detail": "Keyword not found"
}
```

### 4. 키워드 제한 설정 API

#### 4.1 키워드 제한 조회
```
GET /api/v1/settings/keyword-limit
Authorization: Bearer {jwt_token}

Response:
{
  "max_active_keywords": 20,
  "max_inactive_keywords": 10,
  "total_allowed_keywords": 30
}
```

#### 4.2 키워드 제한 업데이트 (관리자용)
```
PUT /api/v1/settings/keyword-limit
Authorization: Bearer {admin_jwt_token}
Content-Type: application/json

Request:
{
  "max_active_keywords": 30,
  "max_inactive_keywords": 20
}

Response:
{
  "success": true,
  "max_active_keywords": 30,
  "max_inactive_keywords": 20,
  "total_allowed_keywords": 50
}
```

---

## 🔐 환경변수 (.env 추가 항목)

```bash
# ===== SNS 로그인 설정 =====

# Kakao OAuth
KAKAO_REST_API_KEY=your_kakao_rest_api_key
KAKAO_CLIENT_SECRET=your_kakao_client_secret
KAKAO_REDIRECT_URI=http://localhost:8000/api/v1/auth/kakao/callback

# Google OAuth
GOOGLE_CLIENT_ID=your_google_client_id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your_google_client_secret
GOOGLE_REDIRECT_URI=http://localhost:8000/api/v1/auth/google/callback

# Apple OAuth
APPLE_CLIENT_ID=com.reviewmaps.app
APPLE_TEAM_ID=your_apple_team_id
APPLE_KEY_ID=your_apple_key_id
APPLE_PRIVATE_KEY_PATH=/path/to/AuthKey_XXX.p8
APPLE_REDIRECT_URI=http://localhost:8000/api/v1/auth/apple/callback

# ===== JWT 설정 =====
JWT_SECRET_KEY=your_jwt_secret_key_here
JWT_ALGORITHM=HS256
JWT_ACCESS_TOKEN_EXPIRE_MINUTES=60
JWT_REFRESH_TOKEN_EXPIRE_DAYS=30

# ===== 광고 설정 (플랫폼별) =====

# AdMob - Android (AOS)
ADMOB_AOS_APP_ID=ca-app-pub-xxx~xxx
ADMOB_AOS_BANNER_AD_UNIT_ID=ca-app-pub-xxx/aos-banner
ADMOB_AOS_INTERSTITIAL_AD_UNIT_ID=ca-app-pub-xxx/aos-interstitial
ADMOB_AOS_REWARDED_AD_UNIT_ID=ca-app-pub-xxx/aos-rewarded

# AdMob - iOS
ADMOB_IOS_APP_ID=ca-app-pub-xxx~xxx
ADMOB_IOS_BANNER_AD_UNIT_ID=ca-app-pub-xxx/ios-banner
ADMOB_IOS_INTERSTITIAL_AD_UNIT_ID=ca-app-pub-xxx/ios-interstitial
ADMOB_IOS_REWARDED_AD_UNIT_ID=ca-app-pub-xxx/ios-rewarded

# Kakao AdFit - Android (AOS)
KAKAO_ADFIT_AOS_BANNER_AD_UNIT_ID=DAN-xxx-aos-banner
KAKAO_ADFIT_AOS_NATIVE_AD_UNIT_ID=DAN-xxx-aos-native

# Kakao AdFit - iOS
KAKAO_ADFIT_IOS_BANNER_AD_UNIT_ID=DAN-xxx-ios-banner
KAKAO_ADFIT_IOS_NATIVE_AD_UNIT_ID=DAN-xxx-ios-native

# Apple Search Ads (iOS만 지원)
APPLE_SEARCH_ADS_ORG_ID=your_org_id
APPLE_SEARCH_ADS_KEY_ID=your_key_id
APPLE_SEARCH_ADS_TEAM_ID=your_team_id
```

---

## 🛠️ 구현 순서 (TDD 방식)

### Phase 1: SNS 로그인 및 인증 시스템 (4일 예상)
1. ✅ **users 앱 생성**
   - `python manage.py startapp users`
2. ✅ **모델 설계 및 마이그레이션**
   - `SocialAccount` 모델 생성
   - `python manage.py makemigrations`
   - `python manage.py migrate`
3. ✅ **JWT 인증 미들웨어 구현 (🔐 중요!)**
   - `users/middleware.py` - JWTAuth 클래스
   - JWT 토큰 생성 및 검증 로직
   - 토큰 만료 처리
4. ✅ **테스트 작성 (TDD)**
   - `users/tests/test_kakao_login.py`
   - `users/tests/test_google_login.py`
   - `users/tests/test_apple_login.py`
   - `users/tests/test_jwt_auth.py` (인증 테스트)
   - `users/tests/test_me_api.py` (/me API 테스트)
5. ✅ **OAuth 검증 서비스 구현**
   - `users/services/kakao.py`
   - `users/services/google.py`
   - `users/services/apple.py`
6. ✅ **API 엔드포인트 구현**
   - `POST /api/v1/auth/kakao`
   - `POST /api/v1/auth/google`
   - `POST /api/v1/auth/apple`
   - `GET /api/v1/users/me` (본인 정보 조회)
   - `PATCH /api/v1/users/me` (본인 정보 수정)
7. ✅ **테스트 실행 및 통과**

### Phase 2: 광고 설정 API (2일 예상)
1. ✅ **settings 앱 생성**
2. ✅ **모델 설계**
   - `AdConfiguration` 모델
   - `AppSettings` 모델
3. ✅ **테스트 작성**
   - `settings/tests/test_ad_config.py`
4. ✅ **API 구현**
   - `GET /api/v1/settings/ads`
   - `PUT /api/v1/settings/ads`
5. ✅ **초기 데이터 생성 (Fixture)**
   - AdMob, Kakao AdFit 기본 설정
6. ✅ **테스트 통과**

### Phase 3: 키워드 관리 API (3일 예상)
1. ✅ **keywords 앱 생성**
2. ✅ **모델 설계**
   - `Keyword` 모델
   - `UserKeyword` 모델
3. ✅ **테스트 작성 (TDD - 권한 체크 포함)**
   - `keywords/tests/test_keyword_crud.py`
   - `keywords/tests/test_keyword_toggle.py`
   - `keywords/tests/test_keyword_limits.py`
   - `keywords/tests/test_keyword_permissions.py` (🔐 권한 테스트 - 중요!)
     - 다른 사용자의 키워드 접근 시 403 에러
     - 비로그인 사용자 접근 시 401 에러
4. ✅ **API 구현 (인증 및 권한 체크 포함)**
   - `GET /api/v1/keywords/my` (로그인 필수)
   - `POST /api/v1/keywords` (로그인 필수)
   - `PATCH /api/v1/keywords/{id}/toggle` (로그인 + 본인 확인 필수)
   - `DELETE /api/v1/keywords/{id}` (로그인 + 본인 확인 필수)
5. ✅ **키워드 제한 로직 구현**
   - 활성화/비활성화 개수 체크
   - 제한 초과 시 에러 반환
6. ✅ **권한 체크 로직 구현 (🔐 중요!)**
   - 모든 API에 JWTAuth 적용
   - 토글/삭제 시 본인 확인 (user_id 비교)
   - 권한 없으면 403 Forbidden 반환
7. ✅ **테스트 통과**

### Phase 4: 설정 관리 API (1일 예상)
1. ✅ **테스트 작성**
   - `settings/tests/test_keyword_limit.py`
2. ✅ **API 구현**
   - `GET /api/v1/settings/keyword-limit`
   - `PUT /api/v1/settings/keyword-limit`
3. ✅ **테스트 통과**

### Phase 5: 통합 테스트 및 문서화 (1일 예상)
1. ✅ **전체 시스템 통합 테스트**
   - 인증 플로우 전체 테스트
   - 권한 체크 통합 테스트
2. ✅ **API 문서 업데이트**
3. ✅ **README 및 예제 작성**

**총 예상 기간**: 11일 (인증 시스템 추가로 1일 증가)

---

## ⚠️ 잠재적 이슈 및 해결 방안

### 1. SNS 토큰 검증 실패
**문제**: 각 플랫폼별 토큰 검증 API 변경 가능성
**해결**:
- 각 플랫폼 공식 SDK 사용
- 예외 처리 및 로깅 강화
- 토큰 만료 시 명확한 에러 메시지

### 2. 광고 플랫폼 확장
**문제**: 새로운 광고 플랫폼 추가 시 스키마 변경
**해결**:
- JSONField를 활용한 유연한 스키마
- 플랫폼별 설정을 동적으로 처리
- 마이그레이션 없이 설정 추가 가능

### 3. 키워드 제한 초과 시 UX
**문제**: 사용자가 제한을 초과했을 때 혼란
**해결**:
- 명확한 에러 메시지 제공
- 현재 사용 중인 개수와 최대 허용 개수 표시
- 비활성화 키워드 삭제 권장

### 4. 동시성 문제 (키워드 개수 체크)
**문제**: 여러 요청이 동시에 들어올 때 제한 초과 가능
**해결**:
- Database-level constraint 추가
- Transaction 사용
- Race condition 방지

### 5. SNS 계정 연동 해제
**문제**: 사용자가 SNS 연동 해제 시 데이터 처리
**해결**:
- Soft delete 방식 (is_active 플래그)
- 연동 해제 API 별도 제공
- 데이터 보존 정책 수립

---

## 🔍 보안 고려사항

### 1. 토큰 보안
- ✅ Access Token, Refresh Token은 암호화 저장
- ✅ JWT Secret Key는 환경변수로 관리
- ✅ HTTPS 사용 (프로덕션)
- ✅ JWT 토큰에 민감 정보 포함 금지 (user_id, email만 포함)

### 2. 시크릿 키 관리
- ✅ 시크릿 키는 절대 클라이언트로 전송하지 않음
- ✅ .env 파일은 .gitignore에 추가
- ✅ 프로덕션 환경에서는 환경변수 또는 Secret Manager 사용

### 3. API 인증 및 권한
- ✅ JWT 기반 인증 (모든 보호된 API)
- ✅ 만료 시간 설정 (Access: 1시간, Refresh: 30일)
- ✅ Rate limiting 적용
- ✅ **본인 확인 필수** (키워드 토글, 삭제 시)
- ✅ **비로그인 사용자 차단** (401 Unauthorized)
- ✅ **권한 없는 접근 차단** (403 Forbidden)

### 4. 개인정보 보호
- ✅ 이메일, 이름 등 개인정보는 암호화 저장 고려
- ✅ GDPR, 개인정보보호법 준수
- ✅ **다른 사용자의 정보 조회 불가** (/me API는 본인만)

### 5. 권한 관리 원칙
- ✅ **Zero Trust**: 모든 요청에 대해 인증 및 권한 확인
- ✅ **Least Privilege**: 최소 권한 원칙 적용
- ✅ **Defense in Depth**: 다층 보안 (인증 + 권한 체크 + DB 제약조건)

---

## 📝 다음 단계 (사용자 확인 필요)

### ✅ 확인 필요 사항

1. **SNS 로그인 설계**
   - ✅ 제안한 "서버 사이드 검증" 방식에 동의하시나요?
   - ❓ 추가로 필요한 SNS 플랫폼이 있나요? (Naver, Facebook 등)

2. **광고 설정**
   - ✅ 제안한 JSON 기반 유연한 스키마에 동의하시나요?
   - ❓ 광고 설정을 관리자만 변경 가능하게 할까요, 아니면 일반 사용자도 가능하게 할까요?

3. **키워드 제한**
   - ✅ 활성화 + 비활성화 = 전체 키워드 수 방식에 동의하시나요?
   - ❓ 기본 제한값은? (활성화 20개, 비활성화 10개로 제안)

4. **구현 우선순위**
   - ❓ SNS 로그인 → 광고 설정 → 키워드 관리 순서로 진행해도 될까요?
   - ❓ 특정 기능을 먼저 구현해야 하는 이유가 있나요?

5. **추가 요구사항**
   - ❓ 사용자 프로필 관리 API도 필요한가요?
   - ❓ 키워드 추천 기능이 필요한가요?
   - ❓ 광고 노출 통계 기능이 필요한가요?

---

## 📌 확인 후 다음 작업

사용자 확인 및 피드백을 받은 후:
1. ✅ 피드백 반영하여 계획 수정
2. ✅ Feature 브랜치 생성 (`feature/sns-login-and-settings`)
3. ✅ Phase 1부터 TDD 방식으로 구현 시작
4. ✅ 각 Phase 완료 후 커밋
5. ✅ 최종 PR 생성 및 리뷰 요청

---

**작성자**: Claude Code
**검토 필요**: 사용자 확인 대기 중
