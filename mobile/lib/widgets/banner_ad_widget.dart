import 'package:flutter/material.dart';
import 'package:flutter_adfit/flutter_adfit.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/ad_service.dart';

/// 상단 배너 광고 위젯 (카카오 AdFit)
/// UX 침해 최소화를 위해 콘텐츠 영역과 시각적으로 구분
class BannerAdWidget extends StatefulWidget {
  final double? height;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  const BannerAdWidget({
    super.key,
    this.height,
    this.margin,
    this.padding,
  });

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  bool _isAdLoaded = false;
  bool _isAdLoading = false;
  final AdService _adService = AdService();

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  /// 배너 광고 로드
  Future<void> _loadBannerAd() async {
    if (_isAdLoading) return;
    
    setState(() {
      _isAdLoading = true;
    });

    try {
      // 광고 로드 완료 이벤트 로깅
      _adService.logUserAction('banner_ad_loaded', {
        'ad_unit_id': _adService.bannerAdId,
        'ad_size': 'banner',
        'ad_provider': 'adfit',
      });
      
      setState(() {
        _isAdLoaded = true;
        _isAdLoading = false;
      });
      
      print('[BannerAdWidget] 배너 광고 로드 완료');
    } catch (e) {
      setState(() {
        _isAdLoaded = false;
        _isAdLoading = false;
      });
      
      // 광고 로드 실패 이벤트 로깅
      _adService.logUserAction('banner_ad_load_failed', {
        'error': e.toString(),
        'ad_provider': 'adfit',
      });
      
      print('[BannerAdWidget] 배너 광고 로드 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 광고가 로드되지 않았거나 로딩 중일 때는 빈 공간 반환
    if (!_isAdLoaded) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      height: widget.height ?? 50.h,
      margin: widget.margin ?? EdgeInsets.symmetric(horizontal: 16.w),
      padding: widget.padding ?? EdgeInsets.all(8.w),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          top: BorderSide(color: Colors.grey[200]!, width: 1),
          bottom: BorderSide(color: Colors.grey[200]!, width: 1),
        ),
      ),
      child: Center(
        child: SizedBox(
          width: 320.w,
          height: 50.h,
          child: AdFitBanner(
            adId: _adService.bannerAdId,
            adSize: AdFitBannerSize.BANNER,
            listener: (AdFitEvent event, AdFitEventData data) {
              if (event == AdFitEvent.AdReceived) {
                print('[BannerAdWidget] 배너 광고 수신 완료');
                setState(() {
                  _isAdLoaded = true;
                });
              } else if (event == AdFitEvent.AdReceiveFailed) {
                print('[BannerAdWidget] 배너 광고 수신 실패: ${data.message}');
                setState(() {
                  _isAdLoaded = false;
                });
                _adService.logUserAction('banner_ad_load_failed', {
                  'error': data.message ?? 'Unknown error',
                  'ad_provider': 'adfit',
                });
              } else if (event == AdFitEvent.AdClicked) {
                print('[BannerAdWidget] 배너 광고 클릭됨');
                _adService.logBannerAdClick();
              }
            },
          ),
        ),
      ),
    );
  }
}

/// 앱 상단 고정 배너 광고
/// 항상 노출 가능하며 UX 침해 최소화
class TopBannerAdWidget extends StatelessWidget {
  const TopBannerAdWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const BannerAdWidget(
      height: 50,
      margin: EdgeInsets.symmetric(horizontal: 16),
      padding: EdgeInsets.all(8),
    );
  }
}

/// 앱 하단 고정 배너 광고
/// 네비게이션 바 위에 배치
class BottomBannerAdWidget extends StatelessWidget {
  const BottomBannerAdWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: const BannerAdWidget(
        height: 50,
        margin: EdgeInsets.symmetric(horizontal: 16),
        padding: EdgeInsets.all(8),
      ),
    );
  }
}
