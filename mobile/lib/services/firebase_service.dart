// lib/services/firebase_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

/// FirebaseService
/// ------------------------------------------------------------
/// Firebase 서비스들을 중앙에서 관리하는 싱글톤 서비스
/// - Analytics: 사용자 행동 분석
/// - Crashlytics: 크래시 리포팅
/// - Performance: 성능 모니터링
/// - Remote Config: 원격 설정 관리
class FirebaseService {
  static FirebaseService? _instance;
  static FirebaseService get instance => _instance ??= FirebaseService._internal();
  
  FirebaseService._internal();

  late FirebaseAnalytics _analytics;
  late FirebaseCrashlytics _crashlytics;
  late FirebasePerformance _performance;
  late FirebaseRemoteConfig _remoteConfig;

  bool _isInitialized = false;

  /// Firebase 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Firebase Core 초기화
      await Firebase.initializeApp();
      
      // 각 서비스 초기화
      _analytics = FirebaseAnalytics.instance;
      _crashlytics = FirebaseCrashlytics.instance;
      _performance = FirebasePerformance.instance;
      _remoteConfig = FirebaseRemoteConfig.instance;

      // Crashlytics 설정
      await _setupCrashlytics();
      
      // Remote Config 설정
      await _setupRemoteConfig();
      

      _isInitialized = true;
      debugPrint('🔥 Firebase initialized successfully');
    } catch (e) {
      debugPrint('❌ Firebase initialization failed: $e');
      rethrow;
    }
  }

  /// Crashlytics 설정
  Future<void> _setupCrashlytics() async {
    // Flutter 프레임워크 에러를 Crashlytics에 보고
    FlutterError.onError = (errorDetails) {
      _crashlytics.recordFlutterFatalError(errorDetails);
    };

    // 플랫폼별 에러를 Crashlytics에 보고
    PlatformDispatcher.instance.onError = (error, stack) {
      _crashlytics.recordError(error, stack, fatal: true);
      return true;
    };

    debugPrint('🔥 Crashlytics configured');
  }

  /// Remote Config 설정
  Future<void> _setupRemoteConfig() async {
    try {
      // 기본값 설정
      await _remoteConfig.setDefaults({
        'feature_search_suggestions': true,
        'feature_dark_mode': false,
        'min_app_version': '1.0.0',
        'maintenance_mode': false,
        'maintenance_message': '서비스 점검 중입니다.',
        'banner_text': '',
        'banner_color': '#2196F3',
        'max_search_results': 50,
      });

      // 설정 업데이트 (개발: 즉시, 프로덕션: 1시간)
      await _remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: kDebugMode 
            ? const Duration(seconds: 10) 
            : const Duration(hours: 1),
      ));

      // 초기 fetch
      await _remoteConfig.fetchAndActivate();
      
      debugPrint('🔥 Remote Config configured');
    } catch (e) {
      debugPrint('⚠️ Remote Config setup failed: $e');
    }
  }


  // ==================== Analytics ====================

  /// 화면 조회 이벤트
  Future<void> logScreenView(String screenName) async {
    if (!_isInitialized) return;
    
    await _analytics.logScreenView(screenName: screenName);
    debugPrint('📊 Screen view: $screenName');
  }

  /// 검색 이벤트
  Future<void> logSearch(String searchTerm, {String? category}) async {
    if (!_isInitialized) return;
    
    await _analytics.logSearch(searchTerm: searchTerm, parameters: {
      'category': ?category,
    });
    debugPrint('📊 Search: $searchTerm');
  }

  /// 캠페인 선택 이벤트
  Future<void> logSelectContent(String contentType, String itemId, {String? itemName}) async {
    if (!_isInitialized) return;
    
    await _analytics.logSelectContent(
      contentType: contentType,
      itemId: itemId,
      parameters: {
        'item_name': ?itemName,
      },
    );
    debugPrint('📊 Select content: $contentType - $itemId');
  }

  /// 커스텀 이벤트
  Future<void> logEvent(String name, Map<String, Object>? parameters) async {
    if (!_isInitialized) return;
    
    await _analytics.logEvent(name: name, parameters: parameters);
    debugPrint('📊 Custom event: $name');
  }

  /// 사용자 속성 설정
  Future<void> setUserProperty(String name, String? value) async {
    if (!_isInitialized) return;
    
    await _analytics.setUserProperty(name: name, value: value);
    debugPrint('📊 User property: $name = $value');
  }

  // ==================== Crashlytics ====================

  /// 사용자 ID 설정
  Future<void> setUserId(String userId) async {
    if (!_isInitialized) return;
    
    await _crashlytics.setUserIdentifier(userId);
    debugPrint('💥 User ID set: $userId');
  }

  /// 커스텀 키 설정
  Future<void> setCustomKey(String key, Object value) async {
    if (!_isInitialized) return;
    
    await _crashlytics.setCustomKey(key, value);
  }

  /// 비치명적 에러 기록
  Future<void> recordError(dynamic exception, StackTrace? stackTrace, {String? reason}) async {
    if (!_isInitialized) return;
    
    await _crashlytics.recordError(
      exception, 
      stackTrace, 
      reason: reason,
      fatal: false,
    );
    debugPrint('💥 Error recorded: $exception');
  }

  /// 로그 기록
  Future<void> log(String message) async {
    if (!_isInitialized) return;
    
    await _crashlytics.log(message);
  }

  // ==================== Performance ====================

  /// HTTP 요청 성능 추적
  HttpMetric newHttpMetric(String url, HttpMethod httpMethod) {
    return _performance.newHttpMetric(url, httpMethod);
  }

  /// 커스텀 트레이스 생성
  Trace newTrace(String traceName) {
    return _performance.newTrace(traceName);
  }

  // ==================== Remote Config ====================

  /// Remote Config 값 가져오기
  bool getBool(String key) => _remoteConfig.getBool(key);
  String getString(String key) => _remoteConfig.getString(key);
  int getInt(String key) => _remoteConfig.getInt(key);
  double getDouble(String key) => _remoteConfig.getDouble(key);

  /// 기능 플래그 확인
  bool isFeatureEnabled(String featureName) {
    return getBool('feature_$featureName');
  }

  /// 앱 버전 체크
  bool isAppVersionSupported(String currentVersion) {
    final minVersion = getString('min_app_version');
    // 간단한 버전 비교 로직 (실제로는 더 정교한 로직 필요)
    return _compareVersions(currentVersion, minVersion) >= 0;
  }

  /// 점검 모드 확인
  bool isMaintenanceMode() => getBool('maintenance_mode');
  String getMaintenanceMessage() => getString('maintenance_message');

  /// Remote Config 새로고침
  Future<void> refreshConfig() async {
    if (!_isInitialized) return;
    
    try {
      await _remoteConfig.fetchAndActivate();
      debugPrint('🔥 Remote Config refreshed');
    } catch (e) {
      debugPrint('⚠️ Remote Config refresh failed: $e');
    }
  }

  // ==================== Utility ====================

  /// 버전 비교 (간단한 구현)
  int _compareVersions(String version1, String version2) {
    List<int> v1Parts = version1.split('.').map(int.parse).toList();
    List<int> v2Parts = version2.split('.').map(int.parse).toList();
    
    for (int i = 0; i < 3; i++) {
      int v1Part = i < v1Parts.length ? v1Parts[i] : 0;
      int v2Part = i < v2Parts.length ? v2Parts[i] : 0;
      
      if (v1Part > v2Part) return 1;
      if (v1Part < v2Part) return -1;
    }
    return 0;
  }

  /// Firebase 서비스 상태 확인
  bool get isInitialized => _isInitialized;
}
