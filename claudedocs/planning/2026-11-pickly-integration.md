# 피클리(picklykorea.kr) 체험단 수집 추가 검토·계획

작성일: 2026-11-27 · 계기: 피클리 운영자가 메일로 리뷰맵 수집 대상 추가를 요청 (네이버 블로그 체험단, 11-27 기준 31건)

## 결론 요약

| 질문 | 답 |
|---|---|
| 1. 로고 | 가져옴. 사이트 아이콘 `https://picklykorea.kr/pickly-icon.svg`(녹색 둥근 사각형에 흰색 "p." 글자), 앱 로고 규격(512×512 PNG)으로 변환 → `claudedocs/planning/assets/pickly/pickly.png`, 원본 `pickly-icon.svg` |
| 2. 스크래핑 대신 API | 가능. 피클리 웹사이트가 쓰는 공개 JSON API(`/api/businesses`)로 목록·상세를 받을 수 있음. 로그인 없이 응답. 다만 robots.txt가 일반 수집기의 `/api/` 접근을 막고 있어, 피클리에 이 API 사용을 서면(메일)으로 확인받은 뒤 운영에 넣음 |
| 3. 리뷰맵 적용 | 가능. 리뷰노트 수집기(`go-scraper/internal/scraper/reviewnote`)와 같은 "API 호출 → 파싱 → 저장" 구조로 붙일 수 있고, 상세 API에 주소·위도·경도가 있어 네이버 지도 보강(지오코딩)도 필요 없음. 앱에 로고를 보이려면 앱 업데이트가 필요 (로고가 앱 안에 들어 있음) |

## 1. 사이트·API 조사 (2026-11-27)

| 항목 | 내용 |
|---|---|
| 사이트 | React SPA(Vite 빌드). 페이지 HTML에는 공고 데이터가 없고 브라우저가 API로 받아 그림 → HTML 스크래핑보다 API가 정확하고 가벼움 |
| 목록 API | `GET https://picklykorea.kr/api/businesses?limit=<n>&offset=<n>&channel=naver_blog` → JSON 배열. 11-27 조회 31건(메일 내용과 일치), 응답 약 90KB |
| 상세 API | `GET https://picklykorea.kr/api/businesses/<id>` → 주소, 위도·경도, 제공 내역, 모집 인원, 일정 등 |
| 카테고리 API | `GET https://picklykorea.kr/api/categories` → 13개 (맛집, 여행, 배송형, 뷰티, 반려동물, 서비스 등) |
| 이미지 | 응답의 `imageUrl`(예: `/objects/businesses/....webp`) 앞에 `https://picklykorea.kr`을 붙이면 공개 이미지(200, webp) |
| 공고 주소 | `https://picklykorea.kr/business/<id>` (회원가입 없이 열람) |
| robots.txt | 모든 수집기: `/api/` 금지. Googlebot·Yeti(네이버)·Bingbot·Daum에만 `/api/businesses` 허용. AI 수집기 이름은 따로 나열해 금지 |
| 로그인 필요 API | 신청, 즐겨찾기, 회원 정보 등 → 쓰지 않음 |

목록 응답에는 주소·좌표가 비어 있고(`address` 빈 문자열, 위도·경도 없음), 상세 응답에만 있습니다. 31건 중 방문형(`businessType=restaurant`) 27건, 배송형(`delivery`) 4건이고, 확정 방식은 선정형(`selection`) 18건, 즉시 확정(`instant`) 13건입니다.

## 2. 리뷰맵 캠페인으로 옮기는 규칙 (`go-scraper/pkg/models.Campaign`)

| 리뷰맵 필드 | 피클리 값 | 비고 |
|---|---|---|
| Platform, Source | "피클리" | 앱 로고 매핑 키와 같아야 함 |
| Title, Company | `name` (예: 꽁크 압구정본점) | |
| Offer | `productInfoOne` (예: 5만원 이용권), 없으면 `benefitsOne` 금액을 "N만원 상당"으로 | 31건 모두 값 있음 |
| CampaignChannel | `channel=naver_blog` → "blog" | 리뷰노트·인플렉서와 같은 값 |
| CampaignType | `businessType` restaurant → "방문형", delivery → "배송형" | |
| ApplyFrom / ApplyDeadline | `applicationStartDate` / `applicationEndDate` (날짜만) | 마감일은 KST 23:59:59로 |
| ReviewDeadline | `experienceEndDate` | |
| Address, Lat, Lng | 상세 API `address`, `latitude`, `longitude` | 방문형만. 배송형은 비움 |
| Region | `city` + `district` (예: 서울 신사) | 배송형 일부는 없음 |
| ImgURL | `https://picklykorea.kr` + `imageUrl` | |
| ContentLink, CompanyLink | `https://picklykorea.kr/business/<id>` | |
| CategoryID | `category.name` → `raw_categories`(source=피클리) → 관리자 화면의 카테고리 매핑 | 처음엔 매핑이 없으므로 맛집·여행·배송형·뷰티 등 매핑 필요 |
| Status | `status=active`만 수집 | |
| (참고) | `confirmationType` instant(바로 확정) / selection(선정) | 앱에 표시 칸이 없어 지금은 저장 안 함. 원하면 제목이나 제공 내역 뒤에 "[바로 확정]" 표시 검토 |

중복 기준은 기존과 같이 platform + title + offer + campaign_channel. 피클리 `id`(UUID)가 고유하므로 ContentLink로도 구분됩니다.

## 3. 요청 규모와 매너

| 항목 | 계획 |
|---|---|
| 주기 | 하루 1번 (리뷰노트 02:00 뒤, 예: 02:30 KST) |
| 요청 수 | 목록 1~2번 + 새로 보거나 바뀐 공고의 상세만 (처음 약 30번, 이후 하루 수 번). 요청 사이 1초 대기 |
| 식별 | User-Agent에 리뷰맵 수집기임과 연락처 주소(사이트 주소) 표시 |
| 중단 조건 | 피클리가 요청하면 즉시 중단 (수집기 설정에서 끄는 스위치) |

## 4. 피클리에 보낼 답장 초안 (개발자가 확인 후 직접 발송)

안녕하세요, 리뷰맵 운영자입니다. 연락 주셔서 감사합니다.

피클리 체험단을 리뷰맵에 넣는 방향으로 검토했습니다. 수집 방법과 관련해 두 가지를 확인 부탁드립니다.

1. 피클리 웹사이트가 쓰는 공고 목록·상세 API(`/api/businesses`, `/api/businesses/<id>`)를 하루 1회, 요청 사이 간격을 두고 조회해도 괜찮을까요? robots.txt에서 `/api/` 경로가 일반 수집기에 막혀 있어 미리 여쭙습니다. 별도로 제공해 주실 수 있는 공고 피드나 API가 있으면 그쪽을 쓰겠습니다.
2. 앱과 지도에 피클리 로고(사이트 아이콘)와 공고 대표 이미지를 표시해도 될까요? 공고를 누르면 피클리 공고 페이지로 바로 연결됩니다.

현재는 네이버 블로그 체험단만 수집할 예정이며, 중단을 원하시면 언제든 이 메일로 알려 주시면 바로 멈추겠습니다.

감사합니다.
리뷰맵 드림

## 5. 단계별 계획 (진행하려면 [승인])

### Phase 0. 허락 받기
- [ ] 0-1 직접: 위 답장 발송 (내용 수정 가능)
- [ ] 0-2 피클리 답장 확인 → API 사용·로고 표시 허락 여부, 별도 피드 제공 여부를 이 문서에 기록

### Phase 1. 수집기 (허락 후)
- [ ] 1-1 `go-scraper/internal/scraper/pickly`: 목록 → 새 공고만 상세 조회 → 2장 규칙으로 변환. 리뷰노트 수집기 구조와 같게 (Scrape, Parse, 보강 없음, Save)
- [ ] 1-2 테스트: 11-27 응답을 고정 데이터(fixture)로 저장해 변환 규칙·배송형·마감일 시간대·이미지 주소를 검증
- [ ] 1-3 `cmd/scraper/main.go`에 플랫폼 등록, 끄기 스위치(환경변수)
- [ ] 1-4 수집 결과를 기존 방식대로 Pushgateway에 push (`internal/runstats`: 실행 중, 성공·실패, 수집·저장 건수)

### Phase 2. 인프라
- [ ] 2-1 infra `charts/helm/prod/reviewmaps/values.yaml` 수집 CronJob에 `pickly` 추가 (리뷰노트 다음 시간)
- [ ] 2-2 첫 수동 실행(`kubectl create job --from=cronjob/...`) → DB 적재 건수 확인 (읽기 전용 조회)

### Phase 3. 카테고리
- [ ] 3-1 관리자 화면에서 피클리 원본 카테고리(맛집, 여행, 배송형, 뷰티, 반려동물, 서비스 등) → 리뷰맵 카테고리 매핑

### Phase 4. 앱 로고 (다음 앱 버전)
- [ ] 4-1 `mobile/asset/image/logo/pickly.png` 추가 (이 문서의 `assets/pickly/pickly.png`)
- [ ] 4-2 로고 매핑 세 곳에 '피클리' 추가: `mobile/lib/models/store_model.dart`의 `_platformLogoFile`, `_platformBannerFile`(배너 없으면 기본), `mobile/lib/widgets/build_store_list_item.dart`의 `_getLogoPathForPlatform`
- [ ] 4-3 로고가 없는 이전 앱 버전에서도 목록이 깨지지 않는지 확인 (매핑이 없으면 빈 문자열 → 기본 표시)

### Phase 5. 모니터링 (원칙 2)
- [ ] 5-1 Grafana `reviewmaps-scraper` 대시보드에 피클리가 자동으로 나오는지 확인 (스크래퍼 라벨 기준), 범위표에 피클리 정상 건수(약 30건) 추가
- [ ] 5-2 기존 수집 알림(KeywordFailed, KeywordStale, ZeroItems, ItemsDropped)이 피클리에도 적용되는지 확인. 응답 구조가 바뀌면 0건 → ZeroItems 알림으로 감지
- [ ] 5-3 `ReviewmapsCronJobNotSucceeded` 대상에 새 CronJob 포함 여부 확인

### Phase 6. 문서
- [ ] 6-1 infra `.claude/CLAUDE.md` 리뷰맵 운영 메모(CronJob 시간표·수집 기준값)에 피클리 추가
- [ ] 6-2 이 문서 진행 기록, 피클리와 주고받은 허락 내용 요약

## 진행 기록

| 날짜 | 항목 | 결과 |
|---|---|---|
| 2026-11-27 | 검토 | 공개 API 확인(목록 31건·상세·카테고리), 필드 매핑, robots.txt `/api/` 제한 확인, 로고 수집·PNG 변환, 운영 DB에 피클리 공고 없음 확인 |
