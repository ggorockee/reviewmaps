// lib/services/campaign_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter/foundation.dart';

import '../models/store_model.dart';
import '../config/config.dart';
import '../utils/network_error_handler.dart';
import 'package:geolocator/geolocator.dart';


/// CampaignService
/// ------------------------------------------------------------
/// - API 엔드포인트 호출 전용 서비스(순수 데이터 계층)
/// - 배포 기준: 콘솔 로그/프린트 전부 제거(무소음)
/// - 공통 타임아웃/리트라이 적용으로 네트워크 탄성 확보
/// - 예외는 상위(UI)에서 스낵바 등으로 사용자 친화 처리
class CampaignService {
  final String baseUrl;
  final String apiKey;
  late final http.Client _client;

  CampaignService(this.baseUrl, {required this.apiKey}) {
    // 플랫폼 간 일관된 소켓 타임아웃 설정
    final io = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..idleTimeout = const Duration(seconds: 3);
    _client = IOClient(io);
  }

  /// 공통 헤더
  Map<String, String> get _headers => {
    'X-API-KEY': apiKey,
    'Accept': 'application/json',
    // 서버 트래픽 구분용 User-Agent (필요 시 변경)
    'User-Agent': 'review-maps-app/1.0 (Flutter; iOS/Android)',
  };

  /// 디버깅 모드에서 API 응답 출력
  void _debugPrintResponse(String method, String url, Map<String, String>? queryParams, http.Response response) {
    if (!AppConfig.isDebugMode) return;
    
    debugPrint('=== API DEBUG ===');
    debugPrint('Method: $method');
    debugPrint('URL: $url');
    if (queryParams != null && queryParams.isNotEmpty) {
      debugPrint('Query Params: $queryParams');
    }
    debugPrint('Status Code: ${response.statusCode}');
    debugPrint('Response Headers: ${response.headers}');
    debugPrint('Response Body: ${response.body}');
    debugPrint('==================');
  }

  /// 리소스 정리(앱 종료/DI 스코프 해제 시 호출 권장)
  void dispose() {
    _client.close();
  }

  /// 헬스 체크: 네트워크/백엔드 가용성 간단 점검
  /// - 성공: true, 실패: false
  /// - 배포: 로깅 없이 결과만 반환
  Future<bool> healthCheck() async {
    try {
      // 1) DNS 확인(플랫폼 네트워크 스택 정상 여부)
      await InternetAddress.lookup('api.review-maps.com');
    } catch (_) {
      // DNS 실패
      return false;
    }

    try {
      // 2) 백엔드 헬스 엔드포인트
      final r = await _client
          .get(Uri.parse('$baseUrl/healthz'), headers: _headers)
          .timeout(const Duration(seconds: 3));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 공통 리트라이 래퍼(지수적 백오프)
  Future<T> _withRetry<T>(Future<T> Function() task, {int retries = 3}) async {
    int attempt = 0;
    Object? lastErr;
    while (attempt < retries) {
      try {
        return await task();
      } catch (e) {
        lastErr = e;
        // 재시도 가능한 에러가 아니면 즉시 종료
        if (!NetworkErrorHandler.isRetryableError(e)) {
          throw Exception(NetworkErrorHandler.getErrorMessage(e));
        }
        // 0.4s, 0.8s, 1.6s …
        final delay = Duration(milliseconds: 400 * (1 << attempt));
        await Future.delayed(delay);
        attempt++;
        debugPrint('[CampaignService] 재시도 $attempt/$retries');
      }
    }
    throw Exception(NetworkErrorHandler.getErrorMessage(lastErr ?? '알 수 없는 오류가 발생했습니다.'));
  }

  /// 공통: 응답 검사 + JSON 파싱 + items 배열 추출
  List<dynamic> _parseItemsOrThrow(http.Response r, {String context = ''}) {
    if (r.statusCode != 200) {
      throw Exception(NetworkErrorHandler.getHttpErrorMessage(r.statusCode));
    }
    final decoded = jsonDecode(utf8.decode(r.bodyBytes));
    final List items =
    (decoded is Map && decoded['items'] is List) ? decoded['items'] : [];
    return items;
  }

  /// 페이지 조회(정렬/오프셋/리밋)
  Future<List<Store>> fetchPage({
    int limit = 200,
    int offset = 0,
    String sort = '-created_at',
  }) async {
    final uri = Uri.parse('$baseUrl/campaigns').replace(queryParameters: {
      'limit': '$limit',
      'offset': '$offset',
      'sort': sort,
    });

    return _withRetry(() async {
      final r =
      await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 3));
      final items = _parseItemsOrThrow(r, context: '캠페인 조회');
      return items
          .map((e) => Store.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// 현재 지도 뷰포트(bbox) 내 캠페인 조회
  Future<List<Store>> fetchInBounds({
    required double south,
    required double west,
    required double north,
    required double east,
    int? categoryId, // 👈 [추가] categoryId를 필터링 조건으로 추가
    int limit = 200,
    int offset = 0,
    String sort = '-created_at',
  }) async {
    final queryParameters = {
      'sw_lat': south.toString(),
      'sw_lng': west.toString(),
      'ne_lat': north.toString(),
      'ne_lng': east.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
      'sort': sort,
    };

    // categoryId가 있으면 쿼리에 동적으로 추가
    if (categoryId != null) {
      queryParameters['category_id'] = categoryId.toString();
    }

    final uri = Uri.parse('$baseUrl/campaigns').replace(queryParameters: queryParameters);

    return _withRetry(() async {
      final r =
      await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 3));
      final items = _parseItemsOrThrow(r, context: '캠페인 조회(bbox)');
      return items
          .map((e) => Store.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// 사용자 위치 기준 가장 가까운 캠페인(거리순, 페이지네이션)
  Future<List<Store>> fetchNearest({
    required double lat,
    required double lng,
    int? categoryId, // categoryId 파라미터 추가
    int limit = 20,
    int offset = 0,
  }) async {
    final queryParameters = {
      'lat': lat.toString(),
      'lng': lng.toString(),
      'sort': 'distance',
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (categoryId != null) {
      queryParameters['category_id'] = categoryId.toString();
    }

    final uri = Uri.parse('$baseUrl/campaigns').replace(queryParameters: queryParameters);

    return _withRetry(() async {
      final r =
      await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 3));
      final items = _parseItemsOrThrow(r, context: '가까운 캠페인 조회');
      final stores = items
          .map((e) => Store.fromJson(e as Map<String, dynamic>))
          .toList();
      
      // 클라이언트에서 거리 계산 및 추가
      final storesWithDistance = stores.map((store) {
        if (store.lat != null && store.lng != null) {
          final distance = Geolocator.distanceBetween(
            lat, lng, store.lat!, store.lng!,
          ) / 1000; // 미터를 킬로미터로 변환
          
          return store.copyWith(distance: distance);
        }
        return store;
      }).toList();
      
      // 거리순으로 정렬
      storesWithDistance.sort((a, b) {
        final distanceA = a.distance ?? double.maxFinite;
        final distanceB = b.distance ?? double.maxFinite;
        return distanceA.compareTo(distanceB);
      });
      
      return storesWithDistance;
    });
  }

  /// 표준 카테고리 전체 목록 조회
  Future<List<Map<String, dynamic>>> fetchCategories() async {
    final uri = Uri.parse('$baseUrl/categories/');

    // --- 👇 [1단계] 요청 직전 정보 로깅 ---
    // developer.log('--- [API 요청 시작] fetchCategories ---', name: 'CampaignService');
    // developer.log('➡️ [URL]: $uri', name: 'CampaignService');
    // developer.log('🔑 [헤더]: $_headers', name: 'CampaignService');
    // ------------------------------------

    // try {
    //   final r = await _client
    //       .get(uri, headers: _headers)
    //       .timeout(const Duration(seconds: 15));
    //
    //   // --- 👇 [2단계] 응답 수신 후 정보 로깅 ---
    //   developer.log('✅ [API 응답 상태 코드]: ${r.statusCode}', name: 'CampaignService');
    //   developer.log('📄 [API 응답 본문]: ${utf8.decode(r.bodyBytes)}', name: 'CampaignService');
    //   // ------------------------------------
    //
    //   if (r.statusCode != 200) {
    //     // 여기서 에러를 던지면 아래 catch 블록으로 감
    //     throw Exception('카테고리 조회 실패: ${r.statusCode}');
    //   }
    //   final decoded = jsonDecode(utf8.decode(r.bodyBytes));
    //   return List<Map<String, dynamic>>.from(decoded);
    // } catch (e) {
    //   // --- 👇 [3단계] 에러 발생 시 정보 로깅 ---
    //   developer.log('❌ [네트워크/파싱 오류] fetchCategories: $e', name: 'CampaignService', error: e);
    //   // ------------------------------------
    //   rethrow; // 기존 에러를 다시 던져서 UI에서 처리하도록 함
    // }



    return _withRetry(() async {
      final r = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));

      // 디버깅 모드에서 API 응답 출력
      _debugPrintResponse('GET', uri.toString(), null, r);

      // 여기서는 items 키 없이 바로 리스트가 반환된다고 가정
      if (r.statusCode != 200) {
        throw Exception('카테고리 조회 실패: ${r.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      // 백엔드 응답이 List<Map> 형태이므로 List<dynamic>으로 캐스팅 후 변환
      return List<Map<String, dynamic>>.from(decoded);
    });
  }

  Future<List<Store>> searchCampaigns({
    required String query,
    int limit = 50, // 검색 결과는 최대 50개까지 가져오도록 설정 (조절 가능)
    int offset = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/campaigns').replace(queryParameters: {
      'q': query, // 👈 백엔드의 검색 파라미터 'q'를 사용
      'limit': '$limit',
      'offset': '$offset',
      'sort': '-created_at', // 최신순으로 정렬
    });

    return _withRetry(() async {
      final r =
      await _client.get(uri, headers: _headers).timeout(
          const Duration(seconds: 30));
      
      // 디버깅 모드에서 API 응답 출력
      _debugPrintResponse('GET', uri.toString(), uri.queryParameters, r);
      
      final items = _parseItemsOrThrow(r, context: '캠페인 검색');
      return items
          .map((e) => Store.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// 단일 캠페인 조회 (ID 기반)
  /// 
  /// 캠페인이 존재하면 Store 객체를 반환하고,
  /// 삭제되었거나 존재하지 않으면 null을 반환합니다.
  Future<Store?> fetchCampaignById(int campaignId) async {
    final uri = Uri.parse('$baseUrl/campaigns/$campaignId');

    return _withRetry(() async {
      try {
        final r = await _client
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 3));

        // 디버깅 모드에서 API 응답 출력
        _debugPrintResponse('GET', uri.toString(), null, r);

        if (r.statusCode == 404) {
          // 캠페인이 삭제되었거나 존재하지 않음
          return null;
        }

        if (r.statusCode != 200) {
          throw Exception(NetworkErrorHandler.getHttpErrorMessage(r.statusCode));
        }

        final decoded = jsonDecode(utf8.decode(r.bodyBytes));
        return Store.fromJson(decoded as Map<String, dynamic>);
      } catch (e) {
        // 네트워크 에러나 404는 null 반환
        if (e.toString().contains('404') || e.toString().contains('Not Found')) {
          return null;
        }
        rethrow;
      }
    });
  }
}
