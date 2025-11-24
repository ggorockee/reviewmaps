import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';

/// Google 소셜 로그인 서비스
class GoogleLoginService {
  // iOS에서는 clientId가 필요함
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: Platform.isIOS
        ? '966129856796-7f4f5j9mtf5g2c5ovjv8qg8mkov4rjuc.apps.googleusercontent.com'
        : null,
    scopes: [
      'email',
      'profile',
    ],
  );

  /// Google 로그인 실행
  /// - 반환값: Google access token
  /// - 예외: Exception
  static Future<String> login() async {
    try {
      // 기존 세션 로그아웃 (선택사항)
      await _googleSignIn.signOut();

      // Google 로그인 시작
      final GoogleSignInAccount? account = await _googleSignIn.signIn();

      if (account == null) {
        throw Exception('Google 로그인이 취소되었습니다.');
      }

      // 인증 정보 가져오기
      final GoogleSignInAuthentication auth = await account.authentication;

      // Access Token 확인
      final accessToken = auth.accessToken;
      if (accessToken == null) {
        throw Exception('Google access token을 가져올 수 없습니다.');
      }

      return accessToken;
    } catch (e) {
      if (e.toString().contains('취소')) {
        rethrow;
      }
      throw Exception('Google 로그인 실패: $e');
    }
  }

  /// Google 로그아웃
  static Future<void> logout() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      throw Exception('Google 로그아웃 실패: $e');
    }
  }

  /// Google 연결 해제
  static Future<void> disconnect() async {
    try {
      await _googleSignIn.disconnect();
    } catch (e) {
      throw Exception('Google 연결 해제 실패: $e');
    }
  }

  /// 현재 로그인된 사용자 정보 조회
  static GoogleSignInAccount? getCurrentUser() {
    return _googleSignIn.currentUser;
  }
}
