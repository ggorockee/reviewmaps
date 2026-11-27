# 리뷰맵 관리자 화면

Nuxt 4 + @nuxt/ui 정적 SPA. 빌드 결과를 nginx(포트 8080, `/healthz`)로 서빙하고, 데이터는 `server/`의 `/admin/v1` API만 사용합니다. 이전 Django 관리자는 `admin-django/`에 보관(전환 후 30일)합니다. 운영 기준(계정·배포·되돌리기·모니터링·카테고리 매핑)은 `claudedocs/admin-operations.md`, 계획·결정은 `claudedocs/planning/2026-11-admin-go-migration.md`.

## 로컬 개발 (운영 DB 없이)

| 순서 | 명령 | 설명 |
|------|------|------|
| 1 | `cd server && go run ./cmd/admindev` | 메모리 SQLite + 예시 데이터로 `/admin/v1`만 띄움 (:3000) |
| 2 | `cd admin && npm install && npm run dev -- --port 3001` | 화면 (:3001), "개발용 로그인" 버튼으로 로그인 |

운영 API로 확인할 때는 `kubectl -n reviewmaps port-forward deploy/reviewmaps-server 3000:3000` 후 같은 방법으로 화면을 띄웁니다(서버의 `ADMIN_ORIGIN`이 `http://localhost:3001`을 허용해야 함).

## 검사

| 명령 | 내용 |
|------|------|
| `npm run lint` | ESLint |
| `npm run typecheck` | vue-tsc |
| `npm test` | Vitest (`test/`) |
| `npm run generate` | 정적 빌드 |

## 화면

| 메뉴 | 할 수 있는 일 |
|------|--------------|
| 대시보드 | 사용자·키워드·캠페인 요약, 출처별 카테고리 없는 캠페인 비율, 최근 변경 |
| 사용자 | 검색, 상세(SNS·키워드·기기, 토큰은 앞 8자만), 비활성, 삭제(이메일 재입력, 앱 탈퇴와 같은 처리) |
| 키워드·키워드 알림 | 켜기/끄기, 삭제, 오래된 알림 일괄 정리(건수 확인 후 soft delete) |
| 캠페인 | 검색·필터, 프로모션 단계, 앱에서 숨기기/복구 (내용 수정은 다음 수집 때 덮어써져 제공 안 함) |
| 카테고리 | 추가·이름 변경·순서·삭제(사용 중이면 불가) |
| 카테고리 매핑 | 미매핑 원본을 사용량 순으로, 추천을 미리 선택, 신뢰도 80% 이상 일괄 매핑. 다음 수집부터 반영 |
| 설정·앱 버전 | 키워드 개수·알림 보관 일수 변경, 앱 버전·광고·요청 제한은 읽기 전용(Remote Config로 이전) |
| 변경 기록 | 관리자 변경 전부 (누가·언제·전후 값) |

## 배포

main 머지 시 `ci-admin.yml`이 `ggorockee/reviewmaps-admin:<날짜>-<커밋>` 이미지를 올립니다. infra 태그 자동 갱신은 저장소 변수 `ADMIN_AUTO_DEPLOY=true`일 때만 동작합니다 (2026-11-27 전환 때 켬). 되돌리기는 infra의 admin 값과 이미지 태그를 Django `20261110-7ed5b97`로 되돌리는 PR입니다.
