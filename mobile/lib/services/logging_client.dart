// lib/services/logging_client.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// LoggingClient
/// ------------------------------------------------------------
/// http.Client를 감싸서 모든 HTTP 요청/응답을 로깅하는 래퍼 클래스
/// - 디버그 모드에서만 동작
/// - 요청: 메서드, URL, 헤더(X-API-KEY 마스킹)
/// - 응답: statusCode, 소요시간, body 크기
/// - 에러: 에러 메시지
class LoggingClient extends http.BaseClient {
  final http.Client _inner;

  LoggingClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stopwatch = Stopwatch()..start();
    
    // 요청 로깅
    _logRequest(request);
    
    try {
      final response = await _inner.send(request);
      stopwatch.stop();
      
      // 응답 로깅
      await _logResponse(response, stopwatch.elapsedMilliseconds);
      
      return response;
    } catch (error) {
      stopwatch.stop();
      
      // 에러 로깅
      _logError(request, error, stopwatch.elapsedMilliseconds);
      
      rethrow;
    }
  }

  /// 요청 로깅
  void _logRequest(http.BaseRequest request) {
    debugPrint('🚀 HTTP Request');
    debugPrint('   Method: ${request.method}');
    debugPrint('   URL: ${request.url}');
    
    // 헤더 로깅 (X-API-KEY는 마스킹)
    if (request.headers.isNotEmpty) {
      debugPrint('   Headers:');
      request.headers.forEach((key, value) {
        if (key.toLowerCase() == 'x-api-key') {
          // API 키 마스킹: 처음 4자리만 표시
          final masked = value.length > 4 
              ? '${value.substring(0, 4)}${'*' * (value.length - 4)}'
              : '${'*' * value.length}';
          debugPrint('     $key: $masked');
        } else {
          debugPrint('     $key: $value');
        }
      });
    }

    // Request body 로깅 (POST/PUT 등)
    if (request is http.Request && request.body.isNotEmpty) {
      try {
        // JSON이면 예쁘게 출력
        final jsonBody = jsonDecode(request.body);
        final prettyJson = const JsonEncoder.withIndent('  ').convert(jsonBody);
        debugPrint('   Body:\n$prettyJson');
      } catch (_) {
        // JSON이 아니면 그대로 출력 (최대 500자)
        final body = request.body.length > 500 
            ? '${request.body.substring(0, 500)}...[truncated]'
            : request.body;
        debugPrint('   Body: $body');
      }
    }
  }

  /// 응답 로깅
  Future<void> _logResponse(http.StreamedResponse response, int elapsedMs) async {
    debugPrint('📥 HTTP Response');
    debugPrint('   Status: ${response.statusCode}');
    debugPrint('   Time: ${elapsedMs}ms');
    
    // Content-Length 또는 실제 body 크기
    final contentLength = response.contentLength;
    if (contentLength != null) {
      debugPrint('   Body Size: ${contentLength} bytes');
    }

    // 응답 헤더 (주요 헤더만)
    final importantHeaders = ['content-type', 'content-length', 'cache-control'];
    final headers = <String, String>{};
    for (final header in importantHeaders) {
      final value = response.headers[header];
      if (value != null) {
        headers[header] = value;
      }
    }
    if (headers.isNotEmpty) {
      debugPrint('   Headers: $headers');
    }

    // 에러 상태코드면 추가 정보
    if (response.statusCode >= 400) {
      debugPrint('   ⚠️  Error Response (${response.statusCode})');
    }
  }

  /// 에러 로깅
  void _logError(http.BaseRequest request, dynamic error, int elapsedMs) {
    debugPrint('❌ HTTP Error');
    debugPrint('   URL: ${request.url}');
    debugPrint('   Time: ${elapsedMs}ms');
    debugPrint('   Error: $error');
    
    // 네트워크 에러 타입별 추가 정보
    if (error is SocketException) {
      debugPrint('   Type: Network Error (${error.osError?.message ?? 'Unknown'})');
    } else if (error is HttpException) {
      debugPrint('   Type: HTTP Exception');
    } else if (error.toString().contains('timeout')) {
      debugPrint('   Type: Timeout Error');
    }
  }

  @override
  void close() {
    _inner.close();
  }
}
