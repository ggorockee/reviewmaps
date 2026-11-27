# selenium-scraper — 리뷰노트 여행 카테고리 상세 수집기

리뷰노트 체험단 > 카테고리 > 여행의 캠페인을 Selenium으로 화면 경로대로 들어가 수집합니다. 상세 페이지에만 있는 **이용 가능·불가 요일, 가능 시간, 당일 방문 가능 여부, 예약 주의사항, 주소·좌표, 네이버 플레이스 주소**를 얻는 것이 목적입니다 (기존 `go-scraper` 리뷰노트 수집기는 목록 API만 써서 이 값이 없음).

## 동작 방식

| 단계 | 화면 동작 | 데이터 출처 |
|------|-----------|-------------|
| 1 | 홈 → 상단 "체험단 검색" | - |
| 2 | "카테고리" 선택 상자 → "여행" (주소에 `categoryId=d1910206-…`) | - |
| 3 | 목록 끝까지 스크롤 | 브라우저가 받은 `/api/v2/campaigns?categoryId=…` 응답 |
| 4 | 캠페인마다 상세 페이지 진입 (`/campaigns/<id>`) | 브라우저가 받은 `/api/campaign?id=<id>` 응답 (**로그인 필요**) |

- 화면 글자 대신 브라우저가 받은 JSON 응답을 Chrome 성능 로그(CDP)에서 읽습니다. 화면 디자인이 바뀌어도 응답 구조가 같으면 깨지지 않습니다.
- 메뉴·선택 상자는 글자("체험단 검색", "카테고리", "여행")로 찾습니다. 사이트가 이 글자를 바꾸면 2단계에서 실패합니다 (메뉴를 못 찾으면 목록 주소로 바로 이동).
- 기본은 모집 중(`SELECT`) 캠페인만 상세 진입. 상세 사이 2~3초 대기, 상세 연속 5회 실패 시 중단.

## 사용법 (이 디렉터리에서)

| 명령 | 설명 |
|------|------|
| `uv sync` | 의존성 설치 (Selenium. chromedriver는 Selenium Manager가 설치된 Chrome에 맞춰 자동 준비) |
| `uv run python -m selenium_scraper login` | Chrome 창이 열리면 **직접** 네이버(또는 Apple)로 로그인. 세션은 `~/.reviewmaps/reviewnote-chrome-profile`에 저장 (저장소 밖) |
| `uv run python -m selenium_scraper crawl --max-details 5` | 시험 실행: 상세 5건만 |
| `uv run python -m selenium_scraper crawl` | 전체 실행 (창 표시). `--headless`로 창 없이 |
| `uv run pytest -q` / `uv run ruff format --check .` | 테스트 / 포맷 검사 |

crawl 옵션: `--max-items`(목록 최대), `--max-details`(상세 최대), `--delay`(상세 사이 초, 기본 2), `--include-closed`(마감 캠페인도 상세 진입), `--out`(결과 경로), `--profile-dir`(프로필 경로).

## 결과

`output/reviewnote-travel-<시각>.json` (gitignore). `meta`에 목록 건수·상세 성공/실패·이용 요일 정보가 있는 건수·로그인 만료 여부, `items`에 캠페인별 레코드.

| 필드 | 내용 |
|------|------|
| `possibleDays` / `impossibleDays` / `possibleTime` | 체험 가능 요일 / 불가 요일 / 가능 시간 (사이트 표기 그대로, 예: "일~목") |
| `sameDayVisit` | 당일 예약·방문 가능 여부 (true/false, 값 없으면 null) |
| `scheduleInformation` | 예약 시 주의사항 |
| `address`, `lat`, `lng`, `naverPlaceUrl` | 방문 주소·좌표·플레이스 주소 |
| `offer`, `information`, `description` | 제공 내역, 제공 상세, 본문 |
| `imageUrl` | Firebase Storage 주소 (사이트가 실제로 쓰는 주소) |
| `raw` | 상세 응답 원본 (아래 개인정보 키 제외) |

저장하지 않는 값: 업체 연락처(`contact`), 업체·신청자 정보(`user`, `applies`, `userApply`, `applyPersonalInfo`), 로그인 사용자 상태(`isLiked` 등).

종료 코드: 0 정상, 1 실패(목록 0건 또는 상세 절반 이상 실패), 2 로그인 필요(세션 만료 시 그때까지 결과는 저장).

## 주의

- 리뷰노트 상세는 로그인한 사용자만 볼 수 있고, `robots.txt`가 `/campaigns/`를 막고 있으며, 제휴·API 요청은 거절된 상태입니다 (2026-11-27). 수집에 쓰는 계정이 제재될 수 있으니 본인 계정 대신 수집 전용 계정을 권장하고, 대기 시간을 줄이지 마세요.
- 로그인 정보(쿠키)는 프로필 폴더에만 있습니다. 저장소·서버에 올리지 마세요.
- 아직 DB 저장·정기 실행·모니터링은 없습니다 (로컬 수동 실행 도구). 진행 상황은 `claudedocs/reviewnote-travel-selenium.md`.
