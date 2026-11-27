import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import '../const/colors.dart';

/// 정렬 옵션 타입 정의
enum SortOption {
  newest('최신등록순', 'newest'),
  deadline('마감임박순', 'deadline'),
  nearest('거리순', 'nearest');

  const SortOption(this.displayName, this.value);
  final String displayName;
  final String value;
}

/// 통일된 정렬 필터 위젯
/// 모든 화면에서 동일한 디자인과 동작을 제공하며,
/// 고정 높이를 쓰지 않아 글자 배율이 커져도 텍스트가 잘리지 않습니다.
class SortFilterWidget extends StatelessWidget {
  final SortOption currentSort;
  final ValueChanged<SortOption> onSortChanged;
  final Position? userPosition;
  final VoidCallback? onLocationRequest;

  const SortFilterWidget({
    super.key,
    required this.currentSort,
    required this.onSortChanged,
    this.userPosition,
    this.onLocationRequest,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: isTablet ? 52.h : 46.h,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
            width: 1.0,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: SortOption.values.map((option) {
              return Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: _buildSortChip(context, option, isTablet),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  /// 개별 정렬 칩 생성
  Widget _buildSortChip(
    BuildContext context,
    SortOption option,
    bool isTablet,
  ) {
    final bool isSelected = currentSort == option;
    final bool isLocationRequired = option == SortOption.nearest && userPosition == null;

    return GestureDetector(
      onTap: () {
        if (option == SortOption.nearest && userPosition == null) {
          onLocationRequest?.call();
        } else {
          onSortChanged(option);
        }
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: isTablet ? 88.w : 60.w,
          minHeight: isTablet ? 36.h : 30.h,
        ),
        child: Container(
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? 14.w : 12.w,
            vertical: isTablet ? 7.h : 6.h,
          ),
          decoration: BoxDecoration(
            color: isSelected ? primaryColor : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(isTablet ? 18.r : 16.r),
            border: Border.all(
              color: isSelected ? primaryColor : Colors.grey.shade300,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                option.displayName,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isTablet ? 14.sp : 13.sp,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                  letterSpacing: -0.2,
                  height: 1.2,
                ),
              ),
              if (isLocationRequired) ...[
                SizedBox(width: 4.w),
                Icon(
                  Icons.location_off_outlined,
                  size: isTablet ? 15.sp : 14.sp,
                  color: isSelected ? Colors.white70 : Colors.grey.shade500,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool _isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide >= 600;
  }
}

/// 정렬 필터 사용을 위한 헬퍼 믹스인
mixin SortFilterMixin<T extends StatefulWidget> on State<T> {
  SortOption currentSort = SortOption.newest;

  void onSortChanged(SortOption newSort) {
    setState(() {
      currentSort = newSort;
    });
  }

  void onLocationRequest() {
    // 각 화면에서 구현
  }
}
