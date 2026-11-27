# 리뷰맵 관리자 운영 문서

작성: 2026-11-27. 관리자 화면을 Django에서 Go API + Nuxt 화면으로 옮긴 뒤의 운영 기준입니다. 결정 과정과 단계별 체크리스트는 `claudedocs/planning/2026-11-admin-go-migration.md`, 화면 개발 방법은 `admin/README.md`.

## 1. 한눈에 보기

| 항목 | 값 |
|---|---|
| 주소 | https://admin.review-maps.com |
| 화면 | `admin/` (Nuxt 4 + @nuxt/ui 정적 화면, nginx 8080), 이미지 `ggorockee/reviewmaps-admin:<날짜>-<커밋>` |
| API | `server/`의 `/admin/v1` (reviewmaps-server, https://api.review-maps.com/admin/v1) |
| DB | 운영 Cloud SQL 그대로 (앱과 같은 DB). 관리자 전용 테이블 `admin_sessions`, `admin_audit_logs` |
| 로그인 | Google 계정 (허용 목록 `ADMIN_EMAILS`) + 예비 아이디/비밀번호 |
| 이전 관리자 | Django (`admin-django/`, 이미지 `20261110-7ed5b97`) — 되돌리기용으로 보관, 2026-12-27 이후 정리 |
| 전환일 | 2026-11-27 (infra #1227) |

## 2. 화면별로 할 수 있는 일

| 메뉴 | 할 수 있는 일 | 주의 |
|---|---|---|
| 대시보드 | 사용자·키워드·캠페인 요약, 출처별 카테고리 없는 캠페인 비율, 최근 변경 | |
| 사용자 | 검색, 상세(SNS·키워드·기기), 비활성, 삭제 | 삭제는 이메일을 다시 입력해야 함. 앱 회원 탈퇴와 같은 처리(키워드·알림·기기·SNS 함께 삭제), 되돌릴 수 없음 |
| 키워드·키워드 알림 | 켜기/끄기, 삭제, 오래된 알림 일괄 정리 | 일괄 정리는 대상 건수를 먼저 확인. 알림 삭제는 soft delete(DB에는 남음) |
| 캠페인 | 검색·필터, 프로모션 단계(0~10), 앱에서 숨기기/복구 | 내용 수정은 다음 수집 때 덮어써져서 제공하지 않음 |
| 카테고리 | 추가·이름 변경·순서·삭제 | 캠페인이나 매핑에서 쓰는 카테고리는 삭제 불가 |
| 카테고리 매핑 | 수집 원본 카테고리를 앱 카테고리에 연결 (사용량 순, 추천 미리 선택). 신뢰도 슬라이더(30~100%, 5% 단위, 기본 80%)로 기준을 정해 "N% 이상 선택", 표 머리 칸 체크박스로 이 페이지 전체 선택·해제, "선택 해제". 기준 이상 추천은 초록 배지 | 다음 수집(매일 00:05, 02:00, 피클리 02:30)부터 반영 |
| 설정·앱 버전 | 키워드 최대 개수(1~100), 알림 보관 일수(1~365) 변경 | 앱 버전·광고·요청 제한은 읽기 전용 (앱 2.2.0부터 Firebase Remote Config로 관리) |
| 변경 기록 | 관리자 변경 전부 (누가·언제·바꾸기 전·후) | 삭제 불가 |

## 3. 로그인과 계정

| 항목 | 내용 |
|---|---|
| 허용 계정 | GSM `prod-reviewmaps-api-credentials`의 `ADMIN_EMAILS` (현재 woohaen88, woohalabs) |
| Google 로그인 조건 | ① `ADMIN_EMAILS`에 있음 ② Google Cloud `yanggo-514212` → Google 인증 플랫폼 → 대상 → 테스트 사용자에 있음 (동의 화면이 "테스트 중"이라 없으면 Google 로그인 창에서 막힘) |
| OAuth 클라이언트 | `yanggo-514212` 웹 클라이언트 (Grafana·ArgoCD·라익찍스 관리자와 공용). 승인된 JavaScript 원본에 `https://admin.review-maps.com`, `http://localhost:3001`, 승인된 리디렉션 URI에 같은 주소 + `/login` |
| 예비 로그인 | 아이디 `rm-breakglass`. 비밀번호 원문은 infra `.secrets/reviewmaps-admin-breakglass.env`(로컬 전용), GSM에는 bcrypt 해시(`ADMIN_PASSWORD_HASH`)만 |
| 세션 | 12시간. 쿠키 `rm_admin`(HttpOnly, Secure, SameSite=Strict, 경로 `/admin/v1`). DB에는 토큰의 SHA-256만 |
| 보안 | 다른 주소에서 온 변경 요청은 403(Origin 검사). 로그인은 IP당 분당 5회 |
| 프로젝트 소유 계정 | `yanggo-514212` 콘솔 수정은 woohalabs11 계정으로 (다른 계정은 "추가 액세스 권한 필요") |

### 관리자 계정 추가·제거 절차

| 순서 | 할 일 |
|---|---|
| 1 | GSM `prod-reviewmaps-api-credentials`의 `ADMIN_EMAILS`(쉼표 구분)를 고친 새 버전 추가 (실행 직전 개발자 승인) |
| 2 | 테스트 사용자에 같은 계정 추가 (콘솔 저장이 반응하지 않으면 광고 차단 확장을 끄고 다시) |
| 3 | Secret 갱신: `kubectl -n reviewmaps annotate externalsecret reviewmaps-api-credentials force-sync=<시각> --overwrite` (기다리면 1시간 안에 자동) |
| 4 | 서버 재시작: `kubectl -n reviewmaps rollout restart deploy/reviewmaps-server` (환경변수는 재시작해야 반영) |
| 5 | 확인: Grafana `reviewmaps-http-metrics` 관리자 행에서 로그인 성공 증가 |

## 4. 배포와 되돌리기

| 대상 | 방법 |
|---|---|
| 화면 | reviewmaps main 머지(`admin/**`) → `ci-admin.yml`이 이미지 빌드 → infra 태그 PR 자동 머지 → ArgoCD. 저장소 변수 `ADMIN_AUTO_DEPLOY=true`일 때만 자동 |
| API | reviewmaps main 머지(`server/**`) → `ci-server.yml` → infra 태그 PR 자동 머지 (앱 API와 같은 서버) |
| 서버 설정 | infra `charts/helm/prod/reviewmaps/values.yaml`의 서버 configMap(`ADMIN_ORIGIN`, `ADMIN_GOOGLE_CLIENT_ID`), ExternalSecret(`ADMIN_EMAILS`, `ADMIN_LOGIN_ID`, `ADMIN_PASSWORD_HASH`). 바꾼 뒤 서버 재시작 필요 |
| 관리자 API 끄기 | 서버 configMap에서 `ADMIN_ORIGIN` 제거 → 재시작 (`/admin/v1` 자체가 등록되지 않음) |
| 되돌리기 (Django로) | infra #1227 revert → ArgoCD 동기화. Service 포트(8000)가 같아 VirtualService 변경 없음. `ADMIN_AUTO_DEPLOY`도 false로 |

## 5. 모니터링

| 대상 | 위치 |
|---|---|
| 대시보드 | https://monitoring.ggorockee.com/d/reviewmaps-http-metrics 의 "관리자 화면" 행(로그인 성공·실패, 허용 목록 밖 시도, 활성 세션, 변경 추이, 최근 변경 표)과 "카테고리 매핑" 행(미매핑 원본, 출처별 카테고리 없는 캠페인 비율) |
| 접속 검사 | blackbox `https://admin.review-maps.com/healthz` (실패 3분이면 CRITICAL 메일) |

| 알림 | 조건 | 등급 |
|---|---|---|
| ReviewmapsAdminLoginFailures | 로그인 실패·거부 10분 10회 초과 | WARN |
| ReviewmapsAdminUnauthorizedLogin | 허용 목록 밖 Google 계정 로그인 시도 | INFO |
| ReviewmapsCategoryUnmappedBacklog | 미매핑 원본 카테고리 50개 이상 7일 | INFO |

| 지표 | 뜻 |
|---|---|
| `reviewmaps_admin_logins_total{method,result}` | 로그인 시도 (method: google/password, result: success/invalid_token/invalid_password/not_allowed/rate_limited) |
| `reviewmaps_admin_changes_total{entity,action}` | 관리자 변경 수 |
| `reviewmaps_admin_sessions_active` | 유효한 세션 수 |
| `reviewmaps_raw_categories_unmapped` | 미매핑 원본 카테고리 수 (5분마다 DB 조회) |
| `reviewmaps_campaigns_uncategorized_ratio{source}` | 카테고리 없는 활성 캠페인 비율 (source="전체" 포함) |

## 6. 카테고리 매핑

### 왜 밀렸나

예전 Django Ninja 서버에는 미매핑 원본 카테고리를 받아 매핑을 저장하는 API가 있었는데, 서버를 Go로 옮기면서 빠져 2025-09 이후 새 원본 카테고리가 매핑되지 않았습니다. 그 결과 활성 캠페인의 49.6%(inflexer 92.5%)가 카테고리 없이 저장되어 앱 카테고리 필터에 나오지 않았습니다. 숫자 원본(`1`~`12`)은 예전 Python 수집기가 카테고리 ID를 원문 칸에 넣은 것이라 번호가 곧 `categories.id`입니다.

### 수집기가 매핑을 쓰는 방식

피클리는 사이트 카테고리를 `피클리>맛집`처럼 접두어를 붙여 원본으로 쌓습니다(첫 수집 뒤 매핑 필요). go-scraper(inflexer, 리뷰노트)는 수집할 때 지역 검색 캐시의 원본 문구 → `raw_categories` → `category_mappings` 순으로 카테고리를 찾습니다. 매핑을 저장하면 다음 수집부터 반영되고, 수집은 지운 뒤 다시 넣는 방식이라 기존 캠페인도 다음 수집 때 바뀝니다.

### 추천 규칙

| 순서 | 규칙 | 신뢰도 |
|---|---|---|
| 1 | 숫자 원본이 `categories.id`와 같으면 그 카테고리 | 100% |
| 2 | 원문의 상위 경로(`>` 앞부분, 긴 것부터)가 기존 매핑에 있으면 그중 가장 많은 카테고리 | 그 카테고리 비율 |
| 3 | 둘 다 없으면 추천 없음 | - |

### 2026-11-27 1차 정리 결과

| 항목 | 값 |
|---|---|
| 신뢰도 80% 이상 추천 일괄 매핑 | 129개 (숫자 원본 12개 포함, 사용량 상위부터 확인 후) |
| 추천 없는 사용량 상위 수동 매핑 (개발자 승인) | 11개: 미술·음악·요리·연기교육 → 문화/클래스, 휴대폰·아동도서 → 쇼핑, 행정복지센터 → 기타, 유람선 → 여행, 카페,디저트 → 카페/디저트, 스포츠교육·레저,테마 → 액티비티 |
| 미매핑 원본 | 623 → 483 (남은 것은 대부분 사용 1~2회) |
| 확인 | 운영 DB 읽기 전용 조회로 저장·변경 기록 확인 |
| 다음 확인 | 2026-11-28 수집 뒤 카테고리 없는 캠페인 비율 (전 49.6%) |

## 7. 이번 전환에서 함께 고친 것

| 문제 | 내용 | 수정 |
|---|---|---|
| 앱 회원 탈퇴 실패 | 운영 DB의 users 외래 키가 모두 NO ACTION(Django 시절 그대로)이라 SNS·키워드·기기 데이터가 있는 사용자(160명 중 146명)는 탈퇴가 실패 | 한 트랜잭션에서 연관 데이터 먼저 삭제 (#304). 앱 탈퇴와 관리자 삭제가 같은 함수 |
| Django 원본 카테고리 화면 | 실제 테이블 컬럼(`raw_text`)과 모델이 달라 동작하지 않았음 | 새 화면으로 대체 |
| 설정 기본값 | 저장된 값이 없는 설정(알림 보관 일수)이 화면에 1로 채워져 잘못 저장될 수 있었음 | 서버가 기본값(3일, 키워드 10개)과 `stored:false`를 줌 (#305) |

알려진 제약: 예전 Django 스태프 사용자 중 `django_admin_log` 기록이 있는 사용자는 삭제 시 외래 키 오류가 납니다 (Phase 7에서 Django 테이블을 정리하면 해소).

## 8. 겪은 문제와 해결

| 증상 | 원인 | 해결 |
|---|---|---|
| 서버 설정을 바꿨는데 `/admin/v1`이 404 | configMap·Secret만 바뀌면 Pod가 다시 뜨지 않음 | `kubectl -n reviewmaps rollout restart deploy/reviewmaps-server` |
| Google 콘솔에서 "추가 액세스 권한 필요" | 다른 계정으로 열림 | 프로젝트 소유 계정 woohalabs11로 (`authuser=woohalabs11@gmail.com`) |
| 테스트 사용자 "저장"이 반응 없음 | 브라우저 확장이 www.gstatic.com 차단 | 광고 차단 확장을 끄고 직접 추가 |
| 콘솔 일부가 영어 | Google 화면 자체가 일부 번역 안 됨 | 주소에 `hl=ko`를 붙이면 대부분 한국어 ("Add users" 등은 그대로) |
| 전환 전 새 이미지가 Django 자리에 들어갈 위험 | CI가 같은 이미지 이름으로 infra 태그를 자동 갱신 | 저장소 변수 `ADMIN_AUTO_DEPLOY`로 전환 전까지 막음 |

## 9. 로컬 개발

| 순서 | 명령 |
|---|---|
| 1 | `cd server && go run ./cmd/admindev` (메모리 SQLite + 예시 데이터, :3000) |
| 2 | `cd admin && npm install && npm run dev -- --port 3001` → "개발용 로그인" |
| 검사 | 화면 `npm run lint`, `npm run typecheck`, `npm test`, `npm run generate` / 서버 `go test ./...` |

## 10. 남은 일

| 시점 | 할 일 |
|---|---|
| 2026-11-28 | 수집 뒤 카테고리 없는 캠페인 비율 확인 (안 내려가면 수집기 매핑 적용 조사) |
| 개발자 | woohalabs@gmail.com을 OAuth 테스트 사용자에 추가 |
| ~2026-12-04 | 1주 관찰: 로그인 실패·오류·변경 기록 |
| 2026-12-27 이후 | Phase 7: `django_admin_log` 내보내기 → Django 테이블 삭제(운영 DB 쓰기, 실행 직전 승인) → `admin-django/` 코드 삭제 |
| 필요 시 | 남은 미매핑 483개 중 신뢰도 80% 미만 추천 판단 |

## 11. 관련 PR

| 저장소 | PR | 내용 |
|---|---|---|
| reviewmaps | #302 | 전환 계획 |
| reviewmaps | #304 | 관리자 API, 회원 탈퇴 수정 |
| reviewmaps | #305 | Nuxt 화면, Django 보관, CI |
| reviewmaps | #306, #307, #308 | 진행 기록 |
| infra | #1223 | 서버 관리자 API 설정 |
| infra | #1224, #1228 | CLAUDE.md 배포 경로 |
| infra | #1225, #1226 | 대시보드·알림 |
| infra | #1227 | 화면 전환 |
