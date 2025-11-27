import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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

  const ExperienceCard({
    super.key,
    required this.store,
    this.width,
    this.dense = false,
    this.compact = false,
    this.bottomAlignMeta = true,
  });

  @override
  Widget build(BuildContext context) {
    final platformColor = platformBadgeColor(store.platform);
    final bool isTab = MediaQuery.of(context).size.shortestSide >= 600;
    
    // 폰트 배율에 따른 동적 크기 조정
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
    final bool isTablet = isTab;
    final double maxScale = isTablet ? 1.10 : 1.30;
    final double clampedScale = textScaleFactor.clamp(1.0, maxScale);
    final double scaleMultiplier = (1.0 + (clampedScale - 1.0) * 0.5).clamp(1.0, 1.3);

    // [ScreenUtil] 여백 프리셋 - 간격 조정
    final double pad = dense ? 10.w : 12.w;
    final double gapBadgeBody = dense ? 2.h : 3.h;
    final double gapTitleOffer = dense ? 2.h : 3.h;

    return InkWell(
      onTap: (store.contentLink ?? '').isEmpty ? null : () => openLink(store.contentLink!),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  style: TextStyle(
                    fontSize: (isTab ? 8.sp : 8.5.sp) * scaleMultiplier,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
              ),
              SizedBox(height: gapBadgeBody),

              // ---------- 업체명(배지/채널 아이콘 포함) ----------
              // 제목은 2줄까지만, 폭을 확보해 줄바꿈 보장
              TitleWithBadges(
                store: store,
                dense: dense,
                scaleMultiplier: scaleMultiplier,
              ),

              SizedBox(height: gapTitleOffer),

              // ---------- 제공내역(있을 때) ----------
              if ((store.offer ?? '').isNotEmpty)
                Text(
                  store.offer!,
                  maxLines: isTab ? 2 : (compact ? 1 : 2),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: (isTab ? 6.5.sp : 9.5.sp) * scaleMultiplier,
                    color: Colors.red,
                    height: isTab ? 1.05 : 1.2,
                  ),
                ),

              // ---------- 오퍼와 D-day 사이의 일정한 간격 ----------
              SizedBox(height: isTab ? 13.h : 10.h),

              // 검색 결과(1열)에서는 타이틀 폰트 기준 1.5배 간격, 
              // 카테고리(2열)에서는 카드 하단 고정으로 정렬 유지
              if (bottomAlignMeta)
                const Spacer()
              else
                SizedBox(height: _offerMetaGap(isTab, textScaleFactor)),

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
  
  /// 오퍼-메타 사이 간격: 타이틀 폰트 크기(추정)의 1.5배를 기준으로 계산
  double _offerMetaGap(bool isTab, double textScale) {
    // 타이틀 추정 폰트 크기: 폰 16.sp, 태블릿 14.sp 기준, 배율 적용
    final double titleFs = (isTab ? 14.sp : 16.sp) * textScale;
    // 1.5배 간격, 너무 커지지 않도록 상한 제한
    final double gap = titleFs * 1.5;
    // 상한/하한을 두어 극단값 방지
    return gap.clamp(8.h, isTab ? 28.h : 24.h);
  }
}
