import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/screens/auth/sign_up_screen.dart';
import 'package:mobile/screens/auth/password_reset_screen.dart';
import 'package:mobile/screens/main_screen.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/sns/kakao_login_service.dart';
import 'package:mobile/services/sns/google_login_service.dart';
import 'package:mobile/services/sns/apple_login_service.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/services/auth_service.dart' show authServiceProvider;
import 'package:mobile/const/colors.dart';
import 'dart:io';

/// Login Version 1 화면
/// Figma 디자인을 기반으로 한 로그인 화면
///
/// [returnRoute] 로그인 후 복귀할 경로 (선택)
/// [returnArguments] 복귀 시 전달할 arguments (선택)
class LoginScreen extends ConsumerStatefulWidget {
  final String? returnRoute;
  final Map<String, dynamic>? returnArguments;

  const LoginScreen({
    super.key,
    this.returnRoute,
    this.returnArguments,
  });

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 로그인 성공 후 네비게이션 처리
  /// returnRoute가 있으면 해당 경로로, 없으면 MainScreen으로 이동
  void _navigateAfterLogin() {
    if (widget.returnRoute != null) {
      // returnRoute가 있으면 해당 경로로 복귀
      Navigator.of(context).pushReplacementNamed(
        widget.returnRoute!,
        arguments: widget.returnArguments,
      );
    } else {
      // returnRoute가 없으면 MainScreen으로 이동
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const MainScreen(),
        ),
      );
    }
  }

  /// 로그인 처리
  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // 유효성 검사
    if (email.isEmpty) {
      _showErrorDialog('이메일을 입력해 주세요.');
      return;
    }

    if (password.isEmpty) {
      _showErrorDialog('비밀번호를 입력해 주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 1. AuthService (Provider 방식) 로그인 수행 (토큰 저장)
      final authService = ref.read(authServiceProvider);
      await authService.login(email: email, password: password);

      if (!mounted) return;

      // 2. 사용자 정보 가져오기
      final userInfo = await authService.getUserInfo();

      if (!mounted) return;

      // 3. Riverpod authProvider 상태 업데이트
      await ref.read(authProvider.notifier).updateAfterLogin(userInfo);

      if (!mounted) return;

      // 4. 로그인 성공 - returnRoute 또는 MainScreen으로 이동
      _navigateAfterLogin();
    } catch (e) {
      if (!mounted) return;

      String errorMessage = '로그인할 수 없습니다.\n잠시 후 다시 시도해 주세요.';
      final errorText = e.toString();

      if (errorText.contains('Exception:')) {
        final serverMessage = errorText.replaceAll('Exception:', '').trim();

        // 서버에서 온 에러 메시지를 네이버 스타일로 변환
        if (serverMessage.contains('Invalid credentials') ||
            serverMessage.contains('incorrect') ||
            serverMessage.contains('wrong')) {
          errorMessage = '아이디 또는 비밀번호를 다시 확인해 주세요.\n등록되지 않은 아이디이거나, 아이디 또는 비밀번호를 잘못 입력하셨습니다.';
        } else if (serverMessage.contains('not found') || serverMessage.contains('존재하지')) {
          errorMessage = '등록되지 않은 이메일입니다.\n이메일을 다시 확인해 주세요.';
        } else if (serverMessage.contains('network') || serverMessage.contains('timeout')) {
          errorMessage = '네트워크 연결이 불안정합니다.\n잠시 후 다시 시도해 주세요.';
        } else {
          errorMessage = serverMessage;
        }
      }

      _showErrorDialog(errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }


  /// Kakao 로그인 처리
  Future<void> _handleKakaoLogin() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Kakao SDK 로그인
      final kakaoAccessToken = await KakaoLoginService.login();
      if (!mounted) return;

      // 2. AuthService (Provider 방식) 서버 로그인
      final authService = ref.read(authServiceProvider);
      await authService.kakaoLogin(kakaoAccessToken);
      if (!mounted) return;

      // 3. 토큰 저장 확인
      final storedAccessToken = await authService.getStoredAccessToken();
      if (storedAccessToken == null) {
        throw Exception('토큰 저장에 실패했습니다.\n다시 시도해 주세요.');
      }

      if (!mounted) return;

      // 4. 사용자 정보 가져오기
      final userInfo = await authService.getUserInfo();
      if (!mounted) return;

      // 5. authProvider 상태 업데이트
      await ref.read(authProvider.notifier).updateAfterLogin(userInfo);
      if (!mounted) return;

      // 6. returnRoute 또는 MainScreen으로 이동
      _navigateAfterLogin();
    } catch (e) {
      if (!mounted) return;

      debugPrint('Kakao 로그인 에러: $e');

      String errorMessage = '카카오 로그인 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.';
      final errorText = e.toString();

      if (errorText.contains('Exception:')) {
        final serverMessage = errorText.replaceAll('Exception:', '').trim();

        // 카카오 SDK 에러 처리
        if (serverMessage.contains('CANCELED')) {
          errorMessage = '로그인이 취소되었습니다.';
        } else if (serverMessage.contains('이메일') && serverMessage.contains('동의')) {
          errorMessage = '카카오 계정에 이메일이 없습니다.\n이메일 제공 동의가 필요합니다.';
        } else if (serverMessage.contains('network') || serverMessage.contains('timeout')) {
          errorMessage = '네트워크 연결이 불안정합니다.\n잠시 후 다시 시도해 주세요.';
        } else if (serverMessage.contains('REDIRECT_URI_MISMATCH')) {
          errorMessage = '카카오 로그인 설정 오류입니다.\n잠시 후 다시 시도해 주세요.';
        } else if (serverMessage.contains('PlatformException')) {
          errorMessage = '카카오 로그인 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.';
        } else if (serverMessage.isNotEmpty && !serverMessage.contains('Exception')) {
          errorMessage = serverMessage;
        }
      }

      _showErrorDialog(errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Google 로그인 처리
  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Google SDK 로그인
      final googleAccessToken = await GoogleLoginService.login();
      if (!mounted) return;

      // 2. AuthService (Provider 방식) 서버 로그인
      final authService = ref.read(authServiceProvider);
      await authService.googleLogin(googleAccessToken);
      if (!mounted) return;

      // 3. 사용자 정보 가져오기
      final userInfo = await authService.getUserInfo();
      if (!mounted) return;

      // 4. authProvider 상태 업데이트
      await ref.read(authProvider.notifier).updateAfterLogin(userInfo);
      if (!mounted) return;

      // 5. returnRoute 또는 MainScreen으로 이동
      _navigateAfterLogin();
    } catch (e) {
      if (!mounted) return;

      debugPrint('Google 로그인 에러: $e');

      String errorMessage = 'Google 로그인할 수 없습니다.\n잠시 후 다시 시도해 주세요.';
      final errorText = e.toString();

      if (errorText.contains('Exception:')) {
        final serverMessage = errorText.replaceAll('Exception:', '').trim();

        if (serverMessage.contains('취소')) {
          // 사용자가 취소한 경우는 에러 다이얼로그 표시 안 함
          setState(() {
            _isLoading = false;
          });
          return;
        } else if (serverMessage.contains('Google 로그인에 실패했습니다')) {
          errorMessage = 'Google 로그인할 수 없습니다.\n잠시 후 다시 시도해 주세요.';
        } else if (serverMessage.contains('네트워크')) {
          errorMessage = '네트워크 연결이 불안정합니다.\n잠시 후 다시 시도해 주세요.';
        } else if (serverMessage.contains('access token')) {
          errorMessage = 'Google 로그인할 수 없습니다.\n잠시 후 다시 시도해 주세요.';
        } else if (serverMessage.isNotEmpty && !serverMessage.contains('PlatformException')) {
          errorMessage = serverMessage;
        }
      }

      _showErrorDialog(errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Apple 로그인 처리
  Future<void> _handleAppleLogin() async {
    // Apple 로그인은 iOS에서만 지원
    if (!Platform.isIOS) {
      _showErrorDialog('Apple 로그인은 iOS에서만 사용할 수 있습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Apple Sign In
      final appleCredentials = await AppleLoginService.login();
      if (!mounted) return;

      // 2. AuthService (Provider 방식) 서버 로그인
      final authService = ref.read(authServiceProvider);
      await authService.appleLogin(
        appleCredentials['identity_token']!,
        appleCredentials['authorization_code'],
      );
      if (!mounted) return;

      // 3. 사용자 정보 가져오기
      final userInfo = await authService.getUserInfo();
      if (!mounted) return;

      // 4. authProvider 상태 업데이트
      await ref.read(authProvider.notifier).updateAfterLogin(userInfo);
      if (!mounted) return;

      // 5. returnRoute 또는 MainScreen으로 이동
      _navigateAfterLogin();
    } catch (e) {
      if (!mounted) return;

      debugPrint('Apple 로그인 에러: $e');

      String errorMessage = 'Apple 로그인 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.';
      final errorText = e.toString();

      if (errorText.contains('Exception:')) {
        final serverMessage = errorText.replaceAll('Exception:', '').trim();

        if (serverMessage.contains('취소')) {
          errorMessage = '로그인이 취소되었습니다.';
        } else if (serverMessage.contains('network') || serverMessage.contains('timeout')) {
          errorMessage = '네트워크 연결이 불안정합니다.\n잠시 후 다시 시도해 주세요.';
        } else if (serverMessage.isNotEmpty) {
          errorMessage = serverMessage;
        }
      }

      _showErrorDialog(errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 에러 다이얼로그 표시
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('알림'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 32.h),

              // 헤드라인
              _buildHeadline(),

              SizedBox(height: 24.h),
              
              // 이메일 입력 필드
              _buildInputField(
                title: '이메일',
                controller: _emailController,
                hintText: '이메일을 입력해 주세요',
                prefixIcon: Icons.person_outline,
              ),
              
              SizedBox(height: 16.h),
              
              // 비밀번호 입력 필드
              _buildPasswordField(),
              
              SizedBox(height: 8.h),
              
              // 비밀번호 찾기
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PasswordResetScreen(),
                      ),
                    );
                  },
                  child: Text(
                    '비밀번호를 잊으셨나요?',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                      letterSpacing: -0.12,
                    ),
                  ),
                ),
              ),

              SizedBox(height: 16.h),
              
              // 로그인 버튼
              _buildLoginButton(),

              SizedBox(height: 12.h),

              // 비밀번호 찾기 링크
              _buildForgotPasswordLink(),

              SizedBox(height: 20.h),

              // 또는 구분선
              _buildOrDivider(),

              SizedBox(height: 20.h),

              // 소셜 로그인 버튼들
              _buildSocialLoginButtons(),

              SizedBox(height: 24.h),

              // 회원가입 링크
              _buildSignUpLink(),

              SizedBox(height: 32.h),
            ],
          ),
        ),
      ),
    );
  }

  // 헤드라인 섹션
  Widget _buildHeadline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '로그인',
          style: TextStyle(
            fontSize: 32.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1C1E),
            letterSpacing: -0.64,
            height: 1.3,
          ),
        ),
        SizedBox(height: 12.h),
        Text(
          '이메일과 비밀번호를 입력해 주세요',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF6C7278),
            letterSpacing: -0.12,
          ),
        ),
      ],
    );
  }

  // 일반 입력 필드
  Widget _buildInputField({
    required String title,
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF6C7278),
            letterSpacing: -0.24,
          ),
        ),
        SizedBox(height: 8.h),
        Container(
          height: 46.h,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(
              color: const Color(0xFFEDF1F3),
              width: 1,
            ),
          ),
          child: TextField(
            controller: controller,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1A1C1E),
              letterSpacing: -0.14,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1A1C1E),
              ),
              prefixIcon: Icon(
                prefixIcon,
                size: 16.sp,
                color: const Color(0xFF6C7278),
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14.w,
                vertical: 13.h,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 비밀번호 입력 필드
  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '비밀번호',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF6C7278),
            letterSpacing: -0.24,
          ),
        ),
        SizedBox(height: 8.h),
        Container(
          height: 46.h,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(
              color: const Color(0xFFEDF1F3),
              width: 1,
            ),
          ),
          child: TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1A1C1E),
              letterSpacing: -0.14,
            ),
            decoration: InputDecoration(
              hintText: '비밀번호를 입력해 주세요',
              hintStyle: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1A1C1E),
              ),
              prefixIcon: Icon(
                Icons.lock_outline,
                size: 16.sp,
                color: const Color(0xFF6C7278),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword 
                    ? Icons.visibility_off_outlined 
                    : Icons.visibility_outlined,
                  size: 16.sp,
                  color: const Color(0xFF6C7278),
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14.w,
                vertical: 13.h,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Log In 버튼
  Widget _buildLoginButton() {
    return Container(
      width: double.infinity,
      height: 48.h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            primaryColor,
            primaryColor,
          ],
        ),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.r),
          ),
          padding: EdgeInsets.zero,
        ),
        child: _isLoading
            ? SizedBox(
                width: 20.w,
                height: 20.w,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                '로그인',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.14,
                ),
              ),
      ),
    );
  }

  // 또는 구분선
  Widget _buildOrDivider() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: const Color(0xFFEDF1F3),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Text(
            '또는',
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF6C7278),
              letterSpacing: -0.12,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: const Color(0xFFEDF1F3),
          ),
        ),
      ],
    );
  }

  // 소셜 로그인 버튼들
  Widget _buildSocialLoginButtons() {
    return Column(
      children: [
        // Google
        _buildSocialButton(
          text: 'Google로 시작하기',
          logoPath: 'asset/image/login/google.png',
          logoLeftPadding: 0,
          onPressed: _isLoading ? null : _handleGoogleLogin,
        ),
        SizedBox(height: 12.h),

        // Apple (iOS에서만 표시)
        if (Platform.isIOS) ...[
          _buildSocialButton(
            text: 'Apple로 시작하기',
            logoPath: 'asset/image/login/apple.png',
            logoLeftPadding: -2,
            onPressed: _isLoading ? null : _handleAppleLogin,
          ),
          SizedBox(height: 12.h),
        ],

        // Kakao
        _buildSocialButton(
          text: 'Kakao로 시작하기',
          logoPath: 'asset/image/login/kakao.png',
          logoLeftPadding: -1,
          onPressed: _isLoading ? null : _handleKakaoLogin,
        ),
      ],
    );
  }

  // 소셜 로그인 버튼 공통
  Widget _buildSocialButton({
    required String text,
    String? logoPath,
    double logoLeftPadding = 0,
    required VoidCallback? onPressed,
  }) {
    return Container(
      width: double.infinity,
      height: 48.h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(
          color: const Color(0xFFEFF0F6),
          width: 1,
        ),
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.r),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 로고 이미지 (있는 경우만)
            if (logoPath != null) ...[
              Transform.translate(
                offset: Offset(logoLeftPadding, 0),
                child: Image.asset(
                  logoPath,
                  width: 20.w,
                  height: 20.w,
                  fit: BoxFit.contain,
                ),
              ),
              SizedBox(width: 12.w),
            ],
            // 버튼 텍스트
            Text(
              text,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1C1E),
                letterSpacing: -0.14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 비밀번호 찾기 링크
  Widget _buildForgotPasswordLink() {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const PasswordResetScreen(),
            ),
          );
        },
        child: Text(
          '비밀번호 찾기',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF6C7278),
            letterSpacing: -0.12,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  // 회원가입 링크
  Widget _buildSignUpLink() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '계정이 없으신가요?',
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF6C7278),
              letterSpacing: -0.12,
            ),
          ),
          SizedBox(width: 4.w),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SignUpScreen(),
                ),
              );
            },
            child: Text(
              '회원가입',
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF4D81E7),
                letterSpacing: -0.12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

