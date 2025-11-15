import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _birthDateController.dispose();
    _phoneController.dispose();
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
              SizedBox(height: 32.h),
              
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
              
              SizedBox(height: 24.h),
              
              // 헤드라인
              _buildHeadline(),
              
              SizedBox(height: 32.h),
              
              // Full Name 입력 필드
              _buildInputField(
                title: 'Full Name',
                controller: _fullNameController,
                hintText: 'Lois Becket',
                prefixIcon: Icons.person_outline,
              ),
              
              SizedBox(height: 16.h),
              
              // Email 입력 필드
              _buildInputField(
                title: 'Email',
                controller: _emailController,
                hintText: 'Loisbecket@gmail.com',
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
              
              SizedBox(height: 24.h),
              
              // Register 버튼
              _buildRegisterButton(),
              
              SizedBox(height: 24.h),
              
              // Login 링크
              _buildLoginLink(),
              
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
          'Sign up',
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
          'Create an account to continue!',
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

  // 생년월일 입력 필드
  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Birth of date',
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
              hintText: '18/03/2024',
              hintStyle: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1A1C1E),
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
          'Phone Number',
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
                    hintText: '(454) 726-0592',
                    hintStyle: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1A1C1E),
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
          'Set Password',
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
            const Color(0xFF1D61E7),
            const Color(0xFF1D61E7),
          ],
        ),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: ElevatedButton(
        onPressed: () {
          // TODO: 회원가입 처리
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
          'Register',
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
            'Already have an account?',
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
              'Login',
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

