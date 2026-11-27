# 리뷰노트 여행 카테고리 상세 수집 (2026-11-27)

운영 수집은 **go-scraper `reviewnote-detail`**(클러스터 CronJob, 브라우저 없음)이 하고, `selenium-scraper/`는 **로그인·세션 쿠키 갱신 도구**로 씁니다 (전체 수집 기능도 남아 있음, 사용법은 `selenium-scraper/README.md`). 이 문서는 조사 결과·결정·운영 절차·남은 일을 기록합니다.

## 운영 구조 (2026-11-28~)

| 구성 | 내용 |
|------|------|
| `reviewnote-detail` (CronJob 00:00) | 0~30분 무작위 대기 → 목록 API(로그인 불필요, 100건씩, 쪽 사이 10~20초)에서 여행·모집 중 고름 → 14일 안에 받은 것 제외, 없는 것·오래된 것 순 → 07:50까지 남은 시간을 남은 건수로 나눈 간격(×0.6~1.2, 최소 30초)으로 상세 API 1건씩 → `campaign_stay_detail` 저장·campaign 행 반영 → 끝에 campaign 전체 맞추기 |
| 차단 방지 | 동시 요청 없음, 401·403·429·5xx 한 번이면 그날 즉시 중단, 다른 실패 3회면 중단, Job 재시도 없음(backoffLimit 0), 08:30 강제 종료(activeDeadlineSeconds), 하루 최대 `REVIEWNOTE_DETAIL_MAX_FETCH` |
| `reviewnote` (CronJob 02:00) | 상세 API는 부르지 않고 `campaign_stay_detail` 값을 붙여 저장 (DELETE 후 INSERT 라 붙이지 않으면 요일이 지워짐) |
| DB | `server/migrations/add_stay_detail_to_campaign.sql`: campaign 에 `possible_days`, `impossible_days`, `possible_time`, `same_day_visit`, `reservation_notice`, `detail_fetched_at` + 보관 테이블 `campaign_stay_detail` |
| 서버 API | campaign 모델에 위 필드 추가 → 캠페인 목록·상세 응답에 포함 (값 없으면 생략) |
| 세션 | GSM `prod-reviewmaps-reviewnote-session` (`REVIEWNOTE_SESSION`, `REVIEWNOTE_SESSION_EXPIRES_AT`) → ExternalSecret `reviewnote-session` (optional, 없으면 상세만 건너뜀) |
| 지표 (Pushgateway, scraper="reviewnote-detail") | `reviewmaps_scraper_detail_session_ok`, `..._session_expiry_timestamp_seconds`(시작 직후 먼저 push), `..._blocked`, `reviewmaps_scraper_last_run_detail{type=target/reused/fetched/error/missing/with_days}` |
| 알림 | 만료 3일 전 [WARN](12시간마다 반복), 만료·401 [ERROR], 만료일 지표 없음 1시간 [ERROR], 차단 신호 [ERROR], Job 실패 [ERROR], 26시간 미성공 [ERROR] |
| 대시보드 | ReviewMaps 수집 서버(`reviewmaps-scraper`) "리뷰노트 여행 상세" 행 |

## 세션 갱신 (약 15일마다, 만료 3일 전 [WARN] 메일이 오면)

1. `selenium-scraper`에서 `uv run python -m selenium_scraper login` → 열린 창에서 **수집 전용 계정**으로 네이버 로그인 (미가입 계정은 회원가입 화면으로 감)
2. `uv run python -m selenium_scraper session | gcloud secrets versions add prod-reviewmaps-reviewnote-session --data-file=- --project=yanggo-514212` (쿠키 값이 화면·파일에 남지 않게 파이프로만 전달, gcloud 쓰기라 실행 전 개발자 승인)
3. ExternalSecret은 1시간마다 갱신. 바로 반영하려면 `kubectl -n reviewmaps annotate externalsecret reviewmaps-reviewnote-session force-sync=$(date +%s) --overwrite`
4. 다음 날 아침 대시보드 "세션 만료까지"가 약 15일로 바뀌었는지 확인

쿠키 형태: `reviewNoteSession`(HttpOnly, 약 15일) 하나로 상세 API 200. 사용해도 연장되지 않음(2026-11-27 확인, 응답에 새 세션 쿠키 없음). `reviewnoteLoginToken`(30일)·`token` 만으로는 401.

## 왜 만들었나

숙박·캠핑장 캠페인의 이용 가능·불가 요일을 앱에 보여주려는 작업(모바일 `StayAvailability`, 브랜치 `feature/stay-available-days`)은 제공 내역 문구에서 요일을 추정합니다. 리뷰노트는 이 값을 상세 페이지에 별도 필드로 갖고 있지만 상세는 로그인해야 보이고, 제휴·API 요청은 거절됐습니다. 그래서 로그인한 브라우저로 화면 경로를 따라 들어가는 Selenium 수집기를 만들었습니다.

## 조사 결과 (2026-11-27)

| 항목 | 내용 |
|------|------|
| 목록 화면 | `/campaigns`, "카테고리" MUI 선택 상자 → "여행" 선택 시 주소 `?categoryId=d1910206-2676-433b-958f-6cb6e7385d1c`, 무한 스크롤 (16건씩) |
| 목록 API | `/api/v2/campaigns?categoryId=…&s=default&limit=16&page=N`, 로그인 불필요. 서버 렌더링 HTML에는 카테고리 필터가 적용되지 않음 |
| 여행 카테고리 규모 | 목록 1,148건 (모집 중 SELECT 413, 진행 중 PROGRESS 735) |
| 상세 화면 | `/campaigns/<id>`, 비로그인 시 "로그인이 필요합니다" → `/sns/login` (네이버·Apple 로그인만) |
| 상세 API | `/api/campaign?id=<id>` (Next.js API, 비로그인 401 "인증되지 않은 사용자입니다.") |
| 로그인 상태 | next-auth 세션(`/api/auth/session`)은 로그인해도 비어 있음. 쿠키 `reviewnoteLoginToken`·`isLogin`으로 판단 |
| 로그인 계정 | 리뷰노트에 가입 안 된 네이버 계정으로 로그인하면 `/users/signup`(회원가입)으로 감 → 가입된 계정 필요 |
| 상세에만 있는 필드 | `possibleDays`, `impossibleDays`, `possibleTime`, `sameDayVisit`, `scheduleInformation`, `zipcode`, `address1`, `address2`, `lat`, `lng`, `storeInformation.naverPlaceUrl`, `information`, `description`, `keyword1~3` (화면 표기 "체험 가능 요일 : …") |
| 요일 값 형태 | `possibleDays`는 "월 / 화 / 수 / 목 / 일"처럼 ` / `로 구분된 요일 목록, "금" 한 개도 있음. `possibleTime`은 "오후 3시 ~ 오전 11시", "24시간 영업" 같은 자유 문구. 시험 5건은 `impossibleDays`가 모두 비어 있음 |
| robots.txt | `Disallow: /campaigns/`, `/users/`, `/applies/` |
| 이미지 주소 | 사이트는 Firebase Storage(`firebasestorage.googleapis.com/v0/b/reviewnote-e92d9.appspot.com/o/<키>?alt=media`) 사용. `go-scraper`가 쓰는 S3 주소(`reviewnote.s3.ap-northeast-2.amazonaws.com/<키>`)는 확인한 16건 모두 404 |

## 결정

| 결정 | 이유 |
|------|------|
| 화면 DOM 대신 CDP 성능 로그에서 API 응답을 읽음 | 화면 구조 변경에 덜 깨지고, 값이 사이트 표기 그대로 남음 |
| 로그인은 사람이 전용 Chrome 프로필에서 직접 | 계정 비밀번호를 코드·Secret에 두지 않음. 네이버 로그인은 자동화 탐지·2단계 인증이 있어 자동 로그인 불가 |
| 기본은 모집 중(SELECT)만 상세 진입 | 리뷰맵이 쓰는 범위(go-scraper도 SELECT만 저장)로 요청 수를 줄임 |
| 운영은 Go(브라우저 없이 쿠키 하나로 HTTP) | 상세 API가 `reviewNoteSession` 쿠키 하나로 열림. 기존 go-scraper·CronJob·지표·알림을 그대로 씀 |
| 상세는 별도 CronJob으로 새벽 내내 천천히 | 차단 방지가 최우선 (개발자 요청 2026-11-27). 시간대는 00:00~08:00(하루 400건 이상 가능), 첫날 100건 시험 후 450건 |
| 상세 값은 보관 테이블이 원본 | campaign 은 수집 때마다 DELETE 후 INSERT 되어 값이 지워짐 |
| 세션 만료일을 시작 직후 push + 지표 없음 알림 | 만료 3일 전 메일이 반드시 가도록 (개발자 요청). Pushgateway PVC 보관이라 Job이 안 돌아도 계산 유지 |
| 업체 연락처·신청자·사용자 상태는 저장 안 함 | 개인정보 |
| 결과는 우선 JSON 파일 | DB 반영 방식(go-scraper 리뷰노트 행에 필드 추가 vs 별도 테이블)을 정하기 전 실제 값 형태부터 확인 |

## 검증 (2026-11-27)

- [x] 단위 테스트 6개 (목록 응답 해석, 레코드 변환, 개인정보 키 제거, 이미지 주소)
- [x] 헤드리스 Chrome 실제 실행: 체험단 검색 메뉴 클릭 → 카테고리 → 여행 → 끝까지 스크롤, 1,148건 수집·전부 '여행'·목록 끝 도달
- [x] 비로그인 상세 진입 시 로그인 필요로 판단하고 중단
- [x] 로그인 후 상세 수집: `crawl --max-items 40 --max-details 5` → 5건 모두 성공, 5건 모두 이용 요일 있음, 약 14초 (2026-11-27)
- [ ] 실제 `possibleDays`·`impossibleDays` 값 형태 확인 후 모바일 `StayAvailability` 파서와 비교

## 진행 (2026-11-27~)

- [x] go-scraper `reviewnote-detail` 구현·단위 테스트(일정 계획, 간격, 대상 고르기, 차단·만료 즉시 중단, 보관값 붙이기), 새 계정 쿠키로 실제 상세 API 호출 확인
- [x] 서버 campaign 모델 필드, 마이그레이션 SQL
- [x] infra: CronJob·ExternalSecret·알림 4개·대시보드 행 (infra PR)
- [x] 운영 DB 마이그레이션 적용 (개발자 승인, 2026-11-27 17:2x, 임시 Pod·한 트랜잭션, 컬럼 6개·보관 테이블 확인, 기존 리뷰노트 12,449행 유지)
- [x] GSM `prod-reviewmaps-reviewnote-session` 생성 (개발자 승인, 버전 1 = 수집 전용 계정 재로그인 쿠키, 만료 2026-12-12 17:43 KST)
- [x] 머지·이미지 반영·ArgoCD 동기화 확인 (reviewmaps #310 → 이미지 `20261127-990dcc0`, infra #1231. reviewmaps·kube-prometheus-stack Synced/Healthy, ExternalSecret SecretSynced, CronJob `reviewmaps-go-cron-reviewnote-detail` backoff 0·deadline 30600·MAX_FETCH 100)
- [x] 만료 3일 전 메일 실제 발송 시험: 시험 그룹(scraper=alert-test)에 만료 2일 남음 push → 5분 뒤 firing → Alertmanager email 수신자로 발송(실패 0) → 그룹 삭제. 실제 그룹에는 만료 시각을 미리 push(남은 14.99일, "만료일 지표 없음" 오탐 방지)
- [ ] 2026-11-28 첫 실행(100건) 결과 확인 → 이상 없으면 `REVIEWNOTE_DETAIL_MAX_FETCH` 450
- [ ] 모바일: 요일 배지를 문구 추정(`StayAvailability`) 대신 `possible_days`/`impossible_days` 우선 사용 (`feature/stay-available-days` 머지 후)
- [ ] 세션 갱신 2026-12-09 무렵 (현재 쿠키 만료 2026-12-12 17:43, 만료 3일 전 [WARN] 메일 2026-12-09 17:43 무렵)

## 겪은 문제 (2026-11-27)

| 문제 | 원인 | 조치 |
|------|------|------|
| 로그인했는데 `login`이 확인 못 함 (10분 시간 초과) | 로그인 뒤 창이 네이버 등 다른 페이지에 머물면 `driver.get_cookies()`가 리뷰노트 쿠키를 못 봄 | CDP `Network.getCookies`로 리뷰노트 주소 쿠키를 직접 조회, 대기 30분 |
| 이전 계정으로 로그인하면 회원가입 화면 | 리뷰노트 미가입 네이버 계정 | 가입된 수집 전용 계정 사용 |
| 세션 쿠키 값이 로컬 작업 로그·대화 기록에 한 번 출력됨 | 백그라운드로 넘어간 명령의 출력 순서 | 로그 파일 삭제, 그 쿠키 대신 재로그인한 새 쿠키를 GSM에 등록. 노출된 쿠키는 운영에 쓰지 않음(2026-12-12 만료). 쿠키 확인은 키·길이만 출력 |
| 노출 쿠키가 든 프로필 | - | `~/.reviewmaps/reviewnote-chrome-profile.exposed-20261127` 로 보관 (이전 계정 프로필은 `.old-account-20261127`), 필요 없으면 삭제 |

## 남은 일

- [x] 로그인 후 상세 5건 시험 수집, 결과 확인
- [ ] 전체(모집 중 413건) 수집 1회, 이용 요일 정보가 있는 비율 확인
- [ ] DB 반영 방식 결정 (campaign에 요일 컬럼 추가 또는 별도 테이블, 서버 API·앱 표시 연결)
- [ ] 정기 실행 여부 결정. 로그인 세션이 필요해 클러스터 CronJob으로 옮기기 어려움 → 정기 실행하면 Pushgateway로 결과(목록·상세 성공·실패·로그인 만료) push와 알림 추가 필요. 그 전까지는 수동 실행이며 결과 `meta`와 종료 코드로 확인
- [ ] `go-scraper` 리뷰노트 이미지 주소(S3 404) 확인·수정 — 별도 작업
