# App Config Implementation Report

**작성일**: 2025-11-15
**프로젝트**: ReviewMaps Server
**담당자**: Claude (TDD 기반 구현)

## 1. 개요

ReviewMaps 모바일 앱의 설정을 DB/API로 중앙화 관리하는 시스템을 TDD 방식으로 구축 완료했습니다.

### 주요 기능
- **광고 설정 관리**: 플랫폼별 광고 네트워크 설정 (AdMob, AppLovin 등)
- **앱 버전 관리**: 버전 체크 및 강제 업데이트 제어
- **일반 설정 관리**: Key-Value 형식의 유연한 설정 시스템

## 2. 구현 내용

### 2.1 모델 (Models)

**파일**: `/Users/woohyeon/ggorockee/reviewmaps/server/app_config/models.py`

#### AdConfig (광고 설정)
- `platform`: Android/iOS 구분
- `ad_network`: 광고 네트워크명 (admob, applovin, unity 등)
- `is_enabled`: 활성화 여부 (기본값: True)
- `ad_unit_ids`: JSON 필드 (banner_id, interstitial_id, native_id, rewarded_id)
- `priority`: 우선순위 (높을수록 우선)
- **인덱스**: platform+is_enabled, priority 복합 인덱스

#### AppVersion (앱 버전)
- `platform`: Android/iOS
- `version`: 버전 (예: 1.3.5)
- `build_number`: 빌드 번호 (예: 50)
- `minimum_version`: 최소 지원 버전 (강제 업데이트 기준)
- `force_update`: 강제 업데이트 여부
- `update_message`: 업데이트 메시지 (nullable)
- `store_url`: Play Store/App Store URL
- `is_active`: 활성화 여부 (기본값: True)
- **인덱스**: platform+is_active, created_at 인덱스

#### AppSetting (일반 설정)
- `key`: 설정 키 (unique)
- `value`: JSON 필드 (유연한 값 저장)
- `description`: 설명 (nullable)
- `is_active`: 활성화 여부 (기본값: True)
- **인덱스**: key, is_active 인덱스

### 2.2 API 엔드포인트 (Django Ninja, 비동기)

**파일**: `/Users/woohyeon/ggorockee/reviewmaps/server/app_config/api.py`

#### 광고 설정 API
```
GET /v1/app-config/ads?platform={android|ios}
```
- 플랫폼별 활성화된 광고 설정 조회
- 우선순위(priority) 높은 순으로 정렬
- 응답: AdConfigSchema 리스트

#### 앱 버전 체크 API
```
GET /v1/app-config/version?platform={android|ios}&current_version={version}
```
- 현재 버전과 최신 버전 비교
- 업데이트 필요 여부 및 강제 업데이트 여부 반환
- 버전 비교 로직: major.minor.patch 형식 파싱
- 응답: VersionCheckResponseSchema
  - `needs_update`: 업데이트 필요 여부
  - `force_update`: 강제 업데이트 여부
  - `latest_version`: 최신 버전
  - `message`: 업데이트 메시지
  - `store_url`: 스토어 URL

#### 일반 설정 API
```
GET /v1/app-config/settings
```
- 모든 활성화된 설정 조회
- key 알파벳 순 정렬
- 응답: AppSettingSchema 리스트

```
GET /v1/app-config/settings/{key}
```
- 특정 키의 설정 조회
- 비활성 설정은 404 반환
- 응답: AppSettingSchema

### 2.3 Pydantic 스키마

**파일**: `/Users/woohyeon/ggorockee/reviewmaps/server/app_config/schemas.py`

- `AdConfigSchema`: 광고 설정 응답
- `AppVersionSchema`: 앱 버전 응답
- `VersionCheckResponseSchema`: 버전 체크 응답 (간소화)
- `AppSettingSchema`: 일반 설정 응답

모든 스키마는 자동 타임스탬프(created_at, updated_at) 포함

### 2.4 Django Admin 패널

**파일**: `/Users/woohyeon/ggorockee/reviewmaps/server/app_config/admin.py`

- `AdConfigAdmin`: 광고 설정 관리
  - list_display: platform, ad_network, is_enabled, priority, created_at
  - list_filter: platform, is_enabled, ad_network
  - fieldsets: 기본정보, 광고유닛ID, 타임스탬프

- `AppVersionAdmin`: 앱 버전 관리
  - list_display: platform, version, build_number, minimum_version, force_update, is_active, created_at
  - list_filter: platform, is_active, force_update
  - fieldsets: 기본정보, 버전관리, 스토어정보, 타임스탬프

- `AppSettingAdmin`: 일반 설정 관리
  - list_display: key, description, is_active, created_at
  - list_filter: is_active
  - fieldsets: 기본정보, 설정값, 타임스탬프

## 3. TDD 테스트 결과

### 3.1 모델 테스트 (`test_models.py`)

**총 23개 테스트 - 모두 통과 ✅**

#### AdConfigModelTest (8개)
- ✅ Android 광고 설정 생성
- ✅ iOS 광고 설정 생성
- ✅ JSON 필드 저장 및 조회
- ✅ 기본값 is_enabled=True
- ✅ 기본값 priority=0
- ✅ 우선순위 정렬 (priority DESC)
- ✅ 문자열 표현
- ✅ updated_at 자동 갱신

#### AppVersionModelTest (7개)
- ✅ Android 앱 버전 생성
- ✅ iOS 앱 버전 생성
- ✅ 기본값 force_update=False
- ✅ 기본값 is_active=True
- ✅ nullable 필드 (update_message)
- ✅ 문자열 표현
- ✅ 정렬 (is_active DESC, created_at DESC)

#### AppSettingModelTest (8개)
- ✅ 앱 설정 생성
- ✅ key 유니크 제약
- ✅ JSON value 필드 (복잡한 구조 포함)
- ✅ 기본값 is_active=True
- ✅ description nullable
- ✅ 문자열 표현
- ✅ 정렬 (key ASC)
- ✅ is_active 필터링

### 3.2 API 테스트 (`test_api.py`)

**총 20개 테스트 - 모두 통과 ✅**

#### AdConfigAPITest (7개)
- ✅ Android 광고 설정 조회
- ✅ iOS 광고 설정 조회
- ✅ platform 파라미터 없을 때 422 에러
- ✅ 잘못된 platform 시 빈 배열
- ✅ 우선순위 정렬 검증
- ✅ 비활성 광고는 반환 안됨
- ✅ 광고 없을 때 빈 배열

#### AppVersionAPITest (7개)
- ✅ 업데이트 불필요 (최신 버전)
- ✅ 업데이트 가능 (구버전)
- ✅ 강제 업데이트 필요 (minimum_version 미만)
- ✅ minimum_version 경계값 검증
- ✅ platform 파라미터 없을 때 422 에러
- ✅ current_version 파라미터 없을 때 422 에러
- ✅ 활성 버전 없을 때 404 에러

#### AppSettingAPITest (4개)
- ✅ 모든 활성 설정 조회
- ✅ 특정 키로 설정 조회
- ✅ 존재하지 않는 키 404 에러
- ✅ 비활성 설정 404 에러

#### APIErrorHandlingTest (2개)
- ✅ 광고 설정 없을 때 빈 배열
- ✅ 설정 없을 때 빈 배열

**전체 테스트 실행 결과**:
```
Ran 43 tests in 0.661s

OK
```

## 4. 데이터베이스 마이그레이션

**마이그레이션 파일**: `app_config/migrations/0001_initial.py`

- ✅ AdConfig 테이블 생성 (ad_configs)
- ✅ AppVersion 테이블 생성 (app_versions)
- ✅ AppSetting 테이블 생성 (app_settings)
- ✅ 모든 인덱스 생성 완료
- ✅ PostgreSQL 13 호환성 설정 적용

## 5. 설정 통합

### 5.1 Django Settings

**파일**: `/Users/woohyeon/ggorockee/reviewmaps/server/config/settings.py`

```python
INSTALLED_APPS = [
    # ...
    'app_config',  # 추가됨
]

# PostgreSQL 13 임시 호환성
from django.db.backends.postgresql.features import DatabaseFeatures
DatabaseFeatures.minimum_database_version = (13, 0)
```

### 5.2 URL 라우팅

**파일**: `/Users/woohyeon/ggorockee/reviewmaps/server/config/urls.py`

```python
from app_config.api import router as app_config_router

api.add_router("/app-config", app_config_router)
```

## 6. 기술 스택 및 특징

### 기술 스택
- **Framework**: Django 5.2.8
- **API**: Django Ninja (비동기 지원)
- **Database**: PostgreSQL 13.21 (추후 14+ 업그레이드 권장)
- **ORM**: Django ORM (비동기 쿼리 사용)
- **Testing**: Django TestCase + pytest-django 스타일

### 구현 특징
1. **완전 비동기**: 모든 API 엔드포인트 `async def` 구현
2. **Django ORM 비동기**: `aget`, `afilter`, `afirst` 등 사용
3. **JSON 필드**: PostgreSQL JSONField로 유연한 데이터 저장
4. **인덱스 최적화**: 자주 사용되는 쿼리에 대한 복합 인덱스
5. **TDD 방식**: 테스트 먼저 작성 → 구현 → 검증
6. **한국어 주석**: 모든 코드에 한국어 docstring 포함

## 7. API 사용 예시

### 7.1 광고 설정 조회
```bash
# Android 광고 설정 조회
curl http://localhost:8000/v1/app-config/ads?platform=android

# 응답 예시
[
  {
    "id": 1,
    "platform": "android",
    "ad_network": "admob",
    "is_enabled": true,
    "ad_unit_ids": {
      "banner_id": "ca-app-pub-xxx/banner",
      "interstitial_id": "ca-app-pub-xxx/interstitial"
    },
    "priority": 1,
    "created_at": "2025-11-15T00:00:00Z",
    "updated_at": "2025-11-15T00:00:00Z"
  }
]
```

### 7.2 앱 버전 체크
```bash
# 버전 체크
curl "http://localhost:8000/v1/app-config/version?platform=android&current_version=1.2.0"

# 응답 예시 (업데이트 필요)
{
  "needs_update": true,
  "force_update": false,
  "latest_version": "1.3.5",
  "message": "새로운 기능이 추가되었습니다.",
  "store_url": "https://play.google.com/store/apps/details?id=com.reviewmaps"
}
```

### 7.3 일반 설정 조회
```bash
# 모든 설정 조회
curl http://localhost:8000/v1/app-config/settings

# 특정 설정 조회
curl http://localhost:8000/v1/app-config/settings/maintenance_mode

# 응답 예시
{
  "id": 1,
  "key": "maintenance_mode",
  "value": {
    "enabled": false,
    "message": ""
  },
  "description": "점검 모드 설정",
  "is_active": true,
  "created_at": "2025-11-15T00:00:00Z",
  "updated_at": "2025-11-15T00:00:00Z"
}
```

## 8. Django Admin 사용법

### 관리자 페이지 접속
```
http://localhost:8000/admin/app_config/
```

### 광고 설정 추가 예시
1. "Ad configs" → "추가" 클릭
2. Platform: Android 선택
3. Ad network: admob 입력
4. Is enabled: 체크
5. Priority: 1 입력
6. Ad unit ids: JSON 형식 입력
   ```json
   {
     "banner_id": "ca-app-pub-xxx/banner",
     "interstitial_id": "ca-app-pub-xxx/interstitial"
   }
   ```
7. 저장

### 앱 버전 추가 예시
1. "App versions" → "추가" 클릭
2. Platform: Android 선택
3. Version: 1.3.5 입력
4. Build number: 50 입력
5. Minimum version: 1.0.0 입력
6. Force update: 필요시 체크
7. Update message: "새로운 기능이 추가되었습니다." 입력
8. Store url: Play Store URL 입력
9. Is active: 체크
10. 저장

## 9. 향후 개선사항

### 9.1 인프라
- [ ] PostgreSQL 14+ 업그레이드 (Django 5.2 공식 지원)
- [ ] Database 복제 설정 (Read Replica)

### 9.2 기능
- [ ] 앱 버전 자동 비활성화 (새 버전 추가 시)
- [ ] 광고 네트워크 fallback 로직
- [ ] 설정 변경 히스토리 추적
- [ ] 캐싱 레이어 추가 (Redis)

### 9.3 모니터링
- [ ] API 응답 시간 모니터링
- [ ] 광고 설정 변경 알림
- [ ] 버전 업데이트 통계

## 10. 결론

TDD 방식으로 ReviewMaps 모바일 앱의 설정 관리 시스템을 성공적으로 구축했습니다.

### 주요 성과
- ✅ 43개 테스트 모두 통과 (100% 성공률)
- ✅ 완전 비동기 API 구현
- ✅ Django Admin 패널로 손쉬운 관리
- ✅ 유연한 JSON 필드로 확장성 확보
- ✅ 한국어 주석으로 유지보수성 향상

### 테스트 커버리지
- 모델: 23개 테스트 ✅
- API: 20개 테스트 ✅
- 총: 43개 테스트 ✅

이제 모바일 앱에서 API를 통해 광고 설정, 앱 버전 관리, 일반 설정을 중앙에서 관리할 수 있습니다.
