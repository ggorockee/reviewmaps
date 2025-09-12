import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// RewardedAdService
/// ------------------------------------------------------------
/// 리워드 광고 관리 서비스
/// - 앱 종료 시 "더 많은 체험단을 보시겠어요?" 형태로 제공
/// - 광고 시청 완료 시 추가 혜택 제공 (프리미엄 정보, 쿠폰 등)
class RewardedAdService {
  static final RewardedAdService _instance = RewardedAdService._internal();
  factory RewardedAdService() => _instance;
  RewardedAdService._internal();

  /// AdMob 리워드 광고 단위 ID (실제 운영 ID)
  static final String _adUnitId = 'ca-app-pub-3219791135582658/4720797760';

  RewardedAd? _rewardedAd;
  bool _isAdReady = false;
  bool _isLoading = false;

  /// 리워드 광고 로딩 상태
  bool get isAdReady => _isAdReady;

  /// 리워드 광고 로딩 중인지 확인
  bool get isLoading => _isLoading;

  /// 리워드 광고 로드
  Future<void> loadAd() async {
    if (_isLoading) return; // 이미 로딩 중이면 중복 방지
    
    _isLoading = true;
    
    // 빌드 모드에 따른 디버깅 정보 출력
    if (kDebugMode) {
      debugPrint('🎯 [RewardedAd] DEBUG 모드에서 리워드광고 로드 시작 - 테스트 광고 표시 예상');
    } else {
      debugPrint('🎯 [RewardedAd] RELEASE 모드에서 리워드광고 로드 시작 - 실제 광고 표시 예상');
    }
    
    try {
      await RewardedAd.load(
        adUnitId: _adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) {
            if (kDebugMode) {
              debugPrint('✅ [RewardedAd] 테스트 리워드광고 로드 완료 (DEBUG 모드)');
            } else {
              debugPrint('✅ [RewardedAd] 실제 리워드광고 로드 완료 (RELEASE 모드)');
            }
            _rewardedAd = ad;
            _isAdReady = true;
            _isLoading = false;
            _setAdCallbacks();
          },
          onAdFailedToLoad: (LoadAdError error) {
            debugPrint('❌ [RewardedAd] 리워드광고 로드 실패: $error');
            _rewardedAd = null;
            _isAdReady = false;
            _isLoading = false;
          },
        ),
      );
    } catch (e) {
      debugPrint('❌ [RewardedAd] 리워드광고 로드 예외: $e');
      _isLoading = false;
    }
  }

  /// 리워드 광고 콜백 설정
  void _setAdCallbacks() {
    _rewardedAd?.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (RewardedAd ad) {
        debugPrint('🎁 [RewardedAd] 리워드 광고 표시됨');
      },
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        debugPrint('🎁 [RewardedAd] 리워드 광고 닫힘');
        ad.dispose();
        _rewardedAd = null;
        _isAdReady = false;
        // 광고 닫힌 후 다음 광고 미리 로드
        loadAd();
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        debugPrint('❌ [RewardedAd] 리워드 광고 표시 실패: $error');
        ad.dispose();
        _rewardedAd = null;
        _isAdReady = false;
        // 실패 시에도 다음 광고 미리 로드
        loadAd();
      },
    );
  }

  /// 리워드 광고 표시
  /// [onRewarded] 광고 시청 완료 시 실행할 콜백
  /// [onAdClosed] 광고 닫힌 후 실행할 콜백
  Future<void> showAd({
    required void Function(RewardedAd, RewardItem) onRewarded,
    VoidCallback? onAdClosed,
  }) async {
    if (!_isAdReady || _rewardedAd == null) {
      debugPrint('⚠️ [RewardedAd] 광고가 준비되지 않음');
      onAdClosed?.call(); // 광고가 없어도 다음 액션 진행
      return;
    }

    // 광고 닫힘 콜백 등록 (기존 콜백에 추가)
    final originalCallback = _rewardedAd!.fullScreenContentCallback;
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: originalCallback?.onAdShowedFullScreenContent,
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        originalCallback?.onAdDismissedFullScreenContent?.call(ad);
        onAdClosed?.call(); // 사용자 정의 콜백 실행
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        originalCallback?.onAdFailedToShowFullScreenContent?.call(ad, error);
        onAdClosed?.call(); // 실패해도 다음 액션 진행
      },
    );

    try {
      await _rewardedAd!.show(
        onUserEarnedReward: (ad, reward) => onRewarded(_rewardedAd!, reward),
      );
    } catch (e) {
      debugPrint('❌ [RewardedAd] 리워드 광고 표시 예외: $e');
      onAdClosed?.call(); // 예외 발생해도 다음 액션 진행
    }
  }

  /// 리소스 정리
  void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isAdReady = false;
    _isLoading = false;
  }
}
