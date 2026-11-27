import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/models/store_model.dart';

/// 마감일 및 거리 정보를 표시하는 칩 위젯들
/// (Text가 시스템 textScaler를 자동 적용하므로 fontSize에 수동 배율을 중복 곱셈하지 않음)
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
    final List<Widget> chips = [];

    if (store.applyDeadline != null) {
      chips.add(DeadlineChip(deadline: store.applyDeadline!, dense: dense));
    }

    if (store.distance != null) {
      chips.add(DistanceChip(distance: store.distance!, dense: dense));
    }

    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: isTablet ? 6.w : 4.w,
      runSpacing: isTablet ? 4.h : 3.h,
      children: chips,
    );
  }

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
    final dDay = _calculateDDay(deadline);
    final isUrgent = dDay != null && dDay <= 3;

    final double horizontalPadding = (dense ? 6.0 : (isTablet ? 10.0 : 8.0)).w;
    final double verticalPadding = (dense ? 2.5 : (isTablet ? 4.0 : 3.0)).h;
    final double fontSize = dense
        ? (isTablet ? 10.sp : 10.5.sp)
        : (isTablet ? 12.sp : 11.5.sp);
    final double borderRadius = (dense ? 10.0 : (isTablet ? 14.0 : 12.0)).r;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: isUrgent
            ? Colors.red.withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isUrgent
              ? Colors.red.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        dDay != null ? 'D-$dDay' : '마감임박',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          color: isUrgent ? Colors.red : Colors.grey[700],
          height: 1.2,
        ),
      ),
    );
  }

  int? _calculateDDay(DateTime deadline) {
    final now = DateTime.now();
    final deadlineDate = DateTime(deadline.year, deadline.month, deadline.day);
    final nowDate = DateTime(now.year, now.month, now.day);
    final difference = deadlineDate.difference(nowDate).inDays;
    return difference >= 0 ? difference : null;
  }

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
    final distanceText = distance >= 1
        ? '${distance.toStringAsFixed(1)}km'
        : '${(distance * 1000).round()}m';

    final double horizontalPadding = (dense ? 6.0 : (isTablet ? 10.0 : 8.0)).w;
    final double verticalPadding = (dense ? 2.5 : (isTablet ? 4.0 : 3.0)).h;
    final double fontSize = dense
        ? (isTablet ? 10.sp : 10.5.sp)
        : (isTablet ? 12.sp : 11.5.sp);
    final double borderRadius = (dense ? 10.0 : (isTablet ? 14.0 : 12.0)).r;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: Colors.blue.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        distanceText,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          color: Colors.blue[700],
          height: 1.2,
        ),
      ),
    );
  }

  bool _isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide >= 600;
  }
}
