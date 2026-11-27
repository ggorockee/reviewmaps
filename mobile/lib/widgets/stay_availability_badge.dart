import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/utils/stay_availability.dart';

/// 숙박/캠핑장 체험단의 이용 가능·불가 요일을 제공 내역 바로 아래에
/// 한눈에 보이도록 표시하는 위젯.
///
/// - 시스템 글자 배율(MediaQuery.textScalerOf)을 그대로 따르며,
///   수동 배율 곱셈을 하지 않아 이중 확대나 잘림을 방지합니다.
/// - 모든 요소는 Wrap으로 배치되어 좁은 2열 카드나 큰 글자 배율에서도
///   가로 오버플로우가 발생하지 않습니다.
class StayAvailabilityBadge extends StatelessWidget {
  final StayAvailability availability;
  final bool dense;

  /// 넓은 1열 카드(지도 목록·알림 등)에서 명시적 요일(월~일)을
  /// 7칸 미니 인디케이터로 함께 표시할지 여부
  final bool showDayStrip;

  const StayAvailabilityBadge({
    super.key,
    required this.availability,
    this.dense = false,
    this.showDayStrip = false,
  });

  @override
  Widget build(BuildContext context) {
    if (availability.isEmpty) return const SizedBox.shrink();

    final bool isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final String? availText = availability.availableText;
    final String? exclText = availability.excludedText;

    final double fontSize = dense
        ? (isTablet ? 9.5.sp : 10.sp)
        : (isTablet ? 11.sp : 11.sp);
    final double iconSize = dense
        ? (isTablet ? 11.sp : 11.5.sp)
        : (isTablet ? 12.5.sp : 12.5.sp);

    final List<Widget> chips = [];

    if (availText != null) {
      chips.add(
        _buildChip(
          icon: Icons.event_available_rounded,
          label: '$availText 가능',
          bgColor: const Color(0xFFE8F5E9),
          borderColor: const Color(0xFFA5D6A7),
          fgColor: const Color(0xFF1B5E20),
          fontSize: fontSize,
          iconSize: iconSize,
        ),
      );
    }

    if (exclText != null) {
      chips.add(
        _buildChip(
          icon: Icons.event_busy_rounded,
          label: '$exclText 불가',
          bgColor: const Color(0xFFFFF3E0),
          borderColor: const Color(0xFFFFCC80),
          fgColor: const Color(0xFFBF360C),
          fontSize: fontSize,
          iconSize: iconSize,
        ),
      );
    }

    return Semantics(
      label: availability.semanticsLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 4.w,
            runSpacing: 3.h,
            children: chips,
          ),
          if (showDayStrip && availability.hasExplicitDays) ...[
            SizedBox(height: 4.h),
            _buildDayStrip(isTablet),
          ],
        ],
      ),
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color borderColor,
    required Color fgColor,
    required double fontSize,
    required double iconSize,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 5.w : 6.w,
        vertical: dense ? 2.h : 2.5.h,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(5.r),
        border: Border.all(color: borderColor, width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: fgColor),
          SizedBox(width: 3.w),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: fgColor,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 월~일 7요일 미니 띠 (가능=초록, 불가=주황 취소선, 미명시=중립)
  Widget _buildDayStrip(bool isTablet) {
    final double fontSize = isTablet ? 9.5.sp : 9.5.sp;

    return Wrap(
      spacing: 3.w,
      runSpacing: 3.h,
      children: List.generate(kWeekdayLabels.length, (idx) {
        final day = idx + 1; // 1=월 ~ 7=일
        final state = availability.dayState(day);
        final Color bg;
        final Color border;
        final Color fg;
        final TextDecoration? decoration;

        if (state == true) {
          bg = const Color(0xFFE8F5E9);
          border = const Color(0xFF81C784);
          fg = const Color(0xFF1B5E20);
          decoration = null;
        } else if (state == false) {
          bg = const Color(0xFFFFEBEE);
          border = const Color(0xFFEF9A9A);
          fg = const Color(0xFFC62828);
          decoration = TextDecoration.lineThrough;
        } else {
          bg = Colors.grey.shade100;
          border = Colors.grey.shade300;
          fg = Colors.grey.shade500;
          decoration = null;
        }

        return Container(
          padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.5.h),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4.r),
            border: Border.all(color: border, width: 0.6),
          ),
          child: Text(
            kWeekdayLabels[idx],
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: state == true ? FontWeight.w700 : FontWeight.w500,
              color: fg,
              decoration: decoration,
              height: 1.15,
            ),
          ),
        );
      }),
    );
  }
}
