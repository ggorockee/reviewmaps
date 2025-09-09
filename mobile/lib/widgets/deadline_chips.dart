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
    final List<Widget> chips = [];

    // 거리 칩만 표시 (마감일 제거)
    if (store.distance != null) {
      chips.add(_buildDistanceChip(store.distance!));
    }

    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 4.w,
      runSpacing: 4.h,
      children: chips,
    );
  }

  Widget _buildDistanceChip(double distance) {
    final distanceText = distance >= 1 
        ? '${distance.toStringAsFixed(1)}km'
        : '${(distance * 1000).round()}m';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6.w : 8.w,
        vertical: dense ? 2.h : 3.h,
      ),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(dense ? 8.r : 10.r),
        border: Border.all(
          color: Colors.blue.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        distanceText,
        style: TextStyle(
          fontSize: dense ? 9.sp : 10.sp,
          fontWeight: FontWeight.w500,
          color: Colors.blue[700],
        ),
      ),
    );
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
    final dDay = _calculateDDay(deadline);
    final isUrgent = dDay != null && dDay <= 3;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6.w : 8.w,
        vertical: dense ? 2.h : 3.h,
      ),
      decoration: BoxDecoration(
        color: isUrgent ? Colors.red.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(dense ? 8.r : 10.r),
        border: Border.all(
          color: isUrgent ? Colors.red.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        dDay != null ? 'D-$dDay' : '마감임박',
        style: TextStyle(
          fontSize: dense ? 9.sp : 10.sp,
          fontWeight: FontWeight.w500,
          color: isUrgent ? Colors.red : Colors.grey[700],
        ),
      ),
    );
  }

  int? _calculateDDay(DateTime deadline) {
    final now = DateTime.now();
    final difference = deadline.difference(now).inDays;
    return difference >= 0 ? difference : null;
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
    final distanceText = distance >= 1 
        ? '${distance.toStringAsFixed(1)}km'
        : '${(distance * 1000).round()}m';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6.w : 8.w,
        vertical: dense ? 2.h : 3.h,
      ),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(dense ? 8.r : 10.r),
        border: Border.all(
          color: Colors.blue.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        distanceText,
        style: TextStyle(
          fontSize: dense ? 9.sp : 10.sp,
          fontWeight: FontWeight.w500,
          color: Colors.blue[700],
        ),
      ),
    );
  }
}
