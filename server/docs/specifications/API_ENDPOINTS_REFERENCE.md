# ReviewMaps API 엔드포인트 레퍼런스

## 개요

**Base URL**: `https://api.example.com`
**API Version**: `v1`
**Protocol**: HTTPS
**Content-Type**: `application/json`

---

## 목차

1. [인증 (Authentication)](#1-인증-authentication)
2. [SNS 로그인](#2-sns-로그인)
3. [사용자 정보 (본인)](#3-사용자-정보-본인)
4. [키워드 알람](#4-키워드-알람)
5. [캠페인](#5-캠페인)
6. [카테고리](#6-카테고리)
7. [앱 설정](#7-앱-설정)
8. [헬스체크](#8-헬스체크)
9. [인증 방식](#9-인증-방식)
10. [에러 코드](#10-에러-코드)

---

## 1. 인증 (Authentication)

### 1.1 회원가입

**POST** `/v1/auth/signup`

이메일과 비밀번호로 회원가입합니다.

**Request Body**:
```json
{
  "email": "user@example.com",
  "password": "securePassword123"
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "bearer"
}
```

**Error Responses**:
- `400`: 이미 가입된 이메일입니다.

---

### 1.2 로그인

**POST** `/v1/auth/login`

이메일과 비밀번호로 로그인합니다.

**Request Body**:
```json
{
  "email": "user@example.com",
  "password": "securePassword123"
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "bearer"
}
```

**Error Responses**:
- `401`: 로그인 정보가 올바르지 않습니다.
- `403`: 이용이 정지된 계정입니다.

---

### 1.3 토큰 갱신

**POST** `/v1/auth/refresh`

Refresh token으로 새로운 access token을 발급받습니다.

**Request Body**:
```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "bearer"
}
```

**Error Responses**:
- `401`: 유효하지 않은 토큰입니다.

---

### 1.4 익명 세션 생성

**POST** `/v1/auth/anonymous`

회원가입 없이 앱 사용을 시작합니다. 기본 7일 유효기간의 세션 토큰을 발급합니다.

**Request Body** (Optional):
```json
{
  "expire_hours": 168
}
```

**Response** (200 OK):
```json
{
  "session_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_at": "2024-11-22T10:30:00Z",
  "expire_hours": 168
}
```

---

### 1.5 익명 사용자 → 회원 전환

**POST** `/v1/auth/convert-anonymous`

익명 사용자를 정식 회원으로 전환하며, 기존 익명 사용자 데이터(키워드 알람 등)를 유지합니다.

**Request Body**:
```json
{
  "session_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "email": "user@example.com",
  "password": "securePassword123"
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "bearer"
}
```

**Error Responses**:
- `401`: 유효하지 않은 세션입니다.
- `400`: 이미 가입된 이메일입니다.

---

### 1.6 내 정보 조회 (Deprecated)

**GET** `/v1/auth/me`

⚠️ **Deprecated**: `/v1/users/me` 사용 권장

**Headers**:
- `Authorization: Bearer {token}`

**Response** (200 OK - 일반 사용자):
```json
{
  "id": 1,
  "email": "user@example.com",
  "is_active": true,
  "date_joined": "2024-11-15T10:30:00Z",
  "login_method": "email"
}
```

**Response** (200 OK - 익명 사용자):
```json
{
  "session_id": "abc123xyz",
  "expires_at": "2024-11-22T10:30:00Z",
  "remaining_hours": 167.5
}
```

---

## 2. SNS 로그인

### 2.1 Kakao 로그인

**POST** `/v1/auth/kakao`

Kakao SDK에서 받은 액세스 토큰을 검증하고 로그인 처리합니다.

**Request Body**:
```json
{
  "access_token": "kakao_access_token_here"
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "bearer",
  "user": {
    "id": 1,
    "email": "user@kakao.com",
    "is_active": true,
    "date_joined": "2024-11-15T10:30:00Z",
    "login_method": "kakao"
  }
}
```

**Error Responses**:
- `401`: Kakao 토큰 검증에 실패했습니다.
- `400`: Kakao 계정에 이메일이 없습니다. 이메일 제공 동의가 필요합니다.

---

### 2.2 Google 로그인

**POST** `/v1/auth/google`

Google SDK에서 받은 액세스 토큰을 검증하고 로그인 처리합니다.

**Request Body**:
```json
{
  "access_token": "google_access_token_here"
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "bearer",
  "user": {
    "id": 2,
    "email": "user@gmail.com",
    "is_active": true,
    "date_joined": "2024-11-15T10:30:00Z",
    "login_method": "google"
  }
}
```

---

### 2.3 Apple 로그인

**POST** `/v1/auth/apple`

Apple Sign In에서 받은 identity token을 검증하고 로그인 처리합니다.

**Request Body**:
```json
{
  "identity_token": "apple_identity_token_here",
  "authorization_code": "apple_authorization_code_here"
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "bearer",
  "user": {
    "id": 3,
    "email": "user@privaterelay.appleid.com",
    "is_active": true,
    "date_joined": "2024-11-15T10:30:00Z",
    "login_method": "apple"
  }
}
```

---

## 3. 사용자 정보 (본인)

### 3.1 내 정보 조회

**GET** `/v1/users/me`

로그인한 사용자 본인의 정보를 조회합니다. 연결된 SNS 계정 정보 포함.

**Headers**:
- `Authorization: Bearer {jwt_token}` (필수)

**Response** (200 OK):
```json
{
  "id": 1,
  "email": "user@example.com",
  "is_active": true,
  "date_joined": "2024-11-15T10:30:00Z",
  "login_method": "kakao",
  "social_accounts": [
    {
      "provider": "kakao",
      "email": "user@kakao.com",
      "connected_at": "2024-11-15T10:30:00Z"
    }
  ]
}
```

---

### 3.2 내 정보 수정

**PATCH** `/v1/users/me`

로그인한 사용자 본인의 정보를 수정합니다. (현재는 수정 가능한 필드 없음, 향후 확장 가능)

**Headers**:
- `Authorization: Bearer {jwt_token}` (필수)

**Request Body**:
```json
{}
```

**Response** (200 OK):
```json
{
  "id": 1,
  "email": "user@example.com",
  "is_active": true,
  "date_joined": "2024-11-15T10:30:00Z",
  "login_method": "email",
  "social_accounts": []
}
```

---

## 4. 키워드 알람

### 4.1 키워드 등록

**POST** `/v1/keyword-alerts/keywords`

관심 키워드를 등록합니다. 활성 키워드 개수 제한이 적용됩니다.

**Headers**:
- `Authorization: Bearer {token}` (JWT 또는 익명 세션 토큰)

**Request Body**:
```json
{
  "keyword": "헬스장"
}
```

**Response** (200 OK):
```json
{
  "id": 1,
  "keyword": "헬스장",
  "is_active": true,
  "created_at": "2024-11-15T10:30:00Z"
}
```

**Error Responses**:
- `400`: 활성 키워드는 최대 20개까지 등록할 수 있습니다.
- `400`: 이미 등록된 키워드입니다.

---

### 4.2 키워드 목록 조회

**GET** `/v1/keyword-alerts/keywords`

등록한 모든 활성 키워드 목록을 조회합니다.

**Headers**:
- `Authorization: Bearer {token}`

**Response** (200 OK):
```json
{
  "keywords": [
    {
      "id": 1,
      "keyword": "헬스장",
      "is_active": true,
      "created_at": "2024-11-15T10:30:00Z"
    },
    {
      "id": 2,
      "keyword": "PT",
      "is_active": true,
      "created_at": "2024-11-15T09:30:00Z"
    }
  ]
}
```

---

### 4.3 키워드 삭제

**DELETE** `/v1/keyword-alerts/keywords/{keyword_id}`

특정 키워드를 삭제합니다 (soft delete).

**Headers**:
- `Authorization: Bearer {token}`

**Response** (200 OK):
```json
{
  "message": "삭제되었습니다."
}
```

**Error Responses**:
- `404`: 키워드를 찾을 수 없습니다.

---

### 4.4 키워드 활성화/비활성화 토글

**PATCH** `/v1/keyword-alerts/keywords/{keyword_id}/toggle`

키워드의 활성화 상태를 토글합니다.

**Headers**:
- `Authorization: Bearer {token}`

**Response** (200 OK):
```json
{
  "id": 1,
  "keyword": "헬스장",
  "is_active": false,
  "created_at": "2024-11-15T10:30:00Z"
}
```

---

### 4.5 알람 목록 조회

**GET** `/v1/keyword-alerts/alerts`

키워드와 매칭된 캠페인 알람 목록을 조회합니다.

**Headers**:
- `Authorization: Bearer {token}`

**Query Parameters**:
- `is_read` (optional, boolean): 읽음/안읽음 필터

**Response** (200 OK):
```json
{
  "alerts": [
    {
      "id": 1,
      "keyword": "헬스장",
      "campaign_id": 123,
      "campaign_title": "헬스장 무료 PT 10회 제공",
      "matched_field": "offer",
      "is_read": false,
      "created_at": "2024-11-15T10:30:00Z"
    }
  ],
  "unread_count": 5
}
```

---

### 4.6 알람 읽음 처리

**POST** `/v1/keyword-alerts/alerts/read`

여러 알람을 한번에 읽음 처리합니다.

**Headers**:
- `Authorization: Bearer {token}`

**Request Body**:
```json
{
  "alert_ids": [1, 2, 3]
}
```

**Response** (200 OK):
```json
{
  "message": "3개의 알람을 읽음 처리했습니다.",
  "updated_count": 3
}
```

---

## 5. 캠페인

### 5.1 캠페인 목록 조회

**GET** `/v1/campaigns/`

캠페인 목록을 조회합니다. 다양한 필터와 정렬 옵션을 제공합니다.

**Query Parameters**:

| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| region | string | 지역 필터 | `서울` |
| offer | string | 오퍼 텍스트 검색 | `무료` |
| campaign_type | string | 캠페인 유형 필터 | `방문형` |
| campaign_channel | string | 캠페인 채널 필터 | `블로그` |
| category_id | integer | 카테고리 ID | `1` |
| q | string | 통합 검색 (회사/오퍼/플랫폼) | `헬스` |
| platform | string | 플랫폼 필터 | `리뷰왕` |
| company | string | 회사명 검색 | `ABC헬스` |
| sw_lat | float | 바운딩 박스 남서 위도 | `37.4` |
| sw_lng | float | 바운딩 박스 남서 경도 | `127.0` |
| ne_lat | float | 바운딩 박스 북동 위도 | `37.6` |
| ne_lng | float | 바운딩 박스 북동 경도 | `127.2` |
| lat | float | 사용자 위도 (거리 계산용) | `37.5` |
| lng | float | 사용자 경도 (거리 계산용) | `127.1` |
| sort | string | 정렬 키 | `-created_at`, `distance` |
| limit | integer | 페이지당 항목 수 (1-200) | `20` |
| offset | integer | 오프셋 | `0` |

**Response** (200 OK):
```json
{
  "items": [
    {
      "id": 1,
      "title": "헬스장 무료 PT 10회 제공",
      "company": "ABC헬스클럽",
      "offer": "무료 PT 10회, 3개월 회원권 50% 할인",
      "region": "서울 강남구",
      "campaign_type": "방문형",
      "campaign_channel": "블로그",
      "platform": "리뷰왕",
      "lat": "37.5",
      "lng": "127.1",
      "category": {
        "id": 1,
        "name": "헬스/피트니스"
      },
      "apply_deadline": "2024-12-31T23:59:59Z",
      "promotion_level": 5,
      "created_at": "2024-11-15T10:30:00Z",
      "distance": 1.5
    }
  ],
  "total": 100,
  "limit": 20,
  "offset": 0
}
```

**정렬 우선순위**:
1. `promotion_level` (내림차순) - 프로모션 레벨 높은 순
2. `distance` (오름차순, sort=distance일 때) - 가까운 순
3. Pseudo-random (동일 레벨 내 균형 분포)
4. 사용자 지정 정렬 (`created_at`, `apply_deadline` 등)

---

## 6. 카테고리

### 6.1 카테고리 목록 조회

**GET** `/v1/categories/`

모든 표준 카테고리 목록을 조회합니다.

**Response** (200 OK):
```json
[
  {
    "id": 1,
    "name": "헬스/피트니스",
    "display_order": 1,
    "created_at": "2024-11-15T10:30:00Z"
  },
  {
    "id": 2,
    "name": "음식점",
    "display_order": 2,
    "created_at": "2024-11-15T10:30:00Z"
  }
]
```

---

### 6.2 카테고리 생성

**POST** `/v1/categories/`

새로운 표준 카테고리를 생성합니다.

**Request Body**:
```json
{
  "name": "카페",
  "display_order": 3
}
```

**Response** (201 Created):
```json
{
  "id": 3,
  "name": "카페",
  "display_order": 3,
  "created_at": "2024-11-15T10:30:00Z"
}
```

**Error Responses**:
- `409`: Category with this name already exists

---

### 6.3 카테고리 상세 조회

**GET** `/v1/categories/{category_id}`

특정 카테고리의 상세 정보를 조회합니다.

**Response** (200 OK):
```json
{
  "id": 1,
  "name": "헬스/피트니스",
  "display_order": 1,
  "created_at": "2024-11-15T10:30:00Z"
}
```

---

### 6.4 카테고리 수정

**PUT** `/v1/categories/{category_id}`

특정 카테고리를 수정합니다.

**Request Body**:
```json
{
  "name": "헬스/피트니스/요가",
  "display_order": 1
}
```

**Response** (200 OK):
```json
{
  "id": 1,
  "name": "헬스/피트니스/요가",
  "display_order": 1,
  "created_at": "2024-11-15T10:30:00Z"
}
```

---

### 6.5 카테고리 삭제

**DELETE** `/v1/categories/{category_id}`

특정 카테고리를 삭제합니다.

**Response** (204 No Content)

**Error Responses**:
- `404`: Category not found
- `400`: Cannot delete category. It is being used by campaigns or mappings.

---

### 6.6 카테고리 순서 업데이트

**PUT** `/v1/categories/order`

모든 카테고리의 display_order를 일괄 업데이트합니다.

**Request Body**:
```json
{
  "ordered_ids": [3, 1, 2]
}
```

**Response** (204 No Content)

**Error Responses**:
- `400`: Provided ID list does not match the existing categories.

---

### 6.7 매핑되지 않은 원본 카테고리 조회

**GET** `/v1/categories/unmapped-categories`

매핑되지 않은 원본 카테고리 목록을 조회합니다.

**Response** (200 OK):
```json
[
  {
    "id": 1,
    "name": "피트니스센터",
    "created_at": "2024-11-15T10:30:00Z"
  }
]
```

---

### 6.8 카테고리 매핑 생성

**POST** `/v1/categories/category-mappings`

원본 카테고리를 표준 카테고리에 매핑합니다.

**Request Body**:
```json
{
  "raw_category_id": 1,
  "standard_category_id": 1
}
```

**Response** (200 OK):
```json
{
  "id": 1,
  "raw_category": {
    "id": 1,
    "name": "피트니스센터"
  },
  "standard_category": {
    "id": 1,
    "name": "헬스/피트니스"
  },
  "created_at": "2024-11-15T10:30:00Z"
}
```

---

## 7. 앱 설정

### 7.1 버전 체크

**GET** `/v1/app-config/version`

앱 버전을 체크하고 업데이트 필요 여부를 확인합니다.

**Query Parameters**:
- `platform` (required): `ios` 또는 `android`
- `current_version` (required): 현재 앱 버전 (예: `1.4.0`)

**Response** (200 OK):
```json
{
  "needs_update": true,
  "force_update": false,
  "latest_version": "1.4.1",
  "message": "새로운 기능이 추가되었습니다.",
  "store_url": "https://apps.apple.com/app/id123456789"
}
```

---

### 7.2 광고 설정 조회

**GET** `/v1/app-config/ads`

플랫폼별 활성화된 광고 네트워크 설정을 조회합니다.

**Query Parameters**:
- `platform` (required): `ios` 또는 `android`

**Response** (200 OK):
```json
[
  {
    "id": 1,
    "platform": "android",
    "ad_network": "admob",
    "is_enabled": true,
    "ad_unit_ids": {
      "banner_id": "ca-app-pub-xxx",
      "interstitial_id": "ca-app-pub-yyy"
    },
    "priority": 10,
    "created_at": "2024-11-15T10:30:00Z",
    "updated_at": "2024-11-15T10:30:00Z"
  }
]
```

---

### 7.3 전체 앱 설정 조회

**GET** `/v1/app-config/settings`

모든 활성화된 앱 설정을 조회합니다.

**Response** (200 OK):
```json
[
  {
    "id": 1,
    "key": "feature_flags",
    "value": {
      "new_ui": true,
      "beta_feature": false
    },
    "description": "기능 플래그 설정",
    "is_active": true,
    "created_at": "2024-11-15T10:30:00Z",
    "updated_at": "2024-11-15T10:30:00Z"
  }
]
```

---

### 7.4 키워드 제한 설정 조회

**GET** `/v1/app-config/settings/keyword-limit`

키워드 등록 개수 제한 설정을 조회합니다.

**Response** (200 OK):
```json
{
  "max_active_keywords": 20,
  "max_inactive_keywords": 0,
  "total_keywords": 20
}
```

---

### 7.5 키워드 제한 설정 업데이트

**PUT** `/v1/app-config/settings/keyword-limit`

키워드 등록 개수 제한을 설정합니다.

**Request Body**:
```json
{
  "max_active_keywords": 30,
  "max_inactive_keywords": 10
}
```

**Response** (200 OK):
```json
{
  "max_active_keywords": 30,
  "max_inactive_keywords": 10,
  "total_keywords": 40
}
```

**Error Responses**:
- `404`: 활성 키워드 최대 개수는 최소 1개 이상이어야 합니다.
- `404`: 비활성 키워드 최대 개수는 0개 이상이어야 합니다.

---

### 7.6 특정 설정 조회

**GET** `/v1/app-config/settings/{key}`

특정 키의 앱 설정을 조회합니다.

**Response** (200 OK):
```json
{
  "id": 1,
  "key": "feature_flags",
  "value": {
    "new_ui": true,
    "beta_feature": false
  },
  "description": "기능 플래그 설정",
  "is_active": true,
  "created_at": "2024-11-15T10:30:00Z",
  "updated_at": "2024-11-15T10:30:00Z"
}
```

---

## 8. 헬스체크

### 8.1 헬스체크

**GET** `/v1/healthz`

서버 상태를 확인합니다.

**Response** (200 OK):
```json
{
  "status": "healthy",
  "service": "reviewmaps-server",
  "version": "1.0.0"
}
```

---

## 9. 인증 방식

### JWT Bearer Token

대부분의 API는 JWT Bearer Token 인증을 사용합니다.

**헤더 예시**:
```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### 익명 세션 토큰

익명 사용자는 세션 토큰을 사용합니다.

**헤더 예시**:
```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### 인증이 필요한 API

- `/v1/users/me` (GET, PATCH)
- `/v1/keyword-alerts/*` (모든 엔드포인트)

### 인증이 불필요한 API

- `/v1/auth/*` (인증 관련 API)
- `/v1/campaigns/*` (캠페인 조회)
- `/v1/categories/*` (카테고리 조회)
- `/v1/app-config/*` (앱 설정 조회)
- `/v1/healthz` (헬스체크)

---

## 10. 에러 코드

### HTTP Status Codes

| Code | Meaning | Description |
|------|---------|-------------|
| 200 | OK | 요청 성공 |
| 201 | Created | 리소스 생성 성공 |
| 204 | No Content | 요청 성공 (응답 본문 없음) |
| 400 | Bad Request | 잘못된 요청 |
| 401 | Unauthorized | 인증 실패 |
| 403 | Forbidden | 권한 없음 |
| 404 | Not Found | 리소스 없음 |
| 409 | Conflict | 리소스 충돌 (중복 등) |
| 422 | Unprocessable Entity | 유효성 검증 실패 |
| 500 | Internal Server Error | 서버 오류 |

### 에러 응답 형식

**일반 에러**:
```json
{
  "detail": "에러 메시지"
}
```

**유효성 검증 에러**:
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

## 11. 페이지네이션

캠페인 목록 등 대량 데이터는 페이지네이션을 지원합니다.

**Query Parameters**:
- `limit`: 페이지당 항목 수 (기본값: 20, 최대: 200)
- `offset`: 시작 위치 (기본값: 0)

**Response 구조**:
```json
{
  "items": [...],
  "total": 100,
  "limit": 20,
  "offset": 0
}
```

---

## 12. 날짜/시간 형식

모든 날짜/시간은 **ISO 8601 형식 (UTC)**을 사용합니다.

**형식**: `YYYY-MM-DDTHH:mm:ssZ`

**예시**:
- `2024-11-15T10:30:00Z`
- `2024-11-15T10:30:00.123456Z`

---

## 13. Swagger UI

대화형 API 문서는 다음 URL에서 확인할 수 있습니다:

```
https://api.example.com/v1/docs
```

---

## 14. 변경 이력

| Version | Date | Changes |
|---------|------|---------|
| v1.0.0 | 2024-11-15 | 초기 릴리스 |
| v1.1.0 | 2024-11-16 | 키워드 제한 설정 API 추가 |

---

## 15. 지원 및 문의

### 관련 문서
- [앱 버전 체크 가이드](../reports/APP_VERSION_CHECK_GUIDE.md)
- [앱 설정 API 명세](APP_CONFIG_API_SPEC.md)

### API 사용 예시

**Flutter**:
```dart
final response = await http.get(
  Uri.parse('https://api.example.com/v1/campaigns/'),
  headers: {
    'Authorization': 'Bearer $accessToken',
    'Content-Type': 'application/json',
  },
);
```

**JavaScript**:
```javascript
const response = await fetch('https://api.example.com/v1/campaigns/', {
  headers: {
    'Authorization': `Bearer ${accessToken}`,
    'Content-Type': 'application/json',
  },
});
```

**cURL**:
```bash
curl -X GET "https://api.example.com/v1/campaigns/" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json"
```
