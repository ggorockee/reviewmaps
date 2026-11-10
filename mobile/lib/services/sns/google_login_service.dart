import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mobile/config/config.dart';

/// Google 소셜 로그인 서비스 (google_sign_in 7.x)
class GoogleLoginService {
  static const List<String> _scopes = ['email', 'profile'];

  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static Future<void>? _initialization;
  static GoogleSignInAccount? _currentUser;

  /// 7.x부터 initialize()는 앱 생명주기 동안 정확히 한 번만 호출해야 함
  static Future<void> _ensureInitialized() {
    return _initialization ??= _googleSignIn.initialize(
      // iOS에서는 clientId가 필요함
      clientId: Platform.isIOS ? AppConfig.googleIosClientId : null,
      // serverClientId는 서버 사이드 인증을 위한 Web Client ID
      serverClientId: AppConfig.googleWebClientId,
    );
  }

  /// Google 로그인 실행
  /// - 반환값: Google access token (서버가 userinfo API로 검증)
  /// - 예외: Exception
  static Future<String> login() async {
    try {
      await _ensureInitialized();

      // 기존 세션 로그아웃 (계정 선택 화면 노출 목적)
      await _googleSignIn.signOut();

      // Google 로그인 시작 (취소 시 GoogleSignInException 발생)
      final account = await _googleSignIn.authenticate(scopeHint: _scopes);
      _currentUser = account;

      // 7.x: access token은 authentication이 아닌 authorizationClient에서 발급
      final authorization =
          await account.authorizationClient.authorizationForScopes(_scopes) ??
              await account.authorizationClient.authorizeScopes(_scopes);

      return authorization.accessToken;
    } on GoogleSignInException catch (e) {
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
          throw Exception('Google 로그인이 취소되었습니다.');
        default:
          throw Exception('Google 로그인에 실패했습니다.');
      }
    } catch (e) {
      final errorMessage = e.toString();
      if (errorMessage.contains('network_error') ||
          errorMessage.contains('NETWORK_ERROR')) {
        throw Exception('네트워크 연결이 불안정합니다.');
      }
      throw Exception('Google 로그인에 실패했습니다.');
    }
  }

  /// Google 로그아웃
  static Future<void> logout() async {
    try {
      await _ensureInitialized();
      await _googleSignIn.signOut();
      _currentUser = null;
    } catch (e) {
      throw Exception('Google 로그아웃 실패: $e');
    }
  }

  /// Google 연결 해제
  static Future<void> disconnect() async {
    try {
      await _ensureInitialized();
      await _googleSignIn.disconnect();
      _currentUser = null;
    } catch (e) {
      throw Exception('Google 연결 해제 실패: $e');
    }
  }

  /// 현재 로그인된 사용자 정보 조회 (이 서비스로 로그인한 계정)
  static GoogleSignInAccount? getCurrentUser() => _currentUser;
}
