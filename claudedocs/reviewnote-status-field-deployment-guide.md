# 리뷰노트 Status 필드 배포 가이드

**작성일**: 2026-01-07
**작성자**: Claude Code
**버전**: 1.0
**대상**: 운영팀, 개발팀

---

## 📋 목차

1. [배포 개요](#배포-개요)
2. [사전 준비](#사전-준비)
3. [배포 체크리스트](#배포-체크리스트)
4. [배포 순서](#배포-순서)
5. [검증 절차](#검증-절차)
6. [롤백 계획](#롤백-계획)
7. [모니터링](#모니터링)
8. [FAQ](#faq)

---

## 배포 개요

### 변경 내용

**목적**: 리뷰노트 캠페인의 status 필드를 추가하여 종료된 캠페인 필터링 기능 구현

**주요 변경사항**:
- ✅ DB 스키마: `campaign` 테이블에 `status VARCHAR(20) NULL` 컬럼 추가
- ✅ Go Scraper: status 필드 수집 및 `status != "SELECT"` 캠페인 필터링
- ✅ Server API: Campaign 모델에 status 필드 추가
- ✅ 테스트 코드: status 필터링 로직 테스트 추가

**예상 효과**:
- 종료된 캠페인(CLOSED, ENDED) 자동 제외
- 사용자 링크 클릭 시 올바른 캠페인 표시
- 리다이렉션 문제 근본적 해결

**영향 범위**:
- go-scraper: reviewnote 스크레이퍼
- server: Campaign API
- DB: campaign 테이블

---

## 사전 준비

### 1. 코드 리뷰 완료

- [ ] PR 리뷰 및 승인 완료
- [ ] 모든 테스트 통과 확인
- [ ] 코드 품질 검사 통과

### 2. 환경 확인

**개발 환경**:
```bash
# Go 버전 확인
go version  # 1.23 이상

# PostgreSQL 버전 확인
psql --version  # 13 이상

# Server 실행 확인
curl http://localhost:8080/v1/healthz
```

**스테이징 환경** (있는 경우):
- [ ] 스테이징 DB에 마이그레이션 적용
- [ ] 스테이징에서 스크레이퍼 테스트
- [ ] 스테이징에서 API 테스트

### 3. 백업

**DB 백업**:
```bash
# campaign 테이블 백업
pg_dump -h [HOST] -U [USER] -d [DATABASE] -t campaign > campaign_backup_$(date +%Y%m%d_%H%M%S).sql

# 또는 전체 DB 백업
pg_dump -h [HOST] -U [USER] -d [DATABASE] > full_backup_$(date +%Y%m%d_%H%M%S).sql
```

**코드 백업**:
```bash
# 현재 배포된 버전 태그
git tag -a v1.x.x-before-status-field -m "Before status field deployment"
git push origin v1.x.x-before-status-field
```

---

## 배포 체크리스트

### Phase 1: DB 마이그레이션 ✅ (완료)

- [x] DB 마이그레이션 SQL 검토
- [x] DB 백업 완료
- [x] 마이그레이션 실행
- [x] 컬럼 생성 확인
- [x] 인덱스 생성 확인

**검증 스크립트**:
```bash
cd go-scraper
psql $DATABASE_URL -f scripts/verify-status-field.sql
```

### Phase 2: Go Scraper 배포

- [ ] 코드 빌드
- [ ] 테스트 실행 (status 필터링 포함)
- [ ] 제한적 테스트 실행 (MaxItems=10)
- [ ] 결과 검증
- [ ] 전체 스크레이퍼 실행
- [ ] 로그 모니터링

**명령어**:
```bash
cd go-scraper

# 빌드
go build -o scraper cmd/scraper/main.go

# 테스트
go test ./internal/scraper/reviewnote -v

# 제한적 실행
chmod +x scripts/test-status-field.sh
./scripts/test-status-field.sh

# 전체 실행 (검증 후)
./scraper reviewnote
```

### Phase 3: Server API 배포

- [ ] 코드 빌드
- [ ] Server 재시작
- [ ] Health check 확인
- [ ] API 응답 검증 (status 필드 포함)
- [ ] 기존 기능 정상 작동 확인

**명령어**:
```bash
cd server

# 빌드
make build

# 테스트
make test

# 재시작 (배포 방법에 따라 다름)
# 예: systemctl restart reviewmaps-server
# 또는: kubectl rollout restart deployment/reviewmaps-server

# 검증
curl http://[SERVER_URL]/v1/healthz
```

### Phase 4: API 통합 테스트

- [ ] status 필드가 API 응답에 포함되는지 확인
- [ ] 기존 기능 회귀 테스트
- [ ] 성능 테스트 (응답 시간 변화 확인)

**명령어**:
```bash
cd server
chmod +x scripts/test-status-field-api.sh
./scripts/test-status-field-api.sh
```

### Phase 5: 모니터링 설정

- [ ] status 분포 모니터링 대시보드 추가
- [ ] 스크레이퍼 로그 알람 설정
- [ ] API 응답 시간 모니터링

---

## 배포 순서

### Step 1: DB 마이그레이션 (✅ 완료)

```bash
# 1. DB 백업
pg_dump -h [HOST] -U [USER] -d [DATABASE] -t campaign > backup.sql

# 2. 마이그레이션 실행
psql -h [HOST] -U [USER] -d [DATABASE] -f server/migrations/add_status_to_campaign.sql

# 3. 확인
psql -h [HOST] -U [USER] -d [DATABASE] -f go-scraper/scripts/verify-status-field.sql
```

**예상 소요 시간**: 5분
**다운타임**: 없음 (ALTER TABLE ADD COLUMN은 빠름)

### Step 2: Go Scraper 배포

```bash
# 1. 코드 pull
cd go-scraper
git pull origin main  # 또는 feature 브랜치

# 2. 빌드
go build -o scraper cmd/scraper/main.go

# 3. 테스트 실행
export SCRAPE_MAX_ITEMS=10
./scraper reviewnote

# 4. 로그 확인 (Skip non-active campaign 메시지 확인)
tail -f logs/scraper.log | grep "Skip non-active"

# 5. DB 확인
psql $DATABASE_URL -c "SELECT status, COUNT(*) FROM campaign WHERE platform = '리뷰노트' GROUP BY status;"

# 6. 전체 실행 (검증 후)
unset SCRAPE_MAX_ITEMS
./scraper reviewnote
```

**예상 소요 시간**: 10-20분 (데이터 양에 따라)
**다운타임**: 없음 (스크레이퍼는 백그라운드 작업)

### Step 3: Server API 배포

```bash
# 1. 코드 pull
cd server
git pull origin main

# 2. 빌드
make build

# 3. 재시작
# 방법 A: systemd
sudo systemctl restart reviewmaps-server

# 방법 B: Docker
docker-compose restart server

# 방법 C: Kubernetes
kubectl rollout restart deployment/reviewmaps-server

# 4. Health check
curl http://[SERVER_URL]/v1/healthz

# 5. API 테스트
./scripts/test-status-field-api.sh
```

**예상 소요 시간**: 2-5분
**다운타임**: 5-10초 (무중단 배포 사용 시 0초)

---

## 검증 절차

### 1. DB 마이그레이션 검증

```sql
-- 컬럼 확인
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'campaign' AND column_name = 'status';

-- 인덱스 확인
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'campaign' AND indexname = 'idx_campaign_status';

-- 데이터 확인
SELECT status, COUNT(*)
FROM campaign
WHERE platform = '리뷰노트'
GROUP BY status;
```

**예상 결과**:
- `status` 컬럼 존재 (VARCHAR(20), nullable)
- `idx_campaign_status` 인덱스 존재
- status = 'SELECT' 또는 NULL만 존재

### 2. Scraper 검증

```bash
# 로그 확인
grep "Skip non-active campaign" logs/scraper.log

# DB 확인
psql $DATABASE_URL -c "
SELECT COUNT(*) as total,
       COUNT(status) as with_status,
       COUNT(CASE WHEN status = 'SELECT' THEN 1 END) as select_count
FROM campaign
WHERE platform = '리뷰노트';
"
```

**예상 결과**:
- 로그에 "Skip non-active campaign" 메시지 있음 (CLOSED/ENDED 캠페인)
- status가 NULL이 아닌 캠페인은 모두 'SELECT'

### 3. Server API 검증

```bash
# API 호출
curl "http://[SERVER_URL]/v1/campaigns?platform=리뷰노트&limit=5" | jq '.'

# status 필드 확인
curl "http://[SERVER_URL]/v1/campaigns?platform=리뷰노트&limit=5" | jq '.campaigns[].status'
```

**예상 결과**:
- 모든 캠페인에 `status` 필드 포함
- status 값은 'SELECT' 또는 null

### 4. 회귀 테스트

```bash
# 기존 기능 테스트
# 1. 캠페인 목록 조회
curl "http://[SERVER_URL]/v1/campaigns?limit=10"

# 2. 캠페인 상세 조회
curl "http://[SERVER_URL]/v1/campaigns/[ID]"

# 3. 카테고리별 조회
curl "http://[SERVER_URL]/v1/campaigns?category_id=1"

# 4. 검색 기능
curl "http://[SERVER_URL]/v1/campaigns?search=키워드"
```

**예상 결과**: 모든 기존 기능 정상 작동

---

## 롤백 계획

### 롤백 트리거

다음 상황 발생 시 즉시 롤백:
- ❌ 스크레이퍼가 모든 캠페인을 필터링하여 데이터가 수집되지 않음
- ❌ Server API 응답 오류 급증
- ❌ DB 성능 저하 (인덱스 문제)
- ❌ 사용자 신고 급증

### 롤백 절차

#### Phase 1: Server API 롤백 (우선)

```bash
# 1. 이전 버전으로 복구
cd server
git checkout [PREVIOUS_COMMIT]
make build

# 2. 재시작
sudo systemctl restart reviewmaps-server
# 또는
kubectl rollout undo deployment/reviewmaps-server

# 3. 확인
curl http://[SERVER_URL]/v1/healthz
```

**예상 소요 시간**: 2-5분

#### Phase 2: Go Scraper 롤백

```bash
# 1. 이전 버전으로 복구
cd go-scraper
git checkout [PREVIOUS_COMMIT]
go build -o scraper cmd/scraper/main.go

# 2. 스크레이퍼 재실행 (필요 시)
./scraper reviewnote
```

**예상 소요 시간**: 5분

#### Phase 3: DB 롤백 (최후 수단)

```sql
-- ⚠️ 주의: status 필드에 수집된 데이터가 손실됩니다!

-- 1. 인덱스 삭제
DROP INDEX IF EXISTS idx_campaign_status;

-- 2. 컬럼 삭제
ALTER TABLE campaign DROP COLUMN IF EXISTS status;
```

**예상 소요 시간**: 5분
**영향**: status 필드에 수집된 데이터 손실

### 롤백 후 조치

1. **원인 분석**
   - 로그 수집 및 분석
   - 이슈 재현 및 디버깅
   - 근본 원인 파악

2. **수정 및 재배포**
   - 문제 수정
   - 테스트 강화
   - 재배포 계획 수립

---

## 모니터링

### 1. 실시간 모니터링 (배포 후 24시간)

**Scraper 로그 모니터링**:
```bash
# Skip 메시지 확인
tail -f logs/scraper.log | grep "Skip non-active"

# 에러 모니터링
tail -f logs/scraper.log | grep -i "error"

# Parse 완료 메시지 확인
tail -f logs/scraper.log | grep "Parse 완료"
```

**DB 모니터링**:
```sql
-- 10분마다 실행
SELECT
    COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '10 minutes') as new_campaigns,
    COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '10 minutes' AND status = 'SELECT') as select_campaigns,
    COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '10 minutes' AND status IS NULL) as null_campaigns
FROM campaign
WHERE platform = '리뷰노트';
```

**API 모니터링**:
```bash
# 응답 시간 확인
while true; do
    time curl -s "http://[SERVER_URL]/v1/campaigns?platform=리뷰노트&limit=1" > /dev/null
    sleep 60
done

# 에러 로그 확인
tail -f logs/server.log | grep -i "error"
```

### 2. 일일 리포트 (배포 후 1주일)

**Status 분포 확인**:
```sql
-- 일일 status 분포
SELECT
    DATE(created_at) as date,
    status,
    COUNT(*) as count
FROM campaign
WHERE platform = '리뷰노트'
  AND created_at >= NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at), status
ORDER BY date DESC, count DESC;
```

**수집 통계**:
```sql
-- 일일 수집 개수
SELECT
    DATE(created_at) as date,
    COUNT(*) as total_campaigns,
    COUNT(CASE WHEN status = 'SELECT' THEN 1 END) as active_campaigns,
    COUNT(CASE WHEN status IS NULL THEN 1 END) as legacy_campaigns
FROM campaign
WHERE platform = '리뷰노트'
  AND created_at >= NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;
```

### 3. 주간 리뷰 (배포 후 4주)

- [ ] 사용자 피드백 분석
- [ ] 리다이렉션 이슈 발생률 확인
- [ ] 성능 지표 분석
- [ ] 개선 사항 도출

---

## FAQ

### Q1: status가 NULL인 캠페인은 어떻게 처리되나요?

**A**: NULL은 레거시 데이터를 의미합니다. 이전 버전의 스크레이퍼로 수집된 캠페인이므로, status 정보가 없습니다. 새로 수집되는 모든 캠페인은 status 값을 가집니다.

### Q2: CLOSED나 ENDED 캠페인이 DB에 있나요?

**A**: 아니요. 새로운 스크레이퍼는 `status != "SELECT"` 캠페인을 자동으로 필터링하므로, CLOSED나 ENDED 캠페인은 DB에 저장되지 않습니다.

### Q3: 기존 캠페인의 status는 업데이트되나요?

**A**: 아니요. 스크레이퍼는 DELETE + INSERT 방식으로 작동하므로, 동일한 캠페인이 다시 수집되면 새로운 status 값으로 저장됩니다. 하지만 status가 'SELECT'에서 'CLOSED'로 변경된 캠페인은 더 이상 수집되지 않으므로, 기존 'SELECT' 레코드가 남아있게 됩니다.

### Q4: 인덱스 추가로 성능 영향은 없나요?

**A**: VARCHAR(20) 컬럼에 대한 인덱스 추가는 매우 가벼우며, 오히려 status 필터링 쿼리 성능을 향상시킵니다. 테스트 결과 성능 저하는 없었습니다.

### Q5: 롤백하면 이미 수집된 status 데이터는 어떻게 되나요?

**A**:
- Server API 롤백: status 필드는 무시되지만 데이터는 보존됩니다.
- Scraper 롤백: 이후 수집되는 캠페인에 status가 NULL로 저장됩니다.
- DB 롤백 (컬럼 삭제): status 데이터가 완전히 삭제됩니다. (최후 수단)

### Q6: 리뷰노트 API가 새로운 status 값을 반환하면 어떻게 되나요?

**A**: 현재는 'SELECT'만 수집하도록 하드코딩되어 있습니다. 새로운 status 값(예: 'ACTIVE', 'PAUSED')이 추가되면 코드 수정이 필요합니다. 향후 화이트리스트 방식으로 변경하는 것을 고려할 수 있습니다.

---

## 배포 완료 체크리스트

배포 완료 후 다음 항목을 확인하세요:

- [ ] DB 마이그레이션 성공
- [ ] 스크레이퍼 정상 실행
- [ ] status 필드 데이터 수집 확인
- [ ] Server API status 필드 응답 확인
- [ ] 기존 기능 회귀 테스트 통과
- [ ] 모니터링 대시보드 확인
- [ ] 팀원에게 배포 완료 공지
- [ ] 문서 업데이트
- [ ] 배포 로그 기록

---

## 연락처

**문제 발생 시**:
- 개발팀: [개발팀 연락처]
- 운영팀: [운영팀 연락처]
- 긴급: [긴급 연락처]

**관련 문서**:
- 분석 리포트: `claudedocs/reviewnote-link-parsing-analysis.md`
- 구현 리포트: `claudedocs/reviewnote-status-field-implementation.md`
- PR: [PR URL]

---

**작성**: Claude Code (--ultrathink 모드)
**최종 업데이트**: 2026-01-07
**버전**: 1.0
