package db

import (
	"slices"
	"testing"
)

func TestBuildAlertRestorePlan(t *testing.T) {
	oldIDsByKey := map[string][]uint{
		"A": {10},     // 기존 캠페인 1개
		"B": {20, 21}, // 같은 키의 중복 레코드 2개 → 둘의 알림 모두 새 ID로
		"C": {30},     // INSERT 실패(새 ID 없음) → 복원 제외
		"D": {40},     // 알림 없음 → 계획에 포함 안 됨
		"E": nil,      // 신규 캠페인 (기존 ID 없음)
	}
	alertIDsByCampaign := map[uint][]uint{
		10: {100, 101},
		20: {200},
		21: {210, 211},
		30: {300},
		99: {999}, // 이번 저장과 무관한 캠페인의 알림 → 절대 포함되면 안 됨
	}
	newIDByKey := map[string]uint{"A": 1000, "B": 2000, "D": 4000, "E": 5000}

	plan := buildAlertRestorePlan(oldIDsByKey, alertIDsByCampaign, newIDByKey)

	want := map[uint][]uint{
		1000: {100, 101},
		2000: {200, 210, 211},
	}
	if len(plan) != len(want) {
		t.Fatalf("계획 대상 수: 기대 %d, 실제 %d (%v)", len(want), len(plan), plan)
	}
	for newID, alerts := range want {
		got := slices.Clone(plan[newID])
		slices.Sort(got)
		if !slices.Equal(got, alerts) {
			t.Errorf("새 ID %d: 기대 %v, 실제 %v", newID, alerts, got)
		}
	}
	for _, alerts := range plan {
		if slices.Contains(alerts, 999) || slices.Contains(alerts, 300) {
			t.Errorf("무관하거나 INSERT 실패한 캠페인의 알림이 포함됨: %v", plan)
		}
	}
}
