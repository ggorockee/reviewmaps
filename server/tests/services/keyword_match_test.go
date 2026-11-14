package services_test

import (
	"fmt"
	"math/rand"
	"regexp"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/ggorockee/reviewmaps/server/internal/models"
	"github.com/ggorockee/reviewmaps/server/internal/services"
)

var base = time.Date(2026, 11, 14, 0, 0, 0, 0, time.UTC)

func strPtr(s string) *string { return &s }

func campaign(id uint, title *string, offer string, createdAt time.Time) models.Campaign {
	return models.Campaign{ID: id, Title: title, Offer: offer, CreatedAt: createdAt}
}

func keyword(id uint, text string, createdAt time.Time) models.Keyword {
	return models.Keyword{ID: id, Keyword: text, IsActive: true, CreatedAt: createdAt}
}

// key 비교용 문자열: keyword:campaign:field
func keys(alerts []models.KeywordAlert) []string {
	out := make([]string, 0, len(alerts))
	for _, a := range alerts {
		out = append(out, fmt.Sprintf("%d:%d:%s", a.KeywordID, *a.CampaignID, a.MatchedField))
	}
	sort.Strings(out)
	return out
}

func TestMatchKeywordAlerts_Rules(t *testing.T) {
	kws := services.PrepareKeywords([]models.Keyword{
		keyword(1, "파주", base),
		keyword(2, "  !!  ", base),            // 정규화 후 빈 문자열 → 제외
		keyword(3, "Coffee Bean", base),       // 공백/대소문자 무시
		keyword(4, "맛집", base.Add(time.Hour)), // 캠페인보다 늦게 등록 → 제외
	})
	if len(kws) != 3 {
		t.Fatalf("빈 키워드 제외 후 3개여야 함: %d", len(kws))
	}

	campaigns := []models.Campaign{
		campaign(10, strPtr("[파주] 맛집 체험단"), "커피 2잔", base.Add(time.Minute)),
		campaign(11, nil, "coffeebean 아메리카노 증정", base.Add(time.Minute)), // 제목 없음 → offer 매칭
		campaign(12, strPtr("파주 카페"), "파주 쿠폰", base.Add(time.Minute)),   // 제목 우선
		campaign(13, strPtr("서울 맛집"), "식사권", base.Add(2*time.Hour)),     // 맛집 키워드 이후 생성 → 매칭
		campaign(14, strPtr("파주 식당"), "식사권", base.Add(-time.Minute)),    // 키워드보다 먼저 생성 → 제외
	}
	existing := map[services.AlertKey]struct{}{
		{KeywordID: 1, CampaignID: 12}: {}, // 이미 알림 있음(soft-deleted 포함) → 제외
	}

	got := keys(services.MatchKeywordAlerts(campaigns, kws, existing))
	want := []string{"1:10:title", "3:11:offer", "4:13:title"}
	sort.Strings(want)

	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("매칭 결과\n got: %v\nwant: %v", got, want)
	}
}

func TestMatchKeywordAlerts_Empty(t *testing.T) {
	if got := services.MatchKeywordAlerts(nil, services.PrepareKeywords(nil), nil); len(got) != 0 {
		t.Errorf("빈 입력은 빈 결과: %v", got)
	}
}

// ---- 기존 구현(캠페인 1개씩 처리하던 ProcessCampaignKeywordMatchingByID) 매칭 로직의 참조 사본 ----

var refRegex = regexp.MustCompile(`[^\w가-힣]`)

func refNormalize(s string) string {
	if s == "" {
		return ""
	}
	return refRegex.ReplaceAllString(strings.ToLower(s), "")
}

func referenceMatch(campaigns []models.Campaign, active []models.Keyword, existing map[services.AlertKey]struct{}) []models.KeywordAlert {
	var out []models.KeywordAlert
	for _, c := range campaigns {
		var titleN string
		if c.Title != nil {
			titleN = refNormalize(*c.Title)
		}
		offerN := refNormalize(c.Offer)
		for _, kw := range active {
			if _, ok := existing[services.AlertKey{KeywordID: kw.ID, CampaignID: c.ID}]; ok {
				continue
			}
			if c.CreatedAt.Before(kw.CreatedAt) {
				continue
			}
			kn := refNormalize(kw.Keyword)
			if kn == "" {
				continue
			}
			field := ""
			if titleN != "" && strings.Contains(titleN, kn) {
				field = "title"
			} else if strings.Contains(offerN, kn) {
				field = "offer"
			}
			if field != "" {
				id := c.ID
				out = append(out, models.KeywordAlert{KeywordID: kw.ID, CampaignID: &id, MatchedField: field})
			}
		}
	}
	return out
}

// 무작위 데이터에서 일괄 매칭 결과가 기존 캠페인별 로직과 동일해야 함
func TestMatchKeywordAlerts_EquivalentToPerCampaignLogic(t *testing.T) {
	words := []string{"파주", "맛집", "카페", "Coffee", "헤어", "네일", "강남", "펜션", "!!", " ", "B-B-Q", "bbq", "일산", "뷰티"}
	rng := rand.New(rand.NewSource(20261114))
	pick := func(n int) string {
		parts := make([]string, n)
		for i := range parts {
			parts[i] = words[rng.Intn(len(words))]
		}
		return strings.Join(parts, " ")
	}

	totalMatches := 0
	for round := 0; round < 50; round++ {
		var active []models.Keyword
		for i := 0; i < 45; i++ {
			active = append(active, keyword(uint(i+1), pick(1+rng.Intn(2)), base.Add(time.Duration(rng.Intn(48)-24)*time.Hour)))
		}
		var campaigns []models.Campaign
		existing := map[services.AlertKey]struct{}{}
		for i := 0; i < 100; i++ {
			var title *string
			if rng.Intn(5) != 0 {
				title = strPtr(pick(1 + rng.Intn(4)))
			}
			c := campaign(uint(1000+i), title, pick(rng.Intn(4)), base.Add(time.Duration(rng.Intn(48)-24)*time.Hour))
			campaigns = append(campaigns, c)
			if rng.Intn(10) == 0 {
				existing[services.AlertKey{KeywordID: uint(1 + rng.Intn(45)), CampaignID: c.ID}] = struct{}{}
			}
		}

		got := keys(services.MatchKeywordAlerts(campaigns, services.PrepareKeywords(active), existing))
		want := keys(referenceMatch(campaigns, active, existing))
		if strings.Join(got, ",") != strings.Join(want, ",") {
			t.Fatalf("round %d: 결과 불일치\n got(%d): %v\nwant(%d): %v", round, len(got), got, len(want), want)
		}
		totalMatches += len(want)
	}
	// 비교가 무의미하게 빈 결과끼리만 이뤄지지 않았는지 확인
	if totalMatches == 0 {
		t.Fatal("무작위 데이터에서 매칭이 하나도 없어 동등성 검증이 무의미함")
	}
	t.Logf("50 rounds, total matches compared: %d", totalMatches)
}

// 운영 규모(780 캠페인 × 45 키워드) 순수 매칭 비용 측정
func BenchmarkMatchKeywordAlerts_780x45(b *testing.B) {
	var active []models.Keyword
	for i := 0; i < 45; i++ {
		active = append(active, keyword(uint(i+1), fmt.Sprintf("키워드%d", i), base))
	}
	kws := services.PrepareKeywords(active)
	var campaigns []models.Campaign
	for i := 0; i < 780; i++ {
		campaigns = append(campaigns, campaign(uint(i+1), strPtr(fmt.Sprintf("[지역] 체험단 키워드%d 맛집", i%60)), "제공 내역 2인 식사권", base.Add(time.Hour)))
	}
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		services.MatchKeywordAlerts(campaigns, kws, nil)
	}
}
