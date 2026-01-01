# Apple 로그인 에러 수정 및 배포 가이드

## 문제점

### App Store 리뷰 거절 사유
```
Guideline 2.1 - Performance - App Completeness
Bug description: The app displayed an error message when attempted to log in using Sign in with Apple.

Review Device: iPad Air 11-inch (M3), iPadOS 26.2
Version reviewed: 2.0.9
```

### 에러 메시지
```
apple 토큰 감옥에 실패하였습니다: failed to parse token: token is malformed: token contains an invalid number of segments
```

## 근본 원인 분석

### 서버 측 문제
`/auth/apple` 엔드포인트가 잘못된 요청 구조체 사용:

| 항목 | 기대값 | 실제값 |
|------|--------|--------|
| 구조체 | `AppleLoginRequest` | `SNSLoginRequest` |
| 필드명 | `identity_token` | `access_token` |
| 결과 | JWT 토큰 파싱 | 빈 문자열 파싱 → 에러 |

### 코드 흐름
```
Flutter App (AppleLoginService)
  → credential.identityToken 생성
  → AuthService.appleLogin(identityToken, authorizationCode)
  → POST /v1/auth/apple
      {
        "identity_token": "eyJhbGc...",
        "authorization_code": "c1234..."
      }
  → Server Handler (auth.go:254)
      ❌ SNSLoginRequest로 파싱 (access_token 필드 기대)
      → req.AccessToken = "" (빈 문자열)
  → apple.go:VerifyAppleToken(ctx, "", clientID)
  → jwt.ParseUnverified("")
      ❌ "token is malformed: invalid number of segments"
```

## 수정 사항

### 파일: `server/internal/handlers/auth.go`

| 항목 | 변경 전 | 변경 후 |
|------|---------|---------|
| 구조체 타입 | `SNSLoginRequest` | `AppleLoginRequest` |
| 필드 접근 | `req.AccessToken` | `req.IdentityToken` |
| Swagger 주석 | `SNSLoginRequest` | `AppleLoginRequest` |

### 커밋 정보
- **Commit**: 831d76f
- **Branch**: fix/apple-login-identity-token
- **PR**: #248 (Merged to main)

## 배포 체크리스트

### 서버 배포

| 작업 | 상태 | 비고 |
|------|------|------|
| 코드 머지 | ✅ | PR #248 main에 squash merge 완료 |
| 서버 빌드 | ✅ | `make build` 성공 |
| 서버 배포 | ⏳ | 프로덕션 서버 배포 필요 |
| 헬스체크 | ⏳ | `/v1/healthz` 확인 |

### 서버 배포 명령어

#### Fly.io 배포 (가정)
```bash
cd server
fly deploy
fly status
```

#### 배포 후 확인
```bash
curl -X GET https://api.reviewmaps.com/v1/healthz
```

### 모바일 앱 테스트

| 작업 | 상태 | 비고 |
|------|------|------|
| 서버 배포 완료 대기 | ⏳ | 서버 배포 후 진행 |
| iPad 실기기 테스트 | ⏳ | iPad Air 11-inch (M3) |
| Apple 로그인 실행 | ⏳ | Sign in with Apple 플로우 |
| 로그인 성공 확인 | ⏳ | 토큰 발급 및 저장 확인 |
| 사용자 정보 로드 | ⏳ | /auth/me API 호출 성공 |

## 테스트 시나리오

### 1. iPad에서 Apple 로그인
```
1. ReviewMaps 앱 실행
2. 로그인 화면에서 "Apple로 시작하기" 탭
3. Apple ID 인증 완료
4. ✅ 로그인 성공 및 홈 화면 전환 확인
5. ✅ 사용자 정보 정상 로드 확인
```

### 2. 에러 로그 확인
서버 로그에서 다음 메시지가 없어야 함:
```
[AppleLogin] Error: apple 토큰 검증에 실패했습니다: failed to parse token
```

정상 로그:
```
[AppleLogin] Token (first 20 chars): eyJhbGciOiJSUzI1NiIsI...
```

## 예상 결과

### 성공 시나리오
1. Apple 로그인 JWT 토큰이 올바르게 파싱됨
2. 사용자 정보 (sub, email) 추출 성공
3. 토큰 발급 및 로그인 완료
4. App Store 리뷰 통과

### 실패 시나리오 (디버깅)
만약 여전히 에러 발생 시 추가 확인 사항:

| 확인 항목 | 방법 |
|-----------|------|
| 서버 배포 상태 | `fly status`, 헬스체크 |
| 환경변수 | `APPLE_CLIENT_ID` 설정 확인 |
| Apple Public Keys | `https://appleid.apple.com/auth/keys` 접근 가능 확인 |
| 네트워크 | 서버 ↔ Apple ID 서버 통신 |

## 관련 파일

### 서버
- `server/internal/handlers/auth.go` - Apple 로그인 엔드포인트
- `server/internal/services/auth.go` - Apple 로그인 비즈니스 로직
- `server/pkg/sns/apple.go` - Apple JWT 검증 로직

### 모바일
- `mobile/lib/services/sns/apple_login_service.dart` - Apple SDK 통합
- `mobile/lib/services/auth_service.dart` - 서버 API 호출
- `mobile/lib/screens/auth/login_screen.dart` - 로그인 UI

## 다음 단계

1. **서버 배포 확인** (우선순위: 🔴 긴급)
   - 프로덕션 서버에 수정사항 배포
   - 헬스체크 및 로그 모니터링

2. **실기기 테스트** (우선순위: 🔴 긴급)
   - iPad Air 11-inch (M3)에서 Apple 로그인 테스트
   - 로그인 성공 여부 확인

3. **App Store 재제출**
   - 테스트 통과 후 TestFlight 배포
   - App Store Review 재제출

## 참고 자료

- App Store 리뷰 거절 이메일: 2025-12-31
- Submission ID: d32a4134-ed96-489f-9528-eaf27644ea01
- PR: https://github.com/ggorockee/reviewmaps/pull/248
