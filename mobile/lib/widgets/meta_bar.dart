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
    final List<Widget> items = [];

    if (showPlatform && store.platform.isNotEmpty) {
      items.add(SimpleMeta(text: store.platform, dense: dense));
    }

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
        if (store.campaignChannel != null && store.campaignChannel!.isNotEmpty) ...[
          SizedBox(height: isTablet ? 6.h : 4.h),
          Row(
            children: buildChannelIcons(store.campaignChannel),
          ),
        ],
      ],
    );
  }

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
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final double horizontalPadding = (dense ? 4.0 : (isTablet ? 8.0 : 6.0)).w;
    final double verticalPadding = (dense ? 1.5 : (isTablet ? 3.0 : 2.0)).h;
    final double fontSize = dense
        ? (isTablet ? 9.sp : 9.sp)
        : (isTablet ? 11.sp : 10.sp);
    final double borderRadius = (dense ? 6.0 : (isTablet ? 10.0 : 8.0)).r;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: (color ?? Colors.grey).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: (color ?? Colors.grey).withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          color: color ?? Colors.grey[700],
          height: 1.2,
        ),
      ),
    );
  }
}
