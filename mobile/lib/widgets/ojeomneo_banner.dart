// ojeomneo_banner.dart
//
// 오점너 앱 프로모션 배너 위젯
// - 가까운 체험단과 추천 체험단 사이에 배치
// - 클릭 시 App Store/Play Store로 이동
// - 반응형 UI (폰/태블릿 대응)

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

class OjeomneoBanner extends StatelessWidget {
  const OjeomneoBanner({super.key});

  static const String _iosUrl = 'https://apps.apple.com/app/id6756233238';
  static const String _androidUrl = 'https://play.google.com/store/apps/details?id=com.woohalabs.ojeomneo';

  Future<void> _openStore(BuildContext context) async {
    try {
      final String storeUrl = Platform.isIOS ? _iosUrl : _androidUrl;
      final uri = Uri.parse(storeUrl);

      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri);
      }
    } catch (e) {
      // 에러 발생 시 무시 (조용히 실패)
      debugPrint('오점너 스토어 링크 열기 실패: $e');
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
          onTap: () => _openStore(context),
          child: Container(
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.r),
              child: Column(
                children: [
                  // 로고 이미지 영역 (전체 높이의 70%)
                  SizedBox(
                    width: double.infinity,
                    height: isTab ? 70.h : 63.h,
                    child: Image.asset(
                      'asset/image/ads/ojeomneo/logo_rectangle.png',
                      fit: BoxFit.cover,
                      cacheWidth: 1024,
                      cacheHeight: 500,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: const Color(0xFFFF8C42).withValues(alpha: 0.1),
                          child: Center(
                            child: Icon(
                              Icons.restaurant,
                              color: const Color(0xFFFF8C42),
                              size: isTab ? 28.sp : 24.sp,
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // 텍스트 영역 (더 작게)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: isTab ? 16.w : 12.w,
                      vertical: isTab ? 8.h : 7.h,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFFFF8C42), // 오렌지
                          Color(0xFFFFB65E), // 밝은 오렌지
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '점심 메뉴 고민 끝! 스케치로 찾는 오늘의 메뉴',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isTab ? 12.sp : 11.sp,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.white,
                          size: isTab ? 14.sp : 12.sp,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
