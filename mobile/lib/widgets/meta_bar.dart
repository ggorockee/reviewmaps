import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/models/store_model.dart';
import 'package:mobile/widgets/deadline_chips.dart';

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
    final List<Widget> items = [];

    // 플랫폼 정보
    if (showPlatform && store.platform.isNotEmpty) {
      items.add(_buildPlatformChip(store.platform));
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

    return Wrap(
      spacing: 6.w,
      runSpacing: 4.h,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: items,
    );
  }

  Widget _buildPlatformChip(String platform) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 4.w : 6.w,
        vertical: dense ? 1.h : 2.h,
      ),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(dense ? 6.r : 8.r),
        border: Border.all(
          color: Colors.grey.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        platform,
        style: TextStyle(
          fontSize: dense ? 8.sp : 9.sp,
          fontWeight: FontWeight.w500,
          color: Colors.grey[700],
        ),
      ),
    );
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
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 4.w : 6.w,
        vertical: dense ? 1.h : 2.h,
      ),
      decoration: BoxDecoration(
        color: (color ?? Colors.grey).withOpacity(0.1),
        borderRadius: BorderRadius.circular(dense ? 6.r : 8.r),
        border: Border.all(
          color: (color ?? Colors.grey).withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: dense ? 8.sp : 9.sp,
          fontWeight: FontWeight.w500,
          color: color ?? Colors.grey[700],
        ),
      ),
    );
  }
}
