package reviewnote

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"sort"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/logger"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/runstats"
	"github.com/ggorockee/reviewmaps/go-scraper/pkg/models"
)

// reviewnote-detail: 여행 카테고리 상세 이용 조건을 새벽(기본 00:00~08:00)에 아주 천천히 받는다.
//
// 차단을 피하는 것이 최우선이다.
//   - 한 번에 1건, 남은 시간을 남은 건수로 나눈 간격(무작위 ±)으로 요청, 최소 DetailMinDelay
//   - 시작 시각을 0~DetailStartJitter 무작위로 늦춤 (매일 같은 시각에 요청하지 않음)
//   - 한 번 받은 상세는 DetailRefreshDays 동안 다시 받지 않음
//   - 건수 제한 없이 대상 전부 (DetailMaxFetch > 0 이면 하룻밤 상한). 마감까지 못 받은 것은 다음 실행에
//   - 401(세션 만료)·403·429·5xx 를 한 번이라도 받으면 그날은 즉시 멈춤 (재시도 없음)

// detailStore 상세 보관 테이블 (테스트에서 바꿔 끼움)
type detailStore interface {
	stayStore
	SaveStayDetail(ctx context.Context, platform, link string, sourceID int, d models.StayDetail) error
	SyncStayDetailsToCampaigns(ctx context.Context, platform string) (int64, error)
}

// detailTarget 상세를 받을 캠페인
type detailTarget struct {
	ID   int
	Link string
}

// listPageFetcher 목록 API 한 페이지 (로그인 불필요). categoryID가 비면 전체 목록
type listPageFetcher func(ctx context.Context, categoryID string, page, limit int) ([]map[string]interface{}, error)

const (
	detailListLimit   = 100
	listProgressEvery = 10 // 목록 진행 로그 간격(쪽)
	// 상세 실패(차단·만료 제외) 허용치: 연속이면 사이트 이상, 누적이 많으면 응답 형식 변경 등으로 보고 멈춘다.
	// 목록을 받은 뒤 지워진 공고가 드문드문 있어도 끝까지 돈다.
	maxDetailErrorsInRow = 3
	maxDetailErrors      = 20
	listPageDelayMin     = time.Second // 목록은 로그인 없는 API라 짧게 (02:00 목록 수집은 0.1초)
	listPageDelayRange   = time.Second
)

// detailPlan 실행 시간 계획
type detailPlan struct {
	StartDelay time.Duration // 시작 전 대기
	Deadline   time.Time     // 이 시각이 지나면 더 요청하지 않음
}

// planDetailRun 마감 시각 안이면(새벽 정기 실행) 무작위로 늦게 시작해 마감-여유 전까지,
// 마감 시각이 지났으면(낮 수동 실행) 바로 시작해 DetailManualRun 동안만 돈다.
func planDetailRun(now time.Time, loc *time.Location, windowEnd string, margin, jitterMax, manual time.Duration, rnd *rand.Rand) (detailPlan, error) {
	end, err := time.ParseInLocation("15:04", windowEnd, loc)
	if err != nil {
		return detailPlan{}, fmt.Errorf("REVIEWNOTE_DETAIL_WINDOW_END 형식 오류(%q): %w", windowEnd, err)
	}
	local := now.In(loc)
	todayEnd := time.Date(local.Year(), local.Month(), local.Day(), end.Hour(), end.Minute(), 0, 0, loc)
	deadline := todayEnd.Add(-margin)
	if !local.Before(deadline) {
		return detailPlan{Deadline: now.Add(manual)}, nil
	}
	var delay time.Duration
	if jitterMax > 0 {
		// 남은 시간의 절반은 넘기지 않음
		maxDelay := jitterMax
		if half := deadline.Sub(local) / 2; half < maxDelay {
			maxDelay = half
		}
		if maxDelay > 0 {
			delay = time.Duration(rnd.Int63n(int64(maxDelay)))
		}
	}
	return detailPlan{StartDelay: delay, Deadline: deadline}, nil
}

// nextGap 다음 요청까지 기다릴 시간: (남은 시간 / 남은 건수) × 0.6~1.2, 최소 minDelay
func nextGap(remaining time.Duration, left int, minDelay time.Duration, rnd *rand.Rand) time.Duration {
	if left < 1 {
		left = 1
	}
	base := remaining / time.Duration(left)
	gap := time.Duration(float64(base) * (0.6 + 0.6*rnd.Float64()))
	// 마지막 몇 건이 남은 시간보다 긴 간격을 뽑아 건너뛰어지지 않도록
	if longest := remaining * 9 / 10; gap > longest {
		gap = longest
	}
	if gap < minDelay {
		gap = minDelay + time.Duration(rnd.Int63n(int64(minDelay/2)+1))
	}
	return gap
}

// pickTargets 보관 값이 없는 것 먼저, 그다음 오래된 순. refresh 안에 받은 것은 제외, 최대 max 건.
func pickTargets(all []detailTarget, stored map[string]models.StayDetail, now time.Time, refresh time.Duration, max int) (targets []detailTarget, fresh int) {
	type cand struct {
		t       detailTarget
		fetched time.Time // 0이면 없음
	}
	var cands []cand
	for _, t := range all {
		d, ok := stored[t.Link]
		switch {
		case !ok:
			cands = append(cands, cand{t: t})
		case now.Sub(d.FetchedAt) >= refresh:
			cands = append(cands, cand{t: t, fetched: d.FetchedAt})
		default:
			fresh++
		}
	}
	sort.SliceStable(cands, func(i, j int) bool { return cands[i].fetched.Before(cands[j].fetched) })
	for _, c := range cands {
		if max > 0 && len(targets) >= max {
			break
		}
		targets = append(targets, c.t)
	}
	return targets, fresh
}

// listDetailTargets 대상 카테고리의 목록(로그인 불필요)을 1~2초 간격으로 넘기며 모집 중 캠페인을 모두 고른다.
// 필터 없는 목록은 앞의 1,600건만 주어 대부분이 빠지므로(2026-11-28: 여행 400건 중 41건) 카테고리로 걸러 받는다.
func (s *Scraper) listDetailTargets(ctx context.Context) ([]detailTarget, int, error) {
	log := logger.GetLogger("scraper.reviewnote.detail")
	cfg := s.Config.Reviewnote
	maxPages := s.Config.Scrape.MaxPages
	if maxPages <= 0 || maxPages > listPageCap {
		maxPages = listPageCap
	}
	categoryIDs := cfg.DetailCategoryIDs
	if len(categoryIDs) == 0 {
		categoryIDs = []string{""}
	}
	seen := map[int]bool{}
	var out []detailTarget
	total, requests := 0, 0
	for _, categoryID := range categoryIDs {
		for page := 0; page < maxPages; page++ {
			if requests > 0 && !s.sleep(ctx, listPageDelayMin+time.Duration(s.rnd.Int63n(int64(listPageDelayRange)))) {
				return nil, total, ctx.Err()
			}
			requests++
			items, err := s.listPage(ctx, categoryID, page, detailListLimit)
			if err != nil {
				return nil, total, fmt.Errorf("목록 %d쪽: %w", page, err)
			}
			if len(items) == 0 {
				break
			}
			total += len(items)
			for _, raw := range items {
				id, _ := raw["id"].(int)
				status, _ := raw["status"].(string)
				category, _ := raw["categoryTitle"].(string)
				if id == 0 || seen[id] || status != "SELECT" || !contains(cfg.DetailCategories, category) {
					continue
				}
				seen[id] = true
				out = append(out, detailTarget{ID: id, Link: fmt.Sprintf("https://www.reviewnote.co.kr/campaigns/%d", id)})
			}
			if (page+1)%listProgressEvery == 0 {
				log.Infof("목록 %d쪽까지 %d건 확인, 대상 %d건", page+1, total, len(out))
			}
			if page == maxPages-1 {
				log.Warnf("목록이 상한(%d쪽)까지 참, 뒤의 공고는 빠졌을 수 있음 (categoryId=%s)", maxPages, categoryID)
			}
		}
	}
	log.Infof("목록 %d건 중 대상(%v, 모집 중) %d건", total, cfg.DetailCategories, len(out))
	return out, total, nil
}

// RunDetail reviewnote-detail 명령. 세션 만료·차단 신호는 실패가 아니라 지표·알림으로 알린다.
// 목록을 못 받거나 DB에 못 쓰면 실패(종료 코드 1, Job 실패 메일).
func (s *Scraper) RunDetail(ctx context.Context) error {
	log := logger.GetLogger("scraper.reviewnote.detail")
	cfg := s.Config.Reviewnote

	stats := runstats.DetailStats{SessionOK: cfg.Session != "", SessionExpiresAt: cfg.SessionExpiresAt}
	// 만료 3일 전 메일이 반드시 가도록, 세션 상태·만료 시각을 가장 먼저 push (이후 단계가 실패해도 남음)
	runstats.SetDetail(stats)
	if err := runstats.PushDetailSession(); err != nil {
		log.Warnf("세션 상태 push 실패: %v", err)
	}
	if !stats.SessionOK {
		log.Error("REVIEWNOTE_SESSION 이 없습니다. 세션 쿠키를 등록해야 상세를 받을 수 있습니다")
		return nil
	}
	if s.details == nil {
		return errors.New("DB 연결 없음")
	}

	plan, err := planDetailRun(time.Now(), s.Config.Batch.Location(), cfg.DetailWindowEnd,
		cfg.DetailEndMargin, cfg.DetailStartJitter, cfg.DetailManualRun, s.rnd)
	if err != nil {
		return err
	}
	log.Infof("시작 전 %s 대기, %s 까지 수집", plan.StartDelay.Round(time.Second), plan.Deadline.Format(time.RFC3339))
	if !s.sleep(ctx, plan.StartDelay) {
		return ctx.Err()
	}

	all, listed, err := s.listDetailTargets(ctx)
	if err != nil {
		return err
	}
	runstats.SetItems(runstats.StageScraped, listed)
	runstats.SetItems(runstats.StageParsed, len(all))
	stats.Targets = int64(len(all))

	links := make([]string, len(all))
	for i, t := range all {
		links[i] = t.Link
	}
	stored, err := s.details.LoadStayDetails(ctx, platformName, links)
	if err != nil {
		return err
	}
	refresh := time.Duration(cfg.DetailRefreshDays) * 24 * time.Hour
	targets, fresh := pickTargets(all, stored, time.Now(), refresh, cfg.DetailMaxFetch)
	stats.Reused = int64(fresh)
	limit := "상한 없음"
	if cfg.DetailMaxFetch > 0 {
		limit = fmt.Sprintf("하룻밤 최대 %d", cfg.DetailMaxFetch)
	}
	log.Infof("대상 %d건: 최근 받은 것 %d건 제외, 이번에 받을 것 %d건 (%s)", len(all), fresh, len(targets), limit)

	stopReason := ""
	errorsInRow := 0
	for i, t := range targets {
		remaining := time.Until(plan.Deadline)
		if remaining <= 0 {
			stopReason = "마감 시각"
			break
		}
		gap := nextGap(remaining, len(targets)-i, cfg.DetailMinDelay, s.rnd)
		if time.Now().Add(gap).After(plan.Deadline) {
			stopReason = "마감 시각"
			break
		}
		if !s.sleep(ctx, gap) {
			stopReason = "종료 요청"
			break
		}
		d, err := s.fetchDetail(ctx, t.ID)
		if errors.Is(err, ErrSessionExpired) {
			stats.SessionOK = false
			stopReason = "세션 만료(401)"
			break
		}
		if errors.Is(err, ErrBlocked) {
			stats.Blocked = true
			stopReason = err.Error()
			break
		}
		if err != nil {
			stats.Errors++
			errorsInRow++
			log.Warnf("상세 실패: %v", err)
			if errorsInRow >= maxDetailErrorsInRow || stats.Errors >= maxDetailErrors {
				stopReason = fmt.Sprintf("상세 실패 연속 %d회, 누적 %d회", errorsInRow, stats.Errors)
				break
			}
			continue
		}
		errorsInRow = 0
		if err := s.details.SaveStayDetail(ctx, platformName, t.Link, t.ID, d.toStayDetail(time.Now())); err != nil {
			return err
		}
		stats.Fetched++
		if stats.Fetched%10 == 0 {
			log.Infof("상세 %d/%d건", stats.Fetched, len(targets))
		}
	}
	if stopReason != "" {
		log.Warnf("상세 수집을 멈춤: %s (받은 것 %d/%d건, 나머지는 다음 실행)", stopReason, stats.Fetched, len(targets))
	}

	synced, err := s.details.SyncStayDetailsToCampaigns(ctx, platformName)
	if err != nil {
		return err
	}
	runstats.SetItems(runstats.StageSaved, int(stats.Fetched))
	runstats.SetItems(runstats.StageUpdated, int(synced))

	after, err := s.details.LoadStayDetails(ctx, platformName, links)
	if err == nil {
		for _, l := range links {
			d, ok := after[l]
			if !ok {
				stats.Missing++
			} else if d.PossibleDays != nil || d.ImpossibleDays != nil {
				stats.WithDays++
			}
		}
	}
	log.Infof("상세 수집 끝: 대상 %d, 최근값 %d, 새로 받음 %d, 실패 %d, 아직 없음 %d, 요일 있음 %d, 세션 정상 %t, 차단 신호 %t, campaign 반영 %d",
		stats.Targets, stats.Reused, stats.Fetched, stats.Errors, stats.Missing, stats.WithDays, stats.SessionOK, stats.Blocked, synced)
	runstats.SetDetail(stats)
	return nil
}
