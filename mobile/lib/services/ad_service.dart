import 'dart:io';
import 'package:flutter/services.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

/// 카카오 AdFit 광고 서비스
/// Google 및 Apple 정책에 위반되지 않으면서 수익화를 최적화
class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  // 카카오 AdFit 광고 단위 ID
  // 배너: 320x50
  static const String _bannerAdId = 'DAN-VkCF8zNFJMU3e3LP';
  
  // 전면광고: 중앙형_프로필 포함_1:1
  static const String _interstitialAdId = 'DAN-StCgaXLBUc4NmDjh';
  
  // 네이티브: 이미지 네이티브(2:1)
  static const String _nativeAdId = 'DAN-zMWhwGJrhKMmPZ0E';

  // Firebase Analytics 인스턴스
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  // 광고 상태 관리
  bool _isInterstitialAdLoaded = false;
  bool _isTrackingPermissionGranted = false;

  /// AdFit 초기화
  Future<void> initialize() async {
    try {
      // iOS 14.5+ App Tracking Transparency 권한 요청
      if (Platform.isIOS) {
        await _requestTrackingPermission();
      }

      // Firebase Analytics 이벤트 로깅
      await _analytics.logEvent(
        name: 'ad_service_initialized',
        parameters: {
          'platform': Platform.isIOS ? 'ios' : 'android',
          'ad_provider': 'adfit',
          'tracking_permission': _isTrackingPermissionGranted,
        },
      );

      print('[AdService] 카카오 AdFit 초기화 완료');
    } catch (e) {
      print('[AdService] 카카오 AdFit 초기화 실패: $e');
      await _analytics.logEvent(
        name: 'ad_service_init_error',
        parameters: {
          'error': e.toString(),
          'ad_provider': 'adfit',
        },
      );
    }
  }

  /// iOS App Tracking Transparency 권한 요청 (앱 업데이트 시 중복 방지)
  Future<void> _requestTrackingPermission() async {
    try {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      
      // 이미 결정된 상태면 권한 요청하지 않음 (중복 방지)
      if (status == TrackingStatus.notDetermined) {
        final newStatus = await AppTrackingTransparency.requestTrackingAuthorization();
        _isTrackingPermissionGranted = newStatus == TrackingStatus.authorized;
        
        await _analytics.logEvent(
          name: 'tracking_permission_requested',
          parameters: {
            'status': _isTrackingPermissionGranted ? 'granted' : 'denied',
          },
        );
      } else {
        _isTrackingPermissionGranted = status == TrackingStatus.authorized;
        
        await _analytics.logEvent(
          name: 'tracking_permission_status',
          parameters: {
            'status': _isTrackingPermissionGranted ? 'granted' : 'denied',
            'already_determined': true,
          },
        );
      }
    } catch (e) {
      print('[AdService] 추적 권한 확인 실패: $e');
    }
  }

  /// 배너 광고 ID 반환
  String get bannerAdId => _bannerAdId;

  /// 전면광고 ID 반환
  String get interstitialAdId => _interstitialAdId;

  /// 네이티브 광고 ID 반환
  String get nativeAdId => _nativeAdId;

  /// 전면광고 로드
  Future<void> loadInterstitialAd() async {
    try {
      // AdFit 전면광고는 표시 시점에 로드되므로 여기서는 상태만 설정
      _isInterstitialAdLoaded = true;
      
      // 광고 로드 완료 이벤트 로깅
      await _analytics.logEvent(
        name: 'interstitial_ad_loaded',
        parameters: {
          'ad_unit_id': interstitialAdId,
          'ad_provider': 'adfit',
        },
      );
      
      print('[AdService] 전면광고 로드 준비 완료');
    } catch (e) {
      print('[AdService] 전면광고 로드 중 오류: $e');
      await _analytics.logEvent(
        name: 'interstitial_ad_load_error',
        parameters: {
          'error': e.toString(),
          'ad_provider': 'adfit',
        },
      );
    }
  }

  /// 전면광고 표시 (앱 진입 시 3-5초 지연 후)
  Future<void> showInterstitialAd() async {
    if (!_isInterstitialAdLoaded) {
      print('[AdService] 전면광고가 로드되지 않음');
      return;
    }

    try {
      // 광고 표시 이벤트 로깅
      await _analytics.logEvent(
        name: 'interstitial_ad_shown',
        parameters: {
          'ad_unit_id': interstitialAdId,
          'ad_provider': 'adfit',
        },
      );

      // AdFit 전면광고 표시
      // flutter_adfit 플러그인에는 전면광고가 없으므로 플랫폼 채널을 통해 직접 호출
      // TODO: 네이티브 코드에서 AdFit 전면광고 구현 필요
      try {
        const platform = MethodChannel('flutter_adfit/interstitial');
        await platform.invokeMethod('showInterstitialAd', {
          'adId': interstitialAdId,
        });
        
        print('[AdService] 전면광고 표시 요청 완료');
        // 광고 표시 후 상태 초기화
        _isInterstitialAdLoaded = false;
      } catch (e) {
        print('[AdService] 전면광고 표시 중 오류: $e');
        await _analytics.logEvent(
          name: 'interstitial_ad_show_error',
          parameters: {
            'error': e.toString(),
            'ad_provider': 'adfit',
          },
        );
        _isInterstitialAdLoaded = false;
      }
      
      print('[AdService] 전면광고 표시 완료');
    } catch (e) {
      print('[AdService] 전면광고 표시 실패: $e');
      await _analytics.logEvent(
        name: 'interstitial_ad_show_error',
        parameters: {
          'error': e.toString(),
          'ad_provider': 'adfit',
        },
      );
    }
  }

  /// 배너 광고 클릭 이벤트 로깅
  Future<void> logBannerAdClick() async {
    await _analytics.logEvent(
      name: 'banner_ad_clicked',
      parameters: {
        'ad_unit_id': bannerAdId,
        'ad_provider': 'adfit',
      },
    );
  }

  /// 전면광고 클릭 이벤트 로깅
  Future<void> logInterstitialAdClick() async {
    await _analytics.logEvent(
      name: 'interstitial_ad_clicked',
      parameters: {
        'ad_unit_id': interstitialAdId,
        'ad_provider': 'adfit',
      },
    );
  }

  /// 네이티브 광고 클릭 이벤트 로깅
  Future<void> logNativeAdClick() async {
    await _analytics.logEvent(
      name: 'native_ad_clicked',
      parameters: {
        'ad_unit_id': nativeAdId,
        'ad_provider': 'adfit',
      },
    );
  }

  /// 광고 수익 이벤트 로깅
  Future<void> logAdRevenue({
    required String adType,
    required double revenue,
    required String currency,
  }) async {
    await _analytics.logEvent(
      name: 'ad_revenue',
      parameters: {
        'ad_type': adType,
        'revenue': revenue,
        'currency': currency,
        'ad_provider': 'adfit',
      },
    );
  }

  /// 앱 세션 시작 이벤트 로깅
  Future<void> logSessionStart() async {
    try {
      await _analytics.logEvent(
        name: 'app_session_start',
        parameters: {
          'platform': Platform.isIOS ? 'ios' : 'android',
          'tracking_permission': _isTrackingPermissionGranted ? 'granted' : 'denied',
        },
      );
    } catch (e) {
      print('⚠️ Analytics session start logging failed: $e');
    }
  }

  /// 앱 세션 종료 이벤트 로깅
  Future<void> logSessionEnd() async {
    try {
      await _analytics.logEvent(
        name: 'app_session_end',
        parameters: {
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
      );
    } catch (e) {
      print('⚠️ Analytics session end logging failed: $e');
    }
  }

  /// 스크린 뷰 이벤트 로깅
  Future<void> logScreenView(String screenName) async {
    await _analytics.logScreenView(screenName: screenName);
  }

  /// 사용자 행동 이벤트 로깅
  Future<void> logUserAction(String action, Map<String, dynamic> parameters) async {
    // logEvent의 parameters는 Map<String, Object>? 타입이어야 하므로,
    // Map<String, dynamic>을 Map<String, Object>로 변환하여 전달합니다.
    await _analytics.logEvent(
      name: action,
      parameters: parameters.map((key, value) => MapEntry(key, value as Object)),
    );
  }
}
