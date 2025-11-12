import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/ad_service.dart';

/// 네이티브 광고 위젯 (카카오 AdFit)
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
      setState(() {
        _isAdLoaded = true;
        _isAdLoading = false;
      });

      // 광고 로드 완료 이벤트 로깅
      _adService.logUserAction('native_ad_loaded', {
        'ad_unit_id': _adService.nativeAdId,
        'ad_provider': 'adfit',
      });

      print('[NativeAdWidget] 네이티브 광고 로드 완료');
    } catch (e) {
      setState(() {
        _isAdLoaded = false;
        _isAdLoading = false;
      });

      // 광고 로드 실패 이벤트 로깅
      _adService.logUserAction('native_ad_load_failed', {
        'error': e.toString(),
        'ad_provider': 'adfit',
      });

      print('[NativeAdWidget] 네이티브 광고 로드 실패: $e');
    }
  }

  /// 네이티브 광고 플레이스홀더
  /// 
  /// 참고: flutter_adfit 플러그인에는 네이티브 광고가 없어서 현재 구현되지 않음
  /// 향후 네이티브 코드로 직접 구현 필요
  Widget _buildNativeAdPlaceholder() {
    return Center(
      child: Text(
        '네이티브 광고 (구현 예정)',
        style: TextStyle(
          color: Colors.grey[400],
          fontSize: 12.sp,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 광고가 로드되지 않았거나 로딩 중일 때는 빈 공간 반환
    if (!_isAdLoaded) {
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
            color: Colors.black.withOpacity(0.05),
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

          // 네이티브 광고 콘텐츠 (2:1 비율)
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(12.r),
                bottomRight: Radius.circular(12.r),
              ),
              child: _buildNativeAdPlaceholder(),
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
