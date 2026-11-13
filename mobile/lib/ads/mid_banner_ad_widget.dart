import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';

/// 홈 화면 중단 배너 광고 (AdMob "중단_배너" 광고 단위)
///
/// - 위치: 가까운 체험단 섹션과 추천 체험단 섹션 사이
/// - 크기: 인라인 적응형 배너 (스크롤 콘텐츠용 권장 형식, 최대 높이 제한)
/// - AdMob 정책 준수:
///   - 콘텐츠(클릭 가능한 카드)와 충분한 간격을 두어 실수 클릭 방지
///   - 광고 로드 실패/미로드 시 빈 영역을 남기지 않음 (레이아웃 점프 최소화)
///   - 위젯 dispose 시 광고 객체 해제
class MidBannerAdWidget extends StatefulWidget {
  /// 광고 표시 시 아래쪽 여백 (다음 섹션과의 간격)
  final double? bottomSpacing;

  const MidBannerAdWidget({super.key, this.bottomSpacing});

  @override
  State<MidBannerAdWidget> createState() => _MidBannerAdWidgetState();
}

class _MidBannerAdWidgetState extends State<MidBannerAdWidget> {
  final AdService _adService = AdService();

  /// 인라인 적응형 배너 최대 높이 (dp) - 콘텐츠를 과도하게 가리지 않도록 제한
  static const int _maxAdHeight = 100;

  BannerAd? _bannerAd;
  AdSize? _platformSize;
  bool _isLoaded = false;
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
    // 좌우 패딩(16.w * 2)을 제외한 실제 표시 폭 기준으로 적응형 크기 계산
    final double availableWidth = MediaQuery.sizeOf(context).width - 32.w;
    final AdSize adaptiveSize = AdSize.getInlineAdaptiveBannerAdSize(
      availableWidth.truncate(),
      _maxAdHeight,
    );

    final String adUnitId = _adService.midBannerAdId;
    final banner = BannerAd(
      adUnitId: adUnitId,
      size: adaptiveSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) async {
          // 인라인 적응형은 서버가 높이를 결정하므로 실제 크기를 조회해 컨테이너에 반영
          final AdSize? size = await (ad as BannerAd).getPlatformAdSize();
          // 위젯이 이미 dispose된 경우 dispose()에서 광고도 해제됨
          if (!mounted || size == null) return;
          setState(() {
            _platformSize = size;
            _isLoaded = true;
          });
          _adService.logUserAction('mid_banner_ad_loaded', {
            'ad_unit_id': adUnitId,
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
          if (kDebugMode) {
            debugPrint('❌ [MidBannerAd] 광고 로드 실패: $error');
          }
          _adService.logUserAction('mid_banner_ad_load_failed', {
            'error_code': error.code,
            'error_message': error.message,
          });
        },
        onAdOpened: (ad) {
          _adService.logUserAction('mid_banner_ad_clicked', {
            'ad_unit_id': adUnitId,
          });
        },
      ),
    );

    // 로드 중 위젯이 dispose되어도 해제될 수 있도록 즉시 참조 보관
    _bannerAd = banner;
    await banner.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BannerAd? ad = _bannerAd;
    final AdSize? size = _platformSize;
    if (!_isLoaded || ad == null || size == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 16.w,
        right: 16.w,
        bottom: widget.bottomSpacing ?? 32.h,
      ),
      child: Center(
        child: SizedBox(
          width: size.width.toDouble(),
          height: size.height.toDouble(),
          child: AdWidget(ad: ad),
        ),
      ),
    );
  }
}
