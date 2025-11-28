import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter/foundation.dart';

import '../models/auth_models.dart';
import '../config/config.dart';
import 'token_storage_service.dart';

// JWT 디코딩은 token_storage_service.dart의 decodeJwtPayload 함수 사용

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
  })  : baseUrl = baseUrl ?? AppConfig.reviewMapBaseUrl,
        apiKey = apiKey ?? AppConfig.reviewMapApiKey {
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

  /// 이메일 인증코드 발송
  /// POST /v1/auth/email/send-code
  /// - 6자리 인증코드 이메일 발송
  /// - 유효시간: 60분
  /// - 재발송: 첫 번째는 바로 가능, 이후 60초 대기
  Future<EmailSendCodeResponse> sendEmailCode({required String email}) async {
    final uri = Uri.parse('$baseUrl/auth/email/send-code');
    final request = EmailSendCodeRequest(email: email);

    try {
      final response = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 30));

      _debugPrintResponse('POST', uri.toString(), response);

      if (response.statusCode == 429) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '잠시 후 다시 시도해 주세요.');
      }

      if (response.statusCode != 200) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '인증코드를 발송할 수 없습니다. 잠시 후 다시 시도해 주세요.');
      }

      return EmailSendCodeResponse.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (e) {
      debugPrint('이메일 인증코드 발송 오류: $e');
      rethrow;
    }
  }

  /// 이메일 인증코드 확인
  /// POST /v1/auth/email/verify-code
  /// - 인증코드 검증 후 verification_token 반환
  /// - 5회 실패 시 재발송 필요
  Future<EmailVerifyCodeResponse> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/email/verify-code');
    final request = EmailVerifyCodeRequest(email: email, code: code);

    try {
      final response = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 10));

      _debugPrintResponse('POST', uri.toString(), response);

      if (response.statusCode == 429) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '인증 시도 횟수를 초과했습니다. 인증코드를 다시 요청해 주세요.');
      }

      if (response.statusCode != 200) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '인증코드가 올바르지 않습니다.');
      }

      return EmailVerifyCodeResponse.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (e) {
      debugPrint('이메일 인증코드 확인 오류: $e');
      rethrow;
    }
  }

  /// 회원가입
  /// POST /v1/auth/signup
  /// - 이메일 인증 완료 후 회원가입
  /// - verification_token 필수
  /// - 비밀번호 8자 이상
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? name,
    required String verificationToken,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/signup');
    final request = SignUpRequest(
      email: email,
      password: password,
      name: name,
      verificationToken: verificationToken,
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

  /// Kakao 로그인
  /// POST /v1/auth/kakao
  /// - Kakao SDK에서 받은 access_token으로 로그인
  Future<AuthResponse> kakaoLogin(String accessToken) async {
    final uri = Uri.parse('$baseUrl/auth/kakao');
    final request = KakaoLoginRequest(accessToken: accessToken);

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
        throw Exception(errorBody['detail'] ?? '카카오 로그인 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.');
      }

      final authResponse =
          AuthResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));

      // JWT 페이로드 디버깅
      if (kDebugMode) {
        debugPrint('[AuthService] JWT 페이로드 디코딩 시작');
        final payload = decodeJwtPayload(authResponse.accessToken);
        if (payload != null) {
          debugPrint('[AuthService] JWT 내용:');
          debugPrint('[AuthService]   - user_id: ${payload['user_id'] ?? payload['sub']}');
          debugPrint('[AuthService]   - email: ${payload['email']}');
          debugPrint('[AuthService]   - exp: ${payload['exp']} (만료시간)');
          if (payload['exp'] != null) {
            final expDate = DateTime.fromMillisecondsSinceEpoch(payload['exp'] * 1000);
            final now = DateTime.now();
            debugPrint('[AuthService]   - 만료일시: $expDate');
            debugPrint('[AuthService]   - 현재시각: $now');
            debugPrint('[AuthService]   - 남은시간: ${expDate.difference(now).inMinutes}분');
          }
        }
      }

      // 토큰 저장
      await _tokenStorage.saveAuthTokens(
        accessToken: authResponse.accessToken,
        refreshToken: authResponse.refreshToken,
      );

      return authResponse;
    } catch (e) {
      debugPrint('Kakao 로그인 오류: $e');
      rethrow;
    }
  }

  /// Google 로그인
  /// POST /v1/auth/google
  /// - Google SDK에서 받은 access_token으로 로그인
  Future<AuthResponse> googleLogin(String accessToken) async {
    final uri = Uri.parse('$baseUrl/auth/google');
    final request = GoogleLoginRequest(accessToken: accessToken);

    debugPrint('[AuthService] Google 로그인 시작');
    debugPrint('[AuthService] URL: $uri');
    debugPrint('[AuthService] Access Token: ${accessToken.substring(0, 20)}...');

    try {
      final response = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('[AuthService] Google 응답 상태: ${response.statusCode}');
      debugPrint('[AuthService] Google 응답 본문: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...');

      _debugPrintResponse('POST', uri.toString(), response);

      if (response.statusCode != 200 && response.statusCode != 201) {
        // HTML 응답 감지 (서버 에러 페이지)
        final bodyString = utf8.decode(response.bodyBytes);
        if (bodyString.contains('<!doctype') || bodyString.contains('<html')) {
          debugPrint('[AuthService] 서버가 HTML 에러 페이지 반환 - 상태: ${response.statusCode}');
          throw Exception('Google 로그인 서버 오류가 발생했습니다.\n잠시 후 다시 시도해 주세요. (${response.statusCode})');
        }
        final errorBody = jsonDecode(bodyString);
        throw Exception(errorBody['detail'] ?? 'Google 로그인 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.');
      }

      final authResponse =
          AuthResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));

      // JWT 페이로드 디버깅
      if (kDebugMode) {
        debugPrint('[AuthService] Google JWT 페이로드 디코딩 시작');
        final payload = decodeJwtPayload(authResponse.accessToken);
        if (payload != null) {
          debugPrint('[AuthService] JWT 내용:');
          debugPrint('[AuthService]   - user_id: ${payload['user_id'] ?? payload['sub']}');
          debugPrint('[AuthService]   - exp: ${payload['exp']} (만료시간)');
        }
      }

      // 토큰 저장
      await _tokenStorage.saveAuthTokens(
        accessToken: authResponse.accessToken,
        refreshToken: authResponse.refreshToken,
      );

      return authResponse;
    } catch (e) {
      debugPrint('Google 로그인 오류: $e');
      rethrow;
    }
  }

  /// Apple 로그인
  /// POST /v1/auth/apple
  /// - Apple Sign In에서 받은 identity_token으로 로그인
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

      _debugPrintResponse('POST', uri.toString(), response);

      if (response.statusCode != 200 && response.statusCode != 201) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? 'Apple 로그인 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.');
      }

      final authResponse =
          AuthResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));

      // JWT 페이로드 디버깅
      if (kDebugMode) {
        debugPrint('[AuthService] Apple JWT 페이로드 디코딩 시작');
        final payload = decodeJwtPayload(authResponse.accessToken);
        if (payload != null) {
          debugPrint('[AuthService] JWT 내용:');
          debugPrint('[AuthService]   - user_id: ${payload['user_id'] ?? payload['sub']}');
          debugPrint('[AuthService]   - exp: ${payload['exp']} (만료시간)');
        }
      }

      // 토큰 저장
      await _tokenStorage.saveAuthTokens(
        accessToken: authResponse.accessToken,
        refreshToken: authResponse.refreshToken,
      );

      return authResponse;
    } catch (e) {
      debugPrint('Apple 로그인 오류: $e');
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
      debugPrint('[AuthService] getUserInfo 호출');
      debugPrint('[AuthService] URL: $uri');
      debugPrint('[AuthService] Headers: ${headers.keys.join(", ")}');
      if (headers['Authorization'] != null) {
        debugPrint('[AuthService] Authorization 헤더: ${headers['Authorization']!.substring(0, 50)}...');
      }

      final response = await _client
          .get(
            uri,
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('[AuthService] 응답 상태 코드: ${response.statusCode}');
      debugPrint('[AuthService] 응답 본문: ${response.body}');

      _debugPrintResponse('GET', uri.toString(), response);

      if (response.statusCode == 401) {
        // 서버의 실제 에러 메시지 파싱 시도
        try {
          final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
          final serverMessage = errorBody['detail'] ?? '로그인이 만료되었습니다.\n다시 로그인해 주세요.';
          debugPrint('[AuthService] 서버 에러 메시지: $serverMessage');
          throw Exception(serverMessage);
        } catch (parseError) {
          // JSON 파싱 실패 시 기본 메시지
          debugPrint('[AuthService] 401 에러 - JSON 파싱 실패: $parseError');
          throw Exception('로그인이 만료되었습니다.\n다시 로그인해 주세요.');
        }
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

  /// 회원 탈퇴
  /// DELETE /v1/auth/me
  /// - 계정 비활성화 (Soft delete)
  /// - 연결된 SNS 계정 삭제
  Future<void> deleteAccount({String? reason}) async {
    final uri = Uri.parse('$baseUrl/auth/me');
    final headers = await _authHeaders();

    try {
      debugPrint('[AuthService] deleteAccount 호출');
      debugPrint('[AuthService] URL: $uri');

      final body = reason != null ? jsonEncode({'reason': reason}) : null;

      final response = await _client
          .delete(
            uri,
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      _debugPrintResponse('DELETE', uri.toString(), response);

      if (response.statusCode == 401) {
        throw Exception('로그인이 만료되었습니다.\n다시 로그인해 주세요.');
      } else if (response.statusCode != 200) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '회원 탈퇴 처리 중 오류가 발생했습니다.');
      }

      // 탈퇴 성공 - 로컬 토큰 삭제
      await _tokenStorage.clearTokens();

      debugPrint('[AuthService] 회원 탈퇴 완료');
    } catch (e) {
      debugPrint('회원 탈퇴 오류: $e');
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

  /// 저장된 Access Token 조회 (디버깅용)
  Future<String?> getStoredAccessToken() async {
    return await _tokenStorage.getAccessToken();
  }

  /// 저장된 Refresh Token 조회 (디버깅용)
  Future<String?> getStoredRefreshToken() async {
    return await _tokenStorage.getRefreshToken();
  }

  /// 유효한 Access Token 조회 (자동 갱신 포함)
  /// - 만료 5분 전이면 자동으로 토큰 갱신
  /// - 갱신 실패 시 null 반환 (재로그인 필요)
  /// - API 호출 전에 이 메서드를 사용하여 유효한 토큰 확보
  Future<String?> getValidAccessToken() async {
    final token = await _tokenStorage.getAccessToken();
    if (token == null) return null;

    // 익명 사용자는 Access Token 자동 갱신 대상 아님
    final isAnonymousUser = await _tokenStorage.isAnonymous();
    if (isAnonymousUser) {
      return await _tokenStorage.getSessionToken();
    }

    // 토큰 만료 임박 여부 확인 (5분 전)
    final isExpiringSoon = await _tokenStorage.isAccessTokenExpiringSoon(thresholdMinutes: 5);

    if (isExpiringSoon) {
      debugPrint('[AuthService] Access Token 만료 임박 - 자동 갱신 시도');

      try {
        await refreshToken();
        debugPrint('[AuthService] Access Token 자동 갱신 성공');
        return await _tokenStorage.getAccessToken();
      } catch (e) {
        debugPrint('[AuthService] Access Token 자동 갱신 실패: $e');
        // 갱신 실패해도 기존 토큰이 아직 유효할 수 있으므로 반환
        final isExpired = await _tokenStorage.isAccessTokenExpired();
        if (!isExpired) {
          return token;
        }
        // 완전히 만료되었으면 null 반환 (재로그인 필요)
        return null;
      }
    }

    return token;
  }

  /// 인증 헤더 조회 (자동 갱신 포함)
  /// - getValidAccessToken을 사용하여 유효한 토큰으로 헤더 생성
  /// - API 호출 시 이 메서드 사용 권장
  Future<Map<String, String>> getValidAuthHeaders() async {
    final accessToken = await getValidAccessToken();
    return {
      ..._headers,
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
    };
  }

  // ===== 비밀번호 재설정 API =====

  /// 비밀번호 재설정 요청 (인증코드 발송)
  /// POST /v1/auth/password/reset-request
  /// - 가입된 이메일(email 로그인)로 6자리 인증코드 발송
  /// - 유효시간: 60분
  Future<PasswordResetResponse> passwordResetRequest({
    required String email,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/password/reset-request');
    final request = PasswordResetRequest(email: email);

    try {
      final response = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 30));

      _debugPrintResponse('POST', uri.toString(), response);

      if (response.statusCode == 429) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '잠시 후 다시 시도해 주세요.');
      }

      if (response.statusCode != 200) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(
            errorBody['detail'] ?? '인증코드를 발송할 수 없습니다. 잠시 후 다시 시도해 주세요.');
      }

      return PasswordResetResponse.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('네트워크 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.');
    }
  }

  /// 비밀번호 재설정 인증코드 확인
  /// POST /v1/auth/password/reset-verify
  /// - 인증코드 확인 후 reset_token 발급
  /// - 5회 실패 시 재요청 필요
  Future<PasswordResetVerifyResponse> passwordResetVerify({
    required String email,
    required String code,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/password/reset-verify');
    final request = PasswordResetVerifyRequest(email: email, code: code);

    try {
      final response = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 30));

      _debugPrintResponse('POST', uri.toString(), response);

      if (response.statusCode == 429) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '인증 시도 횟수를 초과했습니다.');
      }

      if (response.statusCode != 200) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '인증코드를 확인할 수 없습니다.');
      }

      return PasswordResetVerifyResponse.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('네트워크 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.');
    }
  }

  /// 비밀번호 재설정 확정 (새 비밀번호 설정)
  /// POST /v1/auth/password/reset-confirm
  /// - reset_token으로 검증 후 새 비밀번호 설정
  /// - 비밀번호 8자 이상
  Future<MessageResponse> passwordResetConfirm({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/password/reset-confirm');
    final request = PasswordResetConfirmRequest(
      email: email,
      resetToken: resetToken,
      newPassword: newPassword,
    );

    try {
      final response = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 30));

      _debugPrintResponse('POST', uri.toString(), response);

      if (response.statusCode != 200) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '비밀번호를 변경할 수 없습니다.');
      }

      return MessageResponse.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('네트워크 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.');
    }
  }

  /// 비밀번호 변경 (로그인한 사용자)
  /// POST /v1/auth/password/change
  /// - Authorization 헤더 필수
  /// - 현재 비밀번호 확인 후 변경
  Future<MessageResponse> passwordChange({
    required String currentPassword,
    required String newPassword,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/password/change');
    final request = PasswordChangeRequest(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );

    try {
      final headers = await getValidAuthHeaders();
      final response = await _client
          .post(
            uri,
            headers: headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 30));

      _debugPrintResponse('POST', uri.toString(), response);

      if (response.statusCode == 401) {
        throw Exception('로그인이 필요합니다.');
      }

      if (response.statusCode != 200) {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? '비밀번호를 변경할 수 없습니다.');
      }

      return MessageResponse.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('네트워크 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.');
    }
  }
}
