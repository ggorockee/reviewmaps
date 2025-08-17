// lib/services/campaign_service.dart
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../models/store_model.dart';

class CampaignService {
  final String baseUrl;
  final String apiKey;
  late final http.Client _client;

  CampaignService(this.baseUrl, {required this.apiKey}) {
    final io = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15) // 소켓 연결 타임아웃
      ..idleTimeout = const Duration(seconds: 15);
    _client = IOClient(io);
  }

  Map<String, String> get _headers => {
    'X-API-KEY': apiKey,
    'Accept': 'application/json',
    'User-Agent': 'review-maps-app/1.0 (Flutter; iOS/Android)', // WAF 회피용
  };

  Future<void> healthCheck() async {
    try {
      final addrs = await InternetAddress.lookup('api.review-maps.com');
      if (kDebugMode) dev.log('[HC] DNS api.review-maps.com -> $addrs', name: 'Net');
    } catch (e) {
      if (kDebugMode) dev.log('[HC][ERR] DNS lookup failed: $e', name: 'Net');
    }

    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/healthz'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (kDebugMode) dev.log('[HC] /healthz status=${r.statusCode}', name: 'Net');
    } catch (e) {
      if (kDebugMode) dev.log('[HC][ERR] /healthz: $e', name: 'Net');
    }
  }

  Future<T> _withRetry<T>(Future<T> Function() task,
      {int retries = 3}) async {
    int attempt = 0;
    Object? lastErr;
    while (attempt < retries) {
      try {
        return await task();
      } catch (e) {
        lastErr = e;
        final delay = Duration(milliseconds: 400 * (1 << attempt)); // 0.4s, 0.8s, 1.6s
        if (kDebugMode) {
          dev.log('[RETRY] attempt=${attempt + 1} err=$e, sleep=${delay.inMilliseconds}ms',
              name: 'CampaignService');
        }
        await Future.delayed(delay);
        attempt++;
      }
    }
    throw lastErr ?? Exception('unknown error');
  }

  Future<List<Store>> fetchPage({int limit = 200, int offset = 0, String sort = '-created_at'}) async {
    final uri = Uri.parse('$baseUrl/campaigns').replace(queryParameters: {
      'limit': '$limit',
      'offset': '$offset',
      'sort': sort,
    });

    return _withRetry(() async {
      final started = DateTime.now();
      if (kDebugMode) dev.log('[REQ] GET $uri', name: 'CampaignService');

      final r = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));

      final elapsed = DateTime.now().difference(started).inMilliseconds;
      if (kDebugMode) {
        final rawLen = r.bodyBytes.length;
        final preview = r.body.length > 800
            ? '${r.body.substring(0, 800)}…(truncated)'
            : r.body;
        dev.log('[RES] status=${r.statusCode} len=$rawLen elapsed=${elapsed}ms',
            name: 'CampaignService');
        dev.log('[BODY] $preview', name: 'CampaignService');
      }

      if (r.statusCode != 200) {
        throw Exception('캠페인 조회 실패: ${r.statusCode}');
      }

      final decoded = jsonDecode(r.body);
      final List items =
      (decoded is Map && decoded['items'] is List) ? decoded['items'] : [];
      if (kDebugMode) {
        dev.log('[PARSE] items=${items.length} sample=${jsonEncode(items.take(2).toList())}',
            name: 'CampaignService');
      }
      return items.map((e) => Store.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

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
      if (kDebugMode) dev.log('[REQ] GET $uri (bbox)', name: 'CampaignService');
      final r = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));

      if (kDebugMode) dev.log('[RES] bbox status=${r.statusCode}', name: 'CampaignService');
      if (r.statusCode != 200) {
        throw Exception('캠페인 조회 실패(bbox): ${r.statusCode}');
      }

      final decoded = jsonDecode(r.body);
      final List items =
      (decoded is Map && decoded['items'] is List) ? decoded['items'] : [];
      return items.map((e) => Store.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  // --- 👇 [추가된 메소드] ---
  /// 사용자의 현재 위치를 기준으로 가장 가까운 캠페인을 조회합니다. (페이지네이션 지원)
  Future<List<Store>> fetchNearest({
    required double lat,
    required double lng,
    int limit = 20,
    int offset = 0,
  }) async {
    // URI에 거리순 정렬 파라미터를 동적으로 추가
    final uri = Uri.parse('$baseUrl/campaigns').replace(queryParameters: {
      'lat': lat.toString(),
      'lng': lng.toString(),
      'sort': 'distance', // 핵심: 서버에 거리순 정렬을 요청
      'limit': limit.toString(),
      'offset': offset.toString(),
    });

    return _withRetry(() async {
      if (kDebugMode) dev.log('[REQ] GET $uri (nearest)', name: 'CampaignService');
      final r = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));

      if (kDebugMode) dev.log('[RES] nearest status=${r.statusCode}', name: 'CampaignService');
      if (r.statusCode != 200) {
        throw Exception('가까운 캠페인 조회 실패: ${r.statusCode}');
      }

      final decoded = jsonDecode(r.body);
      final List items =
      (decoded is Map && decoded['items'] is List) ? decoded['items'] : [];
      return items.map((e) => Store.fromJson(e as Map<String, dynamic>)).toList();
    });
  }
// --- 👆 [추가된 메소드] ---
}