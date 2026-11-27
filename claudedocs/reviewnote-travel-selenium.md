# 리뷰노트 여행 카테고리 Selenium 수집기 (2026-11-27)

사용법은 `selenium-scraper/README.md`. 이 문서는 조사 결과·결정·남은 일을 기록합니다.

## 왜 만들었나

숙박·캠핑장 캠페인의 이용 가능·불가 요일을 앱에 보여주려는 작업(모바일 `StayAvailability`, 브랜치 `feature/stay-available-days`)은 제공 내역 문구에서 요일을 추정합니다. 리뷰노트는 이 값을 상세 페이지에 별도 필드로 갖고 있지만 상세는 로그인해야 보이고, 제휴·API 요청은 거절됐습니다. 그래서 로그인한 브라우저로 화면 경로를 따라 들어가는 Selenium 수집기를 만들었습니다.

## 조사 결과 (2026-11-27)

| 항목 | 내용 |
|------|------|
| 목록 화면 | `/campaigns`, "카테고리" MUI 선택 상자 → "여행" 선택 시 주소 `?categoryId=d1910206-2676-433b-958f-6cb6e7385d1c`, 무한 스크롤 (16건씩) |
| 목록 API | `/api/v2/campaigns?categoryId=…&s=default&limit=16&page=N`, 로그인 불필요. 서버 렌더링 HTML에는 카테고리 필터가 적용되지 않음 |
| 여행 카테고리 규모 | 목록 1,148건 (모집 중 SELECT 413, 진행 중 PROGRESS 735) |
| 상세 화면 | `/campaigns/<id>`, 비로그인 시 "로그인이 필요합니다" → `/sns/login` (네이버·Apple 로그인만) |
| 상세 API | `/api/campaign?id=<id>` (Next.js API, next-auth 세션 쿠키 필요, 비로그인 401 "인증되지 않은 사용자입니다.") |
| 상세에만 있는 필드 | `possibleDays`, `impossibleDays`, `possibleTime`, `sameDayVisit`, `scheduleInformation`, `address`, `lat`, `lng`, `storeInformation.naverPlaceUrl`, `information`, `description`, `keyword` (상세 화면 JS에서 확인, 화면 표기 "체험 가능 요일 : …") |
| robots.txt | `Disallow: /campaigns/`, `/users/`, `/applies/` |
| 이미지 주소 | 사이트는 Firebase Storage(`firebasestorage.googleapis.com/v0/b/reviewnote-e92d9.appspot.com/o/<키>?alt=media`) 사용. `go-scraper`가 쓰는 S3 주소(`reviewnote.s3.ap-northeast-2.amazonaws.com/<키>`)는 확인한 16건 모두 404 |

## 결정

| 결정 | 이유 |
|------|------|
| 화면 DOM 대신 CDP 성능 로그에서 API 응답을 읽음 | 화면 구조 변경에 덜 깨지고, 값이 사이트 표기 그대로 남음 |
| 로그인은 사람이 전용 Chrome 프로필에서 직접 | 계정 비밀번호를 코드·Secret에 두지 않음. 네이버 로그인은 자동화 탐지·2단계 인증이 있어 자동 로그인 불가 |
| 기본은 모집 중(SELECT)만 상세 진입, 상세 사이 2~3초 | 리뷰맵이 쓰는 범위(go-scraper도 SELECT만 저장)로 요청 수를 줄임. 413건이면 약 20~30분 |
| 업체 연락처·신청자·사용자 상태는 저장 안 함 | 개인정보 |
| 결과는 우선 JSON 파일 | DB 반영 방식(go-scraper 리뷰노트 행에 필드 추가 vs 별도 테이블)을 정하기 전 실제 값 형태부터 확인 |

## 검증 (2026-11-27)

- [x] 단위 테스트 6개 (목록 응답 해석, 레코드 변환, 개인정보 키 제거, 이미지 주소)
- [x] 헤드리스 Chrome 실제 실행: 체험단 검색 메뉴 클릭 → 카테고리 → 여행 → 끝까지 스크롤, 1,148건 수집·전부 '여행'·목록 끝 도달
- [x] 비로그인 상세 진입 시 로그인 필요로 판단하고 중단
- [ ] 로그인 후 상세 수집 (`login` → `crawl --max-details 5`) — 개발자 로그인 필요
- [ ] 실제 `possibleDays`·`impossibleDays` 값 형태 확인 후 모바일 `StayAvailability` 파서와 비교

## 남은 일

- [ ] 로그인 후 상세 5건 시험 수집, 결과 확인
- [ ] 전체(모집 중 413건) 수집 1회, 이용 요일 정보가 있는 비율 확인
- [ ] DB 반영 방식 결정 (campaign에 요일 컬럼 추가 또는 별도 테이블, 서버 API·앱 표시 연결)
- [ ] 정기 실행 여부 결정. 로그인 세션이 필요해 클러스터 CronJob으로 옮기기 어려움 → 정기 실행하면 Pushgateway로 결과(목록·상세 성공·실패·로그인 만료) push와 알림 추가 필요. 그 전까지는 수동 실행이며 결과 `meta`와 종료 코드로 확인
- [ ] `go-scraper` 리뷰노트 이미지 주소(S3 404) 확인·수정 — 별도 작업
