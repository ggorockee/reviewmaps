import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// 네트워크 연결 상태 서비스
/// - 인터넷 연결 상태 확인
/// - 연결 상태 변경 스트림 제공
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final _connectivityController = StreamController<bool>.broadcast();

  /// 연결 상태 변경 스트림
  Stream<bool> get onConnectivityChanged => _connectivityController.stream;

  /// 마지막으로 확인된 연결 상태
  bool _lastKnownState = true;
  bool get isConnected => _lastKnownState;

  /// 인터넷 연결 확인
  /// - DNS lookup을 통해 실제 인터넷 접근 가능 여부 확인
  Future<bool> checkConnectivity() async {
    try {
      // 여러 DNS 서버를 체크하여 신뢰성 향상
      final lookupTargets = [
        'google.com',
        'cloudflare.com',
        'naver.com',
      ];

      for (final target in lookupTargets) {
        try {
          final result = await InternetAddress.lookup(target)
              .timeout(const Duration(seconds: 3));

          if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
            _updateConnectivityState(true);
            return true;
          }
        } catch (_) {
          // 다음 서버 시도
          continue;
        }
      }

      _updateConnectivityState(false);
      return false;
    } catch (e) {
      debugPrint('[ConnectivityService] 연결 확인 실패: $e');
      _updateConnectivityState(false);
      return false;
    }
  }

  /// API 서버 연결 확인
  /// - 실제 API 서버에 접근 가능한지 확인
  Future<bool> checkApiServerConnectivity(String baseUrl) async {
    try {
      final uri = Uri.parse('$baseUrl/healthz');
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);

      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 5));

      client.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[ConnectivityService] API 서버 연결 확인 실패: $e');
      return false;
    }
  }

  /// 연결 상태 업데이트
  void _updateConnectivityState(bool isConnected) {
    if (_lastKnownState != isConnected) {
      _lastKnownState = isConnected;
      _connectivityController.add(isConnected);
      debugPrint('[ConnectivityService] 연결 상태 변경: ${isConnected ? "연결됨" : "연결 끊김"}');
    }
  }

  /// 주기적 연결 상태 모니터링 시작
  Timer? _monitoringTimer;

  void startMonitoring({Duration interval = const Duration(seconds: 30)}) {
    stopMonitoring();
    _monitoringTimer = Timer.periodic(interval, (_) => checkConnectivity());
    // 즉시 한 번 체크
    checkConnectivity();
  }

  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
  }

  void dispose() {
    stopMonitoring();
    _connectivityController.close();
  }
}
