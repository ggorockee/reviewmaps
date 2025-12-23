// blog_banner.dart
//
// 맛집/여행 블로그 띠 배너 위젯
// - 가까운 체험단과 추천 체험단 사이에 배치
// - 클릭 시 외부 블로그로 이동
// - 반응형 UI (폰/태블릿 대응)

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

class BlogBanner extends StatelessWidget {
  const BlogBanner({super.key});

  static const String _blogUrl = 'https://blog.naver.com/paspa96';

  Future<void> _openBlog(BuildContext context) async {
    try {
      final uri = Uri.parse(_blogUrl);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri);
      }
    } catch (e) {
      // 에러 발생 시 무시 (조용히 실패)
      debugPrint('블로그 링크 열기 실패: $e');
    }
  }

  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;

  @override
  Widget build(BuildContext context) {
    final bool isTab = _isTablet(context);

    return RepaintBoundary(
      child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: GestureDetector(
        onTap: () => _openBlog(context),
        child: Container(
          height: isTab ? 70.h : 60.h,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF00C73C), // 네이버 초록
                Color(0xFF00E68C), // 밝은 초록
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(12.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // 로고 이미지 영역
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Container(
                  width: isTab ? 40.w : 36.w,
                  height: isTab ? 40.h : 36.h,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'asset/image/ads/dangmi/logo.jpg',
                      width: isTab ? 40.w : 36.w,
                      height: isTab ? 40.h : 36.h,
                      fit: BoxFit.cover,
                      cacheWidth: 80,
                      cacheHeight: 80,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.restaurant_menu,
                          color: const Color(0xFF00C73C),
                          size: isTab ? 24.sp : 20.sp,
                        );
                      },
                    ),
                  ),
                ),
              ),

              // 텍스트 영역
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '전국 맛집 & 여행 탐방기',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isTab ? 15.sp : 14.sp,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      '맛집 리뷰와 여행 정보를 만나보세요',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: isTab ? 11.sp : 10.sp,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),

              // 화살표 아이콘
              Padding(
                padding: EdgeInsets.only(right: 16.w),
                child: Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: isTab ? 18.sp : 16.sp,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
