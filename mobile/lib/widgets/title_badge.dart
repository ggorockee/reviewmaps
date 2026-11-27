import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/models/store_model.dart';
import 'package:mobile/widgets/new_badge.dart';
import 'package:mobile/screens/home_screen.dart';

/// 제목과 뱃지를 함께 표시하는 위젯
class TitleWithBadges extends StatelessWidget {
  final Store store;
  final bool dense;

  /// 하위 호환용으로 유지 (Text.rich가 MediaQuery.textScalerOf를 자동 적용하므로
  /// fontSize에 중복 곱셈하지 않음)
  final double scaleMultiplier;

  const TitleWithBadges({
    super.key,
    required this.store,
    this.dense = false,
    this.scaleMultiplier = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final isTab = MediaQuery.of(context).size.shortestSide >= 600;

    return Text.rich(
      TextSpan(
        children: [
          // 제목 텍스트
          TextSpan(
            text: store.title,
            style: TextStyle(
              fontSize: dense
                  ? (isTab ? 11.sp : 12.sp)
                  : (isTab ? 13.sp : 15.sp),
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              height: 1.3,
            ),
          ),

          // 채널 아이콘들 (기존 이미지 사용)
          if (store.campaignChannel != null && store.campaignChannel!.isNotEmpty)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: EdgeInsets.only(left: 4.w),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: buildChannelIcons(store.campaignChannel),
                ),
              ),
            ),

          // NEW 뱃지 (기존 위젯 사용)
          if (_shouldShowBadges())
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: EdgeInsets.only(left: 4.w),
                child: NewBadge(dense: dense),
              ),
            ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  bool _shouldShowBadges() {
    return store.isNew == true;
  }
}

/// 간단한 제목 위젯 (뱃지 없음)
class SimpleTitle extends StatelessWidget {
  final String title;
  final bool dense;
  final int maxLines;
  final TextStyle? style;
  final double scaleMultiplier;

  const SimpleTitle({
    super.key,
    required this.title,
    this.dense = false,
    this.maxLines = 2,
    this.style,
    this.scaleMultiplier = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final isTab = MediaQuery.of(context).size.shortestSide >= 600;

    return Text(
      title,
      style: style ??
          TextStyle(
            fontSize: dense
                ? (isTab ? 11.sp : 13.sp)
                : (isTab ? 13.sp : 15.sp),
            fontWeight: FontWeight.w600,
            color: Colors.black87,
            height: 1.3,
          ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
