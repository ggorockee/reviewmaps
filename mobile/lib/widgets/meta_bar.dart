import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/models/store_model.dart';
import 'package:mobile/widgets/deadline_chips.dart';
import 'package:mobile/screens/home_screen.dart';

/// 메타 정보 바 (마감일, 거리, 플랫폼 등)
class MetaBar extends StatelessWidget {
  final Store store;
  final bool dense;
  final bool showDistance;
  final bool showPlatform;

  const MetaBar({
    super.key,
    required this.store,
    this.dense = false,
    this.showDistance = true,
    this.showPlatform = true,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
    final List<Widget> items = [];

    // 플랫폼 정보
    if (showPlatform && store.platform.isNotEmpty) {
      items.add(_buildPlatformChip(store.platform, isTablet, textScaleFactor));
    }

    // 마감일 및 거리 칩들
    items.add(
      DeadlineChips(
        store: store,
        dense: dense,
      ),
    );

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: isTablet ? 8.w : 6.w,
          runSpacing: isTablet ? 6.h : 4.h,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: items,
        ),
        // 채널 아이콘들
        if (store.campaignChannel != null && store.campaignChannel!.isNotEmpty) ...[
          SizedBox(height: isTablet ? 6.h : 4.h),
          Row(
            children: buildChannelIcons(store.campaignChannel),
          ),
        ],
      ],
    );
  }

  Widget _buildPlatformChip(String platform, bool isTablet, double textScaleFactor) {
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
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(adjustedBorderRadius),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        platform,
        style: TextStyle(
          fontSize: adjustedFontSize,
          fontWeight: FontWeight.w500,
          color: Colors.grey[700],
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

/// 간단한 메타 정보 표시
class SimpleMeta extends StatelessWidget {
  final String text;
  final Color? color;
  final bool dense;

  const SimpleMeta({
    super.key,
    required this.text,
    this.color,
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
        color: (color ?? Colors.grey).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(adjustedBorderRadius),
        border: Border.all(
          color: (color ?? Colors.grey).withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: adjustedFontSize,
          fontWeight: FontWeight.w500,
          color: color ?? Colors.grey[700],
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
