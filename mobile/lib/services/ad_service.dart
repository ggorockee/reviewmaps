import 'dart:io';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

/// AdMob 광고 서비스
/// Google 및 Apple 정책에 위반되지 않으면서 수익화를 최적화
class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  // AdMob 앱 ID
  static const String _androidAppId = 'ca-app-pub-3219791135582658~5531424356';
  static const String _iosAppId = 'ca-app-pub-3219791135582658~2537889532';

  // 광고 단위 ID
  static const String _androidBannerAdId = 'ca-app-pub-3219791135582658/4571348868';
  static const String _iosBannerAdId = 'ca-app-pub-3219791135582658/2356249060';
  static const String _androidInterstitialAdId = 'ca-app-pub-3219791135582658/2389577075';
  static const String _iosInterstitialAdId = 'ca-app-pub-3219791135582658/7482692471';
  static const String _androidNativeAdId = 'ca-app-pub-3219791135582658/3299920799';
  static const String _iosNativeAdId = 'ca-app-pub-3219791135582658/4720797760';

  // 테스트용 광고 단위 ID (개발 시 사용)
  static const String _testBannerAdId = 'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitialAdId = 'ca-app-pub-3940256099942544/1033173712';
  static const String _testNativeAdId = 'ca-app-pub-3940256099942544/2247696110';

  // Firebase Analytics 인스턴스
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  // 광고 상태 관리
  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoaded = false;
  bool _isTrackingPermissionGranted = false;

  /// AdMob 초기화
  Future<void> initialize() async {
    try {
      // AdMob 초기화
      await MobileAds.instance.initialize();
      
      // iOS 14.5+ App Tracking Transparency 권한 요청
      if (Platform.isIOS) {
        await _requestTrackingPermission();
      }

      // Firebase Analytics 이벤트 로깅
      await _analytics.logEvent(
        name: 'ad_service_initialized',
        parameters: {
          'platform': Platform.isIOS ? 'ios' : 'android',
          'tracking_permission': _isTrackingPermissionGranted,
        },
      );

      print('[AdService] AdMob 초기화 완료');
    } catch (e) {
      print('[AdService] AdMob 초기화 실패: $e');
      await _analytics.logEvent(
        name: 'ad_service_init_error',
        parameters: {'error': e.toString()},
      );
    }
  }

  /// iOS App Tracking Transparency 권한 요청
  Future<void> _requestTrackingPermission() async {
    try {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      
      if (status == TrackingStatus.notDetermined) {
        final newStatus = await AppTrackingTransparency.requestTrackingAuthorization();
        _isTrackingPermissionGranted = newStatus == TrackingStatus.authorized;
      } else {
        _isTrackingPermissionGranted = status == TrackingStatus.authorized;
      }

      await _analytics.logEvent(
        name: 'tracking_permission_result',
        parameters: {
          'status': _isTrackingPermissionGranted ? 'granted' : 'denied',
        },
      );
    } catch (e) {
      print('[AdService] 추적 권한 요청 실패: $e');
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

  /// 플랫폼별 전면광고 ID 반환
  String get interstitialAdId {
    // 개발 환경에서는 테스트 광고 사용
    if (_isDebugMode()) {
      return _testInterstitialAdId;
    }
    
    return Platform.isIOS ? _iosInterstitialAdId : _androidInterstitialAdId;
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
  bool _isDebugMode() {
    // 실제 배포 시에는 false로 변경
    return true; // 개발 중이므로 테스트 광고 사용
  }

  /// 전면광고 로드
  Future<void> loadInterstitialAd() async {
    try {
      await InterstitialAd.load(
        adUnitId: interstitialAdId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _interstitialAd = ad;
            _isInterstitialAdLoaded = true;
            
            // 광고 로드 완료 이벤트 로깅
            _analytics.logEvent(
              name: 'interstitial_ad_loaded',
              parameters: {'ad_unit_id': interstitialAdId},
            );
            
            print('[AdService] 전면광고 로드 완료');
          },
          onAdFailedToLoad: (error) {
            _isInterstitialAdLoaded = false;
            
            // 광고 로드 실패 이벤트 로깅
            _analytics.logEvent(
              name: 'interstitial_ad_load_failed',
              parameters: {
                'error_code': error.code,
                'error_message': error.message,
              },
            );
            
            print('[AdService] 전면광고 로드 실패: ${error.message}');
          },
        ),
      );
    } catch (e) {
      print('[AdService] 전면광고 로드 중 오류: $e');
      await _analytics.logEvent(
        name: 'interstitial_ad_load_error',
        parameters: {'error': e.toString()},
      );
    }
  }

  /// 전면광고 표시 (앱 진입 시 3-5초 지연 후)
  Future<void> showInterstitialAd() async {
    if (!_isInterstitialAdLoaded || _interstitialAd == null) {
      print('[AdService] 전면광고가 로드되지 않음');
      return;
    }

    try {
      // 광고 표시 이벤트 로깅
      await _analytics.logEvent(
        name: 'interstitial_ad_shown',
        parameters: {'ad_unit_id': interstitialAdId},
      );

      await _interstitialAd!.show();
      
      // 광고 표시 후 상태 초기화
      _interstitialAd = null;
      _isInterstitialAdLoaded = false;
      
      print('[AdService] 전면광고 표시 완료');
    } catch (e) {
      print('[AdService] 전면광고 표시 실패: $e');
      await _analytics.logEvent(
        name: 'interstitial_ad_show_error',
        parameters: {'error': e.toString()},
      );
    }
  }

  /// 배너 광고 클릭 이벤트 로깅
  Future<void> logBannerAdClick() async {
    await _analytics.logEvent(
      name: 'banner_ad_clicked',
      parameters: {'ad_unit_id': bannerAdId},
    );
  }

  /// 전면광고 클릭 이벤트 로깅
  Future<void> logInterstitialAdClick() async {
    await _analytics.logEvent(
      name: 'interstitial_ad_clicked',
      parameters: {'ad_unit_id': interstitialAdId},
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
