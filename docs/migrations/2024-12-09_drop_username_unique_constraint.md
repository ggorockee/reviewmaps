# Database Migration: Username Unique Constraint 제거

**날짜**: 2024-12-09
**타입**: Schema Change
**우선순위**: High

## 개요

SNS 로그인(Kakao, Google, Apple) 지원을 위해 `users` 테이블의 `username` 필드에서 UNIQUE 제약조건을 제거합니다.

## 배경

각 SNS 제공자(Kakao, Google, Apple)가 동일한 username을 사용할 수 있어야 하므로, username 필드의 unique 제약조건이 문제가 됩니다.

예시:
- Kakao 로그인: username = "user123"
- Google 로그인: username = "user123"
- Apple 로그인: username = "user123"

위 경우 모두 허용되어야 하지만, unique 제약조건으로 인해 두 번째 사용자부터 에러가 발생합니다.

## 변경 사항

### 코드 변경 (PR #198)
- GORM User 모델에서 `uniqueIndex:users_username_key` 제거
- Django Admin User 모델에서 `unique=True` 제거

### 데이터베이스 변경 (수동 실행)

**실행할 SQL:**
```sql
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_username_key;
```

**실행 결과 확인:**
```sql
\d users
```

**변경 전:**
```
Indexes:
    "users_pkey" PRIMARY KEY, btree (id)
    "users_username_key" UNIQUE CONSTRAINT, btree (username)
```

**변경 후:**
```
Indexes:
    "users_pkey" PRIMARY KEY, btree (id)
    "idx_email_login_method" btree (email, login_method)
    "users_email_login_method_33736053_uniq" UNIQUE CONSTRAINT, btree (email, login_method)
```

## 실행 환경

| 환경 | 실행 일시 | 실행자 | 상태 |
|------|----------|--------|------|
| Production | 2024-12-09 21:30 KST | Manual | ✅ 완료 |

## 영향 범위

**긍정적 영향:**
- SNS 로그인 사용자들이 동일한 username을 사용할 수 있음
- GORM AutoMigration 경고 메시지 제거
- 사용자 등록 시 username 충돌 에러 해결

**부정적 영향:**
- Username으로는 사용자를 유니크하게 식별할 수 없음 (기존에도 의도된 동작)
- 사용자 식별은 `(email, login_method)` 조합으로 유지

## 롤백 방법

필요 시 다음 SQL로 제약조건을 다시 추가할 수 있습니다:

```sql
ALTER TABLE users ADD CONSTRAINT users_username_key UNIQUE (username);
```

**주의:** 이미 중복된 username이 있을 경우 롤백이 실패합니다.

## 검증

### 변경 전 경고 로그
```
AutoMigrate warning (non-fatal): ERROR: constraint "uni_users_username" of relation "users" does not exist (SQLSTATE 42704)
```

### 변경 후
- ✅ 경고 메시지 사라짐
- ✅ 서버 정상 기동
- ✅ API 정상 동작

## 관련 PR

- #198: fix(auth): SNS 로그인 지원을 위한 username unique 제약조건 제거

## 참고 자료

- 테이블 스키마: `\d users`
- GORM 모델: `server/internal/models/user.go`
- Django 모델: `admin/users/models.py`
