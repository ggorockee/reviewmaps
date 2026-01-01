# Grafana 대시보드 가이드

## 대시보드 구성 추천

### ReviewMaps 통합 대시보드

#### 1. Server Metrics (Go Fiber)

**HTTP Request Rate**
```promql
# 전체 요청률 (QPS)
sum(rate(reviewmaps_http_requests_total[5m]))

# 엔드포인트별 요청률
sum(rate(reviewmaps_http_requests_total[5m])) by (path)

# 상태코드별 요청률
sum(rate(reviewmaps_http_requests_total[5m])) by (status_code)
```

**HTTP Request Duration**
```promql
# P50, P95, P99 레이턴시
histogram_quantile(0.50, sum(rate(reviewmaps_http_request_duration_seconds_bucket[5m])) by (le))
histogram_quantile(0.95, sum(rate(reviewmaps_http_request_duration_seconds_bucket[5m])) by (le))
histogram_quantile(0.99, sum(rate(reviewmaps_http_request_duration_seconds_bucket[5m])) by (le))

# 엔드포인트별 평균 응답시간
rate(reviewmaps_http_request_duration_seconds_sum[5m]) / rate(reviewmaps_http_request_duration_seconds_count[5m])
```

**Error Rate**
```promql
# 4xx 에러율
sum(rate(reviewmaps_http_requests_total{status_code=~"4.."}[5m])) / sum(rate(reviewmaps_http_requests_total[5m])) * 100

# 5xx 에러율
sum(rate(reviewmaps_http_requests_total{status_code=~"5.."}[5m])) / sum(rate(reviewmaps_http_requests_total[5m])) * 100
```

#### 2. Go-Scraper Metrics (CronJob)

**Scraper Execution**
```promql
# 스크레이핑 성공률
sum(rate(scraper_executions_total{status="success"}[1h])) / sum(rate(scraper_executions_total[1h])) * 100

# 수집된 캠페인 수
sum(rate(scraper_campaigns_collected_total[1h]))

# 스크래핑 소요 시간
histogram_quantile(0.95, sum(rate(scraper_duration_seconds_bucket[1h])) by (le, platform))
```

#### 3. Ojeomneo Metrics

**일반 메트릭**
```promql
# Ojeomneo 메트릭 필터링
{environment="production",cluster="woohalabs-prod-gke",job="ojeomneo-server"}
```

### 대시보드 레이아웃 제안

**Row 1: Overview (전체 시스템)**
- Total Request Rate (all services)
- Overall Error Rate
- Average Response Time
- Active Pods

**Row 2: ReviewMaps Server**
- Request Rate by Endpoint
- Response Time P95/P99
- Error Rate by Status Code
- Top 10 Slowest Endpoints

**Row 3: Go-Scraper**
- Scraping Success Rate
- Campaigns Collected (hourly)
- Scraper Duration by Platform
- Failed Scrapes

**Row 4: Ojeomneo**
- Request Rate
- Response Time
- Error Rate
- Active Sessions

**Row 5: Infrastructure**
- CPU Usage
- Memory Usage
- Pod Restarts
- Network I/O

## 추천 Grafana 대시보드 템플릿

### 1. Kubernetes / Applications (ID: 15661)
- 용도: Kubernetes 클러스터 전체 모니터링
- 특징: Pod, Service, Deployment 메트릭 자동 수집

### 2. OpenTelemetry Collector (ID: 15983)
- 용도: OTel Collector 자체 모니터링
- 특징: 수신/처리/전송 메트릭, 파이프라인 상태

### 3. Go Processes (ID: 6671)
- 용도: Go 애플리케이션 모니터링
- 특징: Goroutine, GC, Memory 메트릭
- ReviewMaps Server, Go-Scraper에 적합

### 4. RED Method (ID: 12114)
- 용도: Rate, Errors, Duration 메트릭
- 특징: 마이크로서비스 표준 메트릭
- 모든 서비스에 적용 가능

## 대시보드 Import 방법

Grafana UI → Dashboards → New → Import → Dashboard ID 입력

또는 JSON 파일로 직접 생성 가능 (아래 참조)

## 커스텀 대시보드 JSON

각 앱별 대시보드를 자동 생성하려면:

**grafana/dashboards/** 디렉토리에 JSON 파일 저장
- `reviewmaps-server.json`
- `reviewmaps-scraper.json`
- `ojeomneo.json`

ConfigMap으로 Grafana에 자동 프로비저닝 가능

## 알림(Alert) 설정 추천

**High Error Rate**
```promql
(sum(rate(reviewmaps_http_requests_total{status_code=~"5.."}[5m])) / sum(rate(reviewmaps_http_requests_total[5m])) * 100) > 5
```

**Slow Response Time**
```promql
histogram_quantile(0.95, sum(rate(reviewmaps_http_request_duration_seconds_bucket[5m])) by (le)) > 1
```

**Scraper Failures**
```promql
(sum(rate(scraper_executions_total{status="failure"}[1h])) / sum(rate(scraper_executions_total[1h])) * 100) > 10
```

**Pod Down**
```promql
up{job=~"reviewmaps-.*|ojeomneo-.*"} == 0
```
