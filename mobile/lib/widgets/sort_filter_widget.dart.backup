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
/// 모든 화면에서 동일한 디자인과 동작을 제공
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
      height: isTablet ? 56.h : 48.h,
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
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: Row(
          children: [
            // 정렬 옵션들
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: SortOption.values.map((option) {
                    return Padding(
                      padding: EdgeInsets.only(right: 8.w),
                      child: _buildSortChip(
                        context,
                        option,
                        isTablet,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
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
          // 위치 권한이 필요한 경우
          onLocationRequest?.call();
        } else {
          onSortChanged(option);
        }
      },
      child: Container(
        height: isTablet ? 36.h : 32.h,
        padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 16.w : 14.w,
          vertical: isTablet ? 8.h : 6.h,
        ),
        decoration: BoxDecoration(
          color: isSelected ? PRIMARY_COLOR : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(isTablet ? 18.r : 16.r),
          border: Border.all(
            color: isSelected ? PRIMARY_COLOR : Colors.grey.shade300,
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              option.displayName,
              style: TextStyle(
                fontSize: isTablet ? 14.sp : 13.sp,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey.shade700,
                letterSpacing: -0.2,
              ),
            ),
            if (isLocationRequired) ...[
              SizedBox(width: 4.w),
              Icon(
                Icons.location_off_outlined,
                size: isTablet ? 16.sp : 14.sp,
                color: isSelected ? Colors.white70 : Colors.grey.shade500,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 태블릿 여부 확인
  bool _isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide >= 600;
  }
}

/// 정렬 필터 사용을 위한 헬퍼 믹스인
mixin SortFilterMixin<T extends StatefulWidget> on State<T> {
  SortOption currentSort = SortOption.newest;

  /// 정렬 변경 처리
  void onSortChanged(SortOption newSort) {
    setState(() {
      currentSort = newSort;
    });
  }

  /// 위치 권한 요청 (구현 필요)
  void onLocationRequest() {
    // 각 화면에서 구현
  }
}
