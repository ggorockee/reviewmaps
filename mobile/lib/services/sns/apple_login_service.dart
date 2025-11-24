import 'dart:convert';
import 'dart:math';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';

/// Apple 소셜 로그인 서비스
class AppleLoginService {
  /// Apple 로그인 실행
  /// - 반환값: Map containing identity_token and authorization_code
  /// - 예외: Exception
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
    } catch (e) {
      final errorString = e.toString();
      if (errorString.contains('취소')) {
        rethrow;
      }
      // error 1000 처리
      if (errorString.contains('error 1000')) {
        throw Exception('Apple 로그인 설정이 필요합니다.\nXcode에서 Sign In with Apple을 활성화해주세요.');
      }
      throw Exception('Apple 로그인 실패: $e');
    }
  }

  /// nonce 생성
  static String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  /// SHA256 해시 생성
  static String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Apple 로그인 가능 여부 확인
  static Future<bool> isAvailable() async {
    return await SignInWithApple.isAvailable();
  }
}
