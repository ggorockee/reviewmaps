# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ReviewMaps는 캠페인/리뷰어 정보 제공 서비스로, 모노레포 구조의 풀스택 프로젝트입니다.

**서비스 구성:**
- 백엔드 API (Django + Django Ninja)
- 모바일 앱 (Flutter - iOS/Android)
- 웹 프론트엔드 (Next.js)
- 데이터 수집 (Python Scraper)

## Repository Structure

| Directory | Tech Stack | Description | CLAUDE.md |
|-----------|------------|-------------|-----------|
| `server/` | Django 5.2 + Django Ninja | 비동기 REST API 서버 | ✅ `server/.claude/CLAUDE.md` |
| `mobile/` | Flutter | iOS/Android 모바일 앱 | ✅ `mobile/.claude/CLAUDE.md` |
| `web/` | Next.js 15 + React 19 | 웹 프론트엔드 | - |
| `scrape/` | Python + SQLAlchemy | 캠페인 데이터 수집기 | - |

**Note:** 각 서브 프로젝트의 상세 개발 가이드는 해당 디렉토리의 CLAUDE.md 참조

## Development Commands

### Server (Django)
```bash
cd server
python manage.py runserver 0.0.0.0:8000   # 개발 서버
python manage.py test                      # 전체 테스트
pytest -v                                  # pytest 사용
```

### Mobile (Flutter)
```bash
cd mobile
flutter pub get          # 의존성 설치
flutter run              # 디버그 실행
flutter analyze          # 정적 분석
flutter test             # 테스트 실행
```

### Web (Next.js)
```bash
cd web
npm install              # 의존성 설치
npm run dev              # 개발 서버 (Turbopack)
npm run build            # 프로덕션 빌드
npm run lint             # ESLint 실행
```

### Scraper
```bash
cd scrape
pip install -r requirements.txt           # 의존성 설치
python main.py <scraper_name>             # 스크레이퍼 실행
python main.py <scraper_name> --keyword "검색어"  # 키워드 지정
```

## Architecture Overview

### Data Flow
```
[Scraper] → PostgreSQL ← [Server API] ← [Mobile App / Web]
                              ↓
                         Firebase (FCM 푸시)
```

### Server API Endpoints
- `/v1/auth/*` - 인증 (회원가입, 로그인, SNS 로그인)
- `/v1/users/me/*` - 사용자 정보
- `/v1/campaigns/*` - 캠페인 목록/상세
- `/v1/categories/*` - 카테고리
- `/v1/keyword-alerts/*` - 키워드 알람
- `/v1/app-config/*` - 앱 설정, 버전 체크

### Key Integrations
- **Firebase**: 푸시 알림(FCM), Analytics, Crashlytics, Remote Config
- **Naver Map SDK**: 지도 표시 (Mobile)
- **AdMob**: 광고 (Mobile)
- **SNS Login**: Kakao, Google, Apple

## Core Development Principles

### Server (Django)
- **비동기 우선**: 인증 제외 모든 API는 async 처리
- **TDD**: 테스트 코드 먼저 작성
- **사용자 모델**: email + login_method 조합으로 unique

### Mobile (Flutter)
- **상태 관리**: Riverpod 사용
- **반응형 UI**: ScreenUtil (375x812 기준)
- **Firebase 초기화 실패 허용**: 앱 실행 계속

### Scraper
- **플러그인 구조**: `scrapers/` 폴더에 BaseScraper 상속 클래스 추가
- **DB 직접 연결**: SQLAlchemy로 PostgreSQL 접근

## Environment Setup

### Required Environment Variables

**Server** (server/.env):
- `POSTGRES_*`: DB 연결 정보
- `SECRET_KEY`, `JWT_SECRET_KEY`: 보안 키
- `KAKAO_REST_API_KEY`, `GOOGLE_CLIENT_ID_*`, `APPLE_*`: SNS 로그인
- `FIREBASE_CREDENTIALS_PATH`: FCM 서비스 계정

**Mobile** (mobile/.env):
- `REVIEWMAPS_BASE_URL`, `REVIEWMAPS_X_API_KEY`: API 연결
- `NAVER_*`: 네이버 지도/검색 API 키
- `ADMOB_*`: 광고 단위 ID

**Scraper** (scrape/.env):
- DB 연결 정보

## Testing

```bash
# Server - 전체 테스트
cd server && python manage.py test

# Server - 특정 앱 테스트
python manage.py test campaigns

# Server - pytest
pytest keyword_alerts/tests/ -v

# Mobile - 테스트
cd mobile && flutter test
```

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
