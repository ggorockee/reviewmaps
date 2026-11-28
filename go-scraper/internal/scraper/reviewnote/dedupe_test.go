package reviewnote

import (
	"testing"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/pkg/models"
)

func TestDedupeCampaignsKeepsDetailThenLatest(t *testing.T) {
	day := func(d int) *time.Time {
		v := time.Date(2026, 12, d, 0, 0, 0, 0, time.UTC)
		return &v
	}
	at := func(d, utcHour int) *time.Time {
		v := time.Date(2026, 12, d, utcHour, 0, 0, 0, time.UTC)
		return &v
	}
	fetched := day(1)
	c := func(title string, id int, deadline *time.Time) models.Campaign {
		return models.Campaign{Platform: platformName, Title: title, Offer: "숙박", CampaignChannel: "blog", SourceID: id, ApplyDeadline: deadline}
	}
	withDays := func(v models.Campaign) models.Campaign {
		v.PossibleDays, v.DetailFetchedAt = strp("금"), fetched
		return v
	}
	withDetail := func(v models.Campaign) models.Campaign {
		v.DetailFetchedAt = fetched
		return v
	}

	for name, tc := range map[string]struct {
		in   []models.Campaign
		want int
	}{
		"요일 있는 지난 회차가 요일 없는 최신 회차보다 먼저": {[]models.Campaign{c("a", 2, day(9)), withDays(c("a", 1, day(1)))}, 1},
		"순서가 반대여도 같음":                   {[]models.Campaign{withDays(c("a", 1, day(1))), c("a", 2, day(9))}, 1},
		"요일이 없으면 상세 받은 것":               {[]models.Campaign{c("a", 2, day(9)), withDetail(c("a", 1, day(1)))}, 1},
		"둘 다 요일 있으면 마감이 늦은 것":           {[]models.Campaign{withDays(c("a", 2, day(1))), withDays(c("a", 1, day(9)))}, 1},
		"한국 날짜가 늦으면 최신":                 {[]models.Campaign{c("a", 2, at(9, 14)), c("a", 1, at(9, 16))}, 1},
		"같은 날짜면 나중에 등록된 것":              {[]models.Campaign{c("a", 2, at(9, 1)), c("a", 1, at(9, 14))}, 2},
		"마감 없는 것보다 있는 것":                {[]models.Campaign{c("a", 2, nil), c("a", 1, day(1))}, 1},
		"모두 같으면 나중에 등록된 것":              {[]models.Campaign{c("a", 1, day(1)), c("a", 2, day(1))}, 2},
	} {
		got := dedupeCampaigns(tc.in)
		if len(got) != 1 || got[0].SourceID != tc.want {
			t.Errorf("%s: %d건, %d, want %d", name, len(got), got[0].SourceID, tc.want)
		}
	}

	got := dedupeCampaigns([]models.Campaign{c("a", 1, day(1)), c("b", 3, day(1)), c("a", 2, day(9))})
	if len(got) != 2 || got[0].SourceID != 2 || got[1].SourceID != 3 {
		t.Errorf("다른 공고는 남기고 자리 유지: %d건", len(got))
	}
}
