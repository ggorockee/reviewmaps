import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter/foundation.dart';

import '../models/auth_models.dart';
import '../config/config.dart';
import 'token_storage_service.dart';

/// AuthService
/// ------------------------------------------------------------
/// - 인증 관련 API 호출 전용 서비스
/// - 회원가입, 로그인, 토큰 갱신, 익명 로그인 등 지원
/// - 토큰 저장소와 연동하여 자동 토큰 관리
class AuthService {
  final String baseUrl;
  final String apiKey;
  late final http.Client _client;
  final TokenStorageService _tokenStorage = TokenStorageService();

  AuthService({
    String? baseUrl,
    String? apiKey,
  })  : baseUrl = baseUrl ?? AppConfig.ReviewMapbaseUrl,
        apiKey = apiKey ?? AppConfig.ReviewMapApiKey {
    final io = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 10);
    _client = IOClient(io);
  }

  /// 공통 헤더
  Map<String, String> get _headers => {
        'X-API-KEY': apiKey,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  /// 인증 헤더 (Bearer 토큰 포함)
  Future<Map<String, String>> _authHeaders() async {
    final accessToken = await _tokenStorage.getAccessToken();
    return {
      ..._headers,
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
    };
  }

  /// 디버깅 모드에서 API 응답 출력
  void _debugPrintResponse(String method, String url, http.Response response) {
    if (!AppConfig.isDebugMode) return;

    debugPrint('=== AUTH API DEBUG ===');
    debugPrint('Method: $method');
    debugPrint('URL: $url');
    debugPrint('Status Code: ${response.statusCode}');
    debugPrint('Response Body: ${response.body}');
    debugPrint('======================');
  }

  /// 리소스 정리
  void dispose() {
    _client.close();
  }

  /// 회원가입
  /// POST /v1/auth/signup
  /// - email, password를 받아 access_token, refresh_token 반환
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/signup');
    final request = SignUpRequest(email: email, password: password);

    try {
      final response = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 10));

      _debugPrintResponse('POST', uri.toString(), response);

      if (response.statusCode != 200 && response.statusCode != 201) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '회원가입할 수 없습니다. 잠시 후 다시 시도해 주세요.');
      }

      final authResponse =
          AuthResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));

      // 토큰 저장
      await _tokenStorage.saveAuthTokens(
        accessToken: authResponse.accessToken,
        refreshToken: authResponse.refreshToken,
      );

      return authResponse;
    } catch (e) {
      debugPrint('회원가입 오류: $e');
      rethrow;
    }
  }

  /// 로그인
  /// POST /v1/auth/login
  /// - email, password를 받아 access_token, refresh_token 반환
  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/login');
    final request = LoginRequest(email: email, password: password);

    try {
      final response = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 10));

      _debugPrintResponse('POST', uri.toString(), response);

      if (response.statusCode != 200) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '로그인할 수 없습니다. 잠시 후 다시 시도해 주세요.');
      }

      final authResponse =
          AuthResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));

      // 토큰 저장
      await _tokenStorage.saveAuthTokens(
        accessToken: authResponse.accessToken,
        refreshToken: authResponse.refreshToken,
      );

      return authResponse;
    } catch (e) {
      debugPrint('로그인 오류: $e');
      rethrow;
    }
  }

  /// 토큰 갱신
  /// POST /v1/auth/refresh
  /// - refresh_token을 받아 새로운 access_token, refresh_token 반환
  Future<AuthResponse> refreshToken() async {
    final uri = Uri.parse('$baseUrl/auth/refresh');
    final refreshToken = await _tokenStorage.getRefreshToken();

    if (refreshToken == null) {
      throw Exception('로그인이 만료되었습니다.\n다시 로그인해 주세요.');
    }

    final request = RefreshTokenRequest(refreshToken: refreshToken);

    try {
      final response = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 10));

      _debugPrintResponse('POST', uri.toString(), response);

      if (response.statusCode == 401) {
        // 인증 만료 - 사용자 친화적 메시지
        throw Exception('로그인이 만료되었습니다.\n다시 로그인해 주세요.');
      } else if (response.statusCode != 200) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '로그인 정보를 갱신할 수 없습니다.\n다시 로그인해 주세요.');
      }

      final authResponse =
          AuthResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));

      // 새로운 토큰 저장
      await _tokenStorage.saveAuthTokens(
        accessToken: authResponse.accessToken,
        refreshToken: authResponse.refreshToken,
      );

      return authResponse;
    } catch (e) {
      debugPrint('토큰 갱신 오류: $e');
      rethrow;
    }
  }

  /// 익명 로그인
  /// POST /v1/auth/anonymous
  /// - session_token 반환
  Future<AnonymousResponse> loginAnonymous() async {
    final uri = Uri.parse('$baseUrl/auth/anonymous');

    try {
      final response = await _client
          .post(
            uri,
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      _debugPrintResponse('POST', uri.toString(), response);

      if (response.statusCode != 200 && response.statusCode != 201) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '일시적인 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.');
      }

      final anonymousResponse =
          AnonymousResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));

      // 세션 토큰 저장
      await _tokenStorage.saveSessionToken(anonymousResponse.sessionToken);

      return anonymousResponse;
    } catch (e) {
      debugPrint('익명 로그인 오류: $e');
      rethrow;
    }
  }

  /// 익명 사용자 전환
  /// POST /v1/auth/convert-anonymous
  /// - session_token, email, password를 받아 access_token, refresh_token 반환
  Future<AuthResponse> convertAnonymous({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/convert-anonymous');
    final sessionToken = await _tokenStorage.getSessionToken();

    if (sessionToken == null) {
      throw Exception('이용 시간이 만료되었습니다.\n다시 시작해 주세요.');
    }

    final request = ConvertAnonymousRequest(
      sessionToken: sessionToken,
      email: email,
      password: password,
    );

    try {
      final response = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 10));

      _debugPrintResponse('POST', uri.toString(), response);

      if (response.statusCode != 200) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '계정 전환할 수 없습니다. 잠시 후 다시 시도해 주세요.');
      }

      final authResponse =
          AuthResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));

      // 토큰 저장 (익명 → 일반 사용자)
      await _tokenStorage.saveAuthTokens(
        accessToken: authResponse.accessToken,
        refreshToken: authResponse.refreshToken,
      );

      return authResponse;
    } catch (e) {
      debugPrint('익명 사용자 전환 오류: $e');
      rethrow;
    }
  }

  /// 사용자 정보 조회
  /// GET /v1/auth/me
  /// - 현재 로그인된 사용자 정보 반환
  Future<UserInfo> getUserInfo() async {
    final uri = Uri.parse('$baseUrl/auth/me');
    final headers = await _authHeaders();

    try {
      final response = await _client
          .get(
            uri,
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      _debugPrintResponse('GET', uri.toString(), response);

      if (response.statusCode == 401) {
        // 인증 만료 - 사용자 친화적 메시지
        throw Exception('로그인이 만료되었습니다.\n다시 로그인해 주세요.');
      } else if (response.statusCode != 200) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '사용자 정보를 불러올 수 없습니다.\n잠시 후 다시 시도해 주세요.');
      }

      return UserInfo.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (e) {
      debugPrint('사용자 정보 조회 오류: $e');
      rethrow;
    }
  }

  /// 익명 사용자 정보 조회
  /// GET /v1/auth/me
  /// - 익명 사용자의 세션 정보 반환 (session_id, expires_at, remaining_hours)
  Future<AnonymousUserInfo> getAnonymousUserInfo() async {
    final uri = Uri.parse('$baseUrl/auth/me');
    final sessionToken = await _tokenStorage.getSessionToken();

    if (sessionToken == null) {
      throw Exception('이용 시간이 만료되었습니다.\n다시 시작해 주세요.');
    }

    final headers = {
      ..._headers,
      'Authorization': 'Bearer $sessionToken',
    };

    try {
      final response = await _client
          .get(
            uri,
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      _debugPrintResponse('GET', uri.toString(), response);

      if (response.statusCode == 401) {
        // 세션 만료 - 사용자 친화적 메시지
        throw Exception('이용 시간이 만료되었습니다.\n다시 시작해 주세요.');
      } else if (response.statusCode != 200) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '사용자 정보를 불러올 수 없습니다.\n잠시 후 다시 시도해 주세요.');
      }

      return AnonymousUserInfo.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (e) {
      debugPrint('익명 사용자 정보 조회 오류: $e');
      rethrow;
    }
  }

  /// 로그아웃
  /// - 로컬 토큰 삭제
  Future<void> logout() async {
    await _tokenStorage.clearTokens();
  }

  /// 로그인 상태 확인
  Future<bool> isLoggedIn() async {
    return await _tokenStorage.isLoggedIn();
  }

  /// 익명 사용자 여부 확인
  Future<bool> isAnonymous() async {
    return await _tokenStorage.isAnonymous();
  }
}
