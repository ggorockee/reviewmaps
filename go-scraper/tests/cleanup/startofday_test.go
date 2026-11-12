package cleanup_test

import (
	"testing"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/cleanup"
)

func TestStartOfDayKST(t *testing.T) {
	kst, err := time.LoadLocation("Asia/Seoul")
	if err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name string
		now  time.Time
		want string
	}{
		// 정기 실행 05:00 KST (= 전날 20:00 UTC)
		{"05시 KST", time.Date(2026, 11, 13, 5, 0, 0, 0, kst), "2026-11-13T00:00:00+09:00"},
		// 수동 실행 02:55 KST (기존 버그: 2026-11-12 09:00 KST 반환)
		{"02시55분 KST", time.Date(2026, 11, 12, 17, 55, 0, 0, time.UTC), "2026-11-13T00:00:00+09:00"},
		{"23시59분 KST", time.Date(2026, 11, 13, 23, 59, 59, 0, kst), "2026-11-13T00:00:00+09:00"},
		{"자정 정각", time.Date(2026, 11, 13, 0, 0, 0, 0, kst), "2026-11-13T00:00:00+09:00"},
	}
	for _, c := range cases {
		got := cleanup.StartOfDay(c.now, kst).Format(time.RFC3339)
		if got != c.want {
			t.Errorf("%s: StartOfDay = %s, want %s", c.name, got, c.want)
		}
	}
}

// 기존 구현이 틀렸음을 기록: Truncate(24h)는 KST에서 전날 09:00이 된다.
func TestTruncateIsWrongForKST(t *testing.T) {
	kst, _ := time.LoadLocation("Asia/Seoul")
	now := time.Date(2026, 11, 13, 5, 0, 0, 0, kst)
	if got := now.In(kst).Truncate(24 * time.Hour).In(kst).Format(time.RFC3339); got != "2026-11-12T09:00:00+09:00" {
		t.Errorf("Truncate 동작 가정이 달라짐: %s", got)
	}
}
