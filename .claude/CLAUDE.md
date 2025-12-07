# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ReviewMaps는 캠페인/리뷰어 정보 제공 서비스로, 모노레포 구조의 풀스택 프로젝트입니다.

**서비스 구성:**
- 백엔드 API (Go Fiber + GORM)
- 어드민 패널 (Django Admin + Unfold)
- 모바일 앱 (Flutter - iOS/Android)
- 웹 프론트엔드 (Next.js)
- 데이터 수집 (Go Scraper)

## Repository Structure

| Directory | Tech Stack | Description |
|-----------|------------|-------------|
| `server/` | Go 1.23 + Fiber + GORM | REST API 서버 (Production) |
| `admin/` | Django 5.2 + Unfold | 어드민 패널 (managed=False) |
| `go-scraper/` | Go + Colly | 캠페인 데이터 수집기 |
| `mobile/` | Flutter | iOS/Android 모바일 앱 |
| `web/` | Next.js 15 + React 19 | 웹 프론트엔드 |
| `scrape/` | Python (비활성화) | 레거시 스크레이퍼 (사용 안 함) |

## Development Commands

### Server (Go Fiber)

| 명령어 | 설명 |
|--------|------|
| `cd server && make run` | 개발 서버 실행 |
| `cd server && make dev` | Hot reload (air) |
| `cd server && make test` | 테스트 실행 |
| `cd server && make swagger` | Swagger 문서 생성 |
| `cd server && make build` | 바이너리 빌드 |

### Admin (Django)

| 명령어 | 설명 |
|--------|------|
| `cd admin && uv run python manage.py runserver` | 개발 서버 |
| `cd admin && uv run ruff format --check .` | 포맷 검사 |

### Go Scraper

| 명령어 | 설명 |
|--------|------|
| `cd go-scraper && go run cmd/scraper/main.go reviewnote` | 스크레이퍼 실행 |
| `cd go-scraper && go run cmd/scraper/main.go inflexer --keyword "키워드"` | 키워드 지정 |
| `cd go-scraper && go run cmd/scraper/main.go cleanup` | 만료 캠페인 정리 |
| `cd go-scraper && go run cmd/scraper/main.go dedupe` | 중복 캠페인 정리 |

### Mobile (Flutter)

| 명령어 | 설명 |
|--------|------|
| `cd mobile && flutter pub get` | 의존성 설치 |
| `cd mobile && flutter run` | 디버그 실행 |
| `cd mobile && flutter analyze` | 정적 분석 |
| `cd mobile && flutter test` | 테스트 실행 |

### Web (Next.js)

| 명령어 | 설명 |
|--------|------|
| `cd web && npm install` | 의존성 설치 |
| `cd web && npm run dev` | 개발 서버 (Turbopack) |
| `cd web && npm run build` | 프로덕션 빌드 |

## Architecture Overview

### Data Flow

| 단계 | 흐름 |
|------|------|
| 1 | Go Scraper → PostgreSQL (캠페인 수집) |
| 2 | Go Fiber API ← PostgreSQL (데이터 조회) |
| 3 | Mobile/Web → Go Fiber API (API 호출) |
| 4 | Go Fiber API → Firebase FCM (푸시 알림) |
| 5 | Django Admin → PostgreSQL (데이터 관리) |

### Server API Endpoints

| 경로 | 설명 |
|------|------|
| `/v1/auth/*` | 인증 (회원가입, 로그인, SNS 로그인) |
| `/v1/users/me/*` | 사용자 정보 |
| `/v1/campaigns/*` | 캠페인 목록/상세 |
| `/v1/categories/*` | 카테고리 |
| `/v1/keyword-alerts/*` | 키워드 알람 |
| `/v1/app-config/*` | 앱 설정, 버전 체크 |
| `/v1/internal/*` | 내부 API (Scraper 전용) |
| `/v1/docs/*` | Swagger UI |
| `/v1/healthz` | 헬스체크 |

### Key Integrations

| 서비스 | 용도 |
|--------|------|
| Firebase | 푸시 알림(FCM) |
| SigNoz | 분산 추적, 메트릭, 로그 (OpenTelemetry) |
| Naver Map SDK | 지도 표시 (Mobile) |
| AdMob | 광고 (Mobile) |
| SNS Login | Kakao, Google, Apple |

## Core Development Principles

### Server (Go Fiber)
- **GORM AutoMigration**: 스키마 관리 주체
- **Swagger 필수**: 모든 API에 swaggo 문서화
- **관계 데이터 Preload**: API 응답 시 연관 데이터 포함
- **Go routine 활용**: 병렬 처리 가능한 작업에 goroutine 사용
- **OpenTelemetry**: SigNoz 연동 분산 추적

### Admin (Django)
- **managed=False**: GORM이 생성한 테이블 직접 참조
- **Unfold 테마**: 모던 UI 어드민 패널
- **Migration 없음**: Django migration 비활성화

### Go Scraper
- **플러그인 구조**: `internal/scraper/` 폴더에 스크레이퍼 추가
- **Server API 호출**: 키워드 매칭 알림은 Server API 통해 처리
- **Telemetry 통합**: OpenTelemetry 메트릭 수집

### Mobile (Flutter)
- **상태 관리**: Riverpod 사용
- **반응형 UI**: ScreenUtil (375x812 기준)
- **Firebase 초기화 실패 허용**: 앱 실행 계속

## Environment Setup

### Server (server/.env)

| 변수 | 설명 |
|------|------|
| `DATABASE_URL` | PostgreSQL 연결 문자열 |
| `JWT_SECRET_KEY` | JWT 서명 키 |
| `FIREBASE_CREDENTIALS_PATH` | FCM 서비스 계정 경로 |
| `KAKAO_REST_API_KEY` | Kakao REST API 키 |
| `GOOGLE_CLIENT_ID_*` | Google 클라이언트 ID (iOS/Android/Web) |
| `APPLE_*` | Apple 로그인 설정 |
| `SIGNOZ_ENDPOINT` | SigNoz OTLP 엔드포인트 |

### Admin (admin/.env)

| 변수 | 설명 |
|------|------|
| `DATABASE_URL` | PostgreSQL 연결 문자열 (동일 DB) |
| `SECRET_KEY` | Django 시크릿 키 |
| `DEBUG` | 디버그 모드 |

### Go Scraper (go-scraper/.env)

| 변수 | 설명 |
|------|------|
| `DB_*` | PostgreSQL 연결 정보 |
| `SERVER_API_URL` | Server API 엔드포인트 |
| `SERVER_API_KEY` | Server API 인증 키 |

### Mobile (mobile/.env)

| 변수 | 설명 |
|------|------|
| `REVIEWMAPS_BASE_URL` | API 엔드포인트 |
| `REVIEWMAPS_X_API_KEY` | API 인증 키 |
| `NAVER_*` | 네이버 지도/검색 API 키 |
| `ADMOB_*` | 광고 단위 ID |

## Testing

| 대상 | 명령어 |
|------|--------|
| Server | `cd server && make test` |
| Server (커버리지) | `cd server && make test-cover` |
| Mobile | `cd mobile && flutter test` |

## Task Tracking Rules (작업 추적 규칙)

계획 문서의 작업 항목은 체크박스로 진행 상태를 추적합니다.

| 표기 | 상태 | 설명 |
|------|------|------|
| `[ ]` | 미완료 | 아직 시작하지 않은 작업 |
| `[x]` | 완료 | 완료된 작업 |

**적용 대상:**
- `docs/planning/` 내 모든 계획 문서
- 마이그레이션 체크리스트
- 구현 단계별 작업 목록

**규칙:**
- 작업 완료 시 즉시 `[ ]` → `[x]`로 업데이트
- 세션 종료 전 진행 상태 반드시 저장

## Git Branch & PR Rules

### 브랜치 정책
- **main 브랜치 보호**: main에 직접 push 금지, 반드시 PR을 통해 머지
- **feature 브랜치 사용**: 모든 작업은 feature 브랜치에서 진행

### PR 정책

| 항목 | 설정 |
|------|------|
| 머지 방식 | Squash and Merge (기본값) |
| PR 승인 | 개발자 요청 시 승인 |
| 브랜치 삭제 | 머지 완료 후 feature 브랜치 삭제 |

### 브랜치 네이밍 규칙

| 접두사 | 용도 | 예시 |
|--------|------|------|
| `feature/` | 새 기능 개발 | `feature/user-auth` |
| `fix/` | 버그 수정 | `fix/login-error` |
| `refactor/` | 코드 리팩토링 | `refactor/api-structure` |
| `docs/` | 문서 작업 | `docs/readme-update` |

### 에러 수정 자동화 규칙
- **에러 수정 완료 시**: 수정 후 자동으로 PR 생성 및 승인까지 진행
- **워크플로우**: 에러 분석 → 수정 → 커밋 → PR 생성 → Squash and Merge → 브랜치 삭제
- **적용 대상**: CI/CD 에러, 빌드 에러, 린트 에러 등 모든 에러 수정 작업

## Python Code Quality Rules

### Ruff 포맷 검사 (필수)
Python 파일 수정 후 커밋 전 반드시 실행:

| 디렉토리 | 명령어 |
|----------|--------|
| `admin/` | `cd admin && uv run ruff format --check .` |
| `scrape/` | `cd scrape && uv run ruff format --check .` |
| `server/` (Python) | `cd server && uv run ruff format --check .` |

**워크플로우:**
1. Python 코드 수정
2. `uv run ruff format --check .` 실행
3. 에러 발생 시 `uv run ruff format .` 로 자동 수정
4. 커밋 진행
