import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/models/store_model.dart';
import 'package:mobile/widgets/new_badge.dart';
import 'package:mobile/screens/home_screen.dart';

/// 제목과 뱃지를 함께 표시하는 위젯
class TitleWithBadges extends StatelessWidget {
  final Store store;
  final bool dense;

  const TitleWithBadges({
    super.key,
    required this.store,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final isTab = MediaQuery.of(context).size.shortestSide >= 600;
    
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // 제목
        Text(
          store.title,
          style: TextStyle(
            fontSize: dense 
                ? (isTab ? 10.sp : 13.sp)
                : (isTab ? 12.sp : 15.sp),
            fontWeight: FontWeight.w600,
            color: Colors.black87,
            height: 1.3,
          ),
        ),
        
        // 채널 아이콘들 (기존 이미지 사용)
        if (store.campaignChannel != null && store.campaignChannel!.isNotEmpty) ...[
          SizedBox(width: 6.w),
          ...buildChannelIcons(store.campaignChannel),
        ],
        
        // NEW 뱃지 (기존 위젯 사용)
        if (_shouldShowBadges()) ...[
          SizedBox(width: 6.w),
          NewBadge(dense: dense),
        ],
      ],
    );
  }

  bool _shouldShowBadges() {
    return store.isNew == true;
    // 다른 뱃지 조건들도 여기에 추가
  }
}

/// 간단한 제목 위젯 (뱃지 없음)
class SimpleTitle extends StatelessWidget {
  final String title;
  final bool dense;
  final int maxLines;
  final TextStyle? style;

  const SimpleTitle({
    super.key,
    required this.title,
    this.dense = false,
    this.maxLines = 2,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final isTab = MediaQuery.of(context).size.shortestSide >= 600;
    
    return Text(
      title,
      style: style ?? TextStyle(
        fontSize: dense 
            ? (isTab ? 10.sp : 13.sp)
            : (isTab ? 12.sp : 15.sp),
        fontWeight: FontWeight.w600,
        color: Colors.black87,
        height: 1.3,
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
