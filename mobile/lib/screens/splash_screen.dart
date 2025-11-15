import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/services/app_open_ad_service.dart';
import 'package:mobile/services/ad_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/const/colors.dart';
import 'package:mobile/screens/main_screen.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/widgets/friendly.dart';
import 'package:mobile/widgets/notice_dialog.dart';

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

  final AppOpenAdService _appOpenAdService = AppOpenAdService();
  final AdService _adService = AdService();
  final AuthService _authService = AuthService();

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

    // 2. 세션 시작 이벤트 로깅
    await _adService.logSessionStart();

    // 3. App Open Ad 표시 시도
    await _appOpenAdService.showAdIfAvailable();
    print('[SplashScreen] App Open Ad 표시 시도 완료');

    // 4. 공지사항 팝업 표시 후 메인 화면으로 이동
    _showNoticeAndNavigate();
  }

  /// 로그인 상태 확인 후 적절한 화면으로 이동
  Future<void> _navigateToMain() async {
    if (!mounted) return;

    // 로그인 상태 확인
    final isLoggedIn = await _authService.isLoggedIn();
    print('[SplashScreen] 로그인 상태 확인: ${isLoggedIn ? "로그인됨" : "로그인 안됨"}');

    if (!mounted) return;

    // 로그인되어 있으면 MainScreen, 아니면 LoginScreen으로 이동
    final targetScreen = isLoggedIn ? const MainScreen() : const LoginScreen();
    print('[SplashScreen] ${isLoggedIn ? "메인 화면" : "로그인 화면"}으로 이동');

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
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

  /// 공지사항 팝업 표시 후 메인 화면으로 이동
  Future<void> _showNoticeAndNavigate() async {
    // 공지사항 기능 임시 비활성화 (앱 시작 블로킹 방지)
    // TODO: 공지사항 기능이 필요하면 아래 주석을 해제하세요
    /*
    try {
      print('[SplashScreen] 공지사항 팝업 표시 시작');
      // 공지사항 팝업 표시 (5초 타임아웃)
      await NoticeDialog.show(context).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('[SplashScreen] 공지사항 팝업 타임아웃');
        },
      );
      print('[SplashScreen] 공지사항 팝업 닫힘');
    } catch (e) {
      print('[SplashScreen] 공지사항 팝업 오류: $e');
    }
    */

    // 메인 화면으로 이동
    if (mounted) {
      print('[SplashScreen] 화면 이동 준비');
      _navigateToMain();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 폰트 배율에 따른 반응형 디자인
    final textScaleFactor = MediaQuery.textScalerOf(context).textScaleFactor;
    final bool isTablet = MediaQuery.of(context).size.width > 600;
    
    // 폰트 배율이 클 때 로고 크기와 간격 조정
    final logoSize = (120.w * (1.0 + (textScaleFactor - 1.0) * 0.2)).clamp(100.w, 150.w);
    final spacingMultiplier = (1.0 + (textScaleFactor - 1.0) * 0.3).clamp(1.0, 1.5);
    
    return ClampTextScale(
      max: isTablet ? 1.10 : 1.30,
      child: Scaffold(
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
                      // 앱 로고 - 폰트 배율에 따라 크기 조정
                      Container(
                        width: logoSize,
                        height: logoSize,
                        child: Image.asset(
                          'asset/image/logo/application/splashloading_logo.png',
                          width: logoSize,
                          height: logoSize,
                          fit: BoxFit.contain,
                        ),
                      ),
                      
                      SizedBox(height: (24.h * spacingMultiplier)),
                      
                      // 서브타이틀 - 폰트 배율에 따라 간격 조정
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20.w),
                        child: Text(
                          '내 주변 체험단을 지도로 찾아보세요',
                          style: TextStyle(
                            fontSize: isTablet ? 18.sp : 16.sp,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      
                      SizedBox(height: (60.h * spacingMultiplier)),
                      
                      // 로딩 인디케이터 - 폰트 배율에 따라 크기 조정
                      SizedBox(
                        width: (30.w * (1.0 + (textScaleFactor - 1.0) * 0.2)).clamp(25.w, 40.w),
                        height: (30.w * (1.0 + (textScaleFactor - 1.0) * 0.2)).clamp(25.w, 40.w),
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
      ),
    );
  }
}
