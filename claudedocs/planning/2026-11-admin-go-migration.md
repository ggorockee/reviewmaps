# 리뷰맵 관리자 페이지 이전 계획: Django → Go + Nuxt (Google 로그인)

작성일: 2026-11-27 · 기준: 라익찍스 관리자 콘솔(like-zzix `admin/` + `server/internal/admin`, `server/internal/httpapi/admin.go`)

## 쓰는 방법

- 각 항목 맨 앞 `[ ]`를 보고 진행해도 되면 **`[승인]`** 으로 바꿔 주세요. 빼거나 미룰 항목은 `[보류]`로 적어 주세요.
- 결정 항목(D-)은 고른 선택지에 표시해 주세요. 표시가 없으면 "추천" 안으로 진행합니다.
- 저는 `[승인]` 항목을 Phase 순서대로 진행하고, 끝나면 `[x]`와 결과(PR 번호, 확인한 숫자)를 한 줄 붙입니다.
- 프로젝트 최우선 원칙(infra `claudedocs/00-원칙.md`): 모든 것은 문서로 남기고, 모니터링할 수 없는 것은 끝난 것이 아닙니다. 각 Phase의 "완료 기준"에 문서·모니터링 항목이 들어 있습니다.
- 이 저장소는 공개입니다. 관리자 이메일, 클라이언트 비밀값, 비밀번호 해시는 이 문서와 코드에 적지 않고 GSM에만 둡니다.

## 1. 현재 상태 (2026-11-27 조사)

| 항목 | 현재 |
|---|---|
| 코드 | `admin/` Django 6.1 + django-unfold 테마, gunicorn, Python 3.12 |
| 배포 | 이미지 `ggorockee/reviewmaps-admin`, infra 차트 `charts/helm/prod/reviewmaps`의 하위 차트 `admin`(포트 8000, 프로브 `/health/` `/readiness/` `/liveness/`), Istio VS `reviewmaps-admin-vs` → https://admin.review-maps.com |
| CI | `.github/workflows/ci-admin.yml` (ruff, `manage.py check`, Docker 빌드, infra 태그 PR) |
| 로그인 | 이메일 + 비밀번호 (`users` 테이블에서 `login_method='email'`이고 `is_staff`인 계정). 운영 DB에 스태프·슈퍼유저 5명 |
| DB | 모든 모델이 `managed=False`. 테이블 구조는 Go 서버(GORM 모델)와 `server/migrations/*.sql`이 관리 |
| Django 전용 테이블 | `auth_group`, `auth_group_permissions`, `auth_permission`, `django_admin_log`, `django_content_type`, `django_migrations`, `django_session`, `users_groups`, `users_user_permissions` |
| 모니터링 | blackbox 접속 검사 `https://admin.review-maps.com/login/` 만 있음. 로그인·변경 지표 없음 |

### 화면별 실제 사용량 (`django_admin_log`, 전체 2,663건)

| 화면 | 추가 | 수정 | 삭제 | 마지막 사용 | 판단 |
|---|---|---|---|---|---|
| 키워드 알림 (keyword_alerts_alerts) | - | - | 2,336 | 2025-12-07 | 대량 삭제(정리). 목록·일괄 삭제 필요 |
| 캠페인 (campaign) | 46 | 5 | 197 | 2025-12-18 | 조회·삭제 중심. 수정은 드묾 |
| 앱 버전 (app_versions) | - | 25 | - | **2026-11-15** | 지금도 쓰는 핵심 화면 (강제 업데이트) |
| 사용자 (users) | 3 | 9 | 14 | **2026-11-14** | 계정 삭제 요청 처리. 핵심 |
| 키워드 (keyword_alerts_keywords) | 9 | 4 | 14 | 2025-12-07 | 조회·삭제 |
| SNS 계정 (social_accounts) | - | - | 1 | 2025-11-26 | 조회 위주 |
| 그 밖 (카테고리, 매핑, 광고 설정, 요청 제한, 설정, FCM, 이메일 인증) | 0 | 0 | 0 | - | 등록만 되어 있음. 조회·간단 수정 |

2026년 들어 사용은 월 1~3건으로 적고, 대부분 앱 버전 수정과 사용자 삭제입니다.

### 지금 구조의 문제

| 문제 | 영향 |
|---|---|
| 비밀번호 로그인만 있음, 2단계 인증 없음 | 관리자 계정 비밀번호가 새면 운영 DB 쓰기 권한이 그대로 노출 |
| SNS 계정 화면에 `access_token`·`refresh_token` 원문이 보임 | 관리자 화면 캡처나 계정 탈취 시 사용자 토큰 유출 |
| FCM 토큰, 이메일 인증 코드 원문 표시 | 같음 |
| 캠페인 수정이 go-scraper의 DELETE 후 INSERT에 덮어써짐 | 수정해도 다음 수집 때 사라짐 (관리자는 모름) |
| 앱 버전이 DB(`app_versions`)와 Firebase Remote Config 두 곳에 있음 | 어느 쪽이 앱에 적용되는지 헷갈림. 2.2.1부터 앱은 Remote Config로 업데이트 안내 |
| Python 스택이 이 화면 하나뿐 | 의존성 업데이트·보안 패치를 별도로 챙겨야 함 |
| 누가 무엇을 바꿨는지 대시보드에서 볼 수 없음 | `django_admin_log`에만 있음 (원칙 2 위반) |

## 2. 목표 구조

| 구성 | 내용 |
|---|---|
| 화면 | `admin/`을 Nuxt 4 + @nuxt/ui 정적 SPA로 교체 (라익찍스 `admin/`과 같은 구조). nginx(비루트, 8080)로 서빙, `/healthz` |
| API | 기존 Go 서버(`server/`, api.review-maps.com)에 `/admin/v1` 그룹 추가. 앱 API와 같은 GORM 모델 사용 |
| 로그인 | Google Identity Services → ID 토큰을 서버가 Google 공개키로 검증 → `ADMIN_EMAILS` 허용 목록 확인 → 불투명 세션 쿠키 발급(DB에는 SHA-256만 저장). 예비로 아이디/비밀번호(bcrypt) 로그인 선택 가능 |
| 주소 | https://admin.review-maps.com 그대로 (API와 같은 사이트 review-maps.com → SameSite=Lax 쿠키) |
| 기록 | 모든 변경을 `admin_audit_logs`에 저장, Prometheus 지표 `reviewmaps_admin_logins_total`, `reviewmaps_admin_changes_total` |
| 비밀 | GSM `prod-reviewmaps-api-credentials`에 `ADMIN_EMAILS`, `ADMIN_GOOGLE_CLIENT_ID`(웹), 선택 `ADMIN_LOGIN_ID`·`ADMIN_PASSWORD_HASH` 추가 |

라익찍스에서 그대로 가져올 것

| 라익찍스 위치 | 가져올 내용 |
|---|---|
| `server/internal/admin/auth.go` | Google ID 토큰 검증(JWKS, `aud`·`iss`·`email_verified`), 허용 목록, 세션 토큰 생성·해시 |
| `server/internal/admin/password.go` | 예비 비밀번호 로그인 (bcrypt) |
| `server/internal/httpapi/admin.go` | `/admin/v1` 그룹, CORS(관리자 주소만, credentials), 로그인 요청 제한, `/config` `/auth/google` `/auth/password` `/auth/logout` `/me`, `requireSession` |
| `server/internal/store/migrations/0001_init.sql` | `admin_sessions` 테이블 |
| `server/internal/telemetry` | `admin_logins_total`, `admin_changes_total` |
| `admin/app/composables/useAuth.ts`, `useApi.ts`, `middleware/auth.global.ts`, `pages/login.vue`, `layouts/default.vue` | 로그인 흐름, API 호출(쿠키 포함), 화면 틀 |
| `admin/Dockerfile`, `admin/nginx.conf`, `.github/workflows/ci-admin.yml` | 빌드·서빙·CI |
| infra `charts/helm/prod/like-zzix` admin 부분 | 관리자 Deployment·Service·VS, `ADMIN_ORIGIN` |

## 3. 결정 항목 (Phase 0에서 정함)

| ID | 질문 | 선택지 | 추천 |
|---|---|---|---|
| D1 | 관리자 API 위치 | [같은 서버] 기존 `server/`에 `/admin/v1` 추가 / [별도 서비스] `server/cmd/admin`으로 따로 배포 | 같은 서버: 라익찍스와 같고 모델·DB 연결을 재사용. 앱 트래픽과 같은 Pod라는 점은 요청 제한·CORS로 보완 |
| D2 | 예비 로그인 | [넣음] Google을 못 쓸 때 아이디/비밀번호 1개 / [안 넣음] Google만 | 넣음: Google OAuth 동의 화면이 Testing 상태라 테스트 사용자 설정이 바뀌면 전원 로그인 불가 |
| D3 | 관리자 목록 | [허용 목록] GSM `ADMIN_EMAILS` / [DB] `users.is_staff` 재사용 | 허용 목록: 앱 사용자 테이블과 관리자 권한을 분리 (앱 회원 가입으로 권한이 생길 여지 제거) |
| D4 | 앱 버전 관리 | [Remote Config로 일원화] 관리자 화면에서는 `app_versions`를 읽기 전용, 버전 안내는 Remote Config / [둘 다 유지] | Remote Config 일원화: 2.2.1+ 앱은 Remote Config를 봄. 단 2.2.0 이하가 `/v1/app-config/version`을 쓰는지 서버 지표로 먼저 확인(1-0) |
| D5 | 캠페인 수정 | [조회·삭제·프로모션만] / [전체 수정] | 조회·삭제(soft delete)·`promotion_level`만: 나머지는 수집 때 덮어써짐 |
| D6 | 전환 방식 | [같은 주소 교체] 검증 후 admin.review-maps.com을 새 화면으로, 문제 시 이미지 되돌림 / [임시 주소 병행] 새 주소(인증서·게이트웨이 추가) | 같은 주소 교체: 관리자 화면이라 몇 분 중단은 괜찮고, Django 이미지·차트 값으로 바로 되돌릴 수 있음. 교체 전 로컬·포트포워딩으로 전부 검증 |
| D7 | Django 테이블 정리 | [30일 뒤 백업 후 삭제] / [남겨 둠] | 30일 뒤 삭제: `django_admin_log`는 CSV로 내보내 보관(Cloud SQL 자동 백업은 비용 때문에 꺼 둔 상태) |

## 4. 화면·API 범위

| 화면 | API (`/admin/v1/...`) | 기능 | 주의 |
|---|---|---|---|
| 대시보드 | `GET /summary` | 사용자 수, 오늘 가입, 키워드·알림 수, 캠페인(활성·soft delete), 최근 변경 10건 | 숫자는 읽기만 |
| 사용자 | `GET /users`, `GET /users/:id`, `PATCH /users/:id`(is_active, name), `DELETE /users/:id` | 이메일·이름·로그인 방식 검색, 연결된 SNS·키워드·기기 수 | 삭제는 앱의 회원 탈퇴(`DELETE /v1/users/me`)와 같은 서비스 함수 재사용 (연관 데이터 정리 규칙 통일). 확인 창에 이메일 재입력 |
| SNS 계정 | `GET /users/:id/social-accounts` | 제공자, 이메일, 연결일 | 토큰은 API 응답에서 아예 제외 |
| 키워드 | `GET /keywords`, `DELETE /keywords/:id`, `PATCH /keywords/:id`(is_active) | 키워드·사용자 검색 | |
| 키워드 알림 | `GET /alerts`, `POST /alerts/bulk-delete` (조건: 기간, 읽음 여부, 키워드) | 대량 정리 | `deleted_at` soft delete 규칙 따름 (`add_deleted_at_to_keyword_alerts.sql`) |
| FCM 기기 | `GET /fcm-devices` | 기기 종류, 활성, 사용자 | 토큰은 앞 8자만 |
| 캠페인 | `GET /campaigns`(플랫폼·카테고리·지역·기간·검색, `deleted_at IS NULL` 기본), `GET /campaigns/:id`, `PATCH /campaigns/:id`(promotion_level), `DELETE /campaigns/:id`(soft delete) | | 수집 때 덮어써진다는 안내 문구 |
| 카테고리 | `GET/POST/PATCH/DELETE /categories`, 순서 변경 | 표시 순서 | |
| 카테고리 매핑 | `GET /raw-categories`(매핑 없는 것 먼저), `PUT /raw-categories/:id/mapping` | 수집 원본 카테고리 → 앱 카테고리 연결 | go-scraper 분류에 바로 영향. 변경 기록 필수 |
| 앱 설정 | `GET /settings`, `PUT /settings/:key` (keyword_limit, alert_retention_days) | 값 검증(숫자 범위) | 기존 `services/app_config.go` 재사용 |
| 앱 버전 | `GET /app-versions`, (D4에 따라) `PUT /app-versions/:platform` | 현재·최소 버전, 강제 업데이트 | D4가 일원화면 읽기 전용 + Remote Config 값 함께 표시 |
| 광고 설정·요청 제한 | `GET/PUT /ad-configs`, `GET/PUT /rate-limits` | | 사용 기록 없음 → 2차(Phase 3-9)로 |
| 이메일 인증 | `GET /email-verifications` | 발송·인증 여부 | 코드는 표시 안 함 |
| 변경 기록 | `GET /audit-logs` | 누가·언제·무엇을·전후 값 | |

공통: 목록은 서버 페이지 나눔(기본 50건), 정렬·검색 파라미터 허용 목록, 모든 변경 API는 `admin_audit_logs` 기록과 `reviewmaps_admin_changes_total{entity,action}` 증가.

## Phase 0. 결정·준비

- [ ] 0-1 직접: 위 D1~D7 선택 표시
- [ ] 0-2 제가: 서버 지표로 `/v1/app-config/version`, `/v1/app-config/ads` 호출이 어떤 앱 버전에서 오는지 확인 (D4·광고 설정 화면 필요 여부 근거)
- [ ] 0-3 제가(콘솔, 실행 직전 승인): Google OAuth 웹 클라이언트(yanggo-514212, Grafana·ArgoCD·라익찍스 관리자 공용)의 "승인된 JavaScript 원본"에 `https://admin.review-maps.com`, 로컬 개발용 `http://localhost:3000` 추가
- [ ] 0-4 직접: 관리자 Google 계정 목록 확정 (OAuth 동의 화면이 Testing이라 Test users에도 들어 있어야 로그인 가능)
- [ ] 0-5 제가(GSM 쓰기, 실행 직전 승인): `prod-reviewmaps-api-credentials`에 `ADMIN_EMAILS`, `ADMIN_GOOGLE_CLIENT_ID`, (D2) `ADMIN_LOGIN_ID`·`ADMIN_PASSWORD_HASH` 추가. 위치를 infra `.secrets/README.md`에 기록

완료 기준: 결정 표시 완료, GSM 키 위치 문서화

## Phase 1. 서버: 인증 기반

- [ ] 1-1 SQL 마이그레이션 `server/migrations/`: `admin_sessions`(token_hash, email, expires_at, created_at), `admin_audit_logs`(id, admin_email, action, entity, entity_id, before JSONB, after JSONB, created_at, 인덱스: created_at·entity). GORM AutoMigrate는 운영에서 꺼져 있으므로 SQL로 적용 (적용 절차: 서버 문서의 마이그레이션 방식 그대로)
- [ ] 1-2 `server/internal/admin`: 라익찍스 `auth.go`·`password.go` 이식 (Google 검증기, 허용 목록, 세션 생성·해시, bcrypt). `keyfunc/v3` 의존성 추가
- [ ] 1-3 `/admin/v1` 그룹: CORS(`ADMIN_ORIGIN`만, credentials), 로그인 요청 제한(IP당), `GET /config`(클라이언트 ID·예비 로그인 사용 여부), `POST /auth/google`, `POST /auth/password`, `POST /auth/logout`, `GET /me`, `requireSession`
- [ ] 1-4 쿠키: HttpOnly, Secure, SameSite=Lax, 12시간, 경로 `/admin/v1`. 변경 요청은 `Origin` 헤더가 `ADMIN_ORIGIN`인지 확인 (CSRF 방어)
- [ ] 1-5 지표: `reviewmaps_admin_logins_total{method,result}`, `reviewmaps_admin_changes_total{entity,action}`, `reviewmaps_admin_sessions_active`
- [ ] 1-6 테스트: 검증기(가짜 키), 허용 목록, 세션 만료, 잘못된 Origin, 요청 제한, 로그아웃 (라익찍스 `admin_test.go` 참고). `go test ./...` 통과
- [ ] 1-7 로컬 개발 로그인: `APP_ENV=local`일 때만 `/auth/dev` (라익찍스와 같음)

완료 기준: PR 머지, 운영 서버 배포 후 `/admin/v1/config` 응답, `/metrics`에 새 지표 노출, 서버 기존 테스트·앱 API 영향 없음

## Phase 2. 서버: 관리 API

- [ ] 2-1 공통: 페이지 나눔·정렬·검색 도우미, 변경 기록 도우미(전후 JSON, 토큰류 필드 제외), 응답 DTO에서 민감 필드 제거
- [ ] 2-2 사용자 (목록·상세·수정·삭제). 삭제는 앱 회원 탈퇴와 같은 서비스 함수
- [ ] 2-3 SNS 계정·FCM 기기·이메일 인증 (읽기 전용, 마스킹)
- [ ] 2-4 키워드·키워드 알림 (일괄 정리 포함, soft delete)
- [ ] 2-5 캠페인 (조회, soft delete, promotion_level)
- [ ] 2-6 카테고리·원본 카테고리 매핑
- [ ] 2-7 앱 설정·앱 버전 (D4에 따라)
- [ ] 2-8 대시보드 요약, 변경 기록 조회
- [ ] 2-9 테스트: 핸들러 단위 테스트(권한 없음 401, 민감 필드 미포함, soft delete 조건), Swagger 문서 갱신

완료 기준: 각 API에 테스트, 응답에 토큰·코드 원문이 없음을 테스트로 고정, 운영 배포 후 읽기 API를 포트포워딩으로 확인(쓰기 API는 Phase 5)

## Phase 3. 관리자 화면 (Nuxt)

- [ ] 3-1 `admin/`을 새 Nuxt 프로젝트로 교체 (Django 코드는 Phase 7까지 `admin-django/`로 옮겨 보관). Nuxt 4, @nuxt/ui, TypeScript, ESLint, Vitest — 라익찍스 `admin/package.json` 기준
- [ ] 3-2 로그인 화면: Google 버튼(GIS), 예비 로그인(D2), 로컬 개발 로그인
- [ ] 3-3 레이아웃: 왼쪽 메뉴(대시보드, 사용자, 키워드·알림, 캠페인, 카테고리, 설정, 변경 기록), 로그인한 이메일, 로그아웃
- [ ] 3-4 공통 표 컴포넌트: 서버 페이지 나눔, 검색, 필터, 빈 값 문구, 오류 표시
- [ ] 3-5 사용자 화면 (상세에 SNS·키워드·기기 요약, 삭제 확인 창에 이메일 재입력)
- [ ] 3-6 키워드·알림 화면 (일괄 정리: 조건 미리보기 건수 → 확인)
- [ ] 3-7 캠페인 화면 ("수집 때 덮어써짐" 안내, 삭제·프로모션만)
- [ ] 3-8 카테고리·매핑 화면 (매핑 없는 원본을 위에)
- [ ] 3-9 설정·앱 버전 화면, 2차: 광고 설정·요청 제한
- [ ] 3-10 대시보드·변경 기록 화면
- [ ] 3-11 `Dockerfile`(빌드 시 `API_BASE=https://api.review-maps.com`), `nginx.conf`(보안 헤더, noindex, SPA), 테스트(Vitest)

완료 기준: `npm run lint`, `typecheck`, `test`, `generate` 통과, 로컬에서 운영 API(포트포워딩)로 로그인·조회 확인 화면 캡처

## Phase 4. CI·인프라

- [ ] 4-1 `.github/workflows/ci-admin.yml`을 Node 빌드로 교체 (라익찍스 `ci-admin.yml` 기준: lint·typecheck·test → Docker 빌드·푸시 `ggorockee/reviewmaps-admin` → infra 태그 PR 자동 머지). 이미지 이름은 그대로 두어 차트·ArgoCD 변경을 줄임
- [ ] 4-2 infra `charts/helm/prod/reviewmaps` admin 값: 포트 8000(django) → 8080(http), 프로브 `/healthz`, 리소스(요청 10m/32Mi 수준), Django 환경변수(`ALLOWED_HOSTS`, `POSTGRES_*` 주입) 제거, 읽기 전용 루트 파일시스템. 하위 차트 `charts/admin` 템플릿이 포트 이름 `django`를 쓰면 함께 수정
- [ ] 4-3 infra 서버 값: `ADMIN_ORIGIN=https://admin.review-maps.com`, ExternalSecret에 `ADMIN_EMAILS`·`ADMIN_GOOGLE_CLIENT_ID`·(D2) 키 추가
- [ ] 4-4 blackbox 검사 대상 `https://admin.review-maps.com/login/` → `/healthz`
- [ ] 4-5 ServiceMonitor: 서버 지표는 기존 그대로 수집되는지 확인 (새 지표 이름 포함)

완료 기준: ArgoCD Synced/Healthy, blackbox 성공, 새 지표가 Prometheus에서 조회됨

## Phase 5. 검증·전환 (D6 같은 주소 교체 기준)

- [ ] 5-1 전환 전 점검표: 관리자 전원 Google 로그인 성공(포트포워딩 또는 로컬 화면), 각 화면 조회, 테스트 계정으로 쓰기 API(사용자 비활성, 키워드 삭제, 카테고리 매핑) 실행 후 되돌리기, 변경 기록·지표 증가 확인
- [ ] 5-2 전환: infra 태그 PR로 admin 이미지 교체 → ArgoCD 동기화 → https://admin.review-maps.com 접속, 로그인, 화면 캡처 (CLAUDE.md 검증 규칙: Playwright, 비밀번호는 브라우저에 입력하지 않음)
- [ ] 5-3 되돌리기 절차(문서에 미리 적어 둠): infra admin 값·이미지 태그를 이전 Django 커밋으로 되돌리는 PR → 동기화. Django 이미지 `20261110-7ed5b97` 보존
- [ ] 5-4 1주 관찰: 로그인 실패·오류율·변경 기록 확인 후 Phase 7 진행 여부 결정

완료 기준: 운영 주소에서 새 화면으로 실제 작업 1건 이상(예: 앱 버전 조회, 사용자 검색) 성공, 되돌리기 절차 문서화

## Phase 6. 모니터링·문서

- [ ] 6-1 Grafana 리뷰맵 대시보드에 "관리자" 행: 로그인 성공·실패, 변경 건수(대상별), 활성 세션, 최근 변경 표. 범위표·차트 설명 3단 형식 (infra CLAUDE.md 대시보드 규칙)
- [ ] 6-2 알림: 관리자 로그인 실패 급증 `ReviewmapsAdminLoginFailures`(10분 10회 초과, WARN), 허용 목록 밖 계정 로그인 시도 `ReviewmapsAdminUnauthorizedLogin`(1회, INFO), 관리자 화면 접속 실패는 기존 blackbox 알림 사용. 대시보드 색상 기준과 알림 기준 동일하게
- [ ] 6-3 문서: infra `.claude/CLAUDE.md` 배포 경로 표에 "리뷰맵 관리자 콘솔" 행(라익찍스 행과 같은 형식), 알림 표에 새 알림, `claudedocs/app-release-runbook.md`에 관리자 계정 추가·제거 절차(GSM `ADMIN_EMAILS` 수정 → ExternalSecret 갱신 → 서버 재시작), 이 저장소 `admin/README.md`
- [ ] 6-4 `.secrets/README.md`에 새 GSM 키 위치

완료 기준: 대시보드 캡처, 테스트 알림 메일 수신 확인, 문서 PR 머지

## Phase 7. Django 정리 (전환 30일 뒤, D7)

- [ ] 7-1 `django_admin_log`를 CSV로 내보내 로컬 보관 (읽기 전용 임시 Pod, `default_transaction_read_only`)
- [ ] 7-2 Django 전용 테이블 삭제 SQL을 `server/migrations/`에 작성 → 개발자 확인 후 적용 (운영 DB 쓰기, 실행 직전 승인): `auth_group`, `auth_group_permissions`, `auth_permission`, `django_admin_log`, `django_content_type`, `django_migrations`, `django_session`, `users_groups`, `users_user_permissions`. `users` 테이블의 `is_staff`·`is_superuser`·`password` 컬럼은 앱 서버 모델이 쓰므로 유지
- [ ] 7-3 `admin-django/` 코드, Python 관련 CI 단계, Dependabot Python 설정 제거
- [ ] 7-4 GSM·Secret 중 Django 전용 값(예: `DJANGO_SECRET_KEY`) 제거, 문서 갱신

완료 기준: Django 흔적 없음, 문서·대시보드에 남은 참조 없음

## 위험과 대응

| 위험 | 대응 |
|---|---|
| 관리자 API가 앱 API와 같은 서버에 있어 노출 범위가 넓어짐 | CORS 관리자 주소만, Origin 확인, 세션 쿠키 경로 제한, 로그인 요청 제한, 허용 목록 밖 시도 알림. 필요하면 Istio에서 `/admin/v1` 접근을 관리자 주소 Referer로 제한하는 안 검토 |
| Google OAuth 동의 화면 Testing → 관리자 계정이 Test users에서 빠지면 로그인 불가 | D2 예비 로그인, 0-4에서 목록 확인 |
| 사용자 삭제 규칙이 앱 탈퇴와 달라 데이터가 남거나 과하게 지워짐 | 앱 탈퇴와 같은 서비스 함수 재사용, 테스트로 고정 |
| 키워드 알림 일괄 정리 실수 | 조건으로 먼저 건수 미리보기, soft delete, 변경 기록에 조건 저장 |
| 전환 직후 화면 오류 | 5-3 되돌리기, Django 이미지 보존 |
| 서버 배포에 관리자 코드가 섞여 앱 API 장애 | 관리자 라우트 패키지 분리, 서버 기존 테스트 전부 통과 조건, 배포 후 앱 API 5xx·P95 대시보드 확인 |

## 진행 기록

| 날짜 | 항목 | 결과 |
|---|---|---|
| 2026-11-27 | 계획 작성 | 현재 구조·사용량 조사(운영 DB 읽기 전용), 라익찍스 구조 확인 |
