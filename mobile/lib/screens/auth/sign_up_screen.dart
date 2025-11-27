import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/screens/main_screen.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/const/colors.dart';

/// 회원가입 화면 (이메일 인증 포함)
/// - 이름 (선택)
/// - 이메일 + 인증코드 발송/확인
/// - 비밀번호 (8자 이상)
/// - 비밀번호 확인
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  // 입력 컨트롤러
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _verificationCodeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();

  // UI 상태
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;
  bool _isLoading = false;

  // 이메일 인증 상태
  bool _isSendingCode = false;
  bool _isVerifyingCode = false;
  bool _isEmailVerified = false;
  String? _verificationToken;
  int _sendCount = 0;

  // 타이머 상태
  Timer? _expiryTimer;
  Timer? _resendCooldownTimer;
  int _expirySeconds = 0; // 인증코드 유효 시간 (초)
  int _resendCooldownSeconds = 0; // 재발송 대기 시간 (초)

  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _verificationCodeController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _authService.dispose();
    _expiryTimer?.cancel();
    _resendCooldownTimer?.cancel();
    super.dispose();
  }

  /// 인증코드 만료 타이머 시작 (60분)
  void _startExpiryTimer(int seconds) {
    _expiryTimer?.cancel();
    setState(() {
      _expirySeconds = seconds;
    });

    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_expirySeconds > 0) {
        setState(() {
          _expirySeconds--;
        });
      } else {
        timer.cancel();
        // 만료되면 인증 상태 리셋
        if (!_isEmailVerified) {
          setState(() {
            _verificationToken = null;
          });
        }
      }
    });
  }

  /// 재발송 쿨다운 타이머 시작 (60초)
  void _startResendCooldownTimer() {
    _resendCooldownTimer?.cancel();
    setState(() {
      _resendCooldownSeconds = 60;
    });

    _resendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldownSeconds > 0) {
        setState(() {
          _resendCooldownSeconds--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  /// 타이머 포맷 (mm:ss)
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// 인증코드 발송
  Future<void> _handleSendCode() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _showErrorDialog('이메일을 입력해 주세요.');
      return;
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      _showErrorDialog('이메일 주소를 다시 확인해 주세요.\n올바른 형식의 이메일을 입력해 주세요.');
      return;
    }

    setState(() {
      _isSendingCode = true;
    });

    try {
      final response = await _authService.sendEmailCode(email: email);

      if (!mounted) return;

      setState(() {
        _sendCount++;
        _isEmailVerified = false;
        _verificationToken = null;
        _verificationCodeController.clear();
      });

      // 인증코드 유효 시간 타이머 시작
      _startExpiryTimer(response.expiresIn);

      // 두 번째 발송부터 60초 쿨다운 적용
      if (_sendCount > 1) {
        _startResendCooldownTimer();
      }

      _showSuccessSnackBar('인증코드가 발송되었습니다.');
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog(_parseErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _isSendingCode = false;
        });
      }
    }
  }

  /// 인증코드 확인
  Future<void> _handleVerifyCode() async {
    final email = _emailController.text.trim();
    final code = _verificationCodeController.text.trim();

    if (code.isEmpty) {
      _showErrorDialog('인증코드를 입력해 주세요.');
      return;
    }

    if (code.length != 6) {
      _showErrorDialog('6자리 인증코드를 입력해 주세요.');
      return;
    }

    setState(() {
      _isVerifyingCode = true;
    });

    try {
      final response = await _authService.verifyEmailCode(
        email: email,
        code: code,
      );

      if (!mounted) return;

      setState(() {
        _isEmailVerified = response.verified;
        _verificationToken = response.verificationToken;
      });

      _showSuccessSnackBar('이메일 인증이 완료되었습니다.');
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog(_parseErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _isVerifyingCode = false;
        });
      }
    }
  }

  /// 회원가입 처리
  Future<void> _handleSignUp() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final passwordConfirm = _passwordConfirmController.text.trim();

    // 유효성 검사
    if (email.isEmpty) {
      _showErrorDialog('이메일을 입력해 주세요.');
      return;
    }

    if (!_isEmailVerified || _verificationToken == null) {
      _showErrorDialog('이메일 인증을 완료해 주세요.');
      return;
    }

    if (password.isEmpty) {
      _showErrorDialog('비밀번호를 입력해 주세요.');
      return;
    }

    if (password.length < 8) {
      _showErrorDialog('비밀번호는 8자 이상 입력해 주세요.');
      return;
    }

    if (passwordConfirm.isEmpty) {
      _showErrorDialog('비밀번호 확인을 입력해 주세요.');
      return;
    }

    if (password != passwordConfirm) {
      _showErrorDialog('비밀번호가 일치하지 않습니다.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.signUp(
        email: email,
        password: password,
        name: name.isNotEmpty ? name : null,
        verificationToken: _verificationToken!,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const MainScreen(),
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

      if (serverMessage.contains('already exists') ||
          serverMessage.contains('duplicate') ||
          serverMessage.contains('이미')) {
        errorMessage = '이미 가입된 이메일입니다.\n다른 이메일을 사용하시거나 로그인해 주세요.';
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

  /// 성공 스낵바 표시
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
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
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),

              SizedBox(height: 16.h),

              // 헤드라인
              _buildHeadline(),

              SizedBox(height: 24.h),

              // 이름 입력 필드 (선택)
              _buildNameField(),

              SizedBox(height: 16.h),

              // 이메일 입력 필드 + 발송 버튼
              _buildEmailField(),

              // 인증코드 입력 필드 (발송 후에만 표시)
              if (_expirySeconds > 0 || _isEmailVerified) ...[
                SizedBox(height: 16.h),
                _buildVerificationCodeField(),
              ],

              SizedBox(height: 16.h),

              // 비밀번호 입력 필드
              _buildPasswordField(),

              SizedBox(height: 16.h),

              // 비밀번호 확인 필드
              _buildPasswordConfirmField(),

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

  // 이름 입력 필드 (선택)
  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '이름',
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6C7278),
                letterSpacing: -0.24,
              ),
            ),
            SizedBox(width: 4.w),
            Text(
              '(선택)',
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w400,
                color: const Color(0xFFADB5BD),
                letterSpacing: -0.24,
              ),
            ),
          ],
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
            controller: _nameController,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1A1C1E),
              letterSpacing: -0.14,
            ),
            decoration: InputDecoration(
              hintText: '이름을 입력해 주세요',
              hintStyle: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w400,
                color: const Color(0xFFADB5BD),
              ),
              prefixIcon: Icon(
                Icons.person_outline,
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

  // 이메일 입력 필드 + 발송 버튼
  Widget _buildEmailField() {
    final bool canSendCode =
        !_isSendingCode && !_isEmailVerified && _resendCooldownSeconds == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '이메일',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF6C7278),
            letterSpacing: -0.24,
          ),
        ),
        SizedBox(height: 8.h),
        Row(
          children: [
            // 이메일 입력
            Expanded(
              child: Container(
                height: 46.h,
                decoration: BoxDecoration(
                  color: _isEmailVerified ? const Color(0xFFF5F5F5) : Colors.white,
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(
                    color: _isEmailVerified
                        ? Colors.green.withValues(alpha: 0.5)
                        : const Color(0xFFEDF1F3),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: _emailController,
                  enabled: !_isEmailVerified,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1A1C1E),
                    letterSpacing: -0.14,
                  ),
                  decoration: InputDecoration(
                    hintText: '이메일을 입력해 주세요',
                    hintStyle: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFFADB5BD),
                    ),
                    prefixIcon: Icon(
                      _isEmailVerified
                          ? Icons.check_circle
                          : Icons.email_outlined,
                      size: 16.sp,
                      color: _isEmailVerified
                          ? Colors.green
                          : const Color(0xFF6C7278),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14.w,
                      vertical: 13.h,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8.w),
            // 발송 버튼
            SizedBox(
              width: 72.w,
              height: 46.h,
              child: ElevatedButton(
                onPressed: canSendCode ? _handleSendCode : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      canSendCode ? PRIMARY_COLOR : const Color(0xFFE0E0E0),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: _isSendingCode
                    ? SizedBox(
                        width: 16.w,
                        height: 16.w,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        _resendCooldownSeconds > 0
                            ? '$_resendCooldownSeconds초'
                            : (_sendCount > 0 ? '재발송' : '발송'),
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 인증코드 입력 필드
  Widget _buildVerificationCodeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '인증코드',
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF6C7278),
                letterSpacing: -0.24,
              ),
            ),
            const Spacer(),
            if (_expirySeconds > 0 && !_isEmailVerified)
              Text(
                _formatTime(_expirySeconds),
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                  color: _expirySeconds < 300 ? Colors.red : PRIMARY_COLOR,
                  letterSpacing: -0.24,
                ),
              ),
            if (_isEmailVerified)
              Row(
                children: [
                  Icon(Icons.check_circle, size: 14.sp, color: Colors.green),
                  SizedBox(width: 4.w),
                  Text(
                    '인증완료',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
          ],
        ),
        SizedBox(height: 8.h),
        Row(
          children: [
            // 인증코드 입력
            Expanded(
              child: Container(
                height: 46.h,
                decoration: BoxDecoration(
                  color:
                      _isEmailVerified ? const Color(0xFFF5F5F5) : Colors.white,
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(
                    color: _isEmailVerified
                        ? Colors.green.withValues(alpha: 0.5)
                        : const Color(0xFFEDF1F3),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: _verificationCodeController,
                  enabled: !_isEmailVerified,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1A1C1E),
                    letterSpacing: 4.0,
                  ),
                  decoration: InputDecoration(
                    hintText: '6자리 숫자 입력',
                    hintStyle: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFFADB5BD),
                      letterSpacing: 0,
                    ),
                    prefixIcon: Icon(
                      Icons.pin_outlined,
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
            ),
            SizedBox(width: 8.w),
            // 확인 버튼
            SizedBox(
              width: 72.w,
              height: 46.h,
              child: ElevatedButton(
                onPressed: _isEmailVerified || _isVerifyingCode
                    ? null
                    : _handleVerifyCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isEmailVerified || _isVerifyingCode
                      ? const Color(0xFFE0E0E0)
                      : PRIMARY_COLOR,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: _isVerifyingCode
                    ? SizedBox(
                        width: 16.w,
                        height: 16.w,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        '확인',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
          ],
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
              hintText: '비밀번호를 입력해 주세요 (8자 이상)',
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

  // 비밀번호 확인 필드
  Widget _buildPasswordConfirmField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '비밀번호 확인',
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
            controller: _passwordConfirmController,
            obscureText: _obscurePasswordConfirm,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1A1C1E),
              letterSpacing: -0.14,
            ),
            decoration: InputDecoration(
              hintText: '비밀번호를 다시 입력해 주세요',
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
                  _obscurePasswordConfirm
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 16.sp,
                  color: const Color(0xFF6C7278),
                ),
                onPressed: () {
                  setState(() {
                    _obscurePasswordConfirm = !_obscurePasswordConfirm;
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

  // 가입하기 버튼
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

  // 로그인 링크
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
            onTap: () => Navigator.pop(context),
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
