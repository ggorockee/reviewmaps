import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/widgets/stay_availability_badge.dart';
import 'package:mobile/widgets/title_badge.dart';

import '../const/colors.dart';
import '../models/store_model.dart';
import '../screens/home_screen.dart';
import 'deadline_chips.dart';

class ExperienceCard extends StatelessWidget {
  final Store store;
  final double? width;
  final bool dense;
  final bool compact;

  /// 메타 영역(마감/거리)을 카드 하단에 고정할지 여부
  /// - 카테고리 2열 그리드: true 유지(정렬 일관성)
  /// - 검색 결과 1열 리스트: false로 주어 간격을 타이트하게
  final bool bottomAlignMeta;

  /// 넓은 1열 카드에서 요일 7칸 띠도 함께 표시할지 여부
  final bool showDayStrip;

  const ExperienceCard({
    super.key,
    required this.store,
    this.width,
    this.dense = false,
    this.compact = false,
    this.bottomAlignMeta = true,
    this.showDayStrip = false,
  });

  @override
  Widget build(BuildContext context) {
    final platformColor = platformBadgeColor(store.platform);
    final bool isTab = MediaQuery.of(context).size.shortestSide >= 600;
    final availability = store.stayAvailability;

    // [ScreenUtil] 여백 프리셋 (가로 .w / 세로 .h 분리해 태블릿 세로 패딩 과대 방지)
    final double padH = dense ? 10.w : 12.w;
    final double padV = dense ? 10.h : 12.h;
    final double gapBadgeBody = dense ? 3.h : 4.h;
    final double gapTitleOffer = dense ? 3.h : 4.h;

    return InkWell(
      onTap: (store.contentLink ?? '').isEmpty ? null : () => openLink(store.contentLink!),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: bottomAlignMeta ? MainAxisSize.max : MainAxisSize.min,
            children: [
              // ---------- 플랫폼 뱃지 ----------
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: platformColor,
                  borderRadius: BorderRadius.circular(4.r),
                ),
                child: Text(
                  store.platform,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isTab ? 9.sp : 9.5.sp,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
              ),
              SizedBox(height: gapBadgeBody),

              // ---------- 업체명(배지/채널 아이콘 포함) ----------
              TitleWithBadges(
                store: store,
                dense: dense,
              ),

              SizedBox(height: gapTitleOffer),

              // ---------- 제공내역(있을 때) ----------
              if ((store.offer ?? '').isNotEmpty)
                Text(
                  store.offer!,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isTab ? 9.sp : 10.5.sp,
                    color: Colors.red[700],
                    height: 1.25,
                  ),
                ),

              // ---------- 숙박/캠핑장 이용 가능·불가 요일 (제공 내역 바로 아래) ----------
              if (availability != null) ...[
                SizedBox(height: 5.h),
                StayAvailabilityBadge(
                  availability: availability,
                  dense: dense,
                  showDayStrip: showDayStrip,
                ),
              ],

              // ---------- 본문과 메타(마감/거리) 간격 ----------
              if (bottomAlignMeta)
                const Spacer()
              else
                SizedBox(height: isTab ? 10.h : 8.h),

              SizedBox(height: 4.h),

              // ---------- 마감일 및 거리 칩들 ----------
              Padding(
                padding: EdgeInsets.only(bottom: 1.h),
                child: DeadlineChips(store: store, dense: dense),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
