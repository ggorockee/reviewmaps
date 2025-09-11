import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ad_service.dart';

/// 전면광고 관리 서비스
/// 앱 진입 시 3-5초 지연 후 표시
/// 정책상 허용되며 사용자 세션당 1회 정도 권장
class InterstitialAdManager {
  static final InterstitialAdManager _instance = InterstitialAdManager._internal();
  factory InterstitialAdManager() => _instance;
  InterstitialAdManager._internal();

  final AdService _adService = AdService();
  Timer? _delayTimer;
  bool _hasShownAdInSession = false;
  bool _isInitialized = false;

  /// 전면광고 매니저 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await _adService.loadInterstitialAd();
      _isInitialized = true;
      print('[InterstitialAdManager] 전면광고 매니저 초기화 완료');
    } catch (e) {
      print('[InterstitialAdManager] 초기화 실패: $e');
    }
  }

  /// 앱 진입 시 전면광고 표시 (3-5초 지연)
  /// 첫 화면 진입 후 일정 시간 뒤 표시하여 정책 위반 방지
  void showDelayedInterstitialAd({
    int delaySeconds = 4,
    VoidCallback? onAdShown,
    VoidCallback? onAdFailed,
  }) {
    // 이미 세션에서 광고를 보여줬으면 표시하지 않음
    if (_hasShownAdInSession) {
      print('[InterstitialAdManager] 이미 세션에서 광고를 표시했음');
      return;
    }

    // 기존 타이머가 있으면 취소
    _delayTimer?.cancel();

    print('[InterstitialAdManager] ${delaySeconds}초 후 전면광고 표시 예약');

    _delayTimer = Timer(Duration(seconds: delaySeconds), () async {
      try {
        await _adService.showInterstitialAd();
        _hasShownAdInSession = true;
        
        // 광고 표시 완료 콜백
        onAdShown?.call();
        
        print('[InterstitialAdManager] 전면광고 표시 완료');
        
        // 다음 세션을 위해 새로운 광고 로드
        await _adService.loadInterstitialAd();
      } catch (e) {
        print('[InterstitialAdManager] 전면광고 표시 실패: $e');
        onAdFailed?.call();
      }
    });
  }

  /// 특정 이벤트 후 전면광고 표시 (예: 메뉴 이동 시)
  /// 종료 시 강제 노출 대신 중간 이벤트에 집중
  Future<void> showInterstitialAdOnEvent({
    required String eventName,
    VoidCallback? onAdShown,
    VoidCallback? onAdFailed,
  }) async {
    // 이미 세션에서 광고를 보여줬으면 표시하지 않음
    if (_hasShownAdInSession) {
      print('[InterstitialAdManager] 이미 세션에서 광고를 표시했음');
      return;
    }

    try {
      // 이벤트 로깅
      await _adService.logUserAction('interstitial_ad_event_triggered', {
        'event_name': eventName,
      });

      await _adService.showInterstitialAd();
      _hasShownAdInSession = true;
      
      // 광고 표시 완료 콜백
      onAdShown?.call();
      
      print('[InterstitialAdManager] 이벤트 기반 전면광고 표시 완료: $eventName');
      
      // 다음 세션을 위해 새로운 광고 로드
      await _adService.loadInterstitialAd();
    } catch (e) {
      print('[InterstitialAdManager] 이벤트 기반 전면광고 표시 실패: $e');
      onAdFailed?.call();
    }
  }

  /// 세션 리셋 (앱 재시작 시 호출)
  void resetSession() {
    _hasShownAdInSession = false;
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
