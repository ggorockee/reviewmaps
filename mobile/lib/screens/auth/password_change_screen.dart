import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/const/colors.dart';

/// 비밀번호 변경 화면 (로그인한 사용자)
/// - 현재 비밀번호 확인 → 새 비밀번호 입력 → 변경
class PasswordChangeScreen extends StatefulWidget {
  const PasswordChangeScreen({super.key});

  @override
  State<PasswordChangeScreen> createState() => _PasswordChangeScreenState();
}

class _PasswordChangeScreenState extends State<PasswordChangeScreen> {
  // 입력 컨트롤러
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _newPasswordConfirmController = TextEditingController();

  // UI 상태
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureNewPasswordConfirm = true;
  bool _isLoading = false;

  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _newPasswordConfirmController.dispose();
    _authService.dispose();
    super.dispose();
  }

  /// 비밀번호 변경 처리
  Future<void> _handleChangePassword() async {
    final currentPassword = _currentPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final newPasswordConfirm = _newPasswordConfirmController.text.trim();

    // 유효성 검사
    if (currentPassword.isEmpty) {
      _showErrorDialog('현재 비밀번호를 입력해 주세요.');
      return;
    }

    if (newPassword.isEmpty) {
      _showErrorDialog('새 비밀번호를 입력해 주세요.');
      return;
    }

    if (newPassword.length < 8) {
      _showErrorDialog('새 비밀번호는 8자 이상 입력해 주세요.');
      return;
    }

    if (newPasswordConfirm.isEmpty) {
      _showErrorDialog('새 비밀번호 확인을 입력해 주세요.');
      return;
    }

    if (newPassword != newPasswordConfirm) {
      _showErrorDialog('새 비밀번호가 일치하지 않습니다.');
      return;
    }

    if (currentPassword == newPassword) {
      _showErrorDialog('새 비밀번호는 현재 비밀번호와 달라야 합니다.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.passwordChange(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

      if (!mounted) return;

      // 성공 다이얼로그 표시 후 화면 닫기
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('비밀번호 변경 완료'),
          content: const Text('비밀번호가 성공적으로 변경되었습니다.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // 비밀번호 변경 화면도 닫기
              },
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog(_parseErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 에러 메시지 파싱
  String _parseErrorMessage(Object e) {
    String errorMessage = '오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
    final errorText = e.toString();

    if (errorText.contains('Exception:')) {
      final serverMessage = errorText.replaceAll('Exception:', '').trim();

      if (serverMessage.contains('현재 비밀번호가 일치하지')) {
        errorMessage = '현재 비밀번호가 일치하지 않습니다.\n다시 확인해 주세요.';
      } else if (serverMessage.contains('이메일 로그인')) {
        errorMessage = 'SNS 로그인 사용자는 비밀번호를 변경할 수 없습니다.';
      } else if (serverMessage.contains('로그인이 필요')) {
        errorMessage = '로그인이 필요합니다.\n다시 로그인해 주세요.';
      } else if (serverMessage.contains('network') ||
          serverMessage.contains('timeout')) {
        errorMessage = '네트워크 연결이 불안정합니다.\n잠시 후 다시 시도해 주세요.';
      } else {
        errorMessage = serverMessage;
      }
    }

    return errorMessage;
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 24.sp,
            color: const Color(0xFF1A1C1E),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '비밀번호 변경',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1C1E),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 24.h),

              // 안내 메시지
              Text(
                '보안을 위해 현재 비밀번호를 확인해 주세요',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF6C7278),
                  letterSpacing: -0.14,
                ),
              ),

              SizedBox(height: 24.h),

              // 현재 비밀번호 입력 필드
              _buildCurrentPasswordField(),

              SizedBox(height: 16.h),

              // 새 비밀번호 입력 필드
              _buildNewPasswordField(),

              SizedBox(height: 16.h),

              // 새 비밀번호 확인 필드
              _buildNewPasswordConfirmField(),

              SizedBox(height: 32.h),

              // 변경 버튼
              _buildChangeButton(),

              SizedBox(height: 24.h),
            ],
          ),
        ),
      ),
    );
  }

  // 현재 비밀번호 입력 필드
  Widget _buildCurrentPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '현재 비밀번호',
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
            controller: _currentPasswordController,
            obscureText: _obscureCurrentPassword,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1A1C1E),
              letterSpacing: -0.14,
            ),
            decoration: InputDecoration(
              hintText: '현재 비밀번호 입력',
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
                  _obscureCurrentPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 16.sp,
                  color: const Color(0xFF6C7278),
                ),
                onPressed: () {
                  setState(() {
                    _obscureCurrentPassword = !_obscureCurrentPassword;
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

  // 새 비밀번호 입력 필드
  Widget _buildNewPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '새 비밀번호',
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
            controller: _newPasswordController,
            obscureText: _obscureNewPassword,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1A1C1E),
              letterSpacing: -0.14,
            ),
            decoration: InputDecoration(
              hintText: '새 비밀번호 입력 (8자 이상)',
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
                  _obscureNewPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 16.sp,
                  color: const Color(0xFF6C7278),
                ),
                onPressed: () {
                  setState(() {
                    _obscureNewPassword = !_obscureNewPassword;
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

  // 새 비밀번호 확인 필드
  Widget _buildNewPasswordConfirmField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '새 비밀번호 확인',
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
            controller: _newPasswordConfirmController,
            obscureText: _obscureNewPasswordConfirm,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1A1C1E),
              letterSpacing: -0.14,
            ),
            decoration: InputDecoration(
              hintText: '새 비밀번호 다시 입력',
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
                  _obscureNewPasswordConfirm
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 16.sp,
                  color: const Color(0xFF6C7278),
                ),
                onPressed: () {
                  setState(() {
                    _obscureNewPasswordConfirm = !_obscureNewPasswordConfirm;
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

  // 변경 버튼
  Widget _buildChangeButton() {
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
        onPressed: _isLoading ? null : _handleChangePassword,
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
                '비밀번호 변경',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.16,
                ),
              ),
      ),
    );
  }
}

