import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/ad_service.dart';

/// 네이티브 광고 위젯
/// ============================================================
/// 리스트나 피드에 자연스럽게 삽입되는 네이티브 광고
///
/// ✅ 정책 준수:
/// - "광고" 라벨 명확히 표시
/// - 콘텐츠와 시각적으로 구분
/// - 자연스러운 레이아웃
/// - 사용자 흐름 방해 최소화
///
/// ❌ 금지사항:
/// - 광고 라벨 숨기기
/// - 콘텐츠로 위장하기
/// - 클릭 유도하는 UI
/// ============================================================
class NativeAdWidget extends StatefulWidget {
  final double? height;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  const NativeAdWidget({
    super.key,
    this.height,
    this.margin,
    this.padding,
  });

  @override
  State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget> {
  NativeAd? _nativeAd;
  bool _isAdLoaded = false;
  bool _isAdLoading = false;
  final AdService _adService = AdService();

  @override
  void initState() {
    super.initState();
    _loadNativeAd();
  }

  /// 네이티브 광고 로드
  Future<void> _loadNativeAd() async {
    if (_isAdLoading) return;

    setState(() {
      _isAdLoading = true;
    });

    try {
      _nativeAd = NativeAd(
        adUnitId: _adService.nativeAdId,
        request: const AdRequest(),
        listener: NativeAdListener(
          onAdLoaded: (ad) {
            setState(() {
              _isAdLoaded = true;
              _isAdLoading = false;
            });

            // 광고 로드 완료 이벤트 로깅
            _adService.logUserAction('native_ad_loaded', {
              'ad_unit_id': _adService.nativeAdId,
            });

            debugPrint('[NativeAdWidget] 네이티브 광고 로드 완료');
          },
          onAdFailedToLoad: (ad, error) {
            setState(() {
              _isAdLoaded = false;
              _isAdLoading = false;
            });

            // 광고 로드 실패 이벤트 로깅
            _adService.logUserAction('native_ad_load_failed', {
              'error_code': error.code,
              'error_message': error.message,
            });

            debugPrint('[NativeAdWidget] 네이티브 광고 로드 실패: ${error.message}');

            // 광고 dispose
            ad.dispose();
          },
          onAdOpened: (ad) {
            // 광고 클릭 이벤트 로깅
            _adService.logNativeAdClick();
            debugPrint('[NativeAdWidget] 네이티브 광고 클릭됨');
          },
          onAdClosed: (ad) {
            debugPrint('[NativeAdWidget] 네이티브 광고 닫힘');
          },
        ),
        nativeTemplateStyle: NativeTemplateStyle(
          // 템플릿 스타일 (medium 템플릿 사용)
          templateType: TemplateType.medium,
          mainBackgroundColor: Colors.white,
          cornerRadius: 12.0,
          callToActionTextStyle: NativeTemplateTextStyle(
            textColor: Colors.white,
            backgroundColor: Colors.blue,
            style: NativeTemplateFontStyle.bold,
            size: 14.0,
          ),
          primaryTextStyle: NativeTemplateTextStyle(
            textColor: Colors.black87,
            backgroundColor: Colors.transparent,
            style: NativeTemplateFontStyle.bold,
            size: 16.0,
          ),
          secondaryTextStyle: NativeTemplateTextStyle(
            textColor: Colors.grey,
            backgroundColor: Colors.transparent,
            style: NativeTemplateFontStyle.normal,
            size: 14.0,
          ),
          tertiaryTextStyle: NativeTemplateTextStyle(
            textColor: Colors.grey,
            backgroundColor: Colors.transparent,
            style: NativeTemplateFontStyle.normal,
            size: 12.0,
          ),
        ),
      );

      await _nativeAd!.load();
    } catch (e) {
      setState(() {
        _isAdLoaded = false;
        _isAdLoading = false;
      });

      debugPrint('[NativeAdWidget] 네이티브 광고 로드 중 오류: $e');
    }
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 광고가 로드되지 않았거나 로딩 중일 때는 빈 공간 반환
    if (!_isAdLoaded || _nativeAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      height: widget.height ?? 300.h,
      margin: widget.margin ?? EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      padding: widget.padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: Colors.grey[200]!,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ 정책 준수: 광고 라벨 명확히 표시
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12.r),
                topRight: Radius.circular(12.r),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14.sp,
                  color: Colors.grey[600],
                ),
                SizedBox(width: 4.w),
                Text(
                  '광고',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // 네이티브 광고 콘텐츠
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(12.r),
                bottomRight: Radius.circular(12.r),
              ),
              child: AdWidget(ad: _nativeAd!),
            ),
          ),
        ],
      ),
    );
  }
}

/// 리스트 아이템 형태의 네이티브 광고
/// 추천 체험단 리스트에 자연스럽게 삽입되는 네이티브 광고
class NativeAdListItem extends StatelessWidget {
  const NativeAdListItem({super.key});

  @override
  Widget build(BuildContext context) {
    return NativeAdWidget(
      height: 280.h,
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      padding: EdgeInsets.zero,
    );
  }
}
