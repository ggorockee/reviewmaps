import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// InterstitialAdService
/// ------------------------------------------------------------
/// 전면광고(Interstitial Ad) 관리 서비스
/// - 앱 시작 시, 종료 시, 특정 액션 시 전면광고 표시
/// - 광고 로딩 상태 관리 및 사용자 경험 최적화
class InterstitialAdService {
  static final InterstitialAdService _instance = InterstitialAdService._internal();
  factory InterstitialAdService() => _instance;
  InterstitialAdService._internal();

  /// AdMob 전면광고 단위 ID (실제 운영 ID)
  static final String _adUnitId = 'ca-app-pub-3219791135582658/7482692471';

  InterstitialAd? _interstitialAd;
  bool _isAdReady = false;
  bool _isLoading = false;

  /// 전면광고 로딩 상태
  bool get isAdReady => _isAdReady;

  /// 전면광고 로딩 중인지 확인
  bool get isLoading => _isLoading;

  /// 전면광고 로드
  Future<void> loadAd() async {
    if (_isLoading) return; // 이미 로딩 중이면 중복 방지
    
    _isLoading = true;
    
    // 빌드 모드에 따른 디버깅 정보 출력
    if (kDebugMode) {
      debugPrint('🎯 [InterstitialAd] DEBUG 모드에서 전면광고 로드 시작 - 테스트 광고 표시 예상');
    } else {
      debugPrint('🎯 [InterstitialAd] RELEASE 모드에서 전면광고 로드 시작 - 실제 광고 표시 예상');
    }
    
    try {
      await InterstitialAd.load(
        adUnitId: _adUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (InterstitialAd ad) {
            if (kDebugMode) {
              debugPrint('✅ [InterstitialAd] 테스트 전면광고 로드 완료 (DEBUG 모드)');
            } else {
              debugPrint('✅ [InterstitialAd] 실제 전면광고 로드 완료 (RELEASE 모드)');
            }
            _interstitialAd = ad;
            _isAdReady = true;
            _isLoading = false;
            _setAdCallbacks();
          },
          onAdFailedToLoad: (LoadAdError error) {
            debugPrint('❌ [InterstitialAd] 전면광고 로드 실패: $error');
            _interstitialAd = null;
            _isAdReady = false;
            _isLoading = false;
          },
        ),
      );
    } catch (e) {
      debugPrint('❌ [InterstitialAd] 전면광고 로드 예외: $e');
      _isLoading = false;
    }
  }

  /// 전면광고 콜백 설정
  void _setAdCallbacks() {
    _interstitialAd?.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (InterstitialAd ad) {
        debugPrint('🎯 [InterstitialAd] 전면광고 표시됨');
      },
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        debugPrint('🎯 [InterstitialAd] 전면광고 닫힘');
        ad.dispose();
        _interstitialAd = null;
        _isAdReady = false;
        // 광고 닫힌 후 다음 광고 미리 로드
        loadAd();
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
        debugPrint('❌ [InterstitialAd] 전면광고 표시 실패: $error');
        ad.dispose();
        _interstitialAd = null;
        _isAdReady = false;
        // 실패 시에도 다음 광고 미리 로드
        loadAd();
      },
    );
  }

  /// 전면광고 표시
  /// [onAdClosed] 광고 닫힌 후 실행할 콜백
  Future<void> showAd({VoidCallback? onAdClosed}) async {
    if (!_isAdReady || _interstitialAd == null) {
      debugPrint('⚠️ [InterstitialAd] 광고가 준비되지 않음');
      onAdClosed?.call(); // 광고가 없어도 다음 액션 진행
      return;
    }

    // 광고 닫힘 콜백 등록 (기존 콜백에 추가)
    final originalCallback = _interstitialAd!.fullScreenContentCallback;
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: originalCallback?.onAdShowedFullScreenContent,
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        originalCallback?.onAdDismissedFullScreenContent?.call(ad);
        onAdClosed?.call(); // 사용자 정의 콜백 실행
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
        originalCallback?.onAdFailedToShowFullScreenContent?.call(ad, error);
        onAdClosed?.call(); // 실패해도 다음 액션 진행
      },
    );

    try {
      await _interstitialAd!.show();
    } catch (e) {
      debugPrint('❌ [InterstitialAd] 전면광고 표시 예외: $e');
      onAdClosed?.call(); // 예외 발생해도 다음 액션 진행
    }
  }

  /// 리소스 정리
  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _isAdReady = false;
    _isLoading = false;
  }
}
