# ReviewMaps 전체 업데이트 및 운영 정상화 보고서 (2026-11)

- 작업 기간: 2026-11-10 ~ 2026-11-11
- 계획 문서: `docs/planning/DEPENDENCY_UPDATE_PLAN_2026-11.md`
- 범위: server, go-scraper, web, admin, mobile, CI, Kubernetes/ArgoCD, 스토어 배포 준비

## 1. 요약

| 영역 | 결과 |
|------|------|
| 의존성 업데이트 | 5개 컴포넌트 모두 최신화 후 main 머지 및 배포 완료 (mobile은 스토어 제출 단계) |
| 보안 | 프로덕션 npm 취약점 0건, CI 스크립트 인젝션 수정, git remote 토큰 제거 |
| CI | PR 단계 lint/test/Docker 빌드 검증 도입, 배포 실패 원인 2건 수정 |
| Google Play | targetSdk 36 충족, 미사용 백그라운드 위치 권한 제거, 릴리스 AAB 빌드 |
| iOS | Swift Package Manager 전환, Crashlytics dSYM 업로드 추가, iOS 26.5 플랫폼 설치 |
| ArgoCD | 비정상 앱 2개, ApplicationSet 에러 1개 정상화 (전체 Synced/Healthy) |

## 2. 머지된 PR

### reviewmaps

| PR | 내용 |
|----|------|
| #266 | ci: PR 검증 추가, Actions 최신화, 스크립트 인젝션 수정 |
| #261 | server: Go 1.26 및 의존성 최신화 (계획 문서 포함) |
| #262 | go-scraper: Go 1.26, OTel 1.47, semconv 스키마 충돌 수정 |
| #263 | web: Next.js 16.4 / React 19.3 보안 업데이트, Node 24 |
| #267 | ci: infra 배포 PR auto-merge 실패 대응, 배포 concurrency 분리 |
| #265 | admin: Django 6.1, Unfold 0.110, gunicorn 27 |
| #264 | mobile: Flutter 3.47, iOS SPM 전환, 보안·안정성 개선 |
| #268 | docs: 계획 문서 진행 상황 반영 |
| #269, #271, #272, #273 | mobile: Android 빌드 번호 92 → 100 → 101 → 102 |
| #270 | android: 미사용 location 플러그인 제거 (FOREGROUND_SERVICE_LOCATION 삭제) |

### infra

| PR | 내용 |
|----|------|
| #1117 | ArgoCD 비정상 앱 정상화 (hotsao 잔여 설정 비활성화, ApplicationSet 중복 해소) |
| #1112 | web 배포 태그 반영 (auto-merge 실패로 멈춘 배포 PR 수동 머지) |

## 3. 컴포넌트별 변경

### server (Go Fiber)

| 항목 | 이전 → 이후 |
|------|-------------|
| Go / Docker | 1.23, alpine 3.19 → 1.26, golang:1.26-alpine3.24, alpine 3.24 |
| Fiber | 2.52.10 → 2.52.16 |
| OpenTelemetry | 1.38.0 → 1.47.0 |
| Firebase Admin | 4.18.0 → 4.22.0 |
| google.golang.org/api | 0.231.0 → 0.311.0 |
| x/crypto | 0.41.0 → 0.58.0 |

- deprecated `option.WithCredentials*` → `WithAuthCredentials*(option.ServiceAccount, ...)`
- FCM `Token`/`Tokens`는 유지: `Fid`는 Firebase Installation ID로 앱이 보내는 FCM 등록 토큰과 다른 값이라 교체 시 푸시 전체 실패

### go-scraper

| 항목 | 이전 → 이후 |
|------|-------------|
| Go / Docker | 1.23 → 1.26, alpine 3.24 |
| pgx | 5.7.2 → 5.12.0 |
| OpenTelemetry | 1.32.0 → 1.47.0 (server와 통일) |
| semconv | v1.26.0 → v1.43.0 |

- semconv를 올리지 않으면 `resource.Merge`가 `conflicting Schema URL` 에러를 내 텔레메트리 초기화 실패 (재현 후 수정 확인)

### web (Next.js)

| 항목 | 이전 → 이후 |
|------|-------------|
| next / eslint-config-next | 16.0.7 → 16.4.6 |
| react / react-dom | 19.1.0 → 19.3.1 (정확 버전 고정 유지) |
| Node | 20 (EOL) → 24 LTS |

- eslint 순환 참조 오류 수정 (FlatCompat 제거, flat config 직접 사용)
- `middleware.ts` → `proxy.ts` (Next 16 deprecated 대응), `/app-ads.txt` 응답 유지 확인
- npm audit: 프로덕션 취약점 0건 (dev 도구 minimatch moderate만 잔존)

### admin (Django)

| 항목 | 이전 → 이후 |
|------|-------------|
| Django | 6.0 → 6.1.3 |
| django-unfold | 0.72.0 → 0.110.1 |
| gunicorn | 23.0.0 → 27.0.0 |
| ruff | 0.14.8 → 0.17.4 |

- ruff 0.17 기본 규칙 확장 대응: lint 규칙을 E4/E7/E9/F + I로 명시 고정
- gunicorn 27 control socket 비활성화 (`--no-control-socket`)

### mobile (Flutter)

| 항목 | 이전 → 이후 |
|------|-------------|
| Flutter / Dart | 3.35.4 / 3.9.2 → 3.47.9 / 3.13.7 |
| Firebase | core 3.x → 5.1 (messaging 17, crashlytics 6, analytics 13 등) |
| google_sign_in | 6.3 → 7.2 (API 재작성) |
| kakao / sign_in_with_apple | 1.9 / 6.1 → 2.1 / 8.2 |
| google_mobile_ads | 6.0 → 9.2 |
| flutter_secure_storage | 9.2 → 10.3 (v11은 다음 배포) |
| Android | AGP 9.2.1, Gradle 9.4.1, Kotlin 2.4, Java 17, compileSdk 37, targetSdk 36, minSdk 24 |
| iOS | CocoaPods → Swift Package Manager, 배포 타깃 15.6 통일 |
| 버전 | iOS 2.1.2+1, Android 2.1.2+102 |

주요 판단:

| 판단 | 이유 |
|------|------|
| iOS SPM 전환 | Firebase iOS SDK가 12.9.0(2026-02)을 끝으로 CocoaPods 배포 중단, GMA SDK 13.11+도 CocoaPods 없음 |
| secure_storage v10 경유 | v9 → v11 직행 시 기존 데이터 읽기 불가로 Android 사용자 전원 강제 로그아웃 |
| FCM `getToken` 유지 | deprecated지만 서버가 FCM 등록 토큰 사용 |
| location 패키지 제거 | 코드 미사용, 플러그인이 FOREGROUND_SERVICE_LOCATION과 위치 서비스를 병합 |

## 4. 보안 조치

| 항목 | 상태 | 내용 |
|------|------|------|
| CI 스크립트 인젝션 | ✅ 수정 | manifest 업데이트 단계에서 커밋 메시지를 셸에 직접 삽입 → env 전달로 변경 (admin은 큰따옴표 직접 삽입으로 가장 위험) |
| git remote 토큰 | ✅ 제거 | remote URL의 GitHub 토큰 제거, gh 인증으로 전환 |
| 노출된 GitHub 토큰 폐기 | ⏳ 사용자 조치 | GitHub 설정에서 폐기 필요 |
| mobile/.env의 JWT_* | ⏳ 사용자 조치 | 앱 미사용인데 앱 번들에 포함됨. 삭제 필요, 운영 키와 같으면 서버 키 교체 |
| Naver 검색 API 시크릿 | ⏳ 중기 과제 | 앱에 17쌍 포함 → 서버 프록시 이전 권장 |
| 저장소 비밀값 이력 | ✅ 확인 | 공개 저장소에 .env, xcconfig 비밀값 커밋 이력 없음 |

## 5. CI / 배포 개선

| 문제 | 원인 | 조치 |
|------|------|------|
| PR에서 검증 없음 | 모든 워크플로가 main push에서만 실행 | pull_request 트리거 추가, PR은 Docker 빌드만 (push 없음) |
| Actions 노후화 | checkout v4, setup-uv v4 등 | checkout/setup-* v7, setup-uv v10.3.3, build-push v7, login v4 |
| setup-uv 실패 | v10 메이저 태그 미제공 | 정확한 버전 v10.3.3 고정 |
| web 배포 실패 | infra PR이 clean 상태면 `gh pr merge --auto` 거부 | auto-merge 실패 시 즉시 squash 머지로 대체 |
| 배포 취소 | server/web/admin 공유 concurrency 그룹에서 대기 실행 취소 | 워크플로별 배포 그룹으로 분리 |

## 6. Google Play 대응

| 알림 | 원인 | 조치 |
|------|------|------|
| targetSdk 36 필요 | 기존 빌드가 Flutter 3.35로 targetSdk 35 | Flutter 3.47로 targetSdk 36 |
| FOREGROUND_SERVICE_LOCATION 사용 신고 | 미사용 location 플러그인의 권한 병합 | 패키지 제거 및 manifest에서 권한·서비스 명시 제거 (동영상 제출 불필요) |
| 광고 ID 권한 누락 | 다른 트랙에 2025-09 이전 활성 빌드가 남음 | 새 빌드는 AD_ID 포함 확인. 모든 활성 트랙을 새 빌드로 교체 필요 |
| versionCode 사용됨 | 92, 93 이미 업로드 | 100 → 101 → 102로 상향 |

최종 릴리스 AAB 검증 결과:

| 항목 | 값 |
|------|-----|
| versionName / versionCode | 2.1.2 / 102 |
| targetSdk / compileSdk / minSdk | 36 / 37 / 24 |
| 서명 | 릴리스 키 |
| AD_ID 권한 | 포함 |
| FOREGROUND_SERVICE_LOCATION | 없음 |
| 16KB 페이지 정렬 | 네이티브 라이브러리 6개 및 zipalign 충족 |

## 7. iOS 빌드 환경

| 문제 | 원인 | 조치 |
|------|------|------|
| Crashlytics dSYM 누락 알림 | Crashlytics dSYM 업로드 빌드 단계 없음 | Release/Profile 빌드에 업로드 단계 추가 (SPM 경로) |
| iOS 26.5 미설치로 빌드 불가 | 플랫폼 다운로드 Code 41 실패 | mobileassetd 재시작 후 다운로드 성공, iOS 26.5 (23F77) 설치 |
| codesign 키 접근 창 반복 | 키체인 partition list에 codesign 미허용 | `security set-key-partition-list`로 codesign 허용 설정 |

참고: 개발 Mac이 Intel(x86_64)이며 Flutter는 Intel Mac 지원 축소를 예고함.

## 8. Kubernetes / ArgoCD 정상화 (yanggo-514212)

| 대상 | 이전 상태 | 원인 | 조치 |
|------|-----------|------|------|
| istio-gateway-config | OutOfSync / Sync Failed | 이관 제외된 hotsao의 VirtualService 3개, namespace 없음 | enabled=false, Gateway hotsao TLS 주석 처리 |
| cert-manager | Progressing 26시간 이상 | hotsao.com 인증서 ACME 검증 불가 (DNS 미전환) | hotsao_com 인증서 비활성화, 멈춘 동기화 종료 |
| infra-infrastructure-prod | ErrorOccurred | apps-*-cfg.yaml이 infra-apps-prod와 중복 매칭 | apps-*.yaml 제외 패턴 추가 후 적용 |

결과:

| 항목 | 상태 |
|------|------|
| ArgoCD Application 11개 | 모두 Synced / Healthy |
| ApplicationSet 6개 | 에러 없음, `argocd_yaml/` 파일과 클러스터 일치 |
| 인증서 | ggorockee, review-maps, woohalabs 3개 Ready |
| 서비스 헬스체크 | api, web, admin 모두 200 |

알아둘 것:

| 항목 | 내용 |
|------|------|
| grafana / prom 503 | 모니터링 스택이 이관 시 의도적으로 비활성화됨 (Pod 0개) |
| ggorockee.com 루트 SSL 오류 | 인증서가 와일드카드만 포함, 루트 도메인 서비스 없음 (영향 없음) |

## 9. 남은 작업

### 사용자 조치
- [ ] 노출된 GitHub Personal Access Token 폐기
- [ ] mobile/.env의 JWT_* 4줄 삭제 (운영 키와 같으면 서버 JWT 키 교체)
- [ ] iOS: Xcode에서 Archive 후 App Store Connect 업로드 (빌드 번호 1 중복 시 상향)
- [ ] Android: versionCode 102 업로드, 예전 빌드가 남은 트랙도 새 빌드로 교체 (광고 ID 경고 해소)
- [ ] Play Console 광고 ID 선언 재저장

### 운영 확인
- [ ] 실기기: Google/Kakao/Apple 로그인, 푸시, 광고, 업데이트 후 로그인 유지
- [ ] server: SNS 로그인, FCM 발송
- [ ] go-scraper: 스크레이퍼 실행, SigNoz 수집
- [ ] admin: 상세 편집·저장 화면
- [ ] 릴리스 후 Crashlytics dSYM 업로드 확인

### 후속 개발
- [ ] flutter_secure_storage v11 상향 (v10 배포 정착 후)
- [ ] FCM `getToken` → `register()` 전환 검토
- [ ] Naver 검색 API 서버 프록시 이전
- [ ] 레거시 ci-scrape.yml 정리 여부 결정
- [ ] 기본 템플릿 widget_test.dart 교체 (첫 커밋부터 실패)
- [ ] 모니터링 스택 재활성화 여부 결정

## 10. 빌드 명령 참고

| 대상 | 명령 |
|------|------|
| Android 릴리스 | `flutter build appbundle --release --build-name=2.1.2 --build-number=102` |
| iOS | Xcode에서 `ios/Runner.xcworkspace` → Any iOS Device → Product → Archive |

pubspec.yaml은 iOS 버전 줄이 활성화되어 있으므로 Android 빌드 시 빌드 번호를 반드시 지정한다.
