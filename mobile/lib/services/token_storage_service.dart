import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT 페이로드 디코딩 유틸리티
Map<String, dynamic>? decodeJwtPayload(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;

    final payload = parts[1];
    // Base64 URL 디코딩
    final normalized = base64Url.normalize(payload);
    final decoded = utf8.decode(base64Url.decode(normalized));
    return jsonDecode(decoded) as Map<String, dynamic>;
  } catch (e) {
    debugPrint('[JWT] 디코딩 실패: $e');
    return null;
  }
}

/// TokenStorageService
/// ------------------------------------------------------------
/// - FlutterSecureStorage를 사용한 보안 토큰 저장/로드 서비스
/// - iOS Keychain / Android Keystore를 활용한 안전한 토큰 관리
/// - 인증 토큰(access_token, refresh_token) 및 익명 세션 토큰 관리
/// - 로그아웃 시 모든 토큰 삭제
/// - 토큰 만료 전 자동 갱신 지원
class TokenStorageService {
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _sessionTokenKey = 'session_token';
  static const String _isAnonymousKey = 'is_anonymous';

  // FlutterSecureStorage 인스턴스 (Singleton)
  static final _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true, // Android: EncryptedSharedPreferences 사용
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock, // iOS: 첫 잠금 해제 후 접근 가능
    ),
  );

  /// Access Token 저장
  Future<void> saveAccessToken(String token) async {
    await _storage.write(key: _accessTokenKey, value: token);
  }

  /// Refresh Token 저장
  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _refreshTokenKey, value: token);
  }

  /// 인증 토큰 쌍(access + refresh) 저장
  Future<void> saveAuthTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _storage.write(key: _isAnonymousKey, value: 'false');
  }

  /// 익명 세션 토큰 저장
  Future<void> saveSessionToken(String token) async {
    await _storage.write(key: _sessionTokenKey, value: token);
    await _storage.write(key: _isAnonymousKey, value: 'true');
  }

  /// Access Token 조회
  Future<String?> getAccessToken() async {
    return await _storage.read(key: _accessTokenKey);
  }

  /// Refresh Token 조회
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _refreshTokenKey);
  }

  /// 익명 세션 토큰 조회
  Future<String?> getSessionToken() async {
    return await _storage.read(key: _sessionTokenKey);
  }

  /// 익명 사용자 여부 확인
  Future<bool> isAnonymous() async {
    final value = await _storage.read(key: _isAnonymousKey);
    return value == 'true';
  }

  /// 로그인 상태 확인 (토큰 존재 여부)
  Future<bool> isLoggedIn() async {
    final accessToken = await getAccessToken();
    final sessionToken = await getSessionToken();
    return accessToken != null || sessionToken != null;
  }

  /// 모든 토큰 삭제 (로그아웃)
  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _sessionTokenKey);
    await _storage.delete(key: _isAnonymousKey);
  }

  /// Access Token 만료 임박 여부 확인
  /// - 만료 5분 전이면 true 반환
  /// - 토큰이 없거나 디코딩 실패 시 false 반환
  Future<bool> isAccessTokenExpiringSoon({int thresholdMinutes = 5}) async {
    final token = await getAccessToken();
    if (token == null) return false;

    final payload = decodeJwtPayload(token);
    final exp = payload?['exp'] as int?;
    if (exp == null) return false;

    final expDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    final refreshThreshold = expDate.subtract(Duration(minutes: thresholdMinutes));

    return DateTime.now().isAfter(refreshThreshold);
  }

  /// Access Token 만료 여부 확인
  /// - 이미 만료되었으면 true 반환
  Future<bool> isAccessTokenExpired() async {
    final token = await getAccessToken();
    if (token == null) return true;

    final payload = decodeJwtPayload(token);
    final exp = payload?['exp'] as int?;
    if (exp == null) return false;

    final expDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    return DateTime.now().isAfter(expDate);
  }

  /// Access Token 남은 시간 (분) 조회
  /// - 토큰이 없거나 만료되었으면 null 반환
  Future<int?> getAccessTokenRemainingMinutes() async {
    final token = await getAccessToken();
    if (token == null) return null;

    final payload = decodeJwtPayload(token);
    final exp = payload?['exp'] as int?;
    if (exp == null) return null;

    final expDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    final remaining = expDate.difference(DateTime.now()).inMinutes;

    return remaining > 0 ? remaining : null;
  }
}
