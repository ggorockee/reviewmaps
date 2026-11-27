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
    return _StatusBadge(
      label: 'NEW',
      color: Colors.red,
      dense: dense,
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
    return _StatusBadge(
      label: 'HOT',
      color: Colors.orange[700]!,
      dense: dense,
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
    return _StatusBadge(
      label: '마감임박',
      color: Colors.red,
      dense: dense,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool dense;

  const _StatusBadge({
    required this.label,
    required this.color,
    required this.dense,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final double horizontalPadding = (dense ? 4.0 : (isTablet ? 7.0 : 6.0)).w;
    final double verticalPadding = (dense ? 1.0 : (isTablet ? 2.5 : 2.0)).h;
    final double fontSize = dense
        ? (isTablet ? 8.5.sp : 8.5.sp)
        : (isTablet ? 10.sp : 9.sp);
    final double borderRadius = (dense ? 6.0 : (isTablet ? 9.0 : 8.0)).r;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: color,
          height: 1.2,
        ),
      ),
    );
  }
}
