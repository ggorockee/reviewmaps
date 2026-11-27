package pickly

import (
	"context"
	"encoding/json"
	"os"
	"testing"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/config"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/scraper"
	"github.com/ggorockee/reviewmaps/go-scraper/pkg/models"
)

// testdata 는 2026-11-27 피클리 API 실제 응답 일부 (목록 3건: 맛집 방문형, 배송형, 여행 / 상세 1건)
func load(t *testing.T, name string, v interface{}) {
	t.Helper()
	b, err := os.ReadFile("testdata/" + name)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(b, v); err != nil {
		t.Fatal(err)
	}
}

var beforeDeadline = time.Date(2026, 11, 27, 12, 0, 0, 0, kst)

func TestParseRealListing(t *testing.T) {
	var items []Business
	load(t, "list.json", &items)
	got := Parse(items, beforeDeadline)
	if len(got) != 3 {
		t.Fatalf("3건 기대, got %d", len(got))
	}

	food := got[0]
	if food.Platform != "피클리" || food.Title != "마유유 마라탕 더현대서울점" || food.Offer != "3만원 이용권" || food.CampaignChannel != "blog" {
		t.Errorf("기본 필드: %+v", food)
	}
	if *food.CampaignType != "방문형" || food.Address == nil || *food.Region != "서울 여의도" {
		t.Errorf("방문형 주소·지역: %v %v", food.Address, *food.Region)
	}
	if *food.ContentLink != "https://picklykorea.kr/business/5212edd8-7bc2-420f-b7c3-8bcec6cf094a" {
		t.Errorf("링크: %s", *food.ContentLink)
	}
	if food.ImgURL == nil || (*food.ImgURL)[:len("https://picklykorea.kr/objects/")] != "https://picklykorea.kr/objects/" {
		t.Errorf("이미지 절대 주소: %v", food.ImgURL)
	}
	if want := time.Date(2026, 12, 10, 23, 59, 59, 0, kst); !food.ApplyDeadline.Equal(want) {
		t.Errorf("마감 KST 23:59:59: %v", food.ApplyDeadline)
	}
	if want := time.Date(2026, 11, 27, 0, 0, 0, 0, kst); !food.ApplyFrom.Equal(want) {
		t.Errorf("모집 시작: %v", food.ApplyFrom)
	}
	if food.PossibleDays == nil || *food.PossibleDays != "월 / 화 / 수 / 목 / 금 / 토 / 일" {
		t.Errorf("방문 가능 요일: %v", food.PossibleDays)
	}

	delivery := got[1]
	if *delivery.CampaignType != "배송형" || delivery.Address != nil || delivery.Lat != nil || delivery.Region != nil {
		t.Errorf("배송형은 주소·좌표·지역 없음: %+v", delivery)
	}

	travel := got[2]
	if *travel.Region != "세종" {
		t.Errorf("시·구가 같으면 한 번만: %q", *travel.Region)
	}
	if travel.PossibleDays == nil || *travel.PossibleDays != "월 / 화 / 수 / 목 / 금 / 토 / 일" {
		t.Errorf("요일 정렬: %v", travel.PossibleDays)
	}
}

func TestParseSkipsInactiveExpiredAndDuplicates(t *testing.T) {
	var items []Business
	load(t, "list.json", &items)
	inactive := items[0]
	inactive.ID, inactive.Status = "x", "closed"
	dup := items[0]
	dup.ID = "y"
	got := Parse(append(items, inactive, dup), beforeDeadline)
	if len(got) != 3 {
		t.Errorf("비활성·중복 제외 후 3건, got %d", len(got))
	}
	if n := len(Parse(items, time.Date(2026, 12, 11, 0, 0, 0, 0, kst))); n != 0 {
		t.Errorf("마감 지난 공고 제외, got %d", n)
	}
}

func TestOfferFallbackAndHelpers(t *testing.T) {
	won := "75600"
	if got := offerText(Business{BenefitsOne: &won}); got != "75,600원 상당" {
		t.Errorf("금액 대체 문구: %q", got)
	}
	w := "50000"
	if got := offerText(Business{BenefitsOne: &w}); got != "5만원 상당" {
		t.Errorf("만원 단위: %q", got)
	}
	if d := visitDaysText([]string{"일", "금", "월요일", "월"}); d == nil || *d != "월 / 금 / 일" {
		t.Errorf("요일 정렬·중복: %v", d)
	}
	if visitDaysText(nil) != nil {
		t.Error("요일 없으면 nil")
	}
}

type fakeLocations map[string]models.CampaignKey

func (f fakeLocations) LoadLocationsByLinks(context.Context, string, []string) (map[string]models.CampaignKey, error) {
	return f, nil
}

func TestEnrichLocationsReusesStoredAndFetchesOnlyNew(t *testing.T) {
	var items []Business
	load(t, "list.json", &items)
	var detail Business
	load(t, "detail.json", &detail)
	campaigns := Parse(items, beforeDeadline)

	lat, lng := 37.5, 126.9
	stored := fakeLocations{*campaigns[0].ContentLink: {Lat: &lat, Lng: &lng}}
	var fetched []string
	s := &Scraper{
		BaseScraper: &scraper.BaseScraper{Config: &config.Config{Pickly: config.PicklyConfig{Enabled: true, MaxDetailFetch: 10}}},
		locations:   stored,
		fetchOne: func(_ context.Context, id string) (*Business, error) {
			fetched = append(fetched, id)
			return &detail, nil
		},
		sleep: func(context.Context, time.Duration) bool { return true },
	}
	out := s.enrichLocations(context.Background(), campaigns)

	if *out[0].Lat != 37.5 {
		t.Errorf("저장된 좌표 재사용")
	}
	if len(fetched) != 1 || fetched[0] != "c8bdff34-28ab-4177-b3b5-ab27167d165a" {
		t.Errorf("좌표 없는 방문형(쥬라리움)만 상세 조회, 배송형 제외: %v", fetched)
	}
	if out[2].Lat == nil || *out[2].Lat != 36.4715494 {
		t.Errorf("상세 좌표 반영: %v", out[2].Lat)
	}
	if out[1].Lat != nil {
		t.Errorf("배송형은 좌표 없음")
	}
}

func TestRawCategories(t *testing.T) {
	var items []Business
	load(t, "list.json", &items)
	raws := rawCategories(items)
	if raws[contentLink(items[2].ID)] != "피클리>여행" {
		t.Errorf("원본 카테고리: %v", raws)
	}
}

func TestRunDisabledDoesNothing(t *testing.T) {
	s := &Scraper{
		BaseScraper: &scraper.BaseScraper{Config: &config.Config{}},
		fetchList: func(context.Context, int) ([]Business, error) {
			t.Fatal("꺼져 있으면 요청하면 안 됨")
			return nil, nil
		},
	}
	if err := s.Run(context.Background(), nil); err != nil {
		t.Fatal(err)
	}
}
