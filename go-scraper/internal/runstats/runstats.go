// Package runstats 스크레이퍼 1회 실행(=키워드 1개) 결과를 모아 Prometheus Pushgateway로 push한다.
//
// go-scraper는 CronJob에서 키워드마다 프로세스를 새로 띄워 수 초~수 분 만에 종료되므로
// Prometheus가 pull로 수집할 수 없다. 실행이 끝날 때 결과를 Pushgateway에 남기고,
// Prometheus가 Pushgateway를 수집한다.
//
// 모든 메트릭은 "마지막 실행 결과" gauge이며 grouping key는 (scraper, keyword)이다.
// PUSHGATEWAY_URL 환경변수가 없으면 push를 생략한다.
package runstats

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/common/expfmt"
)

// PushJobName Pushgateway job 라벨 값
const PushJobName = "reviewmaps_scraper"

// 단계별 건수 라벨 값
const (
	StageScraped = "scraped" // 사이트/API에서 받아온 원본 건수
	StageParsed  = "parsed"  // 파싱·중복 제거 후 건수
	StageSaved   = "saved"   // DB 저장 건수 (갱신 + 신규)
	StageUpdated = "updated" // 기존 캠페인 갱신 건수
	StageNew     = "new"     // 신규 캠페인 건수
	StageDeleted = "deleted" // cleanup soft delete 건수
)

// EnrichStats 주소/좌표 보강 통계
type EnrichStats struct {
	Total, CacheHit, APICalled, Geocoded, Skipped, Errors int64
}

// DetailStats 상세 이용 조건 보강 통계 (리뷰노트 여행 카테고리)
type DetailStats struct {
	Targets  int64 // 보강 대상 캠페인 수
	Reused   int64 // 기간 안에 받은 DB 값을 그대로 쓴 수
	Fetched  int64 // 상세 API 성공 수
	Errors   int64 // 상세 API 실패 수 (세션 만료 제외)
	Missing  int64 // 이번에 값을 못 채운 수 (세션 없음·만료·실패·호출 한도)
	WithDays int64 // 저장되는 값 중 가능·불가 요일이 있는 수
	// SessionOK 1=세션 정상, 0=세션 없음 또는 만료(401)
	SessionOK bool
	// SessionExpiresAt 세션 쿠키 만료 시각 (모르면 0)
	SessionExpiresAt time.Time
	// Blocked 403·429·5xx 등 차단·과부하 신호를 받아 멈췄는지
	Blocked bool
}

type collector struct {
	mu            sync.Mutex
	scraper       string
	keyword       string
	start         time.Time
	items         map[string]int64
	enrich        *EnrichStats
	detail        *DetailStats
	alertsCreated int64
	serverAPIErr  bool
}

var cur = &collector{items: map[string]int64{}}

// Start 실행 시작 기록 (main에서 1회 호출)
func Start(scraper, keyword string) {
	cur.mu.Lock()
	defer cur.mu.Unlock()
	cur.scraper, cur.keyword, cur.start = scraper, keyword, time.Now()
	cur.items = map[string]int64{}
	cur.enrich, cur.detail, cur.alertsCreated, cur.serverAPIErr = nil, nil, 0, false
}

// SetItems 단계별 건수 기록
func SetItems(stage string, n int) {
	cur.mu.Lock()
	defer cur.mu.Unlock()
	cur.items[stage] = int64(n)
}

// SetEnrich 보강 통계 기록
func SetEnrich(s EnrichStats) {
	cur.mu.Lock()
	defer cur.mu.Unlock()
	cur.enrich = &s
}

// SetDetail 상세 보강 통계 기록
func SetDetail(s DetailStats) {
	cur.mu.Lock()
	defer cur.mu.Unlock()
	cur.detail = &s
}

// registerDetailSession 세션 상태·만료 시각·차단 신호 지표
func registerDetailSession(reg *prometheus.Registry, d *DetailStats) {
	b := func(v bool) float64 {
		if v {
			return 1
		}
		return 0
	}
	add := func(name, help string, v float64) {
		g := prometheus.NewGauge(prometheus.GaugeOpts{Name: name, Help: help})
		g.Set(v)
		reg.MustRegister(g)
	}
	add("reviewmaps_scraper_detail_session_ok", "상세 API 로그인 세션 정상 여부 (1=정상, 0=없음·만료)", b(d.SessionOK))
	add("reviewmaps_scraper_detail_blocked", "상세 API 차단·과부하 신호(403·429·5xx)로 멈췄는지 (1=멈춤)", b(d.Blocked))
	if !d.SessionExpiresAt.IsZero() {
		add("reviewmaps_scraper_detail_session_expiry_timestamp_seconds", "상세 API 세션 쿠키 만료 시각 (unix 초)", float64(d.SessionExpiresAt.Unix()))
	}
}

// PushDetailSession 세션 상태·만료 시각만 바로 push (상세 수집 시작 직후 호출).
// 이후 단계가 실패해도 만료 전 알림이 계속 계산되도록 한다.
func PushDetailSession() error {
	cur.mu.Lock()
	d := cur.detail
	cur.mu.Unlock()
	if d == nil {
		return nil
	}
	reg := prometheus.NewRegistry()
	registerDetailSession(reg, d)
	return post(reg)
}

// DetailProgress 상세 수집이 도는 동안의 진행 상황
type DetailProgress struct {
	Total  int       // 이번 실행에서 받을 수
	Done   int64     // 받아서 저장한 수
	Errors int64     // 실패 수
	NextAt time.Time // 다음 요청 예정 시각. 이 시각이 한참 지나도 갱신이 없으면 멈춘 것
}

// PushDetailProgress 진행 상황을 바로 push 한다 (실행이 몇 시간 걸려 끝나기 전에 볼 수 있어야 함)
func PushDetailProgress(p DetailProgress) error {
	reg := prometheus.NewRegistry()
	for _, m := range []struct {
		name, help string
		v          float64
	}{
		{"reviewmaps_scraper_detail_progress_total", "진행 중인 상세 수집에서 받을 건수", float64(p.Total)},
		{"reviewmaps_scraper_detail_progress_done", "진행 중인 상세 수집에서 받은 건수", float64(p.Done)},
		{"reviewmaps_scraper_detail_progress_errors", "진행 중인 상세 수집의 실패 건수", float64(p.Errors)},
		{"reviewmaps_scraper_detail_progress_next_timestamp_seconds", "다음 상세 요청 예정 시각 (unix 초)", float64(p.NextAt.Unix())},
	} {
		g := prometheus.NewGauge(prometheus.GaugeOpts{Name: m.name, Help: m.help})
		g.Set(m.v)
		reg.MustRegister(g)
	}
	return post(reg)
}

// SetAlertsCreated 키워드 알림 생성 수 기록
func SetAlertsCreated(n int) {
	cur.mu.Lock()
	defer cur.mu.Unlock()
	cur.alertsCreated = int64(n)
}

// SetServerAPIError 서버 API(키워드 알림 처리) 호출 실패 기록
func SetServerAPIError() {
	cur.mu.Lock()
	defer cur.mu.Unlock()
	cur.serverAPIErr = true
}

// Registry 현재까지 기록된 값으로 push용 레지스트리를 만든다 (테스트에서도 사용).
// success=false면 last_success_timestamp는 포함하지 않아 Pushgateway에 남은 이전 성공 시각이 유지된다.
func Registry(success bool, now time.Time) *prometheus.Registry {
	cur.mu.Lock()
	defer cur.mu.Unlock()
	reg := prometheus.NewRegistry()

	gauge := func(name, help string, v float64) {
		g := prometheus.NewGauge(prometheus.GaugeOpts{Name: name, Help: help})
		g.Set(v)
		reg.MustRegister(g)
	}

	gauge("reviewmaps_scraper_last_run_timestamp_seconds", "마지막 실행 종료 시각 (unix 초)", float64(now.Unix()))
	gauge("reviewmaps_scraper_running", "현재 실행 중 여부 (1=실행 중, 0=종료)", 0)
	if success {
		gauge("reviewmaps_scraper_last_success_timestamp_seconds", "마지막 성공 종료 시각 (unix 초)", float64(now.Unix()))
	}
	ok := 0.0
	if success {
		ok = 1
	}
	gauge("reviewmaps_scraper_last_run_success", "마지막 실행 성공 여부 (1=성공, 0=실패)", ok)
	if !cur.start.IsZero() {
		gauge("reviewmaps_scraper_last_run_duration_seconds", "마지막 실행 소요 시간 (초)", now.Sub(cur.start).Seconds())
	}

	items := prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "reviewmaps_scraper_last_run_items",
		Help: "마지막 실행의 단계별 건수 (scraped/parsed/saved/updated/new/deleted)",
	}, []string{"stage"})
	for stage, n := range cur.items {
		items.WithLabelValues(stage).Set(float64(n))
	}
	reg.MustRegister(items)

	if cur.enrich != nil {
		en := prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "reviewmaps_scraper_last_run_enrich",
			Help: "마지막 실행의 주소/좌표 보강 통계 (total/cache_hit/api_call/geocode/skipped/error)",
		}, []string{"type"})
		e := cur.enrich
		for k, v := range map[string]int64{"total": e.Total, "cache_hit": e.CacheHit, "api_call": e.APICalled, "geocode": e.Geocoded, "skipped": e.Skipped, "error": e.Errors} {
			en.WithLabelValues(k).Set(float64(v))
		}
		reg.MustRegister(en)
	}

	if cur.detail != nil {
		dt := prometheus.NewGaugeVec(prometheus.GaugeOpts{
			Name: "reviewmaps_scraper_last_run_detail",
			Help: "마지막 실행의 상세 이용 조건 보강 통계 (target/reused/fetched/error/missing/with_days)",
		}, []string{"type"})
		d := cur.detail
		for k, v := range map[string]int64{"target": d.Targets, "reused": d.Reused, "fetched": d.Fetched, "error": d.Errors, "missing": d.Missing, "with_days": d.WithDays} {
			dt.WithLabelValues(k).Set(float64(v))
		}
		reg.MustRegister(dt)
		registerDetailSession(reg, d)
	}

	gauge("reviewmaps_scraper_last_run_alerts_created", "마지막 실행으로 생성된 키워드 알림 수", float64(cur.alertsCreated))
	apiErr := 0.0
	if cur.serverAPIErr {
		apiErr = 1
	}
	gauge("reviewmaps_scraper_last_run_server_api_error", "키워드 알림 처리 서버 API 호출 실패 여부 (1=실패)", apiErr)
	return reg
}

// Push 실행 결과를 Pushgateway로 전송한다. PUSHGATEWAY_URL이 없으면 nil을 반환한다.
// 같은 (scraper, keyword) 그룹의 같은 이름 메트릭만 교체(POST)하므로
// 실패 시에도 이전 last_success_timestamp가 유지된다.
//
// client_golang push 패키지는 공백을 "+"로 인코딩하는데 Pushgateway가 이를 공백으로 복원하지 않아
// ("서울 강남" → "서울+강남"), grouping 값은 Pushgateway 공식 형식인 "@base64"로 직접 인코딩한다.
func Push(success bool) error {
	return post(Registry(success, time.Now()))
}

// PushStart 실행 시작을 알린다 (running=1, 시작 시각). 대시보드의 "지금 수집 중인 키워드"에 사용.
// 종료 시 Push가 running=0으로 덮어쓴다. 프로세스가 강제 종료되면 1로 남을 수 있으므로
// 대시보드/알림에서는 실행 중인 Job이 있을 때만 의미 있게 본다.
func PushStart() error {
	reg := prometheus.NewRegistry()
	for name, v := range map[string]float64{
		"reviewmaps_scraper_running":                       1,
		"reviewmaps_scraper_run_started_timestamp_seconds": float64(time.Now().Unix()),
	} {
		g := prometheus.NewGauge(prometheus.GaugeOpts{Name: name, Help: "실행 시작 표시 (running) / 시작 시각"})
		g.Set(v)
		reg.MustRegister(g)
	}
	return post(reg)
}

// post 현재 (scraper, keyword) 그룹으로 레지스트리 내용을 POST한다. PUSHGATEWAY_URL이 없으면 nil.
func post(reg *prometheus.Registry) error {
	url := strings.TrimRight(os.Getenv("PUSHGATEWAY_URL"), "/")
	if url == "" {
		return nil
	}
	cur.mu.Lock()
	scraper, keyword := cur.scraper, cur.keyword
	cur.mu.Unlock()
	if keyword == "" {
		keyword = "전체"
	}

	mfs, err := reg.Gather()
	if err != nil {
		return fmt.Errorf("메트릭 수집 실패: %w", err)
	}
	var body bytes.Buffer
	enc := expfmt.NewEncoder(&body, expfmt.NewFormat(expfmt.TypeTextPlain))
	for _, mf := range mfs {
		if err := enc.Encode(mf); err != nil {
			return fmt.Errorf("메트릭 인코딩 실패: %w", err)
		}
	}

	req, err := http.NewRequest(http.MethodPost, url+GroupPath(scraper, keyword), &body)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", string(expfmt.NewFormat(expfmt.TypeTextPlain)))
	resp, err := (&http.Client{Timeout: 10 * time.Second}).Do(req)
	if err != nil {
		return fmt.Errorf("pushgateway push 실패: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return fmt.Errorf("pushgateway push 실패: HTTP %d", resp.StatusCode)
	}
	return nil
}

// GroupPath Pushgateway grouping 경로 (/metrics/job/<job>/scraper@base64/<..>/keyword@base64/<..>)
func GroupPath(scraper, keyword string) string {
	b64 := func(v string) string {
		if v == "" {
			return "=" // Pushgateway 규칙: 빈 값은 "="
		}
		return base64.RawURLEncoding.EncodeToString([]byte(v))
	}
	return "/metrics/job/" + PushJobName +
		"/scraper@base64/" + b64(scraper) +
		"/keyword@base64/" + b64(keyword)
}
