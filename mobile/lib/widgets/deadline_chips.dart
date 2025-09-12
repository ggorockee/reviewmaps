import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/models/store_model.dart';

/// 마감일 및 거리 정보를 표시하는 칩 위젯들
class DeadlineChips extends StatelessWidget {
  final Store store;
  final bool dense;

  const DeadlineChips({
    super.key,
    required this.store,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    final textScaleFactor = MediaQuery.textScalerOf(context).textScaleFactor;
    final List<Widget> chips = [];

    // 마감일 칩
    if (store.applyDeadline != null) {
      chips.add(_buildDeadlineChip(store.applyDeadline!, isTablet, textScaleFactor));
    }

    // 거리 칩
    if (store.distance != null) {
      chips.add(_buildDistanceChip(store.distance!, isTablet, textScaleFactor));
    }

    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: isTablet ? 6.w : 4.w,
      runSpacing: isTablet ? 6.h : 4.h,
      children: chips,
    );
  }

  Widget _buildDeadlineChip(DateTime deadline, bool isTablet, double textScaleFactor) {
    // D-day 계산
    final dDay = _calculateDDay(deadline);
    final isUrgent = dDay != null && dDay <= 3;

    // 태블릿에서 시스템 폰트 크기에 따라 동적 조정
    final double baseHorizontalPadding = dense ? 6.0 : (isTablet ? 16.0 : 8.0);
    final double baseVerticalPadding = dense ? 3.0 : (isTablet ? 8.0 : 3.0);
    final double baseFontSize = dense ? 11.0 : (isTablet ? 16.0 : 12.0);
    final double baseBorderRadius = dense ? 12.0 : (isTablet ? 20.0 : 12.0);
    
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
        color: isUrgent ? Colors.red.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(adjustedBorderRadius),
        border: Border.all(
          color: isUrgent ? Colors.red.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        dDay != null ? 'D-$dDay' : '마감임박',
        style: TextStyle(
          fontSize: adjustedFontSize,
          fontWeight: FontWeight.w500,
          color: isUrgent ? Colors.red : Colors.grey[700],
          height: 1.2, // 줄 간격 추가로 텍스트 클리핑 방지
        ),
      ),
    );
  }

  Widget _buildDistanceChip(double distance, bool isTablet, double textScaleFactor) {
    final distanceText = distance >= 1 
        ? '${distance.toStringAsFixed(1)}km'
        : '${(distance * 1000).round()}m';

    // 태블릿에서 시스템 폰트 크기에 따라 동적 조정
    final double baseHorizontalPadding = dense ? 6.0 : (isTablet ? 16.0 : 8.0);
    final double baseVerticalPadding = dense ? 3.0 : (isTablet ? 8.0 : 3.0);
    final double baseFontSize = dense ? 11.0 : (isTablet ? 16.0 : 12.0);
    final double baseBorderRadius = dense ? 12.0 : (isTablet ? 20.0 : 12.0);
    
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
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(adjustedBorderRadius),
        border: Border.all(
          color: Colors.blue.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        distanceText,
        style: TextStyle(
          fontSize: adjustedFontSize,
          fontWeight: FontWeight.w500,
          color: Colors.blue[700],
          height: 1.2, // 줄 간격 추가로 텍스트 클리핑 방지
        ),
      ),
    );
  }

  int? _calculateDDay(DateTime deadline) {
    final now = DateTime.now();
    final difference = deadline.difference(now).inDays;
    return difference >= 0 ? difference : null;
  }
  
  /// 태블릿 여부 확인
  bool _isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide >= 600;
  }
}

/// 단일 마감일 칩
class DeadlineChip extends StatelessWidget {
  final DateTime deadline;
  final bool dense;

  const DeadlineChip({
    super.key,
    required this.deadline,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    final textScaleFactor = MediaQuery.textScalerOf(context).textScaleFactor;
    final dDay = _calculateDDay(deadline);
    final isUrgent = dDay != null && dDay <= 3;

    // 태블릿에서 시스템 폰트 크기에 따라 동적 조정
    final double baseHorizontalPadding = dense ? 6.0 : (isTablet ? 16.0 : 8.0);
    final double baseVerticalPadding = dense ? 3.0 : (isTablet ? 8.0 : 3.0);
    final double baseFontSize = dense ? 11.0 : (isTablet ? 16.0 : 12.0);
    final double baseBorderRadius = dense ? 12.0 : (isTablet ? 20.0 : 12.0);
    
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
        color: isUrgent ? Colors.red.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(adjustedBorderRadius),
        border: Border.all(
          color: isUrgent ? Colors.red.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        dDay != null ? 'D-$dDay' : '마감임박',
        style: TextStyle(
          fontSize: adjustedFontSize,
          fontWeight: FontWeight.w500,
          color: isUrgent ? Colors.red : Colors.grey[700],
          height: 1.2, // 줄 간격 추가로 텍스트 클리핑 방지
        ),
      ),
    );
  }

  int? _calculateDDay(DateTime deadline) {
    final now = DateTime.now();
    final difference = deadline.difference(now).inDays;
    return difference >= 0 ? difference : null;
  }
  
  /// 태블릿 여부 확인
  bool _isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide >= 600;
  }
}

/// 단일 거리 칩
class DistanceChip extends StatelessWidget {
  final double distance;
  final bool dense;

  const DistanceChip({
    super.key,
    required this.distance,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    final textScaleFactor = MediaQuery.textScalerOf(context).textScaleFactor;
    final distanceText = distance >= 1 
        ? '${distance.toStringAsFixed(1)}km'
        : '${(distance * 1000).round()}m';

    // 태블릿에서 시스템 폰트 크기에 따라 동적 조정
    final double baseHorizontalPadding = dense ? 6.0 : (isTablet ? 16.0 : 8.0);
    final double baseVerticalPadding = dense ? 3.0 : (isTablet ? 8.0 : 3.0);
    final double baseFontSize = dense ? 11.0 : (isTablet ? 16.0 : 12.0);
    final double baseBorderRadius = dense ? 12.0 : (isTablet ? 20.0 : 12.0);
    
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
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(adjustedBorderRadius),
        border: Border.all(
          color: Colors.blue.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        distanceText,
        style: TextStyle(
          fontSize: adjustedFontSize,
          fontWeight: FontWeight.w500,
          color: Colors.blue[700],
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
