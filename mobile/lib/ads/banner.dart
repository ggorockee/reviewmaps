import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';

/// 홈 상단 고정 배너 광고 (고정형 적응형 배너, Anchored Adaptive Banner)
/// ============================================================
/// - 화면 폭에 맞춰 크기를 결정하는 Google 권장 고정 배너 형식
/// - 스크롤 영역 밖(상단)에 고정되어 항상 노출
/// - 앱바(검색 버튼)와 간격을 두어 의도치 않은 클릭 방지
/// - 로딩 중에는 자리를 확보해 레이아웃 밀림 방지, 로드 실패 시 자리를 접음
/// ============================================================
class MyBannerAdWidget extends StatefulWidget {
  const MyBannerAdWidget({super.key});

  @override
  State<MyBannerAdWidget> createState() => _MyBannerAdWidgetState();
}

class _MyBannerAdWidgetState extends State<MyBannerAdWidget> {
  final AdService _adService = AdService();

  /// 앱바(검색 버튼 등 터치 요소)와 배너 사이 간격 (dp)
  static const double _verticalGap = 6;

  BannerAd? _bannerAd;
  AdSize? _adSize;
  bool _isLoaded = false;
  bool _isFailed = false;
  bool _loadRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 적응형 크기 계산에 MediaQuery가 필요하므로 initState가 아닌 여기서 1회 로드
    if (!_loadRequested) {
      _loadRequested = true;
      _loadAd();
    }
  }

  Future<void> _loadAd() async {
    final int width = MediaQuery.sizeOf(context).width.truncate();
    final AnchoredAdaptiveBannerAdSize? size =
        await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);

    if (!mounted) return;
    if (size == null) {
      debugPrint('❌ [BannerAd] 적응형 배너 크기 계산 실패');
      setState(() => _isFailed = true);
      return;
    }

    final String adUnitId = _adService.bannerAdId;
    if (kDebugMode) {
      debugPrint('🎯 [BannerAd] 고정 적응형 배너 로드 시작 (${size.width}x${size.height}) - $adUnitId');
    }

    final banner = BannerAd(
      size: size,
      adUnitId: adUnitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('❌ [BannerAd] 광고 로드 실패: $error');
          ad.dispose();
          _bannerAd = null;
          _adService.logUserAction('banner_ad_load_failed', {
            'error_code': error.code,
            'error_message': error.message,
          });
          if (mounted) setState(() => _isFailed = true);
        },
        onAdOpened: (ad) {
          _adService.logBannerAdClick();
        },
      ),
    );

    // 로드 중 위젯이 dispose되어도 해제될 수 있도록 즉시 참조 보관
    _bannerAd = banner;
    setState(() => _adSize = size);
    await banner.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 로드 실패 시 빈 공간을 남기지 않음
    if (_isFailed) return const SizedBox.shrink();

    final AdSize? size = _adSize;
    final BannerAd? ad = _bannerAd;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: _verticalGap),
      child: SizedBox(
        width: double.infinity,
        // 크기 계산 전에는 표준 배너 높이(50dp)로 자리 확보
        height: size?.height.toDouble() ?? AdSize.banner.height.toDouble(),
        child: (_isLoaded && ad != null && size != null)
            ? Center(
                child: SizedBox(
                  width: size.width.toDouble(),
                  height: size.height.toDouble(),
                  child: AdWidget(ad: ad),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
