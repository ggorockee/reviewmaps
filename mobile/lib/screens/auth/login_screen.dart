import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/screens/auth/sign_up_screen.dart';

/// Login Version 1 화면
/// Figma 디자인을 기반으로 한 로그인 화면
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
              SizedBox(height: 56.h),
              
              // 헤드라인
              _buildHeadline(),
              
              SizedBox(height: 32.h),
              
              // 이메일 입력 필드
              _buildInputField(
                title: 'Email',
                controller: _emailController,
                hintText: 'Loisbecket@gmail.com',
                prefixIcon: Icons.person_outline,
              ),
              
              SizedBox(height: 16.h),
              
              // 비밀번호 입력 필드
              _buildPasswordField(),
              
              SizedBox(height: 8.h),
              
              // Forgot Password
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    // TODO: Forgot Password 처리
                  },
                  child: Text(
                    'Forgot Password ?',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF4D81E7),
                      letterSpacing: -0.12,
                    ),
                  ),
                ),
              ),
              
              SizedBox(height: 16.h),
              
              // Log In 버튼
              _buildLoginButton(),
              
              SizedBox(height: 16.h),
              
              // Or 구분선
              _buildOrDivider(),
              
              SizedBox(height: 16.h),
              
              // 소셜 로그인 버튼들
              _buildSocialLoginButtons(),
              
              SizedBox(height: 32.h),
              
              // Sign Up 링크
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
          'Sign in',
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
          'Enter your email and password to log in ',
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
          'Password',
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
              hintText: '*******',
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
            const Color(0xFF1D61E7),
            const Color(0xFF1D61E7),
          ],
        ),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: ElevatedButton(
        onPressed: () {
          // TODO: 로그인 처리
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1D61E7),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.r),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          'Log In',
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.14,
          ),
        ),
      ),
    );
  }

  // Or 구분선
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
            'Or',
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
          text: 'Continue with Google',
          onPressed: () {
            // TODO: Google 로그인
          },
        ),
        SizedBox(height: 15.h),
        
        // Apple
        _buildSocialButton(
          text: 'Continue with Apple',
          onPressed: () {
            // TODO: Apple 로그인
          },
        ),
        SizedBox(height: 15.h),
        
        // Kakao
        _buildSocialButton(
          text: 'Continue with Kakao',
          onPressed: () {
            // TODO: Kakao 로그인
          },
        ),
        SizedBox(height: 15.h),
        
        // 회원가입 없이 시작하기
        _buildSocialButton(
          text: '회원가입 없이 시작하기',
          onPressed: () {
            // TODO: 게스트 모드로 시작
          },
        ),
      ],
    );
  }

  // 소셜 로그인 버튼 공통
  Widget _buildSocialButton({
    required String text,
    required VoidCallback onPressed,
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
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1C1E),
            letterSpacing: -0.14,
          ),
        ),
      ),
    );
  }

  // Sign Up 링크
  Widget _buildSignUpLink() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Don't have an account?",
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
              'Sign Up',
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

