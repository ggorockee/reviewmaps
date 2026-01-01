# 로그 수집 설정 가이드

## 현재 상태

| 데이터 | 수집 여부 | 비고 |
|--------|---------|------|
| Metrics | ✅ 수집 중 | Prometheus로 저장 |
| Traces | ⚠️ 부분 수집 | Collector 로그로만 출력, 저장 안 됨 |
| Logs | ❌ 미설정 | 추가 설정 필요 |

## 로그 수집 옵션

### Option 1: Loki (권장)

**장점:**
- Prometheus와 동일한 라벨 시스템
- Grafana 네이티브 통합
- 비용 효율적 (압축 저장)
- 설치 간단

**설정 방법:**

#### 1. Loki 설치
```yaml
# infra/charts/helm/prod/loki/values.yaml
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
```

#### 2. Promtail 설치 (로그 수집기)
```yaml
# infra/charts/helm/prod/promtail/values.yaml
config:
  clients:
    - url: http://loki:3100/loki/api/v1/push
  positions:
    filename: /tmp/positions.yaml
  scrape_configs:
    - job_name: kubernetes-pods
      kubernetes_sd_configs:
        - role: pod
      relabel_configs:
        - source_labels: [__meta_kubernetes_namespace]
          target_label: namespace
        - source_labels: [__meta_kubernetes_pod_name]
          target_label: pod
        - source_labels: [__meta_kubernetes_pod_label_app]
          target_label: app
```

#### 3. 애플리케이션 로그 포맷 (JSON)

**ReviewMaps Server (Go):**
```go
log.SetFormatter(&log.JSONFormatter{
    TimestampFormat: "2006-01-02T15:04:05.000Z",
    FieldMap: log.FieldMap{
        log.FieldKeyTime:  "timestamp",
        log.FieldKeyLevel: "level",
        log.FieldKeyMsg:   "message",
    },
})
```

**Ojeomneo (Python):**
```python
LOGGING = {
    'formatters': {
        'json': {
            '()': 'pythonjsonlogger.jsonlogger.JsonFormatter',
            'format': '%(timestamp)s %(level)s %(message)s'
        }
    }
}
```

#### 4. Grafana에서 Loki 연결

Grafana UI → Configuration → Data Sources → Add Loki
- URL: `http://loki:3100`

### Option 2: OpenTelemetry Collector + Loki

**OTel Collector에 로그 파이프라인 추가:**

```yaml
# otel-collector/values.yaml
config:
  receivers:
    otlp:
      protocols:
        http:
        grpc:
    # 파일 로그 수집
    filelog:
      include:
        - /var/log/pods/*/*/*.log
      operators:
        - type: json_parser

  exporters:
    loki:
      endpoint: http://loki:3100/loki/api/v1/push

  service:
    pipelines:
      logs:
        receivers: [otlp, filelog]
        processors: [batch, resource]
        exporters: [loki]
```

### Option 3: ELK Stack (복잡함, 비권장)

**구성:**
- Elasticsearch: 로그 저장
- Logstash: 로그 처리
- Kibana: 시각화

**단점:**
- 리소스 많이 사용
- 설정 복잡
- Prometheus와 별도 시스템

## 추천 아키텍처

### 통합 관측성 스택

```
애플리케이션
├─ Metrics → OTel Collector → Prometheus → Grafana
├─ Traces → OTel Collector → (향후) Tempo → Grafana
└─ Logs → Promtail → Loki → Grafana
```

**모든 데이터를 Grafana에서 통합 조회 가능**

## Grafana Explore 쿼리 예시

### Logs (Loki)

**ReviewMaps Server 에러 로그:**
```logql
{namespace="reviewmaps", app="reviewmaps-server"} |= "error"
```

**특정 엔드포인트 로그:**
```logql
{namespace="reviewmaps", app="reviewmaps-server"} | json | path="/v1/campaigns"
```

**시간대별 에러 집계:**
```logql
sum(rate({namespace="reviewmaps"} |= "error" [5m])) by (app)
```

### Metrics + Logs 연동

Grafana에서 메트릭 그래프 클릭 → "Explore in Logs" → 해당 시간대 로그 자동 조회

## 로그 보관 정책

**Loki 설정:**
```yaml
limits_config:
  retention_period: 720h  # 30일

table_manager:
  retention_deletes_enabled: true
  retention_period: 720h
```

## 비용 최적화

**로그 레벨별 샘플링:**
- ERROR: 100% 수집
- WARN: 100% 수집
- INFO: 10% 샘플링 (높은 QPS 엔드포인트)
- DEBUG: 1% 샘플링

**Promtail 설정:**
```yaml
pipeline_stages:
  - match:
      selector: '{app="reviewmaps-server"}'
      stages:
        - json:
            expressions:
              level: level
        - drop:
            expression: "level == 'debug'"
            drop_counter_reason: "drop_debug_logs"
```
