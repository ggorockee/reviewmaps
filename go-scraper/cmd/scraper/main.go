package main

import (
	"context"
	"flag"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/ggorockee/reviewmaps/go-scraper/internal/config"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/db"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/logger"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/scraper/reviewnote"
	"github.com/ggorockee/reviewmaps/go-scraper/internal/telemetry"
)

func main() {
	// 로거 초기화
	if err := logger.Init(); err != nil {
		panic(err)
	}
	defer logger.Sync()

	log := logger.GetLogger("main")

	// 컨텍스트 설정 (시그널 핸들링)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Telemetry 초기화
	tel, err := telemetry.New(ctx)
	if err != nil {
		log.Warnf("Telemetry 초기화 실패 (계속 실행): %v", err)
	} else {
		defer func() {
			shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer shutdownCancel()
			if err := tel.Shutdown(shutdownCtx); err != nil {
				log.Warnf("Telemetry shutdown 실패: %v", err)
			}
		}()
		log.Info("Telemetry 초기화 완료")
	}

	// CLI 인자 파싱
	scraperName := flag.String("scraper", "", "실행할 스크레이퍼의 이름")
	keyword := flag.String("keyword", "", "검색할 특정 키워드 (선택)")
	flag.Parse()

	// positional argument도 지원
	if *scraperName == "" && flag.NArg() > 0 {
		*scraperName = flag.Arg(0)
	}

	if *scraperName == "" {
		log.Error("스크레이퍼 이름을 지정해주세요. 예: go run main.go mymilky")
		os.Exit(1)
	}

	// 설정 로드
	cfg, err := config.Load()
	if err != nil {
		log.Errorf("설정 로드 실패: %v", err)
		os.Exit(1)
	}

	// 데이터베이스 연결
	database, err := db.New(&cfg.DB)
	if err != nil {
		log.Errorf("데이터베이스 연결 실패: %v", err)
		os.Exit(1)
	}
	defer database.Close()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigChan
		log.Info("종료 시그널 수신, 정리 중...")
		cancel()
	}()

	// 키워드 설정
	var keywordPtr *string
	if *keyword != "" {
		keywordPtr = keyword
	}

	// 스크레이퍼 실행
	keywordStr := "전체"
	if keywordPtr != nil {
		keywordStr = *keywordPtr
	}

	log.Infof("========== 작업 시작: %s (키워드: %s) ==========", *scraperName, keywordStr)

	// 메트릭 기록 시작
	startTime := time.Now()
	if tel != nil {
		tel.IncrementScrapeTotal(ctx, *scraperName)
	}

	if err := runScraper(ctx, *scraperName, cfg, database, keywordPtr, tel); err != nil {
		log.Errorf("'%s' 실행 중 에러: %v", *scraperName, err)
		if tel != nil {
			tel.IncrementScrapeErrors(ctx, *scraperName)
		}
		os.Exit(1)
	}

	// Duration 메트릭 기록
	if tel != nil {
		tel.RecordScrapeDuration(ctx, time.Since(startTime), *scraperName)
	}

	log.Infof("========== 작업 종료: %s (키워드: %s) ==========", *scraperName, keywordStr)
}

// runScraper 스크레이퍼 실행
func runScraper(ctx context.Context, name string, cfg *config.Config, database *db.DB, keyword *string, tel *telemetry.Telemetry) error {
	log := logger.GetLogger("main")

	switch name {
	case "reviewnote":
		scraper := reviewnote.New(cfg, database, tel)
		return scraper.Run(ctx, keyword)
	default:
		log.Errorf("'%s' 스크레이퍼를 찾을 수 없습니다.", name)
		log.Info("사용 가능한 스크레이퍼: reviewnote")
		return nil
	}
}
