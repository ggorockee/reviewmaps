# Go Fiber 마이그레이션 작업 계획

**참조 문서**: GO_FIBER_MIGRATION_PLAN.md

---

## Phase 1: 기반 인프라 구축

| 상태 | 작업 | 설명 |
|-----|-----|-----|
| [x] | 1.1 | Go 프로젝트 초기화 (go mod init) |
| [x] | 1.2 | Fiber + GORM 기본 설정 |
| [x] | 1.3 | Django Admin 프로젝트 분리 (admin/) |
| [x] | 1.4 | unfold 테마 적용 |
| [x] | 1.5 | Docker Compose 기본 구성 (k8s 사용으로 스킵) |
| [x] | 1.6 | SigNoz 연동 (OpenTelemetry 코드 추가) |

---

## Phase 2: 데이터 모델 마이그레이션

| 상태 | 작업 | 설명 |
|-----|-----|-----|
| [x] | 2.1 | GORM BaseModel 정의 |
| [x] | 2.2 | User 모델 마이그레이션 |
| [x] | 2.3 | SocialAccount 모델 |
| [x] | 2.4 | Category/Campaign 모델 |
| [x] | 2.5 | Keyword Alert 모델들 |
| [x] | 2.6 | AppConfig 모델들 |
| [x] | 2.7 | Django Admin 모델 연동 (managed=False) |
| [x] | 2.8 | 인덱스 및 제약조건 검증 |

---

## Phase 3: API 마이그레이션

| 상태 | 작업 | 설명 |
|-----|-----|-----|
| [x] | 3.1 | JWT 인증 미들웨어 |
| [x] | 3.2 | 회원가입/로그인 API |
| [x] | 3.3 | SNS 로그인 API (Kakao, Google, Apple) |
| [x] | 3.4 | Campaign 목록/상세 API |
| [x] | 3.5 | Category API |
| [x] | 3.6 | Keyword Alerts API |
| [x] | 3.7 | App Config API |
| [x] | 3.8 | Swagger 문서 생성 |

---

## Phase 4: 서비스 마이그레이션

| 상태 | 작업 | 설명 |
|-----|-----|-----|
| [x] | 4.1 | FCM 푸시 서비스 (Go routine 병렬 발송) |
| [x] | 4.2 | 키워드 매칭 서비스 (Go routine 병렬 매칭) |
| [x] | 4.3 | 이메일 발송 서비스 (Go routine 비동기) - 기존 코드 활용 |
| [x] | 4.4 | SNS 토큰 검증 서비스 |

---

## Phase 5: 검증 및 배포

| 상태 | 작업 | 설명 |
|-----|-----|-----|
| [ ] | 5.1 | API 호환성 테스트 (모바일 앱) |
| [ ] | 5.2 | 성능 테스트 (목표: < 500ms) |
| [ ] | 5.3 | SigNoz 대시보드 구성 |
| [ ] | 5.4 | CI/CD 파이프라인 구축 |
| [ ] | 5.5 | 프로덕션 배포 |

---

## 완료 기준 체크리스트

| 상태 | 항목 |
|-----|-----|
| [ ] | 모든 API 엔드포인트 동일 동작 확인 |
| [ ] | Swagger 문서 자동 생성 확인 |
| [ ] | 모든 API 응답에 관계 데이터 포함 확인 |
| [ ] | GORM AutoMigration으로 테이블 생성 확인 |
| [ ] | Django Admin에서 CRUD 정상 동작 확인 |
| [ ] | Go routine 병렬 처리 동작 확인 |
| [ ] | 단위 테스트 커버리지 > 80% |
| [ ] | 통합 테스트 전체 통과 |
| [ ] | API 응답 시간 < 500ms |
| [ ] | SigNoz 메트릭/트레이스 수집 확인 |
| [ ] | 모바일 앱 연동 테스트 통과 |
| [ ] | 프로덕션 배포 완료 |

---

## 진행 현황

| Phase | 전체 | 완료 | 진행률 |
|-------|-----|-----|-------|
| Phase 1 | 6 | 6 | 100% |
| Phase 2 | 8 | 8 | 100% |
| Phase 3 | 8 | 8 | 100% |
| Phase 4 | 4 | 4 | 100% |
| Phase 5 | 5 | 0 | 0% |
| **총계** | **31** | **26** | **84%** |
