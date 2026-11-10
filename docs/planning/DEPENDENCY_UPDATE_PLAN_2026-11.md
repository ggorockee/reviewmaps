# ReviewMaps 전체 의존성 업데이트 계획 (2026-11)

- 조사일: 2026-11-10 (로컬 `go list -m -u`, `flutter pub outdated`, `npm outdated`, `uv lock --dry-run --upgrade`, 공식 릴리스 피드 기준)
- 마지막 커밋: 2026-05-05 (약 6개월 미갱신)
- 브랜치: `chore/dependency-update-2026-11` (컴포넌트별 하위 PR로 분리 권장)

## 1. 요약 (우선순위)

| 우선순위 | 대상 | 사유 |
|----------|------|------|
| 🔴 P0 | web: Next.js 16.0.7 → 16.4.x, React 19.1.0 → 19.3.x | 16.0.7 이후 RSC 관련 보안 패치(DoS, 소스 노출 CVE) 다수 반영 필요 |
| 🔴 P0 | Node 20 (Dockerfile, CI) → Node 24/26 LTS | Node 20은 2026-04 EOL |
| 🔴 P0 | Go 1.23 (go.mod, Dockerfile, CI) → Go 1.26 | Go 1.23/1.24는 보안 지원 종료 (현재 1.27.3 / 1.26.10) |
| 🟡 P1 | mobile: Flutter 3.35.4 → 3.47.9, Firebase/Google Sign-In 등 메이저 업그레이드 | 스토어 SDK 요구사항 및 다수 메이저 지연 |
| 🟡 P1 | server/go-scraper Go 모듈 (OTel 1.38/1.32 → 1.47, x/crypto 0.41 → 0.58) | 보안·버그 패치 누적 |
| 🟢 P2 | admin: Django 6.0 → 6.1, Unfold 0.72 → 0.110, gunicorn 23 → 27 | 기능·패치 업데이트 |
| 🟢 P2 | CI Actions, Alpine 3.19, Python 3.11/3.10 스크립트 | 베이스 이미지·액션 노후화 |

## 2. 툴체인 / 런타임

| 항목 | 현재 | 최신 | 위치 | 비고 |
|------|------|------|------|------|
| Go | 1.23 | 1.27.3 (1.26.10) | server/go.mod, go-scraper/go.mod, Dockerfile 2개, ci-server.yml | 로컬은 1.26.2. 1.26 권장(안정성), 1.27도 가능 |
| Alpine (런타임) | 3.19 | 3.22+ | server, go-scraper Dockerfile | 3.19는 지원 종료 |
| Node | 20 | 26 LTS | web/Dockerfile, ci-web.yml | 로컬 22.17.0 |
| Python (admin) | 3.12 | 3.14 | admin/Dockerfile, ci-admin.yml | 3.12 지원 중, 3.13/3.14 선택 |
| Python (CI 스크립트) | 3.10, 3.11 | 3.12+ | ci-web.yml, ci-go-scraper.yml 등 manifest 업데이트 단계 | 3.10은 2026-10 EOL |
| Flutter / Dart | 3.35.4 / 3.9.2 | 3.47.9 / 3.13.7 | 로컬 SDK, pubspec `sdk: ^3.8.1` | |
| AGP / Kotlin / Gradle | 8.7.3 / 2.1.0 / 8.12 | Flutter 3.47 권장 버전 확인 필요 | mobile/android/settings.gradle.kts, gradle-wrapper.properties | Flutter 업그레이드 시 함께 상향 |
| iOS Deployment Target | Podfile 15.6, pbxproj 13.0/15.6 혼재 | 15.6 통일 | mobile/ios | 불일치 정리 필요 |

## 3. server (Go Fiber)

| 모듈 | 현재 | 최신 | 리스크 |
|------|------|------|--------|
| gofiber/fiber/v2 | 2.52.10 | 2.52.16 | 낮음 (패치). Fiber v3 이전은 별도 과제로 보류 |
| firebase.google.com/go/v4 | 4.18.0 | 4.22.0 | 낮음 |
| golang-jwt/jwt/v5 | 5.3.0 | 5.3.1 | 낮음 |
| prometheus/client_golang | 1.23.2 | 1.25.0 | 낮음 |
| go.opentelemetry.io/otel/* | 1.38.0 | 1.47.0 | 중간 (semconv 경로 변경 가능, 빌드로 검증) |
| golang.org/x/crypto | 0.41.0 | 0.58.0 | 낮음 (보안 패치) |
| google.golang.org/api | 0.231.0 | 0.311.0 | 중간 (SNS 토큰 검증 회귀 테스트) |
| gorm.io/gorm, driver/postgres | 1.31.1 / 1.6.0 | 1.31.2 / 1.6.3 | 낮음 |

## 4. go-scraper

| 모듈 | 현재 | 최신 | 리스크 |
|------|------|------|--------|
| jackc/pgx/v5 | 5.7.2 | 5.12.0 | 낮음~중간 |
| go.opentelemetry.io/otel/* | 1.32.0 | 1.47.0 | 중간 (server와 버전 통일) |
| go.uber.org/zap | 1.27.0 | 1.28.0 | 낮음 |

## 5. admin (Django, uv.lock 기준)

| 패키지 | 현재 | 최신 | 리스크 |
|--------|------|------|--------|
| django | 6.0 | 6.1.3 | 중간 (pyproject 하한 `>=5.2` → `>=6.1` 로 정리) |
| django-unfold | 0.72.0 | 0.110.1 | 높음 (설정 키·템플릿 변경 가능, 어드민 화면 수동 점검) |
| gunicorn | 23.0.0 | 27.0.0 | 중간 (메이저 4단계, 실행 옵션 확인) |
| psycopg2-binary | 2.9.11 | 2.9.13 | 낮음 (psycopg 3 전환은 선택) |
| whitenoise, dj-database-url, python-dotenv | 6.11 / 3.0.1 / 1.2.1 | 6.12 / 3.1.2 / 1.2.4 | 낮음 |
| ruff, pytest, pytest-django (dev) | 0.14.8 / 9.0.1 / 4.11.1 | 0.17.4 / 9.2.0 / 4.14.0 | 낮음 (ruff 신규 룰로 포맷 diff 발생 가능) |

## 6. web (Next.js)

| 패키지 | 현재 | 최신 | 리스크 |
|--------|------|------|--------|
| next, eslint-config-next | 16.0.7 | 16.4.6 | 중간 (🔴 보안 패치 포함, 최우선) |
| react, react-dom | 19.1.0 (고정) | 19.3.1 | 중간 |
| @types/node | ^20 | Node 런타임과 일치 (^24 또는 ^26) | 낮음 |

## 7. mobile (Flutter)

### 7.1 Upgradable (메이저 변경 없음, 즉시 가능)

| 패키지 | 현재 | 목표 |
|--------|------|------|
| app_tracking_transparency | 2.0.6+1 | 2.0.7 |
| crypto | 3.0.6 | 3.0.8 |
| flutter_naver_map | 1.4.1+1 | 1.4.4 |
| flutter_riverpod | 3.0.0-dev.17 (프리릴리스) | 3.5.0 (정식) |
| flutter_svg, http, intl, shared_preferences, url_launcher | - | 최신 마이너 |

### 7.2 메이저 업그레이드 (코드 수정 필요)

| 패키지 | 현재 | 최신 | 영향 범위 |
|--------|------|------|-----------|
| firebase_core 외 Firebase 5종 | 3.15 계열 | 5.1 계열 (core 5.1.0, messaging 17, crashlytics 6, analytics 13, remote_config 7, performance 0.12) | 반드시 일괄 업그레이드. iOS Pod/Android BoM 동반 상향 |
| google_sign_in | 6.3.0 | 7.2.0 | 🔴 API 전면 변경 (`GoogleSignIn.instance`, `initialize`, `authenticate`). services/sns/google_login_service.dart 재작성 |
| kakao_flutter_sdk_user | 1.9.7+3 | 2.1.0 | 메이저. 로그인 플로우 회귀 테스트 |
| sign_in_with_apple | 6.1.4 | 8.2.0 | 메이저 2단계 |
| flutter_local_notifications | 18.0.1 | 23.0.0 | 메이저 다수. 초기화·스케줄링 API 확인 |
| google_mobile_ads | 6.0.0 | 9.2.0 | 메이저 3단계. 광고 SDK 최소 버전 요구 확인 |
| flutter_secure_storage | 9.2.4 | 11.2.0 | 메이저. 기존 저장 토큰 마이그레이션 확인 (로그아웃 유발 위험) |
| permission_handler, location, package_info_plus, proj4dart, flutter_dotenv | - | 최신 메이저 | 개별 체인지로그 확인 |
| flutter_lints (dev) | 5.0.0 | 6.0.0 | 신규 린트 경고 정리 |

### 7.3 미커밋 변경 (작업 전 확인 필요)

| 파일 | 내용 |
|------|------|
| mobile/pubspec.yaml | version `2.1.1+3`(iOS) → `2.1.1+91`(Android) 전환 |
| mobile/ios/Runner.xcodeproj/project.pbxproj | 빌드 설정 변경 |

## 8. CI / 인프라

| 항목 | 현재 | 조치 |
|------|------|------|
| actions/checkout | v4 | 최신 메이저 확인 후 상향 |
| actions/setup-go, setup-node, setup-python | v5 / v4 / v5 | 최신 메이저 상향 |
| astral-sh/setup-uv | v4 | 최신 메이저 상향 |
| docker/build-push-action | v5 | 최신 메이저 상향 |
| ci-scrape.yml | 레거시 스크레이퍼(비활성) | 삭제 또는 비활성화 검토 |

## 9. 실행 순서 (PR 단위)

| 단계 | PR | 병렬 가능 |
|------|----|-----------|
| 1 | `fix/web-security-update`: Next 16.4 / React 19.3 / Node LTS (Dockerfile, CI) | 2·3과 병렬 |
| 2 | `chore/server-go-update`: Go 1.26, Alpine, Go 모듈, OTel | 1·3과 병렬 |
| 3 | `chore/scraper-go-update`: Go 1.26, pgx, OTel (server와 동일 버전) | 1·2와 병렬 |
| 4 | `chore/admin-deps-update`: Django 6.1, Unfold, gunicorn, ruff | 독립 |
| 5 | `chore/mobile-flutter-sdk`: Flutter 3.47, AGP/Kotlin/Gradle, Upgradable 패키지 | 순차 시작점 |
| 6 | `chore/mobile-firebase-v5`: Firebase 일괄 메이저 | 5 이후 |
| 7 | `refactor/mobile-sns-login`: google_sign_in 7, kakao 2, apple 8 | 5 이후 |
| 8 | `chore/mobile-misc-major`: 알림, 광고, secure_storage 등 | 5 이후 |
| 9 | `chore/ci-actions-update`: Actions 메이저, 스크립트 Python, 레거시 워크플로 정리 | 독립 |

## 10. 작업 체크리스트

### 준비
- [x] 전체 컴포넌트 의존성 현황 조사
- [x] 업데이트 계획 문서 작성
- [ ] mobile 미커밋 변경(pubspec 버전, pbxproj) 처리 방침 결정
- [ ] 로컬 Flutter SDK 3.47.9 업그레이드

### web
- [ ] next / eslint-config-next 16.4.x, react / react-dom 19.3.x
- [ ] Node LTS로 Dockerfile, CI `NODE_VERSION`, `@types/node` 상향
- [ ] `npm run build`, `npm run lint` 통과

### server
- [ ] go.mod `go 1.26`, Dockerfile golang 1.26-alpine / alpine 최신, CI `GO_VERSION`
- [ ] `go get -u` 직접 의존성 + `go mod tidy`
- [ ] `make test`, staticcheck, `make swagger` 통과
- [ ] SNS 로그인(Kakao/Google/Apple), FCM 발송 스테이징 검증

### go-scraper
- [ ] go.mod / Dockerfile Go 1.26, Alpine 상향
- [ ] pgx, OTel(server와 동일), zap 업데이트
- [ ] `go build ./...`, `go vet ./...`, reviewnote 스크레이퍼 1회 실행 검증

### admin
- [ ] `uv lock --upgrade`, pyproject 하한 정리
- [ ] Unfold 0.110 설정 변경 사항 반영
- [ ] `uv run ruff format --check .`, 어드민 화면 수동 점검

### mobile
- [ ] Flutter 3.47 + AGP/Kotlin/Gradle 상향, iOS Deployment Target 통일
- [ ] Upgradable 패키지 + riverpod 3.5 정식 버전
- [ ] Firebase 5종 일괄 메이저 업그레이드
- [ ] google_sign_in 7 마이그레이션 (google_login_service.dart)
- [ ] kakao 2.x, sign_in_with_apple 8.x 마이그레이션
- [ ] flutter_local_notifications, google_mobile_ads, flutter_secure_storage 등 메이저
- [ ] `flutter analyze`, `flutter test`, iOS/Android 실기기 빌드 검증
- [ ] 앱 버전 상향 (2.2.0 등) 및 스토어 제출

### CI
- [ ] GitHub Actions 메이저 버전 상향
- [ ] manifest 업데이트 스크립트 Python 3.12+
- [ ] ci-scrape.yml 정리 여부 결정

## 11. 리스크 및 주의사항

| 리스크 | 대응 |
|--------|------|
| flutter_secure_storage 메이저 변경으로 기존 토큰 읽기 실패 → 강제 로그아웃 | 업그레이드 전후 토큰 읽기 테스트, 필요 시 마이그레이션 코드 |
| google_sign_in 7 API 비호환 | 별도 PR로 분리, 3개 플랫폼 로그인 수동 테스트 |
| Unfold 대규모 버전 점프 | 체인지로그 기반 settings 수정, 스테이징 확인 |
| OTel 버전 점프로 SigNoz 수집 누락 | 배포 후 트레이스·메트릭 수집 확인 |
| 서버·앱 동시 배포 시 장애 원인 분리 어려움 | 서버 계열(1~4) 먼저 배포·안정화 후 모바일 진행 |
