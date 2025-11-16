# App Config API 명세서

## 개요

**Base URL**: `/v1/app-config`
**Protocol**: HTTPS
**Content-Type**: `application/json`
**Authentication**: 불필요 (Public API)

---

## 목차

1. [버전 체크 API](#1-버전-체크-api)
2. [광고 설정 API](#2-광고-설정-api)
3. [앱 설정 API](#3-앱-설정-api)
4. [에러 코드](#4-에러-코드)
5. [데이터 타입](#5-데이터-타입)

---

## 1. 버전 체크 API

### 1.1 버전 체크 조회

플랫폼별 앱 버전을 체크하고 업데이트 필요 여부를 확인합니다.

#### Endpoint

```
GET /v1/app-config/version
```

#### Query Parameters

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| platform | string | ✅ | 플랫폼 (ios, android) | ios |
| current_version | string | ✅ | 현재 앱 버전 (semantic versioning) | 1.4.0 |

#### Request Example

```http
GET /v1/app-config/version?platform=ios&current_version=1.4.0 HTTP/1.1
Host: api.example.com
Accept: application/json
```

```bash
# cURL
curl -X GET "https://api.example.com/v1/app-config/version?platform=ios&current_version=1.4.0"
```

```javascript
// JavaScript (Fetch)
const response = await fetch(
  'https://api.example.com/v1/app-config/version?platform=ios&current_version=1.4.0'
);
const data = await response.json();
```

#### Response

**Status Code**: `200 OK`

```json
{
  "needs_update": true,
  "force_update": false,
  "latest_version": "1.4.1",
  "message": "새로운 기능이 추가되었습니다.",
  "store_url": "https://apps.apple.com/app/id123456789"
}
```

#### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| needs_update | boolean | 업데이트 필요 여부 (false=최신, true=업데이트 필요) |
| force_update | boolean | 강제 업데이트 여부 (true=필수 업데이트) |
| latest_version | string | 서버의 최신 버전 |
| message | string \| null | 업데이트 안내 메시지 |
| store_url | string | 앱 스토어 다운로드 URL |

#### Response Scenarios

**시나리오 1: 최신 버전 사용 중**

```json
{
  "needs_update": false,
  "force_update": false,
  "latest_version": "1.4.0",
  "message": null,
  "store_url": "https://apps.apple.com/app/id123456789"
}
```

**시나리오 2: 업데이트 권장**

```json
{
  "needs_update": true,
  "force_update": false,
  "latest_version": "1.4.1",
  "message": "새로운 기능이 추가되었습니다.",
  "store_url": "https://apps.apple.com/app/id123456789"
}
```

**시나리오 3: 강제 업데이트**

```json
{
  "needs_update": true,
  "force_update": true,
  "latest_version": "1.4.1",
  "message": "중요한 보안 업데이트입니다. 즉시 업데이트해주세요.",
  "store_url": "https://apps.apple.com/app/id123456789"
}
```

#### Error Responses

**400 Bad Request - 잘못된 버전 형식**

```json
{
  "detail": "Invalid version format. Expected: major.minor.patch (e.g., 1.4.0)"
}
```

**404 Not Found - 활성 버전 없음**

```json
{
  "detail": "활성화된 버전 정보가 없습니다."
}
```

**422 Unprocessable Entity - 파라미터 누락**

```json
{
  "detail": [
    {
      "loc": ["query", "platform"],
      "msg": "field required",
      "type": "value_error.missing"
    }
  ]
}
```

---

## 2. 광고 설정 API

### 2.1 광고 설정 조회

플랫폼별 활성화된 광고 네트워크 설정을 우선순위 순으로 조회합니다.

#### Endpoint

```
GET /v1/app-config/ads
```

#### Query Parameters

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| platform | string | ✅ | 플랫폼 (ios, android) | android |

#### Request Example

```http
GET /v1/app-config/ads?platform=android HTTP/1.1
Host: api.example.com
Accept: application/json
```

```bash
# cURL
curl -X GET "https://api.example.com/v1/app-config/ads?platform=android"
```

#### Response

**Status Code**: `200 OK`

```json
[
  {
    "id": 1,
    "platform": "android",
    "ad_network": "admob",
    "is_enabled": true,
    "ad_unit_ids": {
      "banner_id": "ca-app-pub-3940256099942544/6300978111",
      "interstitial_id": "ca-app-pub-3940256099942544/1033173712",
      "native_id": "ca-app-pub-3940256099942544/2247696110",
      "rewarded_id": "ca-app-pub-3940256099942544/5224354917"
    },
    "priority": 10,
    "created_at": "2024-11-15T10:30:00Z",
    "updated_at": "2024-11-15T10:30:00Z"
  },
  {
    "id": 2,
    "platform": "android",
    "ad_network": "applovin",
    "is_enabled": true,
    "ad_unit_ids": {
      "banner_id": "applovin-banner-id",
      "interstitial_id": "applovin-interstitial-id"
    },
    "priority": 5,
    "created_at": "2024-11-15T10:31:00Z",
    "updated_at": "2024-11-15T10:31:00Z"
  }
]
```

#### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| id | integer | 광고 설정 고유 ID |
| platform | string | 플랫폼 (ios, android) |
| ad_network | string | 광고 네트워크 이름 (admob, applovin, unity 등) |
| is_enabled | boolean | 활성화 여부 |
| ad_unit_ids | object | 광고 유닛 ID 객체 |
| priority | integer | 우선순위 (높을수록 우선) |
| created_at | string | 생성 일시 (ISO 8601) |
| updated_at | string | 수정 일시 (ISO 8601) |

#### ad_unit_ids Object Structure

```json
{
  "banner_id": "string",
  "interstitial_id": "string",
  "native_id": "string",
  "rewarded_id": "string",
  "rewarded_interstitial_id": "string"
}
```

#### Response Ordering

광고 설정은 다음 순서로 정렬됩니다:
1. `priority` 내림차순 (높은 우선순위 먼저)
2. `created_at` 내림차순 (최신 생성 먼저)

#### Empty Response

플랫폼에 활성화된 광고 설정이 없을 경우:

```json
[]
```

#### Error Responses

**422 Unprocessable Entity - 파라미터 누락**

```json
{
  "detail": [
    {
      "loc": ["query", "platform"],
      "msg": "field required",
      "type": "value_error.missing"
    }
  ]
}
```

---

## 3. 앱 설정 API

### 3.1 전체 설정 조회

활성화된 모든 앱 설정을 조회합니다.

#### Endpoint

```
GET /v1/app-config/settings
```

#### Query Parameters

없음

#### Request Example

```http
GET /v1/app-config/settings HTTP/1.1
Host: api.example.com
Accept: application/json
```

```bash
# cURL
curl -X GET "https://api.example.com/v1/app-config/settings"
```

#### Response

**Status Code**: `200 OK`

```json
[
  {
    "id": 1,
    "key": "feature_flags",
    "value": {
      "new_ui": true,
      "beta_feature": false,
      "dark_mode": true
    },
    "description": "기능 플래그 설정",
    "is_active": true,
    "created_at": "2024-11-15T10:30:00Z",
    "updated_at": "2024-11-15T10:30:00Z"
  },
  {
    "id": 2,
    "key": "maintenance_mode",
    "value": {
      "enabled": false,
      "message": "",
      "scheduled_at": null
    },
    "description": "점검 모드 설정",
    "is_active": true,
    "created_at": "2024-11-15T10:31:00Z",
    "updated_at": "2024-11-15T10:31:00Z"
  }
]
```

#### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| id | integer | 설정 고유 ID |
| key | string | 설정 키 (고유) |
| value | object | 설정 값 (JSON 객체) |
| description | string \| null | 설정 설명 |
| is_active | boolean | 활성화 여부 |
| created_at | string | 생성 일시 (ISO 8601) |
| updated_at | string | 수정 일시 (ISO 8601) |

#### Response Ordering

설정은 `key` 알파벳 순으로 정렬됩니다.

---

### 3.2 특정 설정 조회

특정 키의 설정을 조회합니다.

#### Endpoint

```
GET /v1/app-config/settings/{key}
```

#### Path Parameters

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| key | string | ✅ | 설정 키 | feature_flags |

#### Request Example

```http
GET /v1/app-config/settings/feature_flags HTTP/1.1
Host: api.example.com
Accept: application/json
```

```bash
# cURL
curl -X GET "https://api.example.com/v1/app-config/settings/feature_flags"
```

#### Response

**Status Code**: `200 OK`

```json
{
  "id": 1,
  "key": "feature_flags",
  "value": {
    "new_ui": true,
    "beta_feature": false,
    "dark_mode": true
  },
  "description": "기능 플래그 설정",
  "is_active": true,
  "created_at": "2024-11-15T10:30:00Z",
  "updated_at": "2024-11-15T10:30:00Z"
}
```

#### Error Responses

**404 Not Found - 설정 없음**

```json
{
  "detail": "설정 키 'nonexistent_key'를 찾을 수 없습니다."
}
```

---

## 4. 에러 코드

### HTTP Status Codes

| Status Code | Description | When |
|-------------|-------------|------|
| 200 | OK | 요청 성공 |
| 400 | Bad Request | 잘못된 요청 형식 |
| 404 | Not Found | 리소스를 찾을 수 없음 |
| 422 | Unprocessable Entity | 유효성 검증 실패 |
| 500 | Internal Server Error | 서버 오류 |

### Error Response Format

모든 에러 응답은 다음 형식을 따릅니다:

```json
{
  "detail": "에러 메시지"
}
```

또는 유효성 검증 에러의 경우:

```json
{
  "detail": [
    {
      "loc": ["query", "field_name"],
      "msg": "에러 메시지",
      "type": "error_type"
    }
  ]
}
```

---

## 5. 데이터 타입

### Platform Type

```typescript
type Platform = "ios" | "android";
```

**유효한 값**:
- `ios`: iOS 플랫폼
- `android`: Android 플랫폼

### Version String Format

Semantic Versioning 형식을 따릅니다.

**형식**: `major.minor.patch`

**예시**:
- `1.0.0`
- `1.4.1`
- `2.3.15`

**잘못된 형식**:
- `1.0` (patch 버전 누락)
- `v1.0.0` (v 접두사)
- `1.0.0-beta` (pre-release 태그)

### Ad Network Types

```typescript
type AdNetwork = "admob" | "applovin" | "unity" | "ironsource" | "mintegral" | string;
```

**일반적인 값**:
- `admob`: Google AdMob
- `applovin`: AppLovin
- `unity`: Unity Ads
- `ironsource`: IronSource
- `mintegral`: Mintegral

### DateTime Format

ISO 8601 형식을 사용합니다.

**형식**: `YYYY-MM-DDTHH:mm:ssZ`

**예시**:
- `2024-11-15T10:30:00Z`
- `2024-11-15T10:30:00.123456Z`

**타임존**: UTC (Z)

---

## 6. 사용 예시

### 6.1 앱 시작 시 초기화

```javascript
async function initializeApp() {
  // 1. 버전 체크
  const versionInfo = await checkAppVersion();
  if (versionInfo.force_update) {
    showForceUpdateDialog(versionInfo);
    return; // 앱 실행 중단
  } else if (versionInfo.needs_update) {
    showOptionalUpdateDialog(versionInfo);
  }

  // 2. 광고 설정 로드
  const adConfigs = await loadAdConfigs();
  initializeAdNetworks(adConfigs);

  // 3. 앱 설정 로드
  const appSettings = await loadAppSettings();
  applyAppSettings(appSettings);

  // 앱 시작
  startApp();
}

async function checkAppVersion() {
  const platform = Platform.isIOS ? 'ios' : 'android';
  const currentVersion = await getAppVersion();

  const response = await fetch(
    `${API_BASE_URL}/v1/app-config/version?platform=${platform}&current_version=${currentVersion}`
  );

  return await response.json();
}

async function loadAdConfigs() {
  const platform = Platform.isIOS ? 'ios' : 'android';

  const response = await fetch(
    `${API_BASE_URL}/v1/app-config/ads?platform=${platform}`
  );

  return await response.json();
}

async function loadAppSettings() {
  const response = await fetch(
    `${API_BASE_URL}/v1/app-config/settings`
  );

  return await response.json();
}
```

### 6.2 광고 폭포수(Waterfall) 초기화

```javascript
function initializeAdNetworks(adConfigs) {
  // 우선순위 순으로 정렬됨 (서버에서 이미 정렬됨)
  adConfigs.forEach((config, index) => {
    switch (config.ad_network) {
      case 'admob':
        initializeAdMob(config.ad_unit_ids, index);
        break;
      case 'applovin':
        initializeAppLovin(config.ad_unit_ids, index);
        break;
      case 'unity':
        initializeUnity(config.ad_unit_ids, index);
        break;
    }
  });
}
```

### 6.3 기능 플래그 확인

```javascript
async function checkFeatureFlag(featureName) {
  const response = await fetch(
    `${API_BASE_URL}/v1/app-config/settings/feature_flags`
  );

  const setting = await response.json();
  return setting.value[featureName] === true;
}

// 사용 예시
if (await checkFeatureFlag('new_ui')) {
  renderNewUI();
} else {
  renderOldUI();
}
```

### 6.4 점검 모드 확인

```javascript
async function checkMaintenanceMode() {
  const response = await fetch(
    `${API_BASE_URL}/v1/app-config/settings/maintenance_mode`
  );

  const setting = await response.json();

  if (setting.value.enabled) {
    showMaintenanceScreen(setting.value.message);
    return true;
  }

  return false;
}
```

---

## 7. Rate Limiting

현재 Rate Limiting은 적용되지 않았으나, 향후 다음과 같이 적용될 수 있습니다:

**제한**:
- 분당 100 요청
- IP 기반 제한

**초과 시 응답**:

```json
{
  "detail": "Rate limit exceeded. Please try again later.",
  "retry_after": 60
}
```

**Status Code**: `429 Too Many Requests`

---

## 8. CORS 정책

**허용 출처**: 설정에 따라 다름 (기본값: 모든 출처 허용)

**허용 메서드**: `GET`, `POST`, `PUT`, `DELETE`, `OPTIONS`

**허용 헤더**: `Content-Type`, `Authorization`, `X-Requested-With`

---

## 9. 버전 관리

### API 버전

현재 API 버전: `v1`

모든 엔드포인트는 `/v1/` 접두사를 사용합니다.

### 변경 이력

| Version | Date | Changes |
|---------|------|---------|
| v1.0.0 | 2024-11-15 | 초기 릴리스 |

---

## 10. 지원 및 문의

### Swagger UI

대화형 API 문서는 다음 URL에서 확인할 수 있습니다:

```
http://localhost:8000/v1/docs
```

### 관련 문서

- [앱 버전 체크 가이드](../reports/APP_VERSION_CHECK_GUIDE.md)
- [Django Ninja 공식 문서](https://django-ninja.dev)

### 문제 보고

API 사용 중 문제가 발생하면 다음 정보를 포함하여 보고해주세요:
1. 요청 URL
2. 요청 파라미터
3. 응답 상태 코드
4. 에러 메시지
5. 재현 단계
