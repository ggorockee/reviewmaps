import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ad_service.dart';

/// 전면광고 관리 서비스
///
/// **무효 트래픽 방지 정책**:
/// - 최소 30초 간격 유지 (너무 빈번한 광고 방지)
/// - 세션당 최대 3회 표시 제한
/// - 적절한 타이밍에만 표시 (화면 전환, 검색 완료 등)
class InterstitialAdManager {
  static final InterstitialAdManager _instance = InterstitialAdManager._internal();
  factory InterstitialAdManager() => _instance;
  InterstitialAdManager._internal();

  final AdService _adService = AdService();
  Timer? _delayTimer;
  bool _hasShownAdInSession = false;
  bool _isInitialized = false;

  // 무효 트래픽 방지
  static const String _lastAdShownTimeKey = 'last_interstitial_ad_shown_time';
  static const Duration _minAdInterval = Duration(seconds: 30);
  static const int _maxAdsPerSession = 3;

  DateTime? _lastAdShownTime;
  int _adShownCountInSession = 0;

  /// 전면광고 매니저 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 마지막 광고 표시 시간 로드
      await _loadLastAdShownTime();

      await _adService.loadInterstitialAd();
      _isInitialized = true;
      print('[InterstitialAdManager] 전면광고 매니저 초기화 완료');
    } catch (e) {
      print('[InterstitialAdManager] 초기화 실패: $e');
    }
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
      print('[InterstitialAdManager] 마지막 광고 표시 시간 로드 실패: $e');
    }
  }

  /// 마지막 광고 표시 시간 저장
  Future<void> _saveLastAdShownTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastAdShownTimeKey, DateTime.now().millisecondsSinceEpoch);
      _lastAdShownTime = DateTime.now();
    } catch (e) {
      print('[InterstitialAdManager] 마지막 광고 표시 시간 저장 실패: $e');
    }
  }

  /// 광고 표시 가능 여부 확인 (무효 트래픽 방지)
  bool _canShowAd() {
    // 세션당 최대 광고 표시 횟수 확인
    if (_adShownCountInSession >= _maxAdsPerSession) {
      print('[InterstitialAdManager] 세션당 최대 광고 표시 횟수 초과 ($_adShownCountInSession/$_maxAdsPerSession)');
      return false;
    }

    // 마지막 광고 표시 시간이 최소 간격보다 짧으면 표시하지 않음
    if (_lastAdShownTime != null) {
      final timeSinceLastAd = DateTime.now().difference(_lastAdShownTime!);
      if (timeSinceLastAd < _minAdInterval) {
        final remainingSeconds = (_minAdInterval - timeSinceLastAd).inSeconds;
        print('[InterstitialAdManager] 광고 표시 대기 중: $remainingSeconds초 남음');
        return false;
      }
    }

    return true;
  }

  /// 앱 진입 시 전면광고 표시 (3-5초 지연) - DEPRECATED
  /// 주의: 이 메서드는 더 이상 사용하지 않습니다. App Open Ad를 사용하세요.
  @Deprecated('Use App Open Ad instead')
  void showDelayedInterstitialAd({
    int delaySeconds = 4,
    VoidCallback? onAdShown,
    VoidCallback? onAdFailed,
  }) {
    print('[InterstitialAdManager] showDelayedInterstitialAd는 더 이상 사용되지 않습니다. App Open Ad를 사용하세요.');
  }

  /// 특정 이벤트 후 전면광고 표시 (예: 화면 전환, 검색 완료 등)
  /// 무효 트래픽 방지: 최소 30초 간격, 세션당 최대 3회
  Future<void> showInterstitialAdOnEvent({
    required String eventName,
    VoidCallback? onAdShown,
    VoidCallback? onAdFailed,
  }) async {
    // 무효 트래픽 방지 체크
    if (!_canShowAd()) {
      print('[InterstitialAdManager] 광고 표시 조건 미충족');
      onAdFailed?.call();
      return;
    }

    try {
      // 이벤트 로깅
      await _adService.logUserAction('interstitial_ad_event_triggered', {
        'event_name': eventName,
      });

      await _adService.showInterstitialAd();

      // 광고 표시 완료 후 상태 업데이트
      _hasShownAdInSession = true;
      _adShownCountInSession++;
      await _saveLastAdShownTime();

      // 광고 표시 완료 콜백
      onAdShown?.call();

      print('[InterstitialAdManager] 이벤트 기반 전면광고 표시 완료: $eventName ($_adShownCountInSession/$_maxAdsPerSession)');

      // 다음 광고 미리 로드
      await _adService.loadInterstitialAd();
    } catch (e) {
      print('[InterstitialAdManager] 이벤트 기반 전면광고 표시 실패: $e');
      onAdFailed?.call();
    }
  }

  /// 세션 리셋 (앱 재시작 시 호출)
  void resetSession() {
    _hasShownAdInSession = false;
    _adShownCountInSession = 0;
    _delayTimer?.cancel();
    print('[InterstitialAdManager] 세션 리셋 완료');
  }

  /// 타이머 정리
  void dispose() {
    _delayTimer?.cancel();
  }

  /// 현재 세션에서 광고를 표시했는지 확인
  bool get hasShownAdInSession => _hasShownAdInSession;

  /// 초기화 상태 확인
  bool get isInitialized => _isInitialized;
}
