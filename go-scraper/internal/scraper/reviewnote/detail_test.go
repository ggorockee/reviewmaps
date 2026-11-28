package reviewnote

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/config"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/scraper"
	"github.com/ggorockee/reviewmaps/go-scraper/pkg/models"
)

// memStore 메모리 보관 테이블
type memStore struct {
	rows   map[string]models.StayDetail
	saved  []int
	synced int
}

func newMemStore() *memStore { return &memStore{rows: map[string]models.StayDetail{}} }

func (m *memStore) LoadStayDetails(_ context.Context, _ string, links []string) (map[string]models.StayDetail, error) {
	out := map[string]models.StayDetail{}
	for _, l := range links {
		if d, ok := m.rows[l]; ok {
			out[l] = d
		}
	}
	return out, nil
}

func (m *memStore) SaveStayDetail(_ context.Context, _, link string, id int, d models.StayDetail) error {
	m.rows[link] = d
	m.saved = append(m.saved, id)
	return nil
}

func (m *memStore) SyncStayDetailsToCampaigns(ctx context.Context, _ string) (int64, error) {
	if err := ctx.Err(); err != nil {
		return 0, err
	}
	m.synced++
	return 0, nil
}

func strp(s string) *string { return &s }
func boolp(b bool) *bool    { return &b }
func link(id int) string    { return fmt.Sprintf("https://www.reviewnote.co.kr/campaigns/%d", id) }

func seoul(t *testing.T) *time.Location {
	loc, err := time.LoadLocation("Asia/Seoul")
	if err != nil {
		t.Fatal(err)
	}
	return loc
}

func rc(session string) config.ReviewnoteConfig {
	return config.ReviewnoteConfig{
		Session:           session,
		DetailCategories:  []string{"여행"},
		DetailRefreshDays: 14,
		DetailMaxFetch:    10,
		DetailMinDelay:    30 * time.Second,
		DetailWindowEnd:   "08:00",
		DetailEndMargin:   10 * time.Minute,
		DetailStartJitter: 0,
		DetailManualRun:   time.Hour,
	}
}

// newDetailScraper 대기 없이 돌도록 sleep을 바꾸고, 목록·상세를 가짜로 끼운 스크레이퍼
func newDetailScraper(t *testing.T, r config.ReviewnoteConfig, store *memStore, pages [][]map[string]interface{}, fetch detailFetcher) *Scraper {
	t.Helper()
	cfg := &config.Config{Reviewnote: r, Batch: config.BatchConfig{Timezone: "Asia/Seoul"}}
	return &Scraper{
		BaseScraper: &scraper.BaseScraper{Config: cfg},
		httpClient:  &http.Client{Timeout: 5 * time.Second},
		stays:       store,
		details:     store,
		fetchDetail: fetch,
		listPage: func(_ context.Context, _ string, page, _ int) ([]map[string]interface{}, error) {
			if page < len(pages) {
				return pages[page], nil
			}
			return nil, nil
		},
		sleep: func(ctx context.Context, _ time.Duration) bool { return ctx.Err() == nil },
		rnd:   rand.New(rand.NewSource(1)),
	}
}

func item(id int, category, status string) map[string]interface{} {
	return map[string]interface{}{"id": id, "categoryTitle": category, "status": status}
}

func TestPlanDetailRun(t *testing.T) {
	loc := seoul(t)
	rnd := rand.New(rand.NewSource(1))

	// 새벽 00:05 정기 실행: 07:50 마감, 대기는 30분 이하
	now := time.Date(2026, 11, 28, 0, 5, 0, 0, loc)
	p, err := planDetailRun(now, loc, "08:00", 10*time.Minute, 30*time.Minute, time.Hour, rnd)
	if err != nil {
		t.Fatal(err)
	}
	if want := time.Date(2026, 11, 28, 7, 50, 0, 0, loc); !p.Deadline.Equal(want) {
		t.Errorf("마감 %v, want %v", p.Deadline, want)
	}
	if p.StartDelay < 0 || p.StartDelay > 30*time.Minute {
		t.Errorf("시작 대기 범위 밖: %v", p.StartDelay)
	}

	// 낮 14:00 수동 실행: 바로 시작, 1시간 동안
	now = time.Date(2026, 11, 27, 14, 0, 0, 0, loc)
	p, _ = planDetailRun(now, loc, "08:00", 10*time.Minute, 30*time.Minute, time.Hour, rnd)
	if p.StartDelay != 0 || !p.Deadline.Equal(now.Add(time.Hour)) {
		t.Errorf("수동 실행 계획 오류: %+v", p)
	}

	if _, err := planDetailRun(now, loc, "8시", 0, 0, time.Hour, rnd); err == nil {
		t.Error("잘못된 마감 형식은 에러")
	}
}

func TestNextGapSpreadsAndRespectsMinimum(t *testing.T) {
	rnd := rand.New(rand.NewSource(1))
	// 7시간 동안 400건 → 평균 63초 근처 (0.6~1.2배)
	for i := 0; i < 100; i++ {
		g := nextGap(7*time.Hour, 400, 30*time.Second, rnd)
		if g < 30*time.Second || g > 76*time.Second {
			t.Fatalf("간격 범위 밖: %v", g)
		}
	}
	// 마지막 1건도 남은 시간 안에 받을 수 있어야 함
	for i := 0; i < 100; i++ {
		if g := nextGap(10*time.Minute, 1, 30*time.Second, rnd); g >= 10*time.Minute {
			t.Fatalf("마지막 간격이 남은 시간을 넘음: %v", g)
		}
	}
	// 남은 시간이 적어도 최소 간격은 지킴
	if g := nextGap(time.Minute, 100, 30*time.Second, rnd); g < 30*time.Second {
		t.Fatalf("최소 간격 미만: %v", g)
	}
}

func TestPickTargets(t *testing.T) {
	now := time.Now()
	all := []detailTarget{{1, link(1)}, {2, link(2)}, {3, link(3)}, {4, link(4)}}
	stored := map[string]models.StayDetail{
		link(1): {FetchedAt: now.Add(-24 * time.Hour)},      // 최근 → 제외
		link(2): {FetchedAt: now.Add(-20 * 24 * time.Hour)}, // 오래됨
		link(3): {FetchedAt: now.Add(-30 * 24 * time.Hour)}, // 더 오래됨
	}
	got, fresh := pickTargets(all, stored, now, 14*24*time.Hour, 0)
	if fresh != 1 {
		t.Errorf("최근 값 1건, got %d", fresh)
	}
	if len(got) != 3 || got[0].ID != 4 || got[1].ID != 3 || got[2].ID != 2 {
		t.Errorf("없는 것 먼저, 그다음 오래된 순: %+v", got)
	}
	if got, _ := pickTargets(all, stored, now, 14*24*time.Hour, 2); len(got) != 2 {
		t.Errorf("최대 건수 제한: %d", len(got))
	}
}

func TestRunDetail_FetchesOnlyTravelSelectAndSyncs(t *testing.T) {
	store := newMemStore()
	pages := [][]map[string]interface{}{
		{item(1, "여행", "SELECT"), item(2, "맛집", "SELECT"), item(3, "여행", "PROGRESS")},
		{item(4, "여행", "SELECT"), item(1, "여행", "SELECT")},
	}
	fetch := func(_ context.Context, id int) (*detailResponse, error) {
		return &detailResponse{PossibleDays: strp(" 월 / 화 "), SameDayVisit: boolp(true), ScheduleInformation: strp(" ")}, nil
	}
	s := newDetailScraper(t, rc("s"), store, pages, fetch)

	if err := s.RunDetail(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(store.saved) != 2 || store.saved[0] != 1 || store.saved[1] != 4 {
		t.Fatalf("여행·모집 중(1,4)만 한 번씩: %v", store.saved)
	}
	d := store.rows[link(1)]
	if *d.PossibleDays != "월 / 화" || d.ReservationNotice != nil || !*d.SameDayVisit {
		t.Errorf("값 정리 오류: %+v", d)
	}
	if store.synced != 1 {
		t.Errorf("마지막에 campaign 맞추기 1회")
	}
}

func TestRunDetail_StopsImmediatelyOnBlockOrExpiry(t *testing.T) {
	for name, fetchErr := range map[string]error{
		"차단": fmt.Errorf("%w: 429", ErrBlocked),
		"만료": ErrSessionExpired,
	} {
		t.Run(name, func(t *testing.T) {
			store := newMemStore()
			pages := [][]map[string]interface{}{{item(1, "여행", "SELECT"), item(2, "여행", "SELECT"), item(3, "여행", "SELECT")}}
			calls := 0
			fetch := func(_ context.Context, _ int) (*detailResponse, error) {
				calls++
				return nil, fetchErr
			}
			s := newDetailScraper(t, rc("s"), store, pages, fetch)
			if err := s.RunDetail(context.Background()); err != nil {
				t.Fatal(err)
			}
			if calls != 1 {
				t.Errorf("첫 신호에서 바로 멈춰야 함, calls=%d", calls)
			}
			if store.synced != 1 {
				t.Errorf("멈춰도 campaign 맞추기는 함")
			}
		})
	}
}

func TestRunDetail_ToleratesScatteredErrorsButStopsOnRun(t *testing.T) {
	var items []map[string]interface{}
	for id := 1; id <= 60; id++ {
		items = append(items, item(id, "여행", "SELECT"))
	}
	for name, tc := range map[string]struct {
		fails     func(id int) bool
		wantCalls int
	}{
		"드문 실패는 끝까지": {func(id int) bool { return id%5 == 0 }, 60},
		"연속 3회면 멈춤":  {func(id int) bool { return id >= 10 }, 12},
		"누적 20회면 멈춤": {func(id int) bool { return id%2 == 0 }, 40},
	} {
		t.Run(name, func(t *testing.T) {
			r := rc("s")
			r.DetailMaxFetch = 0
			calls := 0
			fetch := func(_ context.Context, id int) (*detailResponse, error) {
				calls++
				if tc.fails(id) {
					return nil, errors.New("상세 API 응답 404")
				}
				return &detailResponse{PossibleDays: strp("금")}, nil
			}
			s := newDetailScraper(t, r, newMemStore(), [][]map[string]interface{}{items}, fetch)
			if err := s.RunDetail(context.Background()); err != nil {
				t.Fatal(err)
			}
			if calls != tc.wantCalls {
				t.Errorf("호출 %d, want %d", calls, tc.wantCalls)
			}
		})
	}
}

func TestRunDetail_StopSignalStillFinishes(t *testing.T) {
	for name, duringFetch := range map[string]bool{"대기 중 종료": false, "요청 중 종료": true} {
		t.Run(name, func(t *testing.T) {
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			store := newMemStore()
			pages := [][]map[string]interface{}{{item(1, "여행", "SELECT"), item(2, "여행", "SELECT"), item(3, "여행", "SELECT")}}
			calls := 0
			fetch := func(_ context.Context, _ int) (*detailResponse, error) {
				calls++
				if calls == 2 {
					cancel()
					if duringFetch {
						return nil, context.Canceled
					}
				}
				return &detailResponse{PossibleDays: strp("금")}, nil
			}
			s := newDetailScraper(t, rc("s"), store, pages, fetch)
			if err := s.RunDetail(ctx); err != nil {
				t.Fatalf("종료 신호는 실패가 아님: %v", err)
			}
			if calls != 2 || store.synced != 1 {
				t.Errorf("바로 멈추고 campaign 맞추기는 끝내야 함: 호출 %d, 맞추기 %d", calls, store.synced)
			}
		})
	}
}

func TestRunDetail_NoSessionDoesNothing(t *testing.T) {
	store := newMemStore()
	fetch := func(_ context.Context, _ int) (*detailResponse, error) {
		t.Fatal("세션이 없으면 상세를 부르면 안 됨")
		return nil, nil
	}
	s := newDetailScraper(t, rc(""), store, nil, fetch)
	s.listPage = func(context.Context, string, int, int) ([]map[string]interface{}, error) {
		t.Fatal("세션이 없으면 목록도 부르지 않음")
		return nil, nil
	}
	if err := s.RunDetail(context.Background()); err != nil {
		t.Fatal(err)
	}
}

func TestRunDetail_ListsEachCategoryAndFetchesAll(t *testing.T) {
	store := newMemStore()
	r := rc("s")
	r.DetailMaxFetch = 0 // 상한 없음
	r.DetailCategoryIDs = []string{"travel-id"}
	s := newDetailScraper(t, r, store, nil, nil)
	var asked []string
	s.listPage = func(_ context.Context, categoryID string, page, _ int) ([]map[string]interface{}, error) {
		asked = append(asked, fmt.Sprintf("%s:%d", categoryID, page))
		if page >= 30 {
			return nil, nil
		}
		var items []map[string]interface{}
		for i := 0; i < 16; i++ {
			items = append(items, item(page*16+i+1, "여행", "SELECT"))
		}
		return items, nil
	}

	targets, listed, err := s.listDetailTargets(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(targets) != 480 || listed != 480 {
		t.Fatalf("카테고리 목록 끝까지: 대상 %d, 목록 %d", len(targets), listed)
	}
	if asked[0] != "travel-id:0" || asked[len(asked)-1] != "travel-id:30" {
		t.Errorf("categoryId로 요청해야 함: %s … %s", asked[0], asked[len(asked)-1])
	}
	if got, _ := pickTargets(targets, nil, time.Now(), time.Hour, s.Config.Reviewnote.DetailMaxFetch); len(got) != 480 {
		t.Errorf("상한 0이면 전부: %d", len(got))
	}
}

func TestAppendCategoryPages(t *testing.T) {
	s := newDetailScraper(t, rc(""), newMemStore(), nil, nil)
	pages := [][]map[string]interface{}{
		{item(1, "여행", "SELECT"), item(2, "여행", "SELECT")},
		{item(3, "여행", "SELECT"), item(2, "여행", "SELECT")},
	}
	s.listPage = func(_ context.Context, categoryID string, page, _ int) ([]map[string]interface{}, error) {
		if categoryID != "travel-id" {
			t.Fatalf("categoryId: %q", categoryID)
		}
		if page < len(pages) {
			return pages[page], nil
		}
		return nil, nil
	}

	main := []map[string]interface{}{item(1, "여행", "SELECT"), item(9, "맛집", "SELECT")}
	out, err := s.appendCategoryPages(context.Background(), main, []string{"travel-id"})
	if err != nil {
		t.Fatal(err)
	}
	var ids []int
	for _, raw := range out {
		ids = append(ids, raw["id"].(int))
	}
	if fmt.Sprint(ids) != "[1 9 2 3]" {
		t.Errorf("없는 것만 뒤에 붙임: %v", ids)
	}

	if out, _ := s.appendCategoryPages(context.Background(), main, nil); len(out) != 2 {
		t.Errorf("카테고리가 없으면 그대로: %d", len(out))
	}
	s.listPage = func(context.Context, string, int, int) ([]map[string]interface{}, error) {
		return nil, errors.New("boom")
	}
	if _, err := s.appendCategoryPages(context.Background(), main, []string{"travel-id"}); err == nil {
		t.Error("목록 실패는 에러")
	}
}

func TestApplyStoredStayDetails(t *testing.T) {
	store := newMemStore()
	fetched := time.Now().Add(-time.Hour)
	store.rows[link(1)] = models.StayDetail{PossibleDays: strp("금"), FetchedAt: fetched}
	l1, l2 := link(1), link(2)
	s := newDetailScraper(t, rc(""), store, nil, nil)

	out := s.ApplyStoredStayDetails(context.Background(), []models.Campaign{{ContentLink: &l1}, {ContentLink: &l2}, {}})
	if out[0].PossibleDays == nil || *out[0].PossibleDays != "금" || !out[0].DetailFetchedAt.Equal(fetched) {
		t.Errorf("보관 값을 붙여야 함: %+v", out[0])
	}
	if out[1].PossibleDays != nil || out[2].PossibleDays != nil {
		t.Errorf("보관 값이 없으면 비워 둠")
	}
}

func TestFetchDetailHTTP(t *testing.T) {
	status := http.StatusOK
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, err := r.Cookie(sessionCookieName)
		if err != nil || c.Value != "good" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		if status != http.StatusOK {
			w.WriteHeader(status)
			return
		}
		fmt.Fprint(w, `{"possibleDays":"월 / 화","sameDayVisit":true,"scheduleInformation":"2일 전 예약"}`)
	}))
	defer srv.Close()
	orig := detailURLFormat
	detailURLFormat = srv.URL + "/api/campaign?id=%d"
	defer func() { detailURLFormat = orig }()

	s := newDetailScraper(t, rc("good"), newMemStore(), nil, nil)
	d, err := s.fetchDetailHTTP(context.Background(), 1)
	if err != nil {
		t.Fatal(err)
	}
	if *d.PossibleDays != "월 / 화" || !*d.SameDayVisit || *d.ScheduleInformation != "2일 전 예약" {
		t.Errorf("응답 해석 오류: %+v", d)
	}

	for _, st := range []int{http.StatusForbidden, http.StatusTooManyRequests, http.StatusBadGateway} {
		status = st
		if _, err := s.fetchDetailHTTP(context.Background(), 1); !errors.Is(err, ErrBlocked) {
			t.Errorf("%d → ErrBlocked, got %v", st, err)
		}
	}
	status = http.StatusOK
	s.Config.Reviewnote.Session = "bad"
	if _, err := s.fetchDetailHTTP(context.Background(), 1); !errors.Is(err, ErrSessionExpired) {
		t.Errorf("401 → ErrSessionExpired, got %v", err)
	}
}

// 실제 사이트 확인용 (평소에는 건너뜀): REVIEWNOTE_SESSION_LIVE_TEST=<쿠키 값> go test -run Live ./internal/scraper/reviewnote/
func TestFetchDetailLive(t *testing.T) {
	session := os.Getenv("REVIEWNOTE_SESSION_LIVE_TEST")
	if session == "" {
		t.Skip("REVIEWNOTE_SESSION_LIVE_TEST 없음")
	}
	s := newDetailScraper(t, rc(session), newMemStore(), nil, nil)
	d, err := s.fetchDetailHTTP(context.Background(), 1565099)
	if err != nil {
		t.Fatal(err)
	}
	if d.PossibleDays == nil {
		t.Fatal("possibleDays가 비어 있음")
	}
	t.Logf("possibleDays=%q", *d.PossibleDays)
}
