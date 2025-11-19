import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:flutter/services.dart';

/// Kakao 소셜 로그인 서비스
class KakaoLoginService {
  /// Kakao 로그인 실행
  /// - 반환값: Kakao access token
  /// - 예외: PlatformException, KakaoException
  static Future<String> login() async {
    try {
      // 카카오톡 설치 여부 확인
      final installed = await isKakaoTalkInstalled();

      OAuthToken token;
      if (installed) {
        // 카카오톡으로 로그인
        try {
          token = await UserApi.instance.loginWithKakaoTalk();
        } catch (error) {
          // 사용자가 카카오톡 설치 후 디바이스 권한 요청 화면에서 로그인을 취소한 경우
          if (error is PlatformException && error.code == 'CANCELED') {
            rethrow;
          }
          // 카카오톡에 연결된 카카오계정이 없는 경우, 카카오계정으로 로그인
          token = await UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        // 카카오계정으로 로그인
        token = await UserApi.instance.loginWithKakaoAccount();
      }

      return token.accessToken;
    } catch (e) {
      throw Exception('Kakao 로그인 실패: $e');
    }
  }

  /// Kakao 로그아웃
  static Future<void> logout() async {
    try {
      await UserApi.instance.logout();
    } catch (e) {
      throw Exception('Kakao 로그아웃 실패: $e');
    }
  }

  /// Kakao 연결 해제
  static Future<void> unlink() async {
    try {
      await UserApi.instance.unlink();
    } catch (e) {
      throw Exception('Kakao 연결 해제 실패: $e');
    }
  }

  /// 사용자 정보 조회 (디버그용)
  static Future<User?> getUserInfo() async {
    try {
      return await UserApi.instance.me();
    } catch (e) {
      return null;
    }
  }
}
