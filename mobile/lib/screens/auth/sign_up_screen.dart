import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/screens/main_screen.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/const/colors.dart';

/// Sign Up Version 1 화면
/// Figma 디자인을 기반으로 한 회원가입 화면
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _birthDateController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _authService.dispose();
    super.dispose();
  }

  /// 회원가입 처리
  Future<void> _handleSignUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // 유효성 검사
    if (email.isEmpty) {
      _showErrorDialog('이메일을 입력해 주세요.');
      return;
    }

    // 이메일 형식 검증
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      _showErrorDialog('이메일 주소를 다시 확인해 주세요.\n올바른 형식의 이메일을 입력해 주세요.');
      return;
    }

    if (password.isEmpty) {
      _showErrorDialog('비밀번호를 입력해 주세요.');
      return;
    }

    // 비밀번호 길이 검증
    if (password.length < 6) {
      _showErrorDialog('비밀번호는 6자 이상 입력해 주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.signUp(email: email, password: password);

      if (!mounted) return;

      // 회원가입 성공 - MainScreen으로 이동
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const MainScreen(),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      String errorMessage = '회원가입할 수 없습니다.\n잠시 후 다시 시도해 주세요.';
      final errorText = e.toString();

      if (errorText.contains('Exception:')) {
        final serverMessage = errorText.replaceAll('Exception:', '').trim();

        // 서버에서 온 에러 메시지를 네이버 스타일로 변환
        if (serverMessage.contains('already exists') ||
            serverMessage.contains('duplicate') ||
            serverMessage.contains('이미')) {
          errorMessage = '이미 가입된 이메일입니다.\n다른 이메일을 사용하시거나 로그인해 주세요.';
        } else if (serverMessage.contains('invalid email') || serverMessage.contains('이메일')) {
          errorMessage = '이메일 주소를 다시 확인해 주세요.';
        } else if (serverMessage.contains('password') && serverMessage.contains('weak')) {
          errorMessage = '더 안전한 비밀번호를 사용해 주세요.\n영문, 숫자, 특수문자를 조합해 주세요.';
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

  /// 에러 다이얼로그 표시
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
              SizedBox(height: 24.h),

              // 뒤로가기 버튼
              IconButton(
                icon: Icon(
                  Icons.arrow_back_ios,
                  size: 24.sp,
                  color: const Color(0xFF1A1C1E),
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),

              SizedBox(height: 16.h),

              // 헤드라인
              _buildHeadline(),

              SizedBox(height: 24.h),
              
              // 이름 입력 필드
              _buildInputField(
                title: '이름',
                controller: _fullNameController,
                hintText: '이름을 입력해 주세요',
                prefixIcon: Icons.person_outline,
              ),

              SizedBox(height: 16.h),

              // 이메일 입력 필드
              _buildInputField(
                title: '이메일',
                controller: _emailController,
                hintText: '이메일을 입력해 주세요',
                prefixIcon: Icons.email_outlined,
              ),
              
              SizedBox(height: 16.h),
              
              // Birth of date 입력 필드
              _buildDateField(),
              
              SizedBox(height: 16.h),
              
              // Phone Number 입력 필드
              _buildPhoneField(),
              
              SizedBox(height: 16.h),
              
              // Set Password 입력 필드
              _buildPasswordField(),
              
              SizedBox(height: 20.h),

              // 가입하기 버튼
              _buildRegisterButton(),

              SizedBox(height: 20.h),

              // 로그인 링크
              _buildLoginLink(),

              SizedBox(height: 24.h),
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
          '회원가입',
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
          '계정을 만들어 서비스를 시작하세요',
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
                fontWeight: FontWeight.w400,
                color: const Color(0xFFADB5BD),
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

  // 생년월일 입력 필드
  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '생년월일',
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
            controller: _birthDateController,
            readOnly: true,
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: DateTime(2000),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
              );
              if (date != null) {
                _birthDateController.text = 
                  '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
              }
            },
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1A1C1E),
              letterSpacing: -0.14,
            ),
            decoration: InputDecoration(
              hintText: '생년월일을 선택해 주세요',
              hintStyle: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w400,
                color: const Color(0xFFADB5BD),
              ),
              prefixIcon: Icon(
                Icons.calendar_today_outlined,
                size: 16.sp,
                color: const Color(0xFF6C7278),
              ),
              suffixIcon: Icon(
                Icons.calendar_month_outlined,
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

  // 전화번호 입력 필드
  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '휴대전화',
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
          child: Row(
            children: [
              // 국가 코드 선택
              Container(
                width: 62.w,
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(
                      color: const Color(0xFFEDF1F3),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '🇰🇷',
                      style: TextStyle(fontSize: 18.sp),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 12.sp,
                      color: const Color(0xFF6C7278),
                    ),
                  ],
                ),
              ),
              // 전화번호 입력
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1A1C1E),
                    letterSpacing: -0.14,
                  ),
                  decoration: InputDecoration(
                    hintText: '휴대전화 번호를 입력해 주세요',
                    hintStyle: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFFADB5BD),
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
                fontWeight: FontWeight.w400,
                color: const Color(0xFFADB5BD),
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

  // Register 버튼
  Widget _buildRegisterButton() {
    return Container(
      width: double.infinity,
      height: 48.h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            PRIMARY_COLOR,
            PRIMARY_COLOR,
          ],
        ),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleSignUp,
        style: ElevatedButton.styleFrom(
          backgroundColor: PRIMARY_COLOR,
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
                '가입하기',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.14,
                ),
              ),
      ),
    );
  }

  // Login 링크
  Widget _buildLoginLink() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '이미 계정이 있으신가요?',
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
              Navigator.pop(context);
            },
            child: Text(
              '로그인',
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

