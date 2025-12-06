package logger

import (
	"os"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

var (
	// Log 전역 로거 인스턴스
	Log *zap.Logger
	// Sugar 편의 메서드가 포함된 로거
	Sugar *zap.SugaredLogger
)

// Init 로거 초기화
func Init() error {
	// 인코더 설정
	encoderConfig := zapcore.EncoderConfig{
		TimeKey:        "time",
		LevelKey:       "level",
		NameKey:        "logger",
		CallerKey:      "caller",
		MessageKey:     "msg",
		StacktraceKey:  "stacktrace",
		LineEnding:     zapcore.DefaultLineEnding,
		EncodeLevel:    zapcore.CapitalLevelEncoder,
		EncodeTime:     zapcore.ISO8601TimeEncoder,
		EncodeDuration: zapcore.SecondsDurationEncoder,
		EncodeCaller:   zapcore.ShortCallerEncoder,
	}

	// 콘솔 출력용 코어
	consoleEncoder := zapcore.NewConsoleEncoder(encoderConfig)
	consoleCore := zapcore.NewCore(
		consoleEncoder,
		zapcore.AddSync(os.Stdout),
		zapcore.InfoLevel,
	)

	// 로거 생성
	Log = zap.New(consoleCore, zap.AddCaller(), zap.AddStacktrace(zapcore.ErrorLevel))
	Sugar = Log.Sugar()

	return nil
}

// GetLogger 이름이 지정된 로거 반환
func GetLogger(name string) *zap.SugaredLogger {
	if Log == nil {
		_ = Init()
	}
	return Log.Named(name).Sugar()
}

// Sync 로거 버퍼 플러시
func Sync() {
	if Log != nil {
		_ = Log.Sync()
	}
}
