import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/ad_service.dart';

/// 상단 배너 광고 위젯
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
  BannerAd? _bannerAd;
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
      _bannerAd = BannerAd(
        adUnitId: _adService.bannerAdId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            setState(() {
              _isAdLoaded = true;
              _isAdLoading = false;
            });
            
            // 광고 로드 완료 이벤트 로깅
            _adService.logUserAction('banner_ad_loaded', {
              'ad_unit_id': _adService.bannerAdId,
              'ad_size': 'banner',
            });
            
            debugPrint('[BannerAdWidget] 배너 광고 로드 완료');
          },
          onAdFailedToLoad: (ad, error) {
            setState(() {
              _isAdLoaded = false;
              _isAdLoading = false;
            });
            
            // 광고 로드 실패 이벤트 로깅
            _adService.logUserAction('banner_ad_load_failed', {
              'error_code': error.code,
              'error_message': error.message,
            });
            
            debugPrint('[BannerAdWidget] 배너 광고 로드 실패: ${error.message}');
          },
          onAdOpened: (ad) {
            // 광고 클릭 이벤트 로깅
            _adService.logBannerAdClick();
            debugPrint('[BannerAdWidget] 배너 광고 클릭됨');
          },
          onAdClosed: (ad) {
            debugPrint('[BannerAdWidget] 배너 광고 닫힘');
          },
        ),
      );
      
      await _bannerAd!.load();
    } catch (e) {
      setState(() {
        _isAdLoaded = false;
        _isAdLoading = false;
      });
      
      debugPrint('[BannerAdWidget] 배너 광고 로드 중 오류: $e');
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 광고가 로드되지 않았거나 로딩 중일 때는 빈 공간 반환
    if (!_isAdLoaded || _bannerAd == null) {
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
          width: _bannerAd!.size.width.toDouble(),
          height: _bannerAd!.size.height.toDouble(),
          child: AdWidget(ad: _bannerAd!),
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
