import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/const/colors.dart';

/// 앱 업데이트 안내 배너 위젯
class UpdatePillBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  const UpdatePillBanner({
    super.key,
    required this.message,
    this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: PRIMARY_COLOR.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: PRIMARY_COLOR.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.system_update,
            color: PRIMARY_COLOR,
            size: 20.sp,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: isTablet ? 15.sp : 13.sp,
                color: PRIMARY_COLOR,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onTap != null)
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: PRIMARY_COLOR,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  '업데이트',
                  style: TextStyle(
                    fontSize: isTablet ? 14.sp : 12.sp,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (onClose != null) ...[
            SizedBox(width: 8.w),
            GestureDetector(
              onTap: onClose,
              child: Icon(
                Icons.close,
                color: PRIMARY_COLOR,
                size: 18.sp,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  /// 태블릿 여부 확인
  bool _isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide >= 600;
  }
}

/// 일반 업데이트 배너 위젯
class UpdateBanner extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  const UpdateBanner({
    super.key,
    required this.title,
    required this.message,
    this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    return Container(
      margin: EdgeInsets.all(16.w),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: PRIMARY_COLOR,
                size: 24.sp,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: isTablet ? 18.sp : 16.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (onClose != null)
                GestureDetector(
                  onTap: onClose,
                  child: Icon(
                    Icons.close,
                    color: Colors.grey,
                    size: 20.sp,
                  ),
                ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            message,
            style: TextStyle(
              fontSize: isTablet ? 16.sp : 14.sp,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
          if (onTap != null) ...[
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: PRIMARY_COLOR,
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                ),
                child: Text(
                  '업데이트 하기',
                  style: TextStyle(
                    fontSize: isTablet ? 16.sp : 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  /// 태블릿 여부 확인
  bool _isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide >= 600;
  }
}
