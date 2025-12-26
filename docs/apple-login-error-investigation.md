# Apple 앱 스토어 리뷰 거절 - 로그인 에러 조사

## Apple 리뷰 피드백

**거절 사유**: Guideline 2.1 - Performance - App Completeness

**발견된 버그**:
1. Apple 로그인 시도 시 에러 메시지 표시
2. 로그인 중 에러 메시지 표시

**테스트 환경**:
- 기기: iPad Air 11-inch (M3)
- OS: iPadOS 26.2 (※ 현재 iPadOS 최신 버전은 18.x - Apple 내부 테스트 버전으로 추정)
- 앱 버전: 2.0.8

## 코드 분석 결과

### 1. Apple 로그인 구현 (`login_screen.dart:276-338`)

**현재 구현**:
```dart
Future<void> _handleAppleLogin() async {
  // iOS만 지원 체크
  if (!Platform.isIOS) {
    _showErrorDialog('Apple 로그인은 iOS에서만 사용할 수 있습니다.');
    return;
  }

  try {
    // 1. Apple Sign In
    final appleCredentials = await AppleLoginService.login();

    // 2. 서버 로그인
    await authService.appleLogin(
      appleCredentials['identity_token']!,
      appleCredentials['authorization_code'],
    );

    // 3. 사용자 정보 가져오기
    final userInfo = await authService.getUserInfo();

    // 4. authProvider 상태 업데이트
    await ref.read(authProvider.notifier).updateAfterLogin(userInfo);

    // 5. 화면 이동
    _navigateAfterLogin();
  } catch (e) {
    // 에러 처리
    String errorMessage = 'Apple 로그인 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.';
    // ... 세부 에러 메시지 파싱
    _showErrorDialog(errorMessage);
  }
}
```

**분석**:
- ✅ Platform.isIOS 체크 (iPad도 iOS로 인식되므로 문제없음)
- ✅ 에러 처리 구현됨
- ⚠️ 에러 메시지가 모호할 수 있음 (사용자가 원인을 알기 어려움)

### 2. Apple 로그인 서비스 (`apple_login_service.dart:25-67`)

**구현 내용**:
```dart
static Future<Map<String, String>> login() async {
  try {
    // nonce 생성 (보안용)
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    // Apple 로그인 시작
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    // Identity Token 확인
    final identityToken = credential.identityToken;
    if (identityToken == null) {
      throw Exception('Apple identity token을 가져올 수 없습니다.');
    }

    return {
      'identity_token': identityToken,
      'authorization_code': credential.authorizationCode,
    };
  } on SignInWithAppleAuthorizationException catch (e) {
    if (e.code == AuthorizationErrorCode.canceled) {
      throw Exception('Apple 로그인이 취소되었습니다.');
    } else if (e.code == AuthorizationErrorCode.unknown) {
      // error 1000: Xcode에서 Sign In with Apple capability 설정 필요
      throw Exception('Apple 로그인 설정이 필요합니다.\nXcode에서 Sign In with Apple을 활성화해주세요.');
    }
    throw Exception('Apple 로그인 실패: ${e.message}');
  }
}
```

**분석**:
- ✅ SignInWithAppleAuthorizationException 처리
- ✅ 에러 코드별 분기 처리
- ⚠️ `AuthorizationErrorCode.unknown`은 다양한 원인이 있을 수 있음

### 3. 서버 API 엔드포인트 (`auth_service.dart:403-426`)

**구현 내용**:
```dart
Future<AuthResponse> appleLogin(String identityToken, String? authorizationCode) async {
  final uri = Uri.parse('$baseUrl/auth/apple');
  final request = AppleLoginRequest(
    identityToken: identityToken,
    authorizationCode: authorizationCode,
  );

  try {
    final response = await _client
        .post(
          uri,
          headers: _headers,
          body: jsonEncode(request.toJson()),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200 && response.statusCode != 201) {
      final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
      throw Exception(errorBody['detail'] ?? 'Apple 로그인 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.');
    }

    // ... 성공 처리
  }
}
```

**분석**:
- ✅ 타임아웃 설정 (10초)
- ✅ HTTP 상태 코드 체크
- ⚠️ 서버 에러 원인을 클라이언트가 알 수 없음

## 가능한 원인 분석

### 1. iPad 특화 이슈

**가능성**: iPad에서 Sign in with Apple capability 설정 누락
- iPad와 iPhone은 동일한 iOS를 사용하지만, Xcode 프로젝트 설정에서 iPad 타겟에 대한 capability가 누락될 수 있음
- **확인 필요**: Xcode > Signing & Capabilities > Sign in with Apple이 iPad 타겟에도 활성화되어 있는지

### 2. Apple 서버 통신 실패

**가능성**: identity_token 검증 실패
- Apple의 identity token 검증은 Apple 서버와 통신 필요
- 서버에서 token 검증 시 Apple API 호출이 실패할 수 있음
- **확인 필요**: 서버 로그에서 Apple API 호출 실패 여부

### 3. 이메일/이름 스코프 미제공

**가능성**: 재로그인 시 email/fullName이 null
- Apple 로그인은 최초 1회만 email/fullName을 제공
- 재로그인 시 서버가 이 정보를 요구하면 에러 발생
- **확인 필요**: 서버에서 email이 필수 필드인지, 없을 때 처리 로직이 있는지

### 4. iPadOS 버전 호환성 문제

**가능성**: iPadOS 26.2 (미래 버전)에서 API 변경
- Apple이 베타/내부 버전에서 테스트했을 가능성
- Sign in with Apple API가 변경되었을 수 있음
- **대응**: 현재 최신 SDK 사용 확인, 업데이트 필요 시 대응

## 권장 조치 사항

### 즉시 대응 (Urgent)

#### 1. Support URL 업데이트 ✅
- [x] 웹 사이트에 `/support` 페이지 생성
- [x] 네비게이션에 "고객지원" 추가
- [ ] App Store Connect에서 Support URL 변경: https://review-maps.com/support

#### 2. 서버 로그 확인 (필수)
- [ ] iPad Air 11-inch에서 Apple 로그인 시도 시 서버 로그 확인
- [ ] `/v1/auth/apple` 엔드포인트에서 발생하는 에러 확인
- [ ] Apple identity token 검증 실패 로그가 있는지 확인

#### 3. Xcode 설정 확인
- [ ] Xcode > Signing & Capabilities 확인
- [ ] Sign in with Apple이 모든 타겟(iPhone, iPad)에 활성화되어 있는지
- [ ] Bundle ID가 Apple Developer에 등록된 것과 일치하는지

### 중기 대응 (Important)

#### 4. 에러 메시지 개선
현재 에러 메시지가 모호하므로, 사용자 친화적으로 개선:

**Before**:
```
Apple 로그인 중 문제가 발생했습니다.
잠시 후 다시 시도해 주세요.
```

**After (제안)**:
```
Apple 로그인에 실패했습니다.

다음 사항을 확인해주세요:
1. 기기의 Apple ID가 로그인되어 있는지
2. 인터넷 연결이 안정적인지
3. 리뷰맵 앱의 권한 설정이 올바른지

문제가 계속되면 고객지원으로 문의해주세요.
```

#### 5. 로그인 디버깅 정보 추가
개발 모드에서 더 자세한 에러 정보 로깅:
- identity_token 길이, 형식 검증
- 서버 응답 상태 코드와 본문 상세 로깅
- Apple API 호출 실패 시 원인 로깅

#### 6. 대체 로그인 방법 안내
Apple 로그인 실패 시 다른 로그인 방법 안내:
- "Kakao 또는 Google로 로그인 시도해보세요"

### 장기 대응 (Monitoring)

#### 7. 에러 트래킹 시스템 구축
- Firebase Crashlytics 또는 Sentry 연동
- Apple 로그인 실패율 모니터링
- iPad vs iPhone 실패율 비교

#### 8. 자동 재시도 로직
- 네트워크 타임아웃 시 자동 재시도 (최대 3회)
- 재시도 간격: 1초, 3초, 5초

#### 9. 사용자 피드백 수집
- 로그인 실패 시 "문제 신고" 버튼 제공
- 사용자가 겪은 문제를 서버로 전송 (익명화)

## Apple 앱 리뷰 재제출 체크리스트

### Guideline 1.5 - Safety (Support URL)
- [x] `/support` 페이지 생성 완료
- [x] 네비게이션에 "고객지원" 링크 추가
- [ ] App Store Connect에서 Support URL 업데이트
- [ ] Support URL이 정상 작동하는지 확인

### Guideline 2.1 - Performance (로그인 에러)
- [ ] 서버 로그에서 Apple 로그인 에러 원인 확인
- [ ] Xcode Sign in with Apple capability 확인
- [ ] 실제 iPad Air에서 Apple 로그인 테스트
- [ ] 에러 메시지 개선 (사용자 친화적)
- [ ] 일반 로그인 에러도 함께 확인

## 다음 단계

1. **즉시**: App Store Connect에서 Support URL 변경 및 웹사이트 배포
2. **24시간 내**: 서버 로그 확인 및 Xcode 설정 검토
3. **48시간 내**: iPad Air에서 실제 테스트 수행
4. **테스트 완료 후**: Apple에 재제출 (Resolution Center에 조치 사항 설명)

## 참고 자료

- [Apple - Sign in with Apple 문서](https://developer.apple.com/documentation/sign_in_with_apple)
- [Flutter sign_in_with_apple 패키지](https://pub.dev/packages/sign_in_with_apple)
- [App Store 리뷰 가이드라인](https://developer.apple.com/app-store/review/guidelines/)
