import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mobile/config/config.dart';
import 'package:mobile/models/keyword_models.dart';
import 'package:mobile/services/token_storage_service.dart';
import 'package:mobile/utils/network_error_handler.dart';

/// 키워드 알람 서비스
/// - 키워드 등록, 조회, 삭제
/// - 알람 조회 및 읽음 처리
/// - 네트워크 재시도 로직 포함
class KeywordService {
  final String baseUrl = '${AppConfig.reviewMapBaseUrl}/keyword-alerts';
  late final http.Client _client;
  final TokenStorageService _tokenStorage = TokenStorageService();

  final Map<String, String> _headers = {
    'Content-Type': 'application/json; charset=utf-8',
    'X-API-KEY': AppConfig.reviewMapApiKey,
  };

  KeywordService() {
    final io = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 10);
    _client = IOClient(io);
  }

  /// 디버그 출력
  void _debugPrintResponse(String method, String url, http.Response response) {
    if (!AppConfig.isDebugMode) return;
    debugPrint('[$method] $url');
    debugPrint('Status: ${response.statusCode}');
    debugPrint('Response: ${utf8.decode(response.bodyBytes)}');
  }

  /// 인증 헤더 생성
  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await _tokenStorage.getAccessToken() ??
                  await _tokenStorage.getSessionToken();

    if (token == null) {
      throw Exception('로그인이 필요합니다.');
    }

    return {
      ..._headers,
      'Authorization': 'Bearer $token',
    };
  }

  /// 공통 리트라이 래퍼 (지수적 백오프)
  Future<T> _withRetry<T>(Future<T> Function() task, {int retries = 3}) async {
    int attempt = 0;
    Object? lastErr;
    while (attempt < retries) {
      try {
        return await task();
      } catch (e) {
        lastErr = e;
        // 재시도 가능한 에러인 경우에만 재시도
        if (!NetworkErrorHandler.isRetryableError(e)) {
          rethrow;
        }
        // 0.5s, 1s, 2s …
        final delay = Duration(milliseconds: 500 * (1 << attempt));
        await Future.delayed(delay);
        attempt++;
        debugPrint('[KeywordService] 재시도 $attempt/$retries (${delay.inMilliseconds}ms 후)');
      }
    }
    throw lastErr ?? Exception('알 수 없는 오류가 발생했습니다.');
  }

  /// HTTP 응답 에러 처리
  void _handleHttpError(http.Response response, String defaultMessage) {
    try {
      final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
      final serverMessage = errorBody['detail'] as String?;
      throw Exception(
        NetworkErrorHandler.getHttpErrorMessage(
          response.statusCode,
          serverMessage: serverMessage,
        ),
      );
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception(
        NetworkErrorHandler.getHttpErrorMessage(response.statusCode)
      );
    }
  }

  /// 키워드 등록
  /// POST /v1/keyword-alerts/keywords
  Future<KeywordInfo> registerKeyword(String keyword) async {
    final uri = Uri.parse('$baseUrl/keywords');
    final headers = await _getAuthHeaders();
    final request = KeywordRegisterRequest(keyword: keyword);

    return _withRetry(() async {
      try {
        final response = await _client
            .post(
              uri,
              headers: headers,
              body: jsonEncode(request.toJson()),
            )
            .timeout(const Duration(seconds: 10));

        _debugPrintResponse('POST', uri.toString(), response);

        if (response.statusCode != 200 && response.statusCode != 201) {
          _handleHttpError(response, '키워드를 등록할 수 없습니다.');
        }

        return KeywordInfo.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      } catch (e) {
        if (e is Exception && e.toString().contains('Exception:')) {
          rethrow;
        }
        throw Exception(NetworkErrorHandler.getErrorMessage(e));
      }
    });
  }

  /// 내 키워드 목록 조회
  /// GET /v1/keyword-alerts/keywords
  Future<List<KeywordInfo>> getMyKeywords() async {
    final uri = Uri.parse('$baseUrl/keywords');
    final headers = await _getAuthHeaders();

    return _withRetry(() async {
      try {
        final response = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 10));

        _debugPrintResponse('GET', uri.toString(), response);

        if (response.statusCode != 200) {
          _handleHttpError(response, '키워드 목록을 불러올 수 없습니다.');
        }

        final keywordList = KeywordListResponse.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)),
        );
        return keywordList.keywords;
      } catch (e) {
        if (e is Exception && e.toString().contains('Exception:')) {
          rethrow;
        }
        throw Exception(NetworkErrorHandler.getErrorMessage(e));
      }
    });
  }

  /// 키워드 삭제
  /// DELETE /v1/keyword-alerts/keywords/{keyword_id}
  Future<void> deleteKeyword(int keywordId) async {
    final uri = Uri.parse('$baseUrl/keywords/$keywordId');
    final headers = await _getAuthHeaders();

    return _withRetry(() async {
      try {
        final response = await _client
            .delete(uri, headers: headers)
            .timeout(const Duration(seconds: 10));

        _debugPrintResponse('DELETE', uri.toString(), response);

        // 200 OK 또는 204 No Content 모두 성공
        if (response.statusCode != 200 && response.statusCode != 204) {
          _handleHttpError(response, '키워드를 삭제할 수 없습니다.');
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('Exception:')) {
          rethrow;
        }
        throw Exception(NetworkErrorHandler.getErrorMessage(e));
      }
    });
  }

  /// 내 알람 목록 조회
  /// GET /v1/keyword-alerts/alerts
  /// - isRead: 읽음/안읽음 필터
  /// - lat, lng: 사용자 위치 (거리 계산용)
  /// - sort: 정렬 기준 (created_at: 최신순, distance: 가까운순)
  Future<AlertListResponse> getMyAlerts({
    bool? isRead,
    double? lat,
    double? lng,
    String sort = 'created_at',
  }) async {
    final queryParams = <String, String>{};
    if (isRead != null) {
      queryParams['is_read'] = isRead.toString();
    }
    if (lat != null) {
      queryParams['lat'] = lat.toString();
    }
    if (lng != null) {
      queryParams['lng'] = lng.toString();
    }
    queryParams['sort'] = sort;

    final uri = Uri.parse('$baseUrl/alerts').replace(queryParameters: queryParams);
    final headers = await _getAuthHeaders();

    return _withRetry(() async {
      try {
        final response = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 10));

        _debugPrintResponse('GET', uri.toString(), response);

        if (response.statusCode != 200) {
          _handleHttpError(response, '알람 목록을 불러올 수 없습니다.');
        }

        return AlertListResponse.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)),
        );
      } catch (e) {
        if (e is Exception && e.toString().contains('Exception:')) {
          rethrow;
        }
        throw Exception(NetworkErrorHandler.getErrorMessage(e));
      }
    });
  }

  /// 알람 삭제
  /// DELETE /v1/keyword-alerts/alerts/{alert_id}
  Future<void> deleteAlert(int alertId) async {
    final uri = Uri.parse('$baseUrl/alerts/$alertId');
    final headers = await _getAuthHeaders();

    return _withRetry(() async {
      try {
        final response = await _client
            .delete(uri, headers: headers)
            .timeout(const Duration(seconds: 10));

        _debugPrintResponse('DELETE', uri.toString(), response);

        // 200 OK 또는 204 No Content 모두 성공
        if (response.statusCode != 200 && response.statusCode != 204) {
          _handleHttpError(response, '알람을 삭제할 수 없습니다.');
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('Exception:')) {
          rethrow;
        }
        throw Exception(NetworkErrorHandler.getErrorMessage(e));
      }
    });
  }

  /// 알람 읽음 처리
  /// POST /v1/keyword-alerts/alerts/read
  Future<void> markAlertsAsRead(List<int> alertIds) async {
    final uri = Uri.parse('$baseUrl/alerts/read');
    final headers = await _getAuthHeaders();
    final request = MarkAlertsReadRequest(alertIds: alertIds);

    return _withRetry(() async {
      try {
        final response = await _client
            .post(
              uri,
              headers: headers,
              body: jsonEncode(request.toJson()),
            )
            .timeout(const Duration(seconds: 10));

        _debugPrintResponse('POST', uri.toString(), response);

        if (response.statusCode != 200) {
          _handleHttpError(response, '알람을 읽음 처리할 수 없습니다.');
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('Exception:')) {
          rethrow;
        }
        throw Exception(NetworkErrorHandler.getErrorMessage(e));
      }
    });
  }

  /// 키워드 활성화/비활성화 토글
  /// PATCH /v1/keyword-alerts/keywords/{keyword_id}/toggle
  Future<KeywordInfo> toggleKeyword(int keywordId) async {
    final uri = Uri.parse('$baseUrl/keywords/$keywordId/toggle');
    final headers = await _getAuthHeaders();

    return _withRetry(() async {
      try {
        final response = await _client
            .patch(uri, headers: headers)
            .timeout(const Duration(seconds: 10));

        _debugPrintResponse('PATCH', uri.toString(), response);

        if (response.statusCode != 200) {
          _handleHttpError(response, '키워드 상태를 변경할 수 없습니다.');
        }

        return KeywordInfo.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      } catch (e) {
        if (e is Exception && e.toString().contains('Exception:')) {
          rethrow;
        }
        throw Exception(NetworkErrorHandler.getErrorMessage(e));
      }
    });
  }

  /// FCM 디바이스 토큰 등록
  /// POST /v1/keyword-alerts/fcm/register
  Future<void> registerFcmToken(String fcmToken, String deviceType) async {
    final uri = Uri.parse('$baseUrl/fcm/register');
    final headers = await _getAuthHeaders();

    return _withRetry(() async {
      try {
        final response = await _client
            .post(
              uri,
              headers: headers,
              body: jsonEncode({
                'fcm_token': fcmToken,
                'device_type': deviceType,
              }),
            )
            .timeout(const Duration(seconds: 10));

        _debugPrintResponse('POST', uri.toString(), response);

        if (response.statusCode != 200 && response.statusCode != 201) {
          _handleHttpError(response, 'FCM 토큰 등록에 실패했습니다.');
        }

        debugPrint('FCM 토큰 등록 성공');
      } catch (e) {
        if (e is Exception && e.toString().contains('Exception:')) {
          rethrow;
        }
        throw Exception(NetworkErrorHandler.getErrorMessage(e));
      }
    });
  }

  /// FCM 디바이스 토큰 해제
  /// DELETE /v1/keyword-alerts/fcm/unregister
  Future<void> unregisterFcmToken(String fcmToken) async {
    final uri = Uri.parse('$baseUrl/fcm/unregister').replace(
      queryParameters: {'fcm_token': fcmToken},
    );
    final headers = await _getAuthHeaders();

    return _withRetry(() async {
      try {
        final response = await _client
            .delete(uri, headers: headers)
            .timeout(const Duration(seconds: 10));

        _debugPrintResponse('DELETE', uri.toString(), response);

        // 200 OK 또는 204 No Content 모두 성공
        if (response.statusCode != 200 && response.statusCode != 204) {
          _handleHttpError(response, 'FCM 토큰 해제에 실패했습니다.');
        }

        debugPrint('FCM 토큰 해제 성공');
      } catch (e) {
        if (e is Exception && e.toString().contains('Exception:')) {
          rethrow;
        }
        throw Exception(NetworkErrorHandler.getErrorMessage(e));
      }
    });
  }

  void dispose() {
    _client.close();
  }
}
