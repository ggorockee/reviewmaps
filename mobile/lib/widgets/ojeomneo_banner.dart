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

  static const String _iosAppStoreUrl = 'https://apps.apple.com/app/id6756233238';
  static const String _androidPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.woohalabs.ojeomneo';
  static const String _iosAppScheme = 'ojeomneo://';
  static const String _androidPackageName = 'com.woohalabs.ojeomneo';

  Future<void> _openApp(BuildContext context) async {
    try {
      if (Platform.isAndroid) {
        // Android: intent URL 사용 (앱이 있으면 실행, 없으면 Play Store로 자동 이동)
        final intentUrl = 'intent://#Intent;scheme=ojeomneo;package=$_androidPackageName;S.browser_fallback_url=$_androidPlayStoreUrl;end';
        final uri = Uri.parse(intentUrl);

        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          // intent URL 실패 시 직접 Play Store로
          await launchUrl(Uri.parse(_androidPlayStoreUrl), mode: LaunchMode.externalApplication);
        }
      } else if (Platform.isIOS) {
        // iOS: 앱 URL scheme 시도
        final appUri = Uri.parse(_iosAppScheme);

        if (await canLaunchUrl(appUri)) {
          // 앱이 설치되어 있으면 실행
          await launchUrl(appUri, mode: LaunchMode.externalApplication);
        } else {
          // 앱이 없으면 App Store로
          await launchUrl(Uri.parse(_iosAppStoreUrl), mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      // 에러 발생 시 무시 (조용히 실패)
      debugPrint('오점너 앱 열기 실패: $e');
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
          onTap: () => _openApp(context),
          child: Container(
            height: isTab ? 70.h : 60.h,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFF8C42), // 오렌지
                  Color(0xFFFFB65E), // 밝은 오렌지
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
                // 로고 이미지 영역 (정사각형)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Container(
                    width: isTab ? 40.w : 36.w,
                    height: isTab ? 40.h : 36.h,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.r),
                      child: Image.asset(
                        'asset/image/ads/ojeomneo/logo.png',
                        width: isTab ? 40.w : 36.w,
                        height: isTab ? 40.h : 36.h,
                        fit: BoxFit.cover,
                        cacheWidth: 128,
                        cacheHeight: 128,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.restaurant,
                            color: const Color(0xFFFF8C42),
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
                        '점심 메뉴 고민 끝!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isTab ? 15.sp : 14.sp,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        '스케치로 찾는 오늘의 메뉴',
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
