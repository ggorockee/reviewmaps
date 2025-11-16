# ReviewMaps API 문서

## 📋 목차
- [인증 API](#인증-api)
- [키워드 알람 API](#키워드-알람-api)
- [캠페인 API](#캠페인-api)
- [카테고리 API](#카테고리-api)
- [앱 설정 API](#앱-설정-api)

---

## 인증 API

### 1. 회원가입
**Endpoint**: `POST /v1/auth/signup`

**Request Body**:
```json
{
  "email": "user@example.com",
  "password": "password123"
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "bearer"
}
```

**Error Response**:
- `400`: "이미 가입된 이메일입니다."

---

### 2. 로그인
**Endpoint**: `POST /v1/auth/login`

**Request Body**:
```json
{
  "email": "user@example.com",
  "password": "password123"
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "bearer"
}
```

**Error Response**:
- `401`: "로그인 정보가 올바르지 않습니다."
- `403`: "이용이 정지된 계정입니다."

---

### 3. 토큰 갱신
**Endpoint**: `POST /v1/auth/refresh`

**Request Body**:
```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIs..."
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "bearer"
}
```

**Error Response**:
- `401`: "유효하지 않은 토큰입니다."
- `401`: "회원 정보를 찾을 수 없습니다."

---

### 4. 회원가입 없이 시작하기 (익명 세션)
**Endpoint**: `POST /v1/auth/anonymous`

**Request Body** (선택사항):
```json
{
  "expire_hours": 168
}
```

**Response** (200 OK):
```json
{
  "session_token": "eyJhbGciOiJIUzI1NiIs...",
  "expires_at": "2025-01-23T12:00:00Z",
  "expire_hours": 168
}
```

**설명**:
- `expire_hours`: 세션 만료 시간 (시간 단위). 생략 시 기본값 168시간(7일) 사용
- 익명 세션은 회원가입 없이 앱을 사용할 수 있는 임시 계정

---

### 5. 익명 사용자 → 회원 전환
**Endpoint**: `POST /v1/auth/convert-anonymous`

**Request Body**:
```json
{
  "session_token": "eyJhbGciOiJIUzI1NiIs...",
  "email": "user@example.com",
  "password": "password123"
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "bearer"
}
```

**Error Response**:
- `401`: "유효하지 않은 세션입니다."
- `400`: "이미 가입된 이메일입니다."

**설명**:
- 익명 사용자의 데이터(키워드 알람 등)가 자동으로 회원 계정으로 마이그레이션됩니다.

---

### 6. 내 정보 조회
**Endpoint**: `GET /v1/auth/me`

**Headers**:
```
Authorization: Bearer {access_token 또는 session_token}
```

**Response (일반 사용자)** (200 OK):
```json
{
  "id": 1,
  "email": "user@example.com",
  "is_active": true,
  "date_joined": "2025-01-16T12:00:00Z",
  "login_method": "email"
}
```

**Response (익명 사용자)** (200 OK):
```json
{
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "expires_at": "2025-01-23T12:00:00Z",
  "remaining_hours": 167.5
}
```

**Error Response**:
- `401`: "로그인이 필요합니다."
- `401`: "유효하지 않은 토큰입니다."

**설명**:
- `login_method`: 로그인 방식 (`email`, `google`, `apple`, `kakao`, `naver`)
- `remaining_hours`: 익명 세션 남은 시간 (소수점 2자리)

---

## 키워드 알람 API

### 1. 관심 키워드 등록
**Endpoint**: `POST /v1/keyword-alerts/keywords`

**Headers**:
```
Authorization: Bearer {token}
```

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
  "created_at": "2025-01-16T12:00:00Z"
}
```

**Error Response**:
- `400`: "이미 등록된 키워드입니다."
- `401`: "로그인이 필요합니다."

---

### 2. 내 키워드 목록 조회
**Endpoint**: `GET /v1/keyword-alerts/keywords`

**Headers**:
```
Authorization: Bearer {token}
```

**Response** (200 OK):
```json
{
  "keywords": [
    {
      "id": 1,
      "keyword": "헬스장",
      "is_active": true,
      "created_at": "2025-01-16T12:00:00Z"
    },
    {
      "id": 2,
      "keyword": "PT",
      "is_active": true,
      "created_at": "2025-01-16T11:00:00Z"
    }
  ]
}
```

---

### 3. 키워드 삭제
**Endpoint**: `DELETE /v1/keyword-alerts/keywords/{keyword_id}`

**Headers**:
```
Authorization: Bearer {token}
```

**Response** (200 OK):
```json
{
  "message": "삭제되었습니다."
}
```

**Error Response**:
- `404`: "키워드를 찾을 수 없습니다."

---

### 4. 내 알람 목록 조회
**Endpoint**: `GET /v1/keyword-alerts/alerts`

**Headers**:
```
Authorization: Bearer {token}
```

**Query Parameters**:
- `is_read` (optional): `true` | `false` - 읽음/안읽음 필터

**Response** (200 OK):
```json
{
  "alerts": [
    {
      "id": 1,
      "keyword": "헬스장",
      "campaign_id": 123,
      "campaign_title": "○○ 헬스장 방문 리뷰 작성 이벤트",
      "matched_field": "title",
      "is_read": false,
      "created_at": "2025-01-16T12:00:00Z"
    }
  ],
  "unread_count": 5
}
```

---

### 5. 알람 읽음 처리
**Endpoint**: `POST /v1/keyword-alerts/alerts/read`

**Headers**:
```
Authorization: Bearer {token}
```

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

## 캠페인 API

### 1. 캠페인 목록 조회
**Endpoint**: `GET /v1/campaigns`

**Query Parameters**:
- `category_id` (optional): 카테고리 ID 필터
- `lat` (optional): 위도 (거리 정렬 시 필수)
- `lng` (optional): 경도 (거리 정렬 시 필수)
- `sort` (optional): 정렬 방식 (`created_at`, `apply_deadline`, `distance`)
- `order` (optional): 정렬 순서 (`asc`, `desc`)

**Response** (200 OK):
```json
{
  "campaigns": [
    {
      "id": 1,
      "title": "캠페인 제목",
      "category": "음식점",
      "location": "서울시 강남구",
      "promotion_level": 2,
      "apply_deadline": "2025-02-01T23:59:59Z",
      "is_new": true,
      "distance": 1.5
    }
  ],
  "total_count": 100
}
```

---

### 2. 캠페인 상세 조회
**Endpoint**: `GET /v1/campaigns/{campaign_id}`

**Response** (200 OK):
```json
{
  "id": 1,
  "title": "캠페인 제목",
  "description": "캠페인 설명",
  "category": "음식점",
  "location": "서울시 강남구",
  "offer": "제공 내역",
  "promotion_level": 2,
  "apply_deadline": "2025-02-01T23:59:59Z",
  "created_at": "2025-01-16T12:00:00Z"
}
```

**Error Response**:
- `404`: "캠페인을 찾을 수 없습니다."

---

## 카테고리 API

### 1. 카테고리 목록 조회
**Endpoint**: `GET /v1/categories`

**Response** (200 OK):
```json
[
  {
    "id": 1,
    "name": "음식점",
    "display_order": 1,
    "created_at": "2025-01-16T12:00:00Z"
  },
  {
    "id": 2,
    "name": "카페/디저트",
    "display_order": 2,
    "created_at": "2025-01-16T12:00:00Z"
  }
]
```

---

## 앱 설정 API

### 1. 광고 설정 조회
**Endpoint**: `GET /v1/app-config/ads`

**Query Parameters**:
- `platform` (required): `android` | `ios`

**Response** (200 OK):
```json
[
  {
    "id": 1,
    "ad_network": "admob",
    "unit_id": "ca-app-pub-xxx",
    "priority": 1,
    "is_enabled": true
  }
]
```

---

### 2. 버전 체크
**Endpoint**: `GET /v1/app-config/version`

**Query Parameters**:
- `platform` (required): `android` | `ios`
- `current_version` (required): 현재 앱 버전 (예: `1.0.0`)

**Response** (200 OK):
```json
{
  "latest_version": "1.2.0",
  "force_update": false,
  "update_message": "새로운 버전이 출시되었습니다.",
  "store_url": "https://play.google.com/store/apps/..."
}
```

---

### 3. 앱 설정 조회
**Endpoint**: `GET /v1/app-config/settings`

**Response** (200 OK):
```json
[
  {
    "key": "maintenance_mode",
    "value": "false",
    "description": "점검 모드 활성화 여부"
  }
]
```

---

### 4. 특정 설정 조회
**Endpoint**: `GET /v1/app-config/settings/{key}`

**Response** (200 OK):
```json
{
  "key": "maintenance_mode",
  "value": "false",
  "description": "점검 모드 활성화 여부"
}
```

**Error Response**:
- `404`: "설정을 찾을 수 없습니다."

---

## 공통 에러 코드

| 상태 코드 | 설명 |
|---------|------|
| 400 | 잘못된 요청 (유효성 검증 실패 등) |
| 401 | 인증 실패 (토큰 없음, 만료, 유효하지 않음) |
| 403 | 권한 없음 (계정 정지 등) |
| 404 | 리소스를 찾을 수 없음 |
| 500 | 서버 오류 |

---

## 인증 방식

모든 보호된 API는 `Authorization` 헤더에 Bearer 토큰을 포함해야 합니다:

```
Authorization: Bearer {access_token}
```

또는 익명 사용자의 경우:

```
Authorization: Bearer {session_token}
```

---

## 페이지네이션

일부 API는 페이지네이션을 지원합니다 (추후 추가 예정):

**Query Parameters**:
- `page`: 페이지 번호 (기본값: 1)
- `page_size`: 페이지 크기 (기본값: 20, 최대: 100)

**Response**:
```json
{
  "results": [...],
  "total_count": 100,
  "page": 1,
  "page_size": 20
}
```
