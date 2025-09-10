import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/ads/interstitial_ad_service.dart';
import 'package:mobile/const/colors.dart';
import 'package:mobile/screens/main_screen.dart';

/// SplashScreen
/// ------------------------------------------------------------
/// 앱 시작 시 로딩 화면 + 전면광고 표시
/// - 브랜드 로고 및 로딩 애니메이션
/// - 전면광고 준비되면 표시 후 메인 화면으로 이동
/// - 광고 로딩 실패 시에도 자연스럽게 메인 화면으로 이동
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  final InterstitialAdService _adService = InterstitialAdService();

  @override
  void initState() {
    super.initState();
    
    // 로고 애니메이션 설정
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));
    
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.8, curve: Curves.elasticOut),
    ));

    // 애니메이션 시작
    _animationController.forward();
    
    // 스플래시 시퀀스 시작
    _startSplashSequence();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// 스플래시 시퀀스: 로딩 → 광고 → 메인 화면
  Future<void> _startSplashSequence() async {
    // 1. 최소 스플래시 시간 대기 (사용자 경험)
    await Future.delayed(const Duration(milliseconds: 2000));
    
    if (!mounted) return;

    // 2. 전면광고가 준비되었으면 표시
    if (_adService.isAdReady) {
      await _adService.showAd(onAdClosed: _navigateToMain);
    } else {
      // 광고가 준비되지 않았으면 바로 메인 화면으로
      _navigateToMain();
    }
  }

  /// 메인 화면으로 이동
  void _navigateToMain() {
    if (!mounted) return;
    
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const MainScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 앱 로고
                    Container(
                      width: 120.w,
                      height: 120.w,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24.r),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24.r),
                        child: Image.asset(
                          'asset/image/logo/application/reviewmaps.png',
                          width: 120.w,
                          height: 120.w,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    
                    SizedBox(height: 24.h),
                    
                    // 앱 이름
                    // Text(
                    //   '리뷰맵',
                    //   style: TextStyle(
                    //     fontSize: 32.sp,
                    //     fontWeight: FontWeight.w900,
                    //     color: PRIMARY_COLOR,
                    //     letterSpacing: 2.0,
                    //   ),
                    // ),
                    
                    // SizedBox(height: 8.h),
                    
                    // 서브타이틀
                    Text(
                      '내 주변 체험단을 지도로 찾아보세요',
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    
                    SizedBox(height: 60.h),
                    
                    // 로딩 인디케이터
                    SizedBox(
                      width: 30.w,
                      height: 30.w,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.0,
                        valueColor: AlwaysStoppedAnimation<Color>(PRIMARY_COLOR),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
