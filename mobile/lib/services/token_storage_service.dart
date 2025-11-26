import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
/// - SharedPreferences를 사용한 토큰 저장/로드 서비스
/// - 인증 토큰(access_token, refresh_token) 및 익명 세션 토큰 관리
/// - 로그아웃 시 모든 토큰 삭제
/// - 토큰 만료 전 자동 갱신 지원
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
