package reviewnote

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/logger"
	"github.com/ggorockee/reviewmaps/go-scraper/pkg/models"
)

// 상세 API. 로그인한 사용자만 볼 수 있어 세션 쿠키(reviewNoteSession)가 필요하다 (2026-11-27 확인).
// 쿠키 갱신 방법은 claudedocs/reviewnote-travel-selenium.md
var detailURLFormat = "https://www.reviewnote.co.kr/api/campaign?id=%d"

const sessionCookieName = "reviewNoteSession"

// ErrSessionExpired 세션 쿠키가 없거나 만료되어 상세 API가 401을 돌려줌
var ErrSessionExpired = errors.New("리뷰노트 로그인 세션 없음 또는 만료 (401)")

// ErrBlocked 403·429·5xx 등 차단·과부하 신호. 받으면 그날 밤 수집을 즉시 멈춘다
var ErrBlocked = errors.New("리뷰노트 차단 또는 과부하 신호")

// detailResponse 상세 API 응답 중 쓰는 필드
type detailResponse struct {
	PossibleDays        *string `json:"possibleDays"`
	ImpossibleDays      *string `json:"impossibleDays"`
	PossibleTime        *string `json:"possibleTime"`
	SameDayVisit        *bool   `json:"sameDayVisit"`
	ScheduleInformation *string `json:"scheduleInformation"`
}

// stayStore 이전에 받은 상세 값 조회 (테스트에서 바꿔 끼움)
type stayStore interface {
	LoadStayDetails(ctx context.Context, platform string, links []string) (map[string]models.StayDetail, error)
}

type detailFetcher func(ctx context.Context, id int) (*detailResponse, error)

// fetchDetailHTTP 상세 API 호출
func (s *Scraper) fetchDetailHTTP(ctx context.Context, id int) (*detailResponse, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, fmt.Sprintf(detailURLFormat, id), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
	req.Header.Set("Accept", "application/json, text/plain, */*")
	req.Header.Set("Accept-Language", "ko-KR,ko;q=0.9")
	req.Header.Set("Referer", fmt.Sprintf("https://www.reviewnote.co.kr/campaigns/%d", id))
	req.AddCookie(&http.Cookie{Name: sessionCookieName, Value: s.Config.Reviewnote.Session})

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	switch {
	case resp.StatusCode == http.StatusUnauthorized:
		return nil, ErrSessionExpired
	case resp.StatusCode == http.StatusForbidden || resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= 500:
		return nil, fmt.Errorf("%w: 상세 API 응답 %d (id=%d)", ErrBlocked, resp.StatusCode, id)
	case resp.StatusCode != http.StatusOK:
		return nil, fmt.Errorf("상세 API 응답 %d (id=%d)", resp.StatusCode, id)
	}
	var d detailResponse
	if err := json.NewDecoder(resp.Body).Decode(&d); err != nil {
		return nil, fmt.Errorf("상세 API 응답 해석 실패 (id=%d): %w", id, err)
	}
	return &d, nil
}

func cleanText(p *string) *string {
	if p == nil {
		return nil
	}
	t := strings.TrimSpace(*p)
	if t == "" {
		return nil
	}
	return &t
}

func (d *detailResponse) toStayDetail(fetchedAt time.Time) models.StayDetail {
	return models.StayDetail{
		PossibleDays:      cleanText(d.PossibleDays),
		ImpossibleDays:    cleanText(d.ImpossibleDays),
		PossibleTime:      cleanText(d.PossibleTime),
		SameDayVisit:      d.SameDayVisit,
		ReservationNotice: cleanText(d.ScheduleInformation),
		FetchedAt:         fetchedAt,
	}
}

func contains(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

// ApplyStoredStayDetails 02:00 목록 수집(reviewnote)용: 보관 테이블의 상세 값을 캠페인에 붙인다.
// 상세 API는 부르지 않는다 (상세는 reviewnote-detail 이 새벽에 천천히 받음).
// campaign 행은 DELETE 후 INSERT 되므로 이 단계가 없으면 요일 정보가 지워진다.
func (s *Scraper) ApplyStoredStayDetails(ctx context.Context, campaigns []models.Campaign) []models.Campaign {
	log := logger.GetLogger("scraper.reviewnote.detail")
	if s.stays == nil {
		return campaigns
	}
	var links []string
	for _, c := range campaigns {
		if c.ContentLink != nil {
			links = append(links, *c.ContentLink)
		}
	}
	stored, err := s.stays.LoadStayDetails(ctx, platformName, links)
	if err != nil {
		log.Warnf("보관된 상세 값 조회 실패 (이번 저장에는 요일 정보 없이 저장, 새벽 상세 수집이 다시 맞춤): %v", err)
		return campaigns
	}
	applied := 0
	for i := range campaigns {
		if c := &campaigns[i]; c.ContentLink != nil {
			if d, ok := stored[*c.ContentLink]; ok {
				d.Apply(c)
				applied++
			}
		}
	}
	log.Infof("보관된 상세 이용 조건 %d건을 붙였습니다", applied)
	return campaigns
}

// sleepCtx d만큼 기다린다. 컨텍스트가 끝나면 false.
func sleepCtx(ctx context.Context, d time.Duration) bool {
	if d <= 0 {
		return ctx.Err() == nil
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-t.C:
		return true
	}
}
