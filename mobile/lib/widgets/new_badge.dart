import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 새로운 캠페인을 표시하는 뱃지
class NewBadge extends StatelessWidget {
  final bool dense;

  const NewBadge({
    super.key,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
    
    // 태블릿에서 시스템 폰트 크기에 따라 동적 조정
    final double baseHorizontalPadding = dense ? 4.0 : (isTablet ? 8.0 : 6.0);
    final double baseVerticalPadding = dense ? 1.0 : (isTablet ? 3.0 : 2.0);
    final double baseFontSize = dense ? 8.0 : (isTablet ? 12.0 : 9.0);
    final double baseBorderRadius = dense ? 6.0 : (isTablet ? 10.0 : 8.0);
    
    final adjustedHorizontalPadding = (baseHorizontalPadding * textScaleFactor.clamp(0.8, 1.4)).w;
    final adjustedVerticalPadding = (baseVerticalPadding * textScaleFactor.clamp(0.8, 1.4)).h;
    final adjustedFontSize = (baseFontSize * textScaleFactor.clamp(0.8, 1.4));
    final adjustedBorderRadius = (baseBorderRadius * textScaleFactor.clamp(0.8, 1.4)).r;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: adjustedHorizontalPadding,
        vertical: adjustedVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(adjustedBorderRadius),
        border: Border.all(
          color: Colors.red.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        'NEW',
        style: TextStyle(
          fontSize: adjustedFontSize,
          fontWeight: FontWeight.w600,
          color: Colors.red,
          height: 1.2, // 줄 간격 추가로 텍스트 클리핑 방지
        ),
      ),
    );
  }
  
  /// 태블릿 여부 확인
  bool _isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide >= 600;
  }
}

/// 인기 캠페인을 표시하는 뱃지
class HotBadge extends StatelessWidget {
  final bool dense;

  const HotBadge({
    super.key,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
    
    // 태블릿에서 시스템 폰트 크기에 따라 동적 조정
    final double baseHorizontalPadding = dense ? 4.0 : (isTablet ? 8.0 : 6.0);
    final double baseVerticalPadding = dense ? 1.0 : (isTablet ? 3.0 : 2.0);
    final double baseFontSize = dense ? 8.0 : (isTablet ? 12.0 : 9.0);
    final double baseBorderRadius = dense ? 6.0 : (isTablet ? 10.0 : 8.0);
    
    final adjustedHorizontalPadding = (baseHorizontalPadding * textScaleFactor.clamp(0.8, 1.4)).w;
    final adjustedVerticalPadding = (baseVerticalPadding * textScaleFactor.clamp(0.8, 1.4)).h;
    final adjustedFontSize = (baseFontSize * textScaleFactor.clamp(0.8, 1.4));
    final adjustedBorderRadius = (baseBorderRadius * textScaleFactor.clamp(0.8, 1.4)).r;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: adjustedHorizontalPadding,
        vertical: adjustedVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(adjustedBorderRadius),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        'HOT',
        style: TextStyle(
          fontSize: adjustedFontSize,
          fontWeight: FontWeight.w600,
          color: Colors.orange[700],
          height: 1.2, // 줄 간격 추가로 텍스트 클리핑 방지
        ),
      ),
    );
  }
  
  /// 태블릿 여부 확인
  bool _isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide >= 600;
  }
}

/// 마감임박을 표시하는 뱃지
class UrgentBadge extends StatelessWidget {
  final bool dense;

  const UrgentBadge({
    super.key,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
    
    // 태블릿에서 시스템 폰트 크기에 따라 동적 조정
    final double baseHorizontalPadding = dense ? 4.0 : (isTablet ? 8.0 : 6.0);
    final double baseVerticalPadding = dense ? 1.0 : (isTablet ? 3.0 : 2.0);
    final double baseFontSize = dense ? 8.0 : (isTablet ? 12.0 : 9.0);
    final double baseBorderRadius = dense ? 6.0 : (isTablet ? 10.0 : 8.0);
    
    final adjustedHorizontalPadding = (baseHorizontalPadding * textScaleFactor.clamp(0.8, 1.4)).w;
    final adjustedVerticalPadding = (baseVerticalPadding * textScaleFactor.clamp(0.8, 1.4)).h;
    final adjustedFontSize = (baseFontSize * textScaleFactor.clamp(0.8, 1.4));
    final adjustedBorderRadius = (baseBorderRadius * textScaleFactor.clamp(0.8, 1.4)).r;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: adjustedHorizontalPadding,
        vertical: adjustedVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(adjustedBorderRadius),
        border: Border.all(
          color: Colors.red.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        '마감임박',
        style: TextStyle(
          fontSize: adjustedFontSize,
          fontWeight: FontWeight.w600,
          color: Colors.red,
          height: 1.2, // 줄 간격 추가로 텍스트 클리핑 방지
        ),
      ),
    );
  }
  
  /// 태블릿 여부 확인
  bool _isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide >= 600;
  }
}
