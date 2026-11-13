import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/ad_service.dart';

/// 네이티브 광고 위젯 (small 템플릿)
/// ============================================================
/// 리스트나 피드 사이에 얇은 띠 형태로 삽입되는 네이티브 광고
///
/// ✅ 정책 준수:
/// - 템플릿 자체에 "광고" 표시(Ad attribution) 포함
/// - small 템플릿 권장 크기(폭 320dp 이상, 높이 90~200dp) 안에서 표시해
///   광고 이미지가 잘리거나 찌그러지지 않도록 함
/// - 콘텐츠와 시각적으로 구분 (테두리 카드)
///
/// ✅ 안정성:
/// - 스크롤로 화면 밖에 나가도 광고를 유지 (재요청 방지, keep-alive)
/// - 로딩 중에는 자리를 확보해 광고 등장 시 화면이 밀리지 않도록 함
/// - 로드 실패 시 자리를 접어 빈 공간을 남기지 않음
/// - 위젯 dispose 이후 setState 호출 방지 (mounted 확인)
/// ============================================================
class NativeAdWidget extends StatefulWidget {
  final EdgeInsetsGeometry? margin;

  const NativeAdWidget({super.key, this.margin});

  /// small 템플릿 표시 높이 (dp) - 권장 범위 90~200dp 안의 값
  static const double adHeight = 110;

  @override
  State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget>
    with AutomaticKeepAliveClientMixin {
  final AdService _adService = AdService();

  NativeAd? _nativeAd;
  bool _isAdLoaded = false;
  bool _isFailed = false;

  /// 광고가 로드되었으면 스크롤로 화면 밖에 나가도 위젯을 유지해 재요청을 막음
  @override
  bool get wantKeepAlive => _isAdLoaded;

  @override
  void initState() {
    super.initState();
    _loadNativeAd();
  }

  /// 네이티브 광고 로드
  void _loadNativeAd() {
    final String adUnitId = _adService.nativeAdId;

    final ad = NativeAd(
      adUnitId: adUnitId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _isAdLoaded = true);
          updateKeepAlive();

          _adService.logUserAction('native_ad_loaded', {
            'ad_unit_id': adUnitId,
            'template': 'small',
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _nativeAd = null;

          _adService.logUserAction('native_ad_load_failed', {
            'error_code': error.code,
            'error_message': error.message,
          });
          debugPrint('[NativeAdWidget] 네이티브 광고 로드 실패: ${error.message}');

          if (mounted) setState(() => _isFailed = true);
        },
        onAdOpened: (ad) {
          _adService.logNativeAdClick();
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: Colors.white,
        cornerRadius: 12.0,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: Colors.blue,
          style: NativeTemplateFontStyle.bold,
          size: 13.0,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.black87,
          backgroundColor: Colors.transparent,
          style: NativeTemplateFontStyle.bold,
          size: 14.0,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.grey,
          backgroundColor: Colors.transparent,
          style: NativeTemplateFontStyle.normal,
          size: 12.0,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.grey,
          backgroundColor: Colors.transparent,
          style: NativeTemplateFontStyle.normal,
          size: 12.0,
        ),
      ),
    );

    // 로드 중 위젯이 dispose되어도 해제될 수 있도록 즉시 참조 보관
    _nativeAd = ad;
    ad.load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 필수 호출

    // 로드 실패 시 자리를 접음
    final NativeAd? ad = _nativeAd;
    if (_isFailed || ad == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      height: NativeAdWidget.adHeight,
      margin: widget.margin ?? EdgeInsets.symmetric(horizontal: 16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        // 로딩 중에는 빈 카드로 자리만 확보 (등장 시 레이아웃 밀림 방지)
        child: _isAdLoaded ? AdWidget(ad: ad) : const SizedBox.expand(),
      ),
    );
  }
}

/// 리스트 아이템 형태의 네이티브 광고
/// 홈/캠페인 목록/검색 결과 리스트 사이에 삽입되는 small 네이티브 광고
class NativeAdListItem extends StatelessWidget {
  /// 부모가 이미 좌우 패딩을 가진 경우(예: ListView padding) EdgeInsets.zero 전달
  /// (small 템플릿 최소 폭 320dp 확보 목적)
  final EdgeInsetsGeometry? margin;

  const NativeAdListItem({super.key, this.margin});

  @override
  Widget build(BuildContext context) {
    return NativeAdWidget(margin: margin);
  }
}
