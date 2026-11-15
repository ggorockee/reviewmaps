import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

/// AdMob 광고 서비스
/// Google 및 Apple 정책에 위반되지 않으면서 수익화를 최적화
class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  // AdMob 앱 ID (참조용 - ios/Runner/Info.plist 및 AndroidManifest.xml에서 설정)
  // 주의: 앱 ID와 광고 단위 ID는 반드시 같은 AdMob 계정(pub-8516861197467665)이어야 함
  // Android: ca-app-pub-8516861197467665~2285990824
  // iOS: ca-app-pub-8516861197467665~7038364871

  // 광고 단위 ID
  static const String _androidBannerAdId = 'ca-app-pub-8516861197467665/1456124881';
  static const String _iosBannerAdId = 'ca-app-pub-8516861197467665/3701755096';
  static const String _androidNativeAdId = 'ca-app-pub-8516861197467665/4499546031';
  static const String _iosNativeAdId = 'ca-app-pub-8516861197467665/7720891152';

  // 테스트용 광고 단위 ID (개발 시 사용)
  static const String _testBannerAdId = 'ca-app-pub-3940256099942544/6300978111';
  static const String _testNativeAdId = 'ca-app-pub-3940256099942544/2247696110';

  // Firebase Analytics 인스턴스
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  // 광고 상태 관리
  bool _isTrackingPermissionGranted = false;

  /// AdMob 초기화
  Future<void> initialize() async {
    try {
      // AdMob 초기화
      await MobileAds.instance.initialize();

      // 참고: iOS 추적 권한(ATT)은 여기서 요청하지 않음
      // main()은 첫 화면이 그려지기 전이라 iOS가 팝업을 무시할 수 있으므로
      // 스플래시 화면에서 requestTrackingAuthorizationIfNeeded()로 요청

      // Firebase Analytics 이벤트 로깅
      await _analytics.logEvent(
        name: 'ad_service_initialized',
        parameters: {
          'platform': Platform.isIOS ? 'ios' : 'android',
          'tracking_permission': _isTrackingPermissionGranted ? 'granted' : 'denied',
        },
      );

      if (kDebugMode) print('[AdService] AdMob 초기화 완료');
    } catch (e) {
      if (kDebugMode) print('[AdService] AdMob 초기화 실패: $e');
      await _analytics.logEvent(
        name: 'ad_service_init_error',
        parameters: {'error': e.toString()},
      );
    }
  }

  /// 앱 시작 시 추적 권한 요청 (플랫폼별 처리)
  ///
  /// - iOS 14.5+: App Tracking Transparency 시스템 팝업 요청
  ///   앱이 활성 상태(첫 프레임 이후)일 때만 팝업이 표시되므로 스플래시에서 호출
  /// - Android: ATT에 해당하는 시스템 팝업 없음
  ///   (AD_ID 권한은 매니페스트에 선언, 맞춤 광고 여부는 기기 설정에서 사용자가 관리)
  Future<void> requestTrackingAuthorizationIfNeeded() async {
    if (!Platform.isIOS) return;
    await _requestTrackingPermission();
  }

  /// iOS App Tracking Transparency 권한 요청 (앱 업데이트 시 중복 방지)
  Future<void> _requestTrackingPermission() async {
    try {
      // 직전 시스템 팝업(알림 권한 등)이 닫힌 직후에는 앱이 아직 inactive 상태일 수 있어
      // 잠시 대기 후 요청해야 ATT 팝업이 무시되지 않음
      await Future.delayed(const Duration(milliseconds: 500));

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
            'already_determined': 'yes',
          },
        );
      }
    } catch (e) {
      if (kDebugMode) print('[AdService] 추적 권한 확인 실패: $e');
    }
  }

  /// 플랫폼별 배너 광고 ID 반환
  String get bannerAdId {
    // 개발 환경에서는 테스트 광고 사용
    if (_isDebugMode()) {
      return _testBannerAdId;
    }
    
    return Platform.isIOS ? _iosBannerAdId : _androidBannerAdId;
  }

  /// 플랫폼별 네이티브 광고 ID 반환
  String get nativeAdId {
    // 개발 환경에서는 테스트 광고 사용
    if (_isDebugMode()) {
      return _testNativeAdId;
    }
    
    return Platform.isIOS ? _iosNativeAdId : _androidNativeAdId;
  }

  /// 디버그 모드 확인
  /// kDebugMode를 사용하여 자동으로 디버그/릴리즈 구분
  bool _isDebugMode() {
    return kDebugMode; // 디버그 빌드에서는 테스트 광고, 릴리즈에서는 실제 광고
  }

  /// 배너 광고 클릭 이벤트 로깅
  Future<void> logBannerAdClick() async {
    await _analytics.logEvent(
      name: 'banner_ad_clicked',
      parameters: {'ad_unit_id': bannerAdId},
    );
  }

  /// 네이티브 광고 클릭 이벤트 로깅
  Future<void> logNativeAdClick() async {
    await _analytics.logEvent(
      name: 'native_ad_clicked',
      parameters: {'ad_unit_id': nativeAdId},
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
      debugPrint('⚠️ Analytics session start logging failed: $e');
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
      debugPrint('⚠️ Analytics session end logging failed: $e');
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
