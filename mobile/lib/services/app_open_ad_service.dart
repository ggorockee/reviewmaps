import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App Open Ad 서비스
///
/// 앱 시작 및 포그라운드 복귀 시 표시되는 전체 화면 광고
///
/// **무효 트래픽 방지 정책**:
/// - 최소 4시간 간격 유지 (Google 권장)
/// - 세션당 1회 표시 제한
/// - 광고 로드 실패 시 재시도 제한
class AppOpenAdService with WidgetsBindingObserver {
  static final AppOpenAdService _instance = AppOpenAdService._internal();
  factory AppOpenAdService() => _instance;
  AppOpenAdService._internal();

  // 광고 단위 ID
  static const String _androidAppOpenAdId = 'ca-app-pub-8516861197467665/9887604087';
  static const String _iosAppOpenAdId = 'ca-app-pub-8516861197467665/9780078288';

  // 테스트용 광고 단위 ID
  static const String _testAppOpenAdId = 'ca-app-pub-3940256099942544/9257395921';

  // SharedPreferences 키
  static const String _lastAdShownTimeKey = 'last_app_open_ad_shown_time';

  // 무효 트래픽 방지: 최소 광고 표시 간격 (4시간)
  static const Duration _minAdInterval = Duration(hours: 4);

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  AppOpenAd? _appOpenAd;
  bool _isAdLoaded = false;
  bool _isShowingAd = false;
  bool _hasShownAdInSession = false;
  DateTime? _lastAdShownTime;
  int _loadAttempts = 0;
  static const int _maxLoadAttempts = 3;

  /// App Open Ad 서비스 초기화
  Future<void> initialize() async {
    try {
      // 마지막 광고 표시 시간 로드
      await _loadLastAdShownTime();

      // 앱 라이프사이클 리스너 등록
      WidgetsBinding.instance.addObserver(this);

      // 초기 광고 로드
      await loadAd();

      await _analytics.logEvent(
        name: 'app_open_ad_service_initialized',
        parameters: {
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
      );

      if (kDebugMode) print('[AppOpenAdService] 초기화 완료');
    } catch (e) {
      if (kDebugMode) print('[AppOpenAdService] 초기화 실패: $e');
      await _analytics.logEvent(
        name: 'app_open_ad_service_init_error',
        parameters: {'error': e.toString()},
      );
    }
  }

  /// 플랫폼별 App Open Ad ID 반환
  String get _appOpenAdId {
    if (_isDebugMode()) {
      return _testAppOpenAdId;
    }
    return Platform.isIOS ? _iosAppOpenAdId : _androidAppOpenAdId;
  }

  /// 디버그 모드 확인
  bool _isDebugMode() {
    return kDebugMode;
  }

  /// 마지막 광고 표시 시간 로드
  Future<void> _loadLastAdShownTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_lastAdShownTimeKey);
      if (timestamp != null) {
        _lastAdShownTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    } catch (e) {
      if (kDebugMode) print('[AppOpenAdService] 마지막 광고 표시 시간 로드 실패: $e');
    }
  }

  /// 마지막 광고 표시 시간 저장
  Future<void> _saveLastAdShownTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastAdShownTimeKey, DateTime.now().millisecondsSinceEpoch);
      _lastAdShownTime = DateTime.now();
    } catch (e) {
      if (kDebugMode) print('[AppOpenAdService] 마지막 광고 표시 시간 저장 실패: $e');
    }
  }

  /// 광고 표시 가능 여부 확인
  bool _canShowAd() {
    // 이미 세션에서 광고를 표시했으면 표시하지 않음
    if (_hasShownAdInSession) {
      if (kDebugMode) print('[AppOpenAdService] 이미 세션에서 광고를 표시했음');
      return false;
    }

    // 현재 광고를 표시 중이면 표시하지 않음
    if (_isShowingAd) {
      if (kDebugMode) print('[AppOpenAdService] 현재 광고를 표시 중');
      return false;
    }

    // 광고가 로드되지 않았으면 표시하지 않음
    if (!_isAdLoaded || _appOpenAd == null) {
      if (kDebugMode) print('[AppOpenAdService] 광고가 로드되지 않음');
      return false;
    }

    // 마지막 광고 표시 시간이 최소 간격보다 짧으면 표시하지 않음
    if (_lastAdShownTime != null) {
      final timeSinceLastAd = DateTime.now().difference(_lastAdShownTime!);
      if (timeSinceLastAd < _minAdInterval) {
        final remainingTime = _minAdInterval - timeSinceLastAd;
        if (kDebugMode) print('[AppOpenAdService] 광고 표시 대기 중: ${remainingTime.inMinutes}분 남음');
        return false;
      }
    }

    return true;
  }

  /// App Open Ad 로드
  Future<void> loadAd() async {
    if (kDebugMode) print('[AppOpenAdService] 광고 로드 시작 (시도 횟수: $_loadAttempts/$_maxLoadAttempts)');

    // 이미 광고가 로드되어 있으면 건너뜀
    if (_isAdLoaded && _appOpenAd != null) {
      if (kDebugMode) print('[AppOpenAdService] 광고가 이미 로드되어 있음');
      return;
    }

    // 로드 시도 횟수 제한
    if (_loadAttempts >= _maxLoadAttempts) {
      if (kDebugMode) print('[AppOpenAdService] 광고 로드 시도 횟수 초과');
      return;
    }

    _loadAttempts++;
    if (kDebugMode) print('[AppOpenAdService] App Open Ad 로드 요청 - Ad Unit ID: $_appOpenAdId');

    try {
      await AppOpenAd.load(
        adUnitId: _appOpenAdId,
        request: const AdRequest(),
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (ad) {
            _appOpenAd = ad;
            _isAdLoaded = true;
            _loadAttempts = 0; // 로드 성공 시 카운터 리셋

            // 광고 이벤트 리스너 설정
            _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
              onAdShowedFullScreenContent: (ad) {
                _isShowingAd = true;
                if (kDebugMode) print('[AppOpenAdService] 광고 표시 시작');
              },
              onAdDismissedFullScreenContent: (ad) {
                _isShowingAd = false;
                _isAdLoaded = false;
                ad.dispose();
                _appOpenAd = null;

                // 다음 광고 미리 로드
                loadAd();

                if (kDebugMode) print('[AppOpenAdService] 광고 닫힘');
              },
              onAdFailedToShowFullScreenContent: (ad, error) {
                _isShowingAd = false;
                _isAdLoaded = false;
                ad.dispose();
                _appOpenAd = null;

                _analytics.logEvent(
                  name: 'app_open_ad_show_failed',
                  parameters: {
                    'error_code': error.code,
                    'error_message': error.message,
                  },
                );

                if (kDebugMode) print('[AppOpenAdService] 광고 표시 실패: ${error.message}');
              },
            );

            _analytics.logEvent(
              name: 'app_open_ad_loaded',
              parameters: {'ad_unit_id': _appOpenAdId},
            );

            if (kDebugMode) print('[AppOpenAdService] 광고 로드 완료');
          },
          onAdFailedToLoad: (error) {
            _isAdLoaded = false;
            _appOpenAd = null;

            _analytics.logEvent(
              name: 'app_open_ad_load_failed',
              parameters: {
                'error_code': error.code,
                'error_message': error.message,
                'load_attempts': _loadAttempts,
              },
            );

            if (kDebugMode) print('[AppOpenAdService] 광고 로드 실패 ($_loadAttempts/$_maxLoadAttempts): ${error.message}');
          },
        ),
      );
    } catch (e) {
      if (kDebugMode) print('[AppOpenAdService] 광고 로드 중 오류: $e');
      await _analytics.logEvent(
        name: 'app_open_ad_load_error',
        parameters: {'error': e.toString()},
      );
    }
  }

  /// App Open Ad 표시
  Future<void> showAdIfAvailable() async {
    if (!_canShowAd()) {
      return;
    }

    try {
      await _analytics.logEvent(
        name: 'app_open_ad_shown',
        parameters: {'ad_unit_id': _appOpenAdId},
      );

      await _appOpenAd!.show();

      // 광고 표시 완료 후 상태 업데이트
      _hasShownAdInSession = true;
      await _saveLastAdShownTime();

      if (kDebugMode) print('[AppOpenAdService] 광고 표시 완료');
    } catch (e) {
      if (kDebugMode) print('[AppOpenAdService] 광고 표시 실패: $e');
      await _analytics.logEvent(
        name: 'app_open_ad_show_error',
        parameters: {'error': e.toString()},
      );
    }
  }

  /// 앱 라이프사이클 변경 감지
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 포그라운드 복귀 시 광고 표시
      showAdIfAvailable();
    }
  }

  /// 세션 리셋
  void resetSession() {
    _hasShownAdInSession = false;
    if (kDebugMode) print('[AppOpenAdService] 세션 리셋 완료');
  }

  /// 리소스 정리
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appOpenAd?.dispose();
    _appOpenAd = null;
    _isAdLoaded = false;
    _isShowingAd = false;
  }

  /// 현재 세션에서 광고를 표시했는지 확인
  bool get hasShownAdInSession => _hasShownAdInSession;

  /// 광고 로드 상태 확인
  bool get isAdLoaded => _isAdLoaded;

  /// 광고 표시 중인지 확인
  bool get isShowingAd => _isShowingAd;
}
