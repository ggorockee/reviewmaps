package models_test

import (
	"sync"
	"testing"

	"github.com/ggorockee/reviewmaps/server/internal/models"
	"gorm.io/gorm/schema"
)

// KeywordAlert의 (keyword_id, campaign_id) 유니크 인덱스는 soft-delete 행을 제외하는 부분 인덱스여야 함
// (soft-deleted 알림은 재생성 방지용으로 보존되며, 운영 마이그레이션 add_partial_unique_index_keyword_alerts.sql과 일치)
func TestKeywordAlertPartialUniqueIndex(t *testing.T) {
	s, err := schema.Parse(&models.KeywordAlert{}, &sync.Map{}, schema.NamingStrategy{})
	if err != nil {
		t.Fatalf("스키마 파싱 실패: %v", err)
	}

	var found bool
	for _, idx := range s.ParseIndexes() {
		if idx.Name != "keyword_alerts_keyword_campaign_unique" {
			continue
		}
		found = true
		if idx.Class != "UNIQUE" {
			t.Errorf("UNIQUE 인덱스여야 함: %q", idx.Class)
		}
		if idx.Where != "deleted_at IS NULL" {
			t.Errorf("부분 인덱스 조건 불일치: %q", idx.Where)
		}
		if len(idx.Fields) != 2 || idx.Fields[0].DBName != "keyword_id" || idx.Fields[1].DBName != "campaign_id" {
			t.Errorf("컬럼 순서는 (keyword_id, campaign_id): %+v", idx.Fields)
		}
	}
	if !found {
		t.Fatal("keyword_alerts_keyword_campaign_unique 인덱스가 정의되지 않음")
	}
}
