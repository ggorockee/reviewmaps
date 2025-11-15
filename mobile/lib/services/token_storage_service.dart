import 'package:shared_preferences/shared_preferences.dart';

/// TokenStorageService
/// ------------------------------------------------------------
/// - SharedPreferences를 사용한 토큰 저장/로드 서비스
/// - 인증 토큰(access_token, refresh_token) 및 익명 세션 토큰 관리
/// - 로그아웃 시 모든 토큰 삭제
class TokenStorageService {
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _sessionTokenKey = 'session_token';
  static const String _isAnonymousKey = 'is_anonymous';

  /// Access Token 저장
  Future<void> saveAccessToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, token);
  }

  /// Refresh Token 저장
  Future<void> saveRefreshToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_refreshTokenKey, token);
  }

  /// 인증 토큰 쌍(access + refresh) 저장
  Future<void> saveAuthTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
    await prefs.setBool(_isAnonymousKey, false);
  }

  /// 익명 세션 토큰 저장
  Future<void> saveSessionToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionTokenKey, token);
    await prefs.setBool(_isAnonymousKey, true);
  }

  /// Access Token 조회
  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  /// Refresh Token 조회
  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  /// 익명 세션 토큰 조회
  Future<String?> getSessionToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionTokenKey);
  }

  /// 익명 사용자 여부 확인
  Future<bool> isAnonymous() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isAnonymousKey) ?? false;
  }

  /// 로그인 상태 확인 (토큰 존재 여부)
  Future<bool> isLoggedIn() async {
    final accessToken = await getAccessToken();
    final sessionToken = await getSessionToken();
    return accessToken != null || sessionToken != null;
  }

  /// 모든 토큰 삭제 (로그아웃)
  Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_sessionTokenKey);
    await prefs.remove(_isAnonymousKey);
  }
}
