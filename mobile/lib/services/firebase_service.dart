// lib/services/firebase_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';

/// FirebaseService
/// ------------------------------------------------------------
/// Firebase 서비스들을 중앙에서 관리하는 싱글톤 서비스
/// - Analytics: 사용자 행동 분석
/// - Crashlytics: 크래시 리포팅
/// - Performance: 성능 모니터링
/// - Remote Config는 RemoteConfigService에서 단독 관리
class FirebaseService {
  static FirebaseService? _instance;
  static FirebaseService get instance => _instance ??= FirebaseService._internal();
  
  FirebaseService._internal();

  late FirebaseAnalytics _analytics;
  late FirebaseCrashlytics _crashlytics;
  late FirebasePerformance _performance;

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

      // Crashlytics 설정
      await _setupCrashlytics();

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

  /// Firebase 서비스 상태 확인
  bool get isInitialized => _isInitialized;
}
