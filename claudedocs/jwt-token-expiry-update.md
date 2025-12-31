# JWT 토큰 만료 시간 업데이트

## 변경 사항

**문제**: Access Token이 15분마다 만료되어 사용자가 자주 재로그인해야 함

**해결**: Access Token 만료 시간을 30일로 연장

| 항목 | 변경 전 | 변경 후 |
|------|---------|---------|
| Access Token 만료 | 15분 | 30일 (43200분) |
| Refresh Token 만료 | 7일 | 30일 |

## 서버 환경변수 업데이트

### Fly.io 배포인 경우
```bash
fly secrets set JWT_ACCESS_TOKEN_EXPIRE_MINUTES=43200
fly secrets set JWT_REFRESH_TOKEN_EXPIRE_DAYS=30
```

### .env 파일 직접 수정
```env
JWT_ACCESS_TOKEN_EXPIRE_MINUTES=43200  # 30일
JWT_REFRESH_TOKEN_EXPIRE_DAYS=30
```

### 환경변수 확인
```bash
# Fly.io
fly secrets list

# 로컬
grep JWT .env
```

## 배포 후 확인

### 1. 서버 재시작 확인
```bash
fly status
```

### 2. 새로 로그인 후 토큰 만료 시간 확인
모바일 앱에서 로그인 후 JWT 페이로드를 확인하면 만료 시간이 30일 후로 설정되어 있어야 합니다.

## 영향

- **기존 사용자**: 기존 토큰은 여전히 15분 만료 (다음 로그인 시 30일 토큰 발급)
- **신규 로그인**: 30일 동안 자동 로그인 유지
- **보안**: Refresh Token도 30일로 연장하여 일관성 유지

## 참고

- 변경 파일: `server/.env.example`
- 관련 코드: `server/pkg/auth/jwt.go`, `server/internal/config/config.go`
