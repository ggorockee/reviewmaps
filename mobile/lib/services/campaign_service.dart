// lib/services/campaign_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models/store_model.dart';

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
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 15);
    _client = IOClient(io);
  }

  /// 공통 헤더
  Map<String, String> get _headers => {
    'X-API-KEY': apiKey,
    'Accept': 'application/json',
    // 서버 트래픽 구분용 User-Agent (필요 시 변경)
    'User-Agent': 'review-maps-app/1.0 (Flutter; iOS/Android)',
  };

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
          .timeout(const Duration(seconds: 15));
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
        // 0.4s, 0.8s, 1.6s …
        final delay = Duration(milliseconds: 400 * (1 << attempt));
        await Future.delayed(delay);
        attempt++;
      }
    }
    throw lastErr ?? Exception('unknown error');
  }

  /// 공통: 응답 검사 + JSON 파싱 + items 배열 추출
  List<dynamic> _parseItemsOrThrow(http.Response r, {String context = ''}) {
    if (r.statusCode != 200) {
      throw Exception('$context 실패: ${r.statusCode}');
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
      await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
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
    int limit = 200,
    int offset = 0,
    String sort = '-created_at',
  }) async {
    final uri = Uri.parse('$baseUrl/campaigns').replace(queryParameters: {
      'sw_lat': south.toString(),
      'sw_lng': west.toString(),
      'ne_lat': north.toString(),
      'ne_lng': east.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
      'sort': sort,
    });

    return _withRetry(() async {
      final r =
      await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
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
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/campaigns').replace(queryParameters: {
      'lat': lat.toString(),
      'lng': lng.toString(),
      'sort': 'distance', // 서버가 distance 정렬 지원해야 함
      'limit': limit.toString(),
      'offset': offset.toString(),
    });

    return _withRetry(() async {
      final r =
      await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 30));
      final items = _parseItemsOrThrow(r, context: '가까운 캠페인 조회');
      return items
          .map((e) => Store.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }
}
