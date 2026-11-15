import 'package:flutter/foundation.dart';
import 'package:mobile/services/consent_service.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';

/// 홈 최상단 배너 광고 (인라인 적응형 배너, Inline Adaptive Banner)
/// ============================================================
/// - 스크롤 콘텐츠 안에 배치되어 위로 스크롤하면 함께 사라짐
/// - 스크롤 영역용 Google 권장 형식: 화면 폭에 맞추고 높이는 최대값으로 제한
/// - 앱바(검색 버튼)와 간격을 두어 의도치 않은 클릭 방지
/// - 로딩 중에는 표준 배너 높이로 자리 확보, 로드 실패 시 자리를 접음
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

  /// 인라인 적응형 배너 최대 높이 (dp) - 첫 화면 콘텐츠를 과도하게 가리지 않도록 제한
  static const int _maxAdHeight = 60;

  BannerAd? _bannerAd;
  AdSize? _platformSize;
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

  void _loadAd() {
    // 광고 동의 전에는 광고 요청 금지 (UMP 정책)
    if (!ConsentService().isAdsInitialized) return;
    final int width = MediaQuery.sizeOf(context).width.truncate();
    final AdSize size = AdSize.getInlineAdaptiveBannerAdSize(width, _maxAdHeight);
    final String adUnitId = _adService.bannerAdId;

    if (kDebugMode) {
      debugPrint('🎯 [BannerAd] 인라인 적응형 배너 로드 시작 (폭 $width, 최대 높이 $_maxAdHeight) - $adUnitId');
    }

    final banner = BannerAd(
      size: size,
      adUnitId: adUnitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) async {
          // 인라인 적응형은 서버가 높이를 결정하므로 실제 크기를 조회해 컨테이너에 반영
          final AdSize? platformSize = await (ad as BannerAd).getPlatformAdSize();
          // 위젯이 이미 dispose된 경우 dispose()에서 광고도 해제됨
          if (!mounted || platformSize == null) return;
          setState(() {
            _platformSize = platformSize;
            _isLoaded = true;
          });
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
    banner.load();
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

    final AdSize? size = _platformSize;
    final BannerAd? ad = _bannerAd;
    final bool ready = _isLoaded && ad != null && size != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: _verticalGap),
      child: SizedBox(
        width: double.infinity,
        // 로드 전에는 표준 배너 높이(50dp)로 자리 확보해 레이아웃 밀림 최소화
        height: ready ? size.height.toDouble() : AdSize.banner.height.toDouble(),
        child: ready
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
