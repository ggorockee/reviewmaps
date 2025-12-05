# Django → Go Fiber 마이그레이션 계획

## 1. 개요 (Overview)

### 1.1 현재 상태 (AS-IS)

| 구성요소 | 기술 스택 |
|---------|----------|
| Backend API | Django 5.2 + Django Ninja (async) |
| Admin | Django Admin (기본) |
| Database | PostgreSQL |
| ORM | Django ORM |
| Migration | Django migrations |
| 모니터링 | Prometheus + django_prometheus |
| 푸시 알림 | Firebase Admin SDK (Python) |

### 1.2 목표 상태 (TO-BE)

| 구성요소 | 기술 스택 |
|---------|----------|
| Backend API | Go Fiber + GORM |
| Admin | Django Admin (unfold 테마) |
| Database | PostgreSQL (동일) |
| ORM | GORM (AutoMigration) |
| Migration | GORM AutoMigration만 사용 |
| 모니터링 | SigNoz |
| 푸시 알림 | Firebase Admin SDK (Go) |
| 문서화 | Swagger (swaggo) |

### 1.3 핵심 제약사항

| 규칙 | 설명 |
|-----|------|
| API 엔드포인트 유지 | 모든 `/v1/*` 엔드포인트 경로 변경 금지 |
| Swagger 필수 | 모든 API에 Swagger 문서 자동 생성 |
| 관계 데이터 포함 | API 응답 시 연관 데이터 항상 포함 (Preload) |
| Migration 단일화 | Django migration 비활성화, GORM AutoMigration만 사용 |
| Admin-GORM 동기화 | Django Admin과 GORM 테이블 항상 연동 |
| Go routine 활용 | 병렬 처리 가능한 모든 작업에 goroutine 사용 |
| TDD 필수 | 테스트 코드 먼저 작성 후 구현 |

---

## 2. 아키텍처 변경 (Architecture Changes)

### 2.1 시스템 구조 변경

**AS-IS:** Mobile/Web → Django Ninja API → PostgreSQL ← Django Admin

**TO-BE:** Mobile/Web → Go Fiber API → PostgreSQL ← Django Admin (GORM AutoMigration 담당)
                    ↓
              SigNoz 모니터링

### 2.2 디렉토리 구조

| 디렉토리 | 설명 |
|---------|------|
| admin/ | Django Admin (Python 3.12 + uv) |
| admin/.venv/ | uv 가상환경 |
| admin/pyproject.toml | uv 의존성 |
| admin/config/ | Django 설정 (GORM 테이블 연동) |
| admin/users/ | 사용자 모델 (managed=False) + admin.py (unfold) |
| admin/campaigns/ | 캠페인 관리 |
| admin/keyword_alerts/ | 키워드 알람 관리 |
| admin/app_config/ | 앱 설정 관리 |
| server/ | Go Fiber API |
| server/cmd/api/ | main.go 엔트리포인트 |
| server/internal/config/ | 환경설정 |
| server/internal/database/ | GORM 연결 및 AutoMigration |
| server/internal/models/ | GORM 모델 |
| server/internal/handlers/ | HTTP 핸들러 |
| server/internal/services/ | 비즈니스 로직 |
| server/internal/middleware/ | 미들웨어 |
| server/pkg/firebase/ | FCM 서비스 |
| server/pkg/auth/ | JWT, SNS 인증 |
| server/docs/ | Swagger 생성 파일 |
| server/tests/ | 테스트 코드 |
| mobile/ | Flutter (변경 없음) |
| web/ | Next.js (변경 없음) |
| scrape/ | Python Scraper (변경 없음) |

### 2.3 컴포넌트 역할 분담

| 컴포넌트 | 역할 | 비고 |
|---------|-----|-----|
| Go Fiber Server | API 서비스, 비즈니스 로직 | 모든 API 요청 처리 |
| GORM | ORM, AutoMigration | 스키마 관리 주체 |
| Django Admin | 데이터 관리 UI | CRUD 전용, migration 없음 |
| SigNoz | 분산 추적, 메트릭, 로그 | OpenTelemetry 기반 |

---

## 3. 데이터베이스 마이그레이션 (Database Migration)

### 3.1 GORM 모델 설계 원칙

1. **테이블명 유지**: Django의 `db_table` 값 그대로 사용
2. **인덱스명 유지**: 기존 인덱스명 보존
3. **관계 설정**: `Preload`로 관계 데이터 자동 로드
4. **Soft Delete**: 필요한 모델에만 적용

### 3.2 모델 매핑 테이블 (운영 DB 기준)

**비즈니스 도메인 테이블**

| Django 모델 | GORM 모델 | 테이블명 | 설명 |
|------------|----------|---------|------|
| User | User | users | 사용자 |
| SocialAccount | SocialAccount | social_accounts | SNS 계정 연동 |
| EmailVerification | EmailVerification | email_verifications | 이메일 인증 |
| Category | Category | categories | 캠페인 카테고리 |
| Campaign | Campaign | campaign | 캠페인 |
| RawCategory | RawCategory | raw_categories | 원본 카테고리 |
| CategoryMapping | CategoryMapping | category_mappings | 카테고리 매핑 |
| FCMDevice | FCMDevice | keyword_alerts_fcm_devices | FCM 디바이스 토큰 |
| Keyword | Keyword | keyword_alerts_keywords | 관심 키워드 |
| KeywordAlert | KeywordAlert | keyword_alerts_alerts | 키워드 알람 |
| AdConfig | AdConfig | ad_configs | 광고 설정 |
| AppVersion | AppVersion | app_versions | 앱 버전 |
| AppSetting | AppSetting | app_settings | 앱 설정 |
| RateLimitConfig | RateLimitConfig | rate_limit_configs | Rate Limit 설정 |

**캐시 테이블**

| GORM 모델 | 테이블명 | 설명 |
|----------|---------|------|
| GeocodeCache | geocode_cache | 지오코딩 캐시 |
| LocalSearchCache | local_search_cache | 로컬 검색 캐시 |

**Django 내부 테이블 (Admin 전용)**

| 테이블명 | 설명 | GORM 관리 |
|---------|------|----------|
| auth_group | Django 그룹 | ❌ Django Admin 전용 |
| auth_group_permissions | 그룹 권한 | ❌ Django Admin 전용 |
| auth_permission | 권한 | ❌ Django Admin 전용 |
| django_admin_log | Admin 로그 | ❌ Django Admin 전용 |
| django_content_type | 콘텐츠 타입 | ❌ Django Admin 전용 |
| django_migrations | 마이그레이션 기록 | ❌ Django Admin 전용 |
| django_session | 세션 | ❌ Django Admin 전용 |
| users_groups | 사용자-그룹 M2M | ❌ Django Admin 전용 |
| users_user_permissions | 사용자-권한 M2M | ❌ Django Admin 전용 |

**시스템 테이블**

| 테이블명 | 설명 | 관리 주체 |
|---------|------|----------|
| spatial_ref_sys | PostGIS 좌표계 | PostgreSQL |

**중요:** GORM AutoMigration은 비즈니스 도메인 테이블과 캐시 테이블만 관리. Django 내부 테이블은 Django Admin이 자체 관리

### 3.3 GORM 모델 구조

**BaseModel (CoreModel 대체)**

| 필드 | GORM 태그 | 설명 |
|-----|----------|------|
| ID | primaryKey | 기본 키 |
| CreatedAt | autoCreateTime | 생성 시각 |
| UpdatedAt | autoUpdateTime | 수정 시각 |

**User 모델 필드 정의**

| 필드 | 타입 | GORM 태그 | 설명 |
|-----|-----|----------|------|
| ID | uint | primaryKey | 기본 키 |
| Username | string | uniqueIndex;size:255;not null | 사용자명 |
| Email | string | size:255;not null | 이메일 |
| Password | string | size:255 | 비밀번호 (JSON 제외) |
| LoginMethod | string | size:20;default:email | 로그인 방식 |
| Name | string | size:100 | 이름 |
| ProfileImage | string | size:500 | 프로필 이미지 URL |
| IsActive | bool | default:true | 활성 상태 |
| IsStaff | bool | default:false | 스태프 권한 |
| IsSuperuser | bool | default:false | 슈퍼유저 권한 |
| DateJoined | time.Time | autoCreateTime | 가입일시 |
| LastLogin | *time.Time | - | 마지막 로그인 |

**User 모델 관계**

| 관계 | 타입 | 외래키 |
|-----|-----|-------|
| SocialAccounts | []SocialAccount | UserID |
| FCMDevices | []FCMDevice | UserID |
| Keywords | []Keyword | UserID |

**Campaign 모델 필드 정의**

| 필드 | 타입 | GORM 태그 | 설명 |
|-----|-----|----------|------|
| ID | uint | primaryKey | 기본 키 |
| CategoryID | *uint | index:idx_cpg_category | 카테고리 FK |
| Platform | string | size:20;not null | 플랫폼 |
| Company | string | size:255;not null | 업체명 |
| CompanyLink | *string | type:text | 업체 링크 |
| Offer | string | type:text;not null | 제공 내용 |
| ApplyDeadline | *time.Time | index:idx_cpg_deadline | 신청 마감일 |
| ReviewDeadline | *time.Time | - | 리뷰 마감일 |
| ApplyFrom | *time.Time | - | 신청 시작일 |
| Address | *string | type:text | 주소 |
| Lat | *float64 | type:decimal(9,6) | 위도 |
| Lng | *float64 | type:decimal(9,6) | 경도 |
| ImgURL | *string | type:text | 이미지 URL |
| ContentLink | *string | type:text | 콘텐츠 링크 |
| SearchText | *string | size:20 | 검색 텍스트 |
| Source | *string | size:100 | 출처 |
| Title | *string | type:text | 제목 |
| CampaignType | *string | size:50;index:idx_cpg_type | 캠페인 유형 |
| Region | *string | size:100;index:idx_cpg_region | 지역 |
| CampaignChannel | *string | size:255 | 캠페인 채널 |
| PromotionLevel | int | default:0 | 프로모션 레벨 |
| CreatedAt | time.Time | autoCreateTime;index:idx_cpg_created,sort:desc | 생성일시 |
| UpdatedAt | time.Time | autoUpdateTime | 수정일시 |

### 3.4 복합 인덱스 설정

| 인덱스명 | 필드 | 용도 |
|---------|-----|-----|
| idx_cpg_promo_ddl_loc | promotion_level, apply_deadline, lat, lng | 추천 캠페인 조회 최적화 |
| idx_cpg_location_deadline | lat, lng, apply_deadline | 거리 기반 조회 최적화 |
| idx_cpg_promo_created | -promotion_level, -created_at | 프로모션 우선 정렬 |

### 3.5 Django Admin 연동

**핵심 설정:**
- 모든 모델에 `managed = False` 설정
- GORM이 생성한 테이블을 직접 참조
- `db_table`은 GORM 테이블명과 동일하게 유지

---

## 4. API 마이그레이션 (API Migration)

### 4.1 엔드포인트 매핑

| 메서드 | 엔드포인트 | 설명 |
|-------|-----------|-----|
| POST | /v1/auth/email/send-code | 이메일 인증코드 발송 |
| POST | /v1/auth/email/verify-code | 인증코드 확인 |
| POST | /v1/auth/signup | 회원가입 |
| POST | /v1/auth/login | 로그인 |
| POST | /v1/auth/refresh | 토큰 갱신 |
| POST | /v1/auth/anonymous | 익명 세션 |
| POST | /v1/auth/kakao | Kakao 로그인 |
| POST | /v1/auth/google | Google 로그인 |
| POST | /v1/auth/apple | Apple 로그인 |
| GET | /v1/users/me | 내 정보 조회 |
| PUT | /v1/users/me | 정보 수정 |
| DELETE | /v1/users/me | 회원 탈퇴 |
| GET | /v1/campaigns | 캠페인 목록 |
| GET | /v1/campaigns/:id | 캠페인 상세 |
| GET | /v1/categories | 카테고리 목록 |
| POST | /v1/keyword-alerts/keywords | 키워드 등록 |
| GET | /v1/keyword-alerts/keywords | 키워드 목록 |
| DELETE | /v1/keyword-alerts/keywords/:id | 키워드 삭제 |
| PATCH | /v1/keyword-alerts/keywords/:id/toggle | 키워드 토글 |
| GET | /v1/keyword-alerts/alerts | 알람 목록 |
| POST | /v1/keyword-alerts/alerts/read | 알람 읽음 처리 |
| DELETE | /v1/keyword-alerts/alerts/:id | 알람 삭제 |
| POST | /v1/keyword-alerts/fcm/register | FCM 등록 |
| DELETE | /v1/keyword-alerts/fcm/unregister | FCM 해제 |
| GET | /v1/app-config/ads | 광고 설정 |
| GET | /v1/app-config/version | 버전 체크 |
| GET | /v1/app-config/settings | 앱 설정 목록 |
| GET | /v1/app-config/settings/:key | 특정 설정 조회 |
| GET | /v1/app-config/settings/keyword-limit | 키워드 제한 조회 |
| PUT | /v1/app-config/settings/keyword-limit | 키워드 제한 설정 |
| GET | /v1/healthz | 헬스체크 |

### 4.2 Go Fiber 라우터 그룹

| 그룹 | 경로 | 미들웨어 |
|-----|-----|---------|
| auth | /v1/auth | - |
| users | /v1/users | AuthRequired |
| campaigns | /v1/campaigns | - |
| categories | /v1/categories | - |
| keyword-alerts | /v1/keyword-alerts | AuthRequired |
| app-config | /v1/app-config | - |
| health | /v1 | - |

### 4.3 Swagger 설정

| 항목 | 값 |
|-----|---|
| Title | ReviewMaps API |
| Version | 1.0.0 |
| Description | 캠페인 추천 시스템 API |
| Host | localhost:8000 |
| BasePath | /v1 |
| Security | BearerAuth (header: Authorization) |

---

## 5. 서비스 마이그레이션 (Service Migration)

### 5.1 인증 서비스

**JWT Claims 구조**

| 필드 | 타입 | 설명 |
|-----|-----|-----|
| UserID | uint | 사용자 ID |
| Type | string | "access" 또는 "refresh" |
| RegisteredClaims | jwt.RegisteredClaims | 표준 클레임 |

**토큰 설정**

| 토큰 유형 | 만료 시간 |
|---------|---------|
| Access Token | 15분 |
| Refresh Token | 7일 |
| Anonymous Session | 7일 (설정 가능) |

**SNS 토큰 검증 함수**

| 함수 | 반환 | 설명 |
|-----|-----|-----|
| VerifyKakaoToken | *KakaoUserInfo, error | Kakao API 호출 |
| VerifyGoogleToken | *GoogleUserInfo, error | Google API 호출 |
| VerifyAppleToken | *AppleUserInfo, error | Apple JWT 검증 |

### 5.2 FCM 푸시 서비스

**FCMService 메서드**

| 메서드 | 설명 | Go routine |
|-------|-----|-----------|
| NewFCMService | Firebase 초기화 | - |
| SendToDevice | 단일 디바이스 전송 | - |
| SendToMultipleDevices | 여러 디바이스 병렬 전송 | ✅ |

### 5.3 키워드 매칭 서비스

**MatchKeywordsAsync 처리 흐름**

| 단계 | 설명 | Go routine |
|-----|-----|-----------|
| 1 | 활성 키워드 조회 | - |
| 2 | 병렬 매칭 처리 | ✅ |
| 3 | 매칭 결과 저장 | - |
| 4 | 푸시 알림 발송 | ✅ |

---

## 6. 인프라 및 모니터링 (Infrastructure)

### 6.1 SigNoz 통합

| 항목 | 설명 |
|-----|-----|
| 패키지 | go.opentelemetry.io/otel |
| Exporter | otlptracehttp |
| Service Name | reviewmaps-api |
| Endpoint | SIGNOZ_ENDPOINT 환경변수 |

### 6.2 Docker 서비스 구성

| 서비스 | 이미지/빌드 | 포트 | 의존성 |
|-------|-----------|-----|-------|
| api | ./server/Dockerfile | 8000:8000 | db, signoz |
| admin | ./admin/Dockerfile | 8001:8000 | db |
| db | postgres:15 | 5432:5432 | - |
| signoz | signoz/signoz-otel-collector | 4318:4318 | - |

### 6.3 환경변수

**Go Fiber Server**

| 변수 | 설명 |
|-----|-----|
| SERVER_PORT | 서버 포트 (기본: 8000) |
| SERVER_ENV | 환경 (development/production) |
| DATABASE_URL | PostgreSQL 연결 문자열 |
| JWT_SECRET_KEY | JWT 서명 키 |
| JWT_ACCESS_TOKEN_EXPIRE_MINUTES | Access 토큰 만료 시간 (분) |
| JWT_REFRESH_TOKEN_EXPIRE_DAYS | Refresh 토큰 만료 시간 (일) |
| FIREBASE_CREDENTIALS_PATH | Firebase 서비스 계정 키 경로 |
| KAKAO_REST_API_KEY | Kakao REST API 키 |
| GOOGLE_CLIENT_ID_IOS | Google iOS 클라이언트 ID |
| GOOGLE_CLIENT_ID_ANDROID | Google Android 클라이언트 ID |
| GOOGLE_CLIENT_ID_WEB | Google Web 클라이언트 ID |
| APPLE_TEAM_ID | Apple Team ID |
| APPLE_KEY_ID | Apple Key ID |
| APPLE_BUNDLE_ID | Apple Bundle ID |
| SIGNOZ_ENDPOINT | SigNoz 엔드포인트 |

**Django Admin**

| 변수 | 설명 |
|-----|-----|
| SECRET_KEY | Django 시크릿 키 |
| DEBUG | 디버그 모드 |
| ALLOWED_HOSTS | 허용 호스트 |
| DATABASE_URL | PostgreSQL 연결 문자열 (동일 DB) |

---

## 7. 테스트 전략 (Testing Strategy)

### 7.1 TDD 워크플로우

| 단계 | 설명 |
|-----|-----|
| 1 | 테스트 작성 (Red) |
| 2 | 테스트 실행 → 실패 확인 |
| 3 | 최소 구현 (Green) |
| 4 | 테스트 통과 확인 |
| 5 | 리팩토링 |
| 6 | 커밋 |

### 7.2 테스트 디렉토리 구조

| 경로 | 설명 |
|-----|-----|
| server/tests/unit/models/ | 모델 단위 테스트 |
| server/tests/unit/services/ | 서비스 단위 테스트 |
| server/tests/unit/utils/ | 유틸리티 단위 테스트 |
| server/tests/integration/ | API 통합 테스트 |
| server/tests/e2e/ | E2E 테스트 |

### 7.3 테스트 패키지

| 패키지 | 용도 |
|-------|-----|
| github.com/stretchr/testify/assert | 단언문 |
| github.com/stretchr/testify/suite | 테스트 스위트 |
| github.com/stretchr/testify/mock | 모킹 |

---

## 8. 마이그레이션 단계 (Migration Phases)

### Phase 1: 기반 인프라 구축

| 상태 | 작업 | 설명 | 담당 |
|-----|-----|-----|-----|
| [ ] | 1.1 | Go 프로젝트 초기화 (go mod init) | Backend |
| [ ] | 1.2 | Fiber + GORM 기본 설정 | Backend |
| [ ] | 1.3 | Django Admin 프로젝트 분리 | Backend |
| [ ] | 1.4 | unfold 테마 적용 | Backend |
| [ ] | 1.5 | Docker Compose 기본 구성 | DevOps |
| [ ] | 1.6 | SigNoz 연동 테스트 | DevOps |

### Phase 2: 데이터 모델 마이그레이션

| 상태 | 작업 | 설명 | 우선순위 |
|-----|-----|-----|---------|
| [ ] | 2.1 | GORM BaseModel 정의 | High |
| [ ] | 2.2 | User 모델 마이그레이션 | High |
| [ ] | 2.3 | SocialAccount 모델 | High |
| [ ] | 2.4 | Category/Campaign 모델 | High |
| [ ] | 2.5 | Keyword Alert 모델들 | Medium |
| [ ] | 2.6 | AppConfig 모델들 | Medium |
| [ ] | 2.7 | Django Admin 모델 연동 (managed=False) | High |
| [ ] | 2.8 | 인덱스 및 제약조건 검증 | High |

### Phase 3: API 마이그레이션

| 상태 | 작업 | 설명 | 의존성 |
|-----|-----|-----|-------|
| [ ] | 3.1 | JWT 인증 미들웨어 | Phase 2.2 |
| [ ] | 3.2 | 회원가입/로그인 API | Phase 2.2 |
| [ ] | 3.3 | SNS 로그인 API (Kakao, Google, Apple) | Phase 2.3 |
| [ ] | 3.4 | Campaign 목록/상세 API | Phase 2.4 |
| [ ] | 3.5 | Category API | Phase 2.4 |
| [ ] | 3.6 | Keyword Alerts API | Phase 2.5 |
| [ ] | 3.7 | App Config API | Phase 2.6 |
| [ ] | 3.8 | Swagger 문서 생성 | All APIs |

### Phase 4: 서비스 마이그레이션

| 상태 | 작업 | 설명 | Go routine 활용 |
|-----|-----|-----|----------------|
| [ ] | 4.1 | FCM 푸시 서비스 | ✅ 병렬 발송 |
| [ ] | 4.2 | 키워드 매칭 서비스 | ✅ 병렬 매칭 |
| [ ] | 4.3 | 이메일 발송 서비스 | ✅ 비동기 발송 |
| [ ] | 4.4 | SNS 토큰 검증 서비스 | ❌ 순차 처리 |

### Phase 5: 검증 및 배포

| 상태 | 작업 | 설명 |
|-----|-----|-----|
| [ ] | 5.1 | API 호환성 테스트 (모바일 앱) |
| [ ] | 5.2 | 성능 테스트 (목표: < 500ms) |
| [ ] | 5.3 | SigNoz 대시보드 구성 |
| [ ] | 5.4 | CI/CD 파이프라인 구축 |
| [ ] | 5.5 | 프로덕션 배포 |

---

## 9. 롤백 계획 (Rollback Plan)

### 각 단계별 롤백 방법

| Phase | 롤백 방법 |
|-------|---------|
| Phase 1 | 기존 Django 서버 유지 (병렬 운영) |
| Phase 2 | GORM AutoMigration 롤백 (down migration) |
| Phase 3 | Nginx에서 Django로 라우팅 복원 |
| Phase 4 | 기존 Python 서비스 재활성화 |
| Phase 5 | 이전 버전 Docker 이미지로 롤백 |

### 롤백 트리거 조건

| 조건 | 임계값 |
|-----|-------|
| API 응답 시간 | > 1000ms (지속 5분 이상) |
| 에러율 | > 5% |
| 모바일 앱 크래시율 | 증가 감지 |
| 데이터 정합성 | 이슈 발견 |

---

## 10. 체크리스트 (Checklist)

### 마이그레이션 완료 기준

| 상태 | 항목 |
|-----|-----|
| [ ] | 모든 API 엔드포인트 동일 동작 확인 |
| [ ] | Swagger 문서 자동 생성 확인 |
| [ ] | 모든 API 응답에 관계 데이터 포함 확인 |
| [ ] | GORM AutoMigration으로 테이블 생성 확인 |
| [ ] | Django Admin에서 CRUD 정상 동작 확인 |
| [ ] | Go routine 병렬 처리 동작 확인 |
| [ ] | 단위 테스트 커버리지 > 80% |
| [ ] | 통합 테스트 전체 통과 |
| [ ] | API 응답 시간 < 500ms |
| [ ] | SigNoz 메트릭/트레이스 수집 확인 |
| [ ] | 모바일 앱 연동 테스트 통과 |
| [ ] | 프로덕션 배포 완료 |

---

## 부록: 참고 라이브러리

### Go 패키지

| 패키지 | 용도 |
|-------|-----|
| github.com/gofiber/fiber/v2 | HTTP 프레임워크 |
| gorm.io/gorm | ORM |
| gorm.io/driver/postgres | PostgreSQL 드라이버 |
| github.com/golang-jwt/jwt/v5 | JWT 처리 |
| firebase.google.com/go/v4 | Firebase SDK |
| github.com/swaggo/swag | Swagger 생성 |
| github.com/stretchr/testify | 테스트 프레임워크 |
| go.opentelemetry.io/otel | OpenTelemetry |

### Python (Django Admin)

| 패키지 | 용도 |
|-------|-----|
| django | 웹 프레임워크 |
| django-unfold | Admin 테마 |
| psycopg2-binary | PostgreSQL 드라이버 |
