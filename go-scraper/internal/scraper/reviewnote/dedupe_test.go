package reviewnote

import (
	"testing"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/pkg/models"
)

func TestDedupeCampaignsKeepsRichest(t *testing.T) {
	day := func(d int) *time.Time {
		v := time.Date(2026, 12, d, 0, 0, 0, 0, time.UTC)
		return &v
	}
	fetched := day(1)
	c := func(title, id string, deadline *time.Time) models.Campaign {
		return models.Campaign{Platform: platformName, Title: title, Offer: "숙박", CampaignChannel: "blog", ContentLink: strp(id), ApplyDeadline: deadline}
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
		want string
	}{
		"요일 있는 것이 마감이 늦은 것보다 먼저": {[]models.Campaign{c("a", "late", day(9)), withDays(c("a", "days", day(1)))}, "days"},
		"순서가 반대여도 같음":            {[]models.Campaign{withDays(c("a", "days", day(1))), c("a", "late", day(9))}, "days"},
		"요일이 없으면 상세 받은 것":        {[]models.Campaign{c("a", "none", day(9)), withDetail(c("a", "detail", day(1)))}, "detail"},
		"둘 다 요일 있으면 마감이 늦은 것":    {[]models.Campaign{withDays(c("a", "early", day(1))), withDays(c("a", "late", day(9)))}, "late"},
		"마감 없는 것보다 있는 것":         {[]models.Campaign{c("a", "nodate", nil), c("a", "dated", day(1))}, "dated"},
		"모두 같으면 처음 것":            {[]models.Campaign{c("a", "first", day(1)), c("a", "second", day(1))}, "first"},
	} {
		got := dedupeCampaigns(tc.in)
		if len(got) != 1 || *got[0].ContentLink != tc.want {
			t.Errorf("%s: %d건, %s, want %s", name, len(got), *got[0].ContentLink, tc.want)
		}
	}

	got := dedupeCampaigns([]models.Campaign{c("a", "a1", day(1)), c("b", "b1", day(1)), c("a", "a2", day(9))})
	if len(got) != 2 || *got[0].ContentLink != "a2" || *got[1].ContentLink != "b1" {
		t.Errorf("다른 공고는 남기고 자리 유지: %d건", len(got))
	}
}
