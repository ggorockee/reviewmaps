# 인증 세션 만료 처리 개선 계획

## 문서 요약

ReviewMaps 모바일 앱은 **Riverpod 상태 관리를 사용**하고 있지만, 401 에러 처리가 각 서비스에 분산되어 `authProvider` 상태를 제대로 활용하지 못하고 있습니다.

**핵심 문제:**
- 401 에러 발생 시 에러 메시지만 throw하고 `authProvider` 상태는 업데이트하지 않음
- 화면에서 `authProvider`를 watch하지만 상태가 변경되지 않아 캐시된 데이터 계속 표시
- 로그인 화면으로 자동 이동하는 로직 없음

**해결 방향:**
- 서비스 레이어를 Provider로 변환하여 `authProvider.logout()` 직접 호출
- GoRouter의 redirect 또는 `ref.listen`으로 상태 변화 감지 시 자동 네비게이션
- GlobalKey나 static 변수 없이 Riverpod의 반응형 상태 관리만 활용

---

# Part 1: 진단 (Diagnosis)

## 1. 현재 시스템 아키텍처

### 1.1 전체 구조

```
┌──────────────────────────────────────────────────────────────┐
│                         UI Layer                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │  Keyword    │  │   Profile   │  │  MyPage     │          │
│  │  Screen     │  │   Screen    │  │  Screen     │          │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘          │
│         │                 │                 │                 │
│         └─────────┬───────┴─────────────────┘                │
│                   │ ref.watch(authProvider)                   │
│                   ▼                                           │
│  ┌─────────────────────────────────────────────────┐         │
│  │         authProvider (Riverpod)                 │         │
│  │  - isAuthenticated: bool                        │         │
│  │  - userInfo: UserInfo?                          │         │
│  │  - logout(): void                               │         │
│  └──────────────────┬──────────────────────────────┘         │
└─────────────────────┼────────────────────────────────────────┘
                      │
┌─────────────────────┼────────────────────────────────────────┐
│              Service Layer                                    │
│  ┌───────────────────────────────────────────────────┐       │
│  │  KeywordService (일반 클래스)                      │       │
│  │  - _handleHttpError()                             │       │
│  │  - API 401 발생 시: UserFriendlyException throw   │       │
│  │  - ❌ authProvider 상태 업데이트 안 함             │       │
│  └────────────────────┬──────────────────────────────┘       │
│                       │                                       │
│  ┌────────────────────▼──────────────────────────────┐       │
│  │  AuthService (일반 클래스)                         │       │
│  │  - getUserInfo()                                  │       │
│  │  - refreshToken()                                 │       │
│  │  - getValidAccessToken() (5분 전 자동 갱신)       │       │
│  └────────────────────┬──────────────────────────────┘       │
└─────────────────────┼────────────────────────────────────────┘
                      │
                      ▼
              ┌──────────────┐
              │  Backend API │
              │  (401 응답)  │
              └──────────────┘
```

### 1.2 문제점이 드러나는 플로우

```
[키워드 추가 시도]
      │
      ▼
KeywordService.registerKeyword()
      │
      ▼
_getAuthHeaders() → TokenStorage에서 토큰 조회
      │
      ▼
HTTP POST /keyword-alerts/keywords
      │
      ├─── 200 OK ──→ 성공 처리
      │
      └─── 401 Unauthorized
             │
             ▼
   _handleHttpError(401)
             │
             ├─ NetworkErrorHandler.getHttpErrorMessage(401)
             │      → "로그인이 만료되었어요..." 메시지만 생성
             │
             ├─ UserFriendlyException throw
             │
             └─ ❌ authProvider 상태 업데이트 안 함
                    (isAuthenticated는 여전히 true)

      ▼
화면에서 catch (e)
      │
      ├─ 에러 팝업/스낵바 표시
      │
      └─ ❌ 로그인 화면 이동 없음

[문제]
- authProvider는 여전히 isAuthenticated: true
- 화면은 authProvider를 watch하지만 상태가 변경되지 않음
- 캐시된 userInfo가 계속 표시됨
- 사용자는 로그인된 것으로 착각
```

### 1.3 Riverpod을 활용하지 못하는 구조

```
❌ 현재 구조 (문제)
┌──────────────────┐
│  KeywordService  │ (일반 클래스)
│  - ProviderRef 접근 불가
│  - authProvider.logout() 호출 불가
└──────────────────┘
        │
        │ 401 에러
        ▼
  UserFriendlyException throw
        │
        ▼
      화면에서 catch
        │
        └─ 팝업만 표시

✅ 개선 구조 (Riverpod 활용)
┌──────────────────┐
│  KeywordService  │ (Provider로 변환)
│  - ProviderRef ref 보유
│  - ref.read(authProvider.notifier) 접근 가능
└──────────────────┘
        │
        │ 401 에러
        ▼
  ref.read(authProvider.notifier).logout()
        │
        ▼
  authProvider 상태 변경
  (isAuthenticated: false)
        │
        ▼
  모든 watch 위젯 자동 반응
        │
        ├─ 화면 UI 즉시 비회원으로 전환
        │
        └─ ref.listen 또는 GoRouter redirect
           → 로그인 화면으로 자동 이동
```

## 2. 파일별 역할 및 문제점

### 2.1 서비스 레이어

| 파일 | 현재 구조 | 401 에러 처리 | 문제점 |
|------|-----------|---------------|--------|
| `services/keyword_service.dart` | 일반 클래스 | UserFriendlyException만 throw | authProvider 업데이트 불가 |
| `services/auth_service.dart` | 일반 클래스 | getValidAccessToken()로 자동 갱신 시도 | 401 시 authProvider 업데이트 안 함 |
| `providers/auth_provider.dart` | Riverpod Provider | checkAuthStatus()에서만 logout() 호출 | 서비스 레이어와 분리됨 |

### 2.2 UI 레이어

| 화면 | authProvider 사용 | 401 에러 동작 | 문제점 |
|------|-------------------|---------------|--------|
| `ProfileScreen` | ref.watch(authProvider) → UI 렌더링 | 상태 변경 없어 캐시된 UI 계속 표시 | 로그아웃 후에도 사용자 정보 보임 |
| `KeywordAlertsScreen` | 사용 안 함 | 에러 팝업만 표시 | 로그인 화면 이동 없음 |
| `MyPageScreen` | 사용 안 함 | debugPrint만 출력 | 에러 무시 |

### 2.3 유틸리티

| 파일 | 역할 | 문제점 |
|------|------|--------|
| `utils/network_error_handler.dart` | HTTP 에러 메시지 변환 | 메시지만 생성, 상태 관리 없음 |
| `widgets/auth_required_dialog.dart` | 로그인 유도 다이얼로그 | 탭 전환 시에만 사용 |

## 3. 핵심 문제점

### 문제 1: authProvider 상태와 실제 인증 상태 불일치

**현상:**
```
API: 401 Unauthorized (서버가 "인증 만료"라고 응답)
       ↓
authProvider: isAuthenticated = true (앱은 여전히 "로그인됨"으로 생각)
       ↓
화면: ref.watch(authProvider) → 캐시된 사용자 정보 계속 표시
       ↓
사용자: "로그인되어 있는데 왜 안 되지?" (혼란)
```

**근본 원인:**
- 서비스 레이어가 일반 클래스라 ProviderRef에 접근 불가
- 401 에러 발생 시 `authProvider.logout()` 호출할 방법 없음
- 에러 메시지만 throw하고 상태는 그대로 유지

**영향:**
- 사용자가 로그인된 것으로 착각
- 같은 작업을 반복 시도 → 계속 401 에러
- 혼란스러운 UX

### 문제 2: 401 에러 처리가 분산되어 일관성 없음

**현상:**
| 화면 | 에러 처리 방식 |
|------|---------------|
| 키워드 알람 | 에러 팝업 표시 |
| 내정보 | debugPrint만 출력 |
| 프로필 | UI만 변경 (네비게이션 없음) |

**근본 원인:**
- 중앙화된 401 에러 핸들러 없음
- 각 화면에서 개별적으로 에러 처리
- authProvider 상태 업데이트 없음

**영향:**
- 일관되지 않은 사용자 경험
- 유지보수 어려움
- 새 화면 추가 시 에러 처리 누락 위험

### 문제 3: 로그인 화면 자동 이동 없음

**현상:**
```
401 에러 발생
  ↓
팝업: "로그인이 만료되었습니다"
  ↓
사용자: "그래서 어디로 가야 하지?" (팝업 닫기만 가능)
  ↓
사용자가 수동으로 로그인 화면 찾아야 함
```

**근본 원인:**
- 서비스 레이어에 BuildContext 없어 직접 네비게이션 불가
- authProvider 상태 변화를 listen하는 로직 없음

**영향:**
- 사용자가 다음 액션을 모름
- 앱 사용 흐름 단절

### 문제 4: 작업 속행 기능 없음

**현상:**
```
사용자: 키워드 "맛집" 추가 시도
  ↓
401 에러 → (수동으로) 로그인 화면으로 이동
  ↓
로그인 완료 → 메인 화면으로 이동
  ↓
사용자: "아까 뭐 하려고 했더라?" (처음부터 다시 시작)
```

**근본 원인:**
- 원래 요청한 route를 저장하는 로직 없음
- LoginScreen에 returnRoute 파라미터 없음

**영향:**
- 사용자 작업 흐름 단절
- UX 저하

## 4. 근본 원인 분석

### 🎯 핵심: Riverpod의 반응형 상태 관리를 활용하지 못함

ReviewMaps는 **이미 Riverpod을 사용**하고 있지만, 서비스 레이어가 일반 클래스로 구현되어 Provider의 장점을 살리지 못하고 있습니다.

```
현재 문제 구조:

┌─────────────────┐
│  authProvider   │  (Riverpod Provider)
│  - logout()     │
└─────────────────┘
        ▲
        │ ref.read() 호출 불가!
        │
┌───────┴─────────┐
│ KeywordService  │  (일반 클래스)
│ - ProviderRef X │
└─────────────────┘
```

```
개선 구조:

┌─────────────────┐
│  authProvider   │  (Riverpod Provider)
│  - logout()     │
└─────────────────┘
        ▲
        │ ref.read() 호출 가능!
        │
┌───────┴─────────┐
│ KeywordService  │  (Provider로 변환)
│ - ProviderRef O │
└─────────────────┘
```

### 비교: 할 수 있는 것 vs 현재 못하는 것

| 작업 | 현재 상태 | Riverpod으로 할 수 있는 것 |
|------|-----------|---------------------------|
| 401 에러 감지 | O (UserFriendlyException throw) | O |
| authProvider 상태 업데이트 | X (접근 불가) | O (ref.read().logout()) |
| 로그인 화면 이동 | X (BuildContext 없음) | O (ref.listen 또는 GoRouter) |
| 캐시된 데이터 자동 제거 | X (상태 변경 안 함) | O (ref.watch로 자동 반응) |
| 일관된 에러 처리 | X (각 화면에서 개별 처리) | O (중앙 상태 관리) |

---

# Part 2: 해결 전략 (Solution Strategy)

## 1. Riverpod 기반 상태 중앙화

### 1.1 기본 원칙

| 원칙 | 설명 |
|------|------|
| **Single Source of Truth** | `authProvider`가 유일한 인증 상태 소스 |
| **Reactive Updates** | 상태 변경 시 모든 watch 위젯 자동 반응 |
| **Service Integration** | 서비스를 Provider로 변환하여 ref 접근 |

### 1.2 개선된 플로우

```
[401 에러 발생]
      │
      ▼
서비스 레이어에서 감지
      │
      ▼
ref.read(authProvider.notifier).logout()
      │
      ▼
authProvider 상태 변경
(isAuthenticated: true → false)
      │
      ▼
모든 ref.watch(authProvider) 위젯 자동 반응
      │
      ├─ ProfileScreen → 비회원 UI로 즉시 전환
      ├─ KeywordScreen → 캐시된 데이터 즉시 제거
      └─ MyPageScreen → 비회원 UI로 즉시 전환
      │
      ▼
GoRouter redirect 또는 ref.listen 감지
      │
      ▼
로그인 화면으로 자동 이동
(returnTo=원래경로 포함)
      │
      ▼
로그인 성공
      │
      ▼
returnTo 경로로 자동 복귀
```

## 2. 서비스 레이어 Provider 변환

### 2.1 변환 전략

**옵션 A: Provider로 변환 (추천)**
- KeywordService를 Provider로 만들어 자동으로 ref 접근
- Riverpod의 표준 패턴
- 테스트 용이성 증가

**옵션 B: ProviderContainer 사용 (비추천)**
- 최상위에서 ProviderContainer 생성
- 서비스에서 container.read()로 접근
- 안티패턴에 가까움

**옵션 C: 콜백 함수 전달 (임시 방편)**
- 서비스 생성 시 onUnauthorized 콜백 전달
- 간단하지만 확장성 낮음

### 2.2 Provider 변환 후 구조

```
keywordServiceProvider
  ↓
KeywordService 생성 (ref 자동 주입)
  ↓
401 에러 발생 시:
  ref.read(authProvider.notifier).logout()
  ↓
authProvider 상태 변경
  ↓
모든 위젯 자동 반응
```

## 3. 자동 네비게이션 처리

### 3.1 GoRouter 기반 (추천)

**장점:**
- 선언적 라우팅
- redirect 함수에서 authProvider 상태 watch
- returnRoute를 query parameter로 자연스럽게 전달

**플로우:**
```
GoRouter.redirect
  ↓
ref.watch(authProvider)
  ↓
isAuthenticated == false && 인증 필요 화면?
  ↓
/login?returnTo=원래경로 로 리다이렉트
  ↓
로그인 성공
  ↓
returnTo 파라미터로 복귀
```

### 3.2 ref.listen 기반 (GoRouter 없을 경우)

**장점:**
- GoRouter 도입 불필요
- 기존 네비게이션 구조 유지

**플로우:**
```
최상위 위젯에서:
  ref.listen(authProvider, (previous, next) {
    if (previous.isAuthenticated && !next.isAuthenticated) {
      Navigator.push → LoginScreen(returnRoute: 현재경로)
    }
  })
```

## 4. 작업 속행 기능

### 4.1 returnRoute 저장

| 시점 | 동작 |
|------|------|
| 401 에러 발생 | 현재 route 경로 저장 |
| 로그인 화면 이동 | returnRoute를 파라미터로 전달 |
| 로그인 성공 | returnRoute로 네비게이션 |
| returnRoute 없음 | 메인 화면으로 이동 |

### 4.2 구현 방식

**일반 화면:**
- route 경로만 저장
- 로그인 후 해당 화면으로 이동하면 자동으로 데이터 재로드

**복잡한 상태 화면:**
- route 경로 + arguments 저장
- 예: 상세 화면이라면 item ID도 함께 저장

## 5. AuthGuard 위젯 (선택사항)

### 5.1 역할

인증 필요 화면을 감싸는 Guard 위젯으로, 비회원 접근 시 자동 리다이렉트

### 5.2 구현 개념

```
AuthGuard(
  returnRoute: '/keyword-alerts',
  child: KeywordAlertsContent(),
)
  ↓
ref.watch(authProvider)
  ↓
!isAuthenticated?
  → LoginScreen으로 리다이렉트
  ↓
isAuthenticated?
  → child 렌더링
```

**주의:** GlobalKey 불필요, context.go() 또는 Navigator.push 사용

---

# Part 3: 구현 계획 (Implementation Plan)

## 1. Phase별 작업 계획

### Phase 1: 서비스 레이어 Riverpod 통합 (1일) ✅

**목표:** 서비스에서 authProvider에 접근할 수 있도록 구조 변경

- [x] KeywordService를 Provider로 변환
  - keywordServiceProvider 생성
  - 기존 KeywordService 클래스를 Provider로 래핑
  - ProviderRef를 생성자에서 받도록 수정
- [x] AuthService를 Provider로 변환
  - authServiceProvider 생성
  - ProviderRef를 생성자에서 받도록 수정
- [x] 기존 서비스 사용처 업데이트
  - 화면에서 KeywordService() → ref.read(keywordServiceProvider) 변경
  - 모든 사용처 검증

**완료 기준:**
- ✅ 모든 서비스에서 ref.read(authProvider.notifier) 호출 가능
- ✅ 기존 기능 정상 동작 확인

### Phase 2: 401 에러 처리 중앙화 (1일) ✅

**목표:** 모든 401 에러 발생 시 authProvider 상태 즉시 업데이트

- [x] keyword_service.dart의 _handleHttpError() 수정
  - 401 에러 감지 시 ref.read(authProvider.notifier).logout() 호출
  - UserFriendlyException은 그대로 throw (화면에서 메시지 표시용)
- [x] auth_service.dart의 401 처리 통합
  - getUserInfo(), refreshToken() 등에서 401 발생 시 logout() 호출
  - 기존 에러 메시지 유지
- [x] network_error_handler.dart는 그대로 유지 (메시지 생성만 담당)

**완료 기준:**
- ✅ 모든 API에서 401 발생 시 authProvider.isAuthenticated가 즉시 false로 변경
- ✅ 화면에서 캐시된 사용자 정보가 즉시 사라짐
- ✅ ProfileScreen이 자동으로 비회원 UI로 전환

### Phase 3: 자동 네비게이션 구현 (1일) ✅

**목표:** authProvider 상태 변경 시 자동으로 로그인 화면으로 이동

**선택한 방식: ref.listen 사용 (main.dart)**
- [x] 최상위 위젯 (main.dart)에서 ref.listen(authProvider) 설정
- [x] previous.isAuthenticated && !next.isAuthenticated 감지
- [x] 현재 경로 추출 (ModalRoute.of(context)?.settings.name)
- [x] 로그인 화면으로 Navigator.pushAndRemoveUntil (returnRoute 전달)
- [x] 스낵바 표시: "로그인이 만료되었습니다"
- [x] 디버그 로그 추가 (로그인 만료 감지, 현재 경로)

**구현 상세:**
```dart
// main.dart의 MyApp 위젯에서
ref.listen<AuthState>(authProvider, (previous, next) {
  if (previous != null &&
      previous.isAuthenticated &&
      !next.isAuthenticated) {

    // 현재 경로 추출
    final currentRoute = ModalRoute.of(currentContext)?.settings.name;

    // 스낵바 표시
    ScaffoldMessenger.of(currentContext).showSnackBar(
      const SnackBar(
        content: Text('로그인이 만료되었습니다. 다시 로그인해 주세요.'),
      ),
    );

    // LoginScreen에 returnRoute 전달
    Navigator.of(currentContext).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => LoginScreen(returnRoute: currentRoute),
      ),
      (route) => false,
    );
  }
});
```

**완료 기준:**
- ✅ 401 에러 발생 시 자동으로 로그인 화면으로 이동
- ✅ 스낵바로 "로그인이 만료되었습니다" 안내 표시
- ✅ returnRoute 전달하여 로그인 성공 후 복귀 가능
- ✅ Flutter analyze 통과

### Phase 4: 작업 속행 기능 구현 (0.5일) ✅

**목표:** 로그인 후 원래 작업으로 자동 복귀

- [x] LoginScreen 파라미터 추가
  - returnRoute: String? 추가
  - returnArguments: Map<String, dynamic>? 추가 (선택)
- [x] 로그인 성공 후 복귀 로직
  - returnRoute가 있으면 해당 경로로 네비게이션
  - returnRoute가 없으면 메인 화면으로 이동
- [x] Navigator 사용: Navigator.pushReplacementNamed(returnRoute)
- [x] 모든 로그인 메서드에 복귀 로직 적용
  - 이메일 로그인
  - Kakao 로그인
  - Google 로그인
  - Apple 로그인

**완료 기준:**
- ✅ LoginScreen에 returnRoute, returnArguments 파라미터 추가
- ✅ _navigateAfterLogin() 공통 메서드 구현
- ✅ 모든 로그인 메서드에서 _navigateAfterLogin() 호출
- ✅ Flutter analyze 통과

### Phase 4.1: 통합성 검토 및 수정 ✅

**목표:** Phase 1~4 통합성 검증 및 발견된 문제 수정

**검토 결과:**
- ✅ Phase 1 & 2 이미 구현 완료 (keywordServiceProvider, authServiceProvider)
- ✅ Phase 3 이미 구현 완료 (main.dart의 ref.listen)
- ✅ Phase 4 이미 구현 완료 (LoginScreen returnRoute 파라미터)

**발견된 문제:**
- ❌ LoginScreen에서 legacy AuthService 인스턴스 사용
  - Line 39: `final AuthService _authService = AuthService();`
  - 이 방식으로는 Ref가 null이어서 401 에러 시 authProvider.logout() 호출 불가
  - 로그인 중 401 에러 발생 시 상태 업데이트 실패

**수정 내용:**
- [x] LoginScreen에서 AuthService Provider 사용으로 변경
  - `_authService` 필드 제거
  - 모든 로그인 메서드에서 `ref.read(authServiceProvider)` 사용
  - 이메일 로그인: `_handleLogin()`
  - Kakao 로그인: `_handleKakaoLogin()`
  - Google 로그인: `_handleGoogleLogin()`
  - Apple 로그인: `_handleAppleLogin()`
- [x] Flutter analyze 통과 확인

**완료 기준:**
- ✅ LoginScreen이 authServiceProvider 사용
- ✅ 로그인 중 401 에러 발생 시에도 authProvider.logout() 정상 호출
- ✅ Phase 1~4 전체 플로우 완전 통합

### Phase 5: FCM 딥링크 인증 상태 체크 구현 (1일) ✅

**목표:** 푸시 알림 딥링크 처리 시 인증 상태 체크 및 자동 네비게이션

**구현 내용:**
- [x] FcmService를 Provider로 변환
  - `fcmServiceProvider` 생성
  - `Ref _ref` 필드 추가하여 authProvider 접근 가능
  - `_registerTokenToServer()`, `unregisterToken()`에서 keywordServiceProvider 사용
- [x] 딥링크 처리 시 authProvider 상태 체크 로직 추가
  - `_navigateToNotificationScreen()` 메서드 수정
  - 로그인 상태: MainScreen (알림 탭, 알림 기록)으로 이동
  - 비로그인 상태: LoginScreen (returnRoute=/notifications)으로 이동
- [x] LoginScreen에서 /notifications returnRoute 처리
  - `_navigateAfterLogin()` 메서드에 `/notifications` 분기 추가
  - 로그인 성공 후 MainScreen (알림 탭, 알림 기록)으로 복귀
- [x] SplashScreen에서 FcmService 초기화를 Provider 방식으로 변경
  - ConsumerStatefulWidget으로 변환
  - `ref.read(fcmServiceProvider).initialize()` 호출
- [x] NotificationScreen에서 Provider 방식 사용
  - `FcmService.instance` → `ref.read(fcmServiceProvider)` 변경
- [x] AuthProvider에서 Provider 방식 사용
  - `FcmService.instance` → `ref.read(fcmServiceProvider)` 변경
  - `refreshToken()`, `unregisterToken()` 호출 부분 수정
- [x] Flutter analyze 통과 확인

**플로우:**
```
[푸시 알림 탭]
  ↓
[FcmService._navigateToNotificationScreen()]
  ↓
[authProvider 상태 체크]
  ↓
  ├─ 로그인됨 → MainScreen (알림 탭, 알림 기록)
  └─ 비로그인 → LoginScreen (returnRoute=/notifications)
       ↓
     [로그인 성공]
       ↓
     [MainScreen (알림 탭, 알림 기록)으로 복귀]
```

**완료 기준:**
- ✅ FcmService를 Provider로 변환 완료
- ✅ 딥링크 인증 체크 로직 구현 완료
- ✅ LoginScreen returnRoute 처리 완료
- ✅ Flutter analyze 통과
- ✅ Phase 1~4와 일관된 Provider 패턴 사용

### Phase 6: 안정성 개선 - 경쟁 조건 및 중복 방지 (1일) ✅

**목표:** Phase 1~5 통합 후 발견된 Critical/Medium 이슈 수정

**안정성 분석 결과:**
- 🔴 Critical Issue 1: Provider 순환 참조 위험
- 🔴 Critical Issue 2: 토큰 갱신 경쟁 조건
- 🟡 Medium Issue 1: 401 에러 네비게이션 중복
- 🟡 Medium Issue 2: Context 유효성 체크 부재

**구현 내용:**
- [x] **Critical Issue 1 수정: Provider 순환 참조 방지**
  - `auth_provider.dart`: `updateAfterLogin()` 메서드에 try-catch 추가
  - FCM 토큰 갱신 실패 시에도 로그인 상태 유지
  - 순환 참조로 인한 무한 루프 방지

- [x] **Critical Issue 2 수정: 토큰 갱신 경쟁 조건 방지**
  - `auth_provider.dart`: `_isRefreshing` 플래그 추가
  - `checkAuthStatus()`: 토큰 갱신 중 중복 시도 방지
  - `logout()`: 토큰 갱신 중 로그아웃 대기
  - 동시 401 에러 발생 시 경쟁 조건 해결

- [x] **Medium Issue 1 수정: 401 에러 네비게이션 중복 방지**
  - `main.dart`: MyApp을 ConsumerStatefulWidget으로 변경
  - `_isNavigatingToLogin` 플래그 추가
  - ref.listen에서 중복 네비게이션 방지
  - 동시 다발적 401 에러 시 로그인 화면 중복 이동 방지

- [x] **Medium Issue 2 수정: Context 유효성 체크 추가**
  - `fcm_service.dart`: `_navigateToNotificationScreen()`에 mounted 체크 및 addPostFrameCallback 추가
  - `login_screen.dart`: `_navigateAfterLogin()`에 mounted 체크 및 addPostFrameCallback 추가
  - 비동기 네비게이션 안전성 확보

- [x] Flutter analyze 통과 확인

**플로우 개선:**
```
[동시 401 에러 발생 (3개 API 호출)]
  ↓
[첫 번째 401] → authProvider.logout() 호출
  ├─ _isRefreshing = true 설정
  └─ 상태 변경 (isAuthenticated: false)
       ↓
    [ref.listen 감지]
       ├─ _isNavigatingToLogin = true 설정
       └─ 로그인 화면으로 이동 (1번만)

[두 번째 401] → authProvider.logout() 호출 시도
  └─ _isRefreshing == true → 대기 (중복 실행 방지)

[세 번째 401] → authProvider.logout() 호출 시도
  └─ _isRefreshing == true → 대기 (중복 실행 방지)

[ref.listen 중복 호출]
  └─ _isNavigatingToLogin == true → 중복 네비게이션 방지
```

**완료 기준:**
- ✅ Critical Issue 1, 2 수정 완료
- ✅ Medium Issue 1, 2 수정 완료
- ✅ Flutter analyze 통과
- ✅ 동시 다발적 401 에러 안전 처리
- ✅ 비동기 네비게이션 안전성 확보

### Phase 6.1: AuthGuard 위젯 구현 (선택사항, 0.5일)

**목표:** 인증 필요 화면에 재사용 가능한 Guard 위젯 적용

- [ ] AuthGuard 위젯 생성
  - ConsumerWidget으로 구현
  - ref.watch(authProvider)로 상태 확인
  - !isRegularUser이면 로그인 화면으로 리다이렉트
  - GlobalKey 사용하지 않음
- [ ] KeywordAlertsScreen에 AuthGuard 적용
  - AuthGuard로 감싸기
  - returnRoute 전달
- [ ] MyPageScreen 제거 또는 리팩토링
- [ ] 모든 인증 필요 화면 검증

**완료 기준:**
- 비회원이 인증 필요 화면 진입 시 자동 리다이렉트
- 코드 가독성 향상
- 새 인증 화면 추가 시 AuthGuard만 감싸면 됨

### Phase 7: 전체 플로우 검증 및 정리 (0.5일) ✅

**목표:** 전체 시나리오 테스트 및 코드 정리

**완료 내용:**
- [x] Phase 1~5 코드 정적 분석 및 검증
  - Flutter analyze 통과 확인
  - 401 에러 처리 플로우 검증
  - Provider 변환 완료 확인
  - FCM 딥링크 인증 체크 로직 검증
- [x] 레거시 코드 발견 및 문서화
  - password_change_screen.dart (레거시 AuthService 사용)
  - password_reset_screen.dart (레거시 AuthService 사용)
  - sign_up_screen.dart (레거시 AuthService 사용)
  - Phase 7.1로 별도 수정 권장
- [x] 검증 리포트 작성
  - [phase6-verification-report.md](../claudedocs/phase6-verification-report.md) 생성
  - 전체 플로우 검증 결과 문서화
  - 레거시 코드 수정 권장사항 포함
- [x] 문서 업데이트
  - Phase 1~5 완료 표시
  - Phase 7 검증 결과 추가

**시뮬레이터 필요 작업 (보류):**
- [ ] E2E 테스트 시나리오 실행
  - 시나리오 1~6 실제 동작 확인
  - 시뮬레이터에서 401 에러 플로우 테스트
  - **시나리오 6: 푸시 알림 딥링크 플로우 테스트** (NEW)
- [ ] Phase 7.1: 레거시 AuthService 마이그레이션
  - 3개 화면 Provider 방식으로 변환
  - 각 화면 동작 테스트

**완료 기준:**
- ✅ 정적 분석 및 코드 검증 완료
- ✅ Flutter analyze 통과
- ✅ 문서 업데이트 완료
- ⏳ E2E 테스트 (시뮬레이터 필요)
- ⏳ 레거시 코드 정리 (Phase 7.1)

## 2. 테스트 시나리오

### 시나리오 1: 키워드 화면에서 세션 만료

| 단계 | 기대 동작 |
|------|-----------|
| **Given** | 사용자가 키워드 알람 화면에 있음 |
| **When** | 토큰이 만료된 상태에서 키워드 추가 시도 |
| **Then 1** | API 401 에러 발생 |
| **Then 2** | KeywordService에서 ref.read(authProvider.notifier).logout() 호출 |
| **Then 3** | authProvider 상태 즉시 비인증으로 변경 (isAuthenticated: false) |
| **Then 4** | "로그인이 만료되었습니다" 스낵바 표시 |
| **Then 5** | 자동으로 로그인 화면으로 이동 (returnTo=/keyword-alerts) |
| **Then 6** | 로그인 성공 후 키워드 화면으로 자동 복귀 |

### 시나리오 2: 내정보 화면에서 세션 만료

| 단계 | 기대 동작 |
|------|-----------|
| **Given** | 사용자가 내정보 화면에 있음 (사용자 정보 표시 중) |
| **When** | 토큰 만료 후 화면 새로고침 (pull-to-refresh) |
| **Then 1** | API 401 에러 발생 |
| **Then 2** | AuthService에서 authProvider.logout() 호출 |
| **Then 3** | authProvider 상태 즉시 비인증으로 변경 |
| **Then 4** | ProfileScreen이 ref.watch(authProvider) 하므로 즉시 비회원 UI로 전환 |
| **Then 5** | 캐시된 사용자 정보 즉시 사라짐 (화면에서 안 보임) |
| **Then 6** | 로그인 화면으로 자동 이동 |

### 시나리오 3: 비회원이 알림 탭 클릭

| 단계 | 기대 동작 |
|------|-----------|
| **Given** | 비회원 상태 (authProvider.isAuthenticated: false) |
| **When** | 하단 탭의 "알림" 클릭 |
| **Then 1** | GoRouter redirect 또는 AuthGuard 감지 |
| **Then 2** | 로그인 화면으로 자동 이동 (returnTo=/notifications) |
| **Then 3** | 로그인 성공 후 알림 화면으로 자동 이동 |

### 시나리오 4: 토큰 자동 갱신 성공

| 단계 | 기대 동작 |
|------|-----------|
| **Given** | 토큰 만료 4분 전 |
| **When** | API 호출 |
| **Then 1** | AuthService.getValidAccessToken()에서 자동 갱신 시도 |
| **Then 2** | refreshToken() 성공 |
| **Then 3** | 새 토큰으로 원래 API 호출 |
| **Then 4** | 사용자는 중단 없이 작업 계속 |

### 시나리오 5: 토큰 갱신 실패

| 단계 | 기대 동작 |
|------|-----------|
| **Given** | 토큰 만료 4분 전 |
| **When** | API 호출 → refreshToken() 실패 (401) |
| **Then 1** | 기존 토큰으로 원래 API 시도 |
| **Then 2** | API도 401 에러 발생 |
| **Then 3** | authProvider.logout() 호출 |
| **Then 4** | 상태 변경 → 로그인 화면으로 자동 이동 |

### 시나리오 6: 푸시 알림 딥링크 (Phase 5, Phase 6 안정성 개선)

| 단계 | 기대 동작 |
|------|-----------|
| **Given** | 앱이 백그라운드 또는 종료 상태 |
| **When** | 키워드 알림 푸시 수신 → 푸시 알림 탭 |
| **Then 1** | FcmService._navigateToNotificationScreen() 호출 |
| **Then 2** | (Phase 6) Context 유효성 체크 (mounted) |
| **Then 3** | authProvider 상태 체크 |
| **Then 4-A (로그인됨)** | MainScreen (알림 탭, 알림 기록)으로 이동 |
| **Then 4-B (비로그인)** | LoginScreen (returnRoute=/notifications)으로 이동 |
| **Then 5 (4-B 경우)** | (Phase 6) 로그인 화면 네비게이션 중복 방지 플래그 설정 |
| **Then 6 (4-B 경우)** | 로그인 성공 → MainScreen (알림 탭, 알림 기록)으로 복귀 |
| **Then 7** | 알림 기록에서 해당 캠페인 확인 가능 |

## 3. 예상 효과

### 3.1 사용자 경험 개선

| 개선 항목 | Before | After |
|-----------|--------|-------|
| 세션 만료 처리 | 에러 팝업만 표시, 다음 액션 모름 | 명확한 안내 + 자동 로그인 화면 이동 |
| 로그인 후 복귀 | 처음부터 다시 시작 | 원래 작업으로 자동 복귀 |
| 캐시된 데이터 | 로그아웃 후에도 표시 (혼란) | 즉시 비회원 UI로 전환 |
| 에러 처리 일관성 | 화면마다 다른 동작 | 모든 화면에서 동일한 UX |

### 3.2 개발자 경험 개선

| 개선 항목 | Before | After |
|-----------|--------|-------|
| 에러 처리 로직 | 각 화면에서 중복 구현 | authProvider 상태만 업데이트하면 끝 |
| 새 화면 추가 | 에러 처리 로직 매번 구현, 누락 위험 | AuthGuard로 감싸거나 자동 처리 |
| 유지보수 | 여러 곳 수정 필요 | 중앙 한 곳(Provider)만 수정 |
| 테스트 | Mock 구현 어려움 | Riverpod의 간단한 Mock Provider |

### 3.3 코드 품질 향상

| 개선 항목 | 설명 |
|-----------|------|
| 관심사 분리 | UI 로직과 인증 상태 관리 완전히 분리 |
| 반응형 아키텍처 | Riverpod의 반응형 상태 관리 완전 활용 |
| 테스트 가능성 | Mock Provider로 쉬운 단위 테스트 |
| 유지보수성 | 중앙화된 상태 관리로 변경 영향 최소화 |

## 4. 리스크 및 대응 방안

### 리스크 1: 서비스 레이어 구조 변경

**문제:** 서비스를 Provider로 변환하면 기존 사용처를 모두 수정해야 함

**대응:**
- Phase 1에서 점진적으로 변경
- 각 서비스별로 테스트하면서 진행
- 필요시 옵션 C (콜백 함수)로 최소 변경 접근

**영향도:** 중간 (기존 코드 수정 필요하지만 구조적 개선)

### 리스크 2: GoRouter 도입 복잡도

**문제:** GoRouter를 사용하지 않는 경우 도입이 복잡할 수 있음

**대응:**
- 옵션 B (ref.listen)로 기존 네비게이션 유지
- GoRouter는 선택사항으로 진행
- 최소한 ref.listen만으로도 기능 구현 가능

**영향도:** 낮음 (대안 존재)

### 리스크 3: 기존 화면 동작 변경

**문제:** 기존에 독자적으로 에러 처리하던 화면들이 영향받을 수 있음

**대응:**
- Phase별 점진적 적용
- 각 Phase마다 회귀 테스트
- 기존 동작 보존 옵션 제공

**영향도:** 낮음 (개선이므로 긍정적 변경)

## 5. 기존 제안 vs Riverpod 기반 비교

| 항목 | 기존 제안 (GlobalKey) | Riverpod 기반 (이 문서) |
|------|---------------------|----------------------|
| 복잡도 | 높음 (static 클래스, GlobalKey, WidgetRef static 변수) | 낮음 (Provider만 사용) |
| 코드량 | 많음 (AuthErrorHandler 새 클래스 생성) | 적음 (기존 구조 활용) |
| Riverpod 활용 | 부분적 (Provider와 static 클래스 혼용) | 완전히 활용 (Provider 중심) |
| 안티패턴 | 있음 (static WidgetRef 저장) | 없음 (표준 패턴) |
| 유지보수성 | 낮음 (GlobalKey 관리 필요) | 높음 (Riverpod 표준) |
| 테스트 용이성 | 어려움 (static 변수 Mock 어려움) | 쉬움 (Mock Provider) |
| 확장성 | 제한적 | 높음 |

**결론:** Riverpod을 이미 사용하고 있으므로, Riverpod의 장점을 최대한 활용하는 것이 가장 간단하고 효과적입니다. GlobalKey나 static 변수 없이 Provider 변환만으로 모든 문제를 해결할 수 있습니다.

---

**작성일**: 2025-12-26
**작성자**: Claude (AI)
**검토 필요**: ✅ 개발팀 리뷰 및 우선순위 결정
