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
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 4.w : 6.w,
        vertical: dense ? 1.h : 2.h,
      ),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(dense ? 6.r : 8.r),
        border: Border.all(
          color: Colors.red.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        'NEW',
        style: TextStyle(
          fontSize: dense ? 8.sp : 9.sp,
          fontWeight: FontWeight.w600,
          color: Colors.red,
        ),
      ),
    );
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
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 4.w : 6.w,
        vertical: dense ? 1.h : 2.h,
      ),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(dense ? 6.r : 8.r),
        border: Border.all(
          color: Colors.orange.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        'HOT',
        style: TextStyle(
          fontSize: dense ? 8.sp : 9.sp,
          fontWeight: FontWeight.w600,
          color: Colors.orange[700],
        ),
      ),
    );
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
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 4.w : 6.w,
        vertical: dense ? 1.h : 2.h,
      ),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(dense ? 6.r : 8.r),
        border: Border.all(
          color: Colors.red.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        '마감임박',
        style: TextStyle(
          fontSize: dense ? 8.sp : 9.sp,
          fontWeight: FontWeight.w600,
          color: Colors.red,
        ),
      ),
    );
  }
}
