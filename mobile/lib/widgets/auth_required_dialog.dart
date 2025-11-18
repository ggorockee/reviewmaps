import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 회원 인증 필수 다이얼로그
/// - 알림, 내정보 등 회원 전용 기능 접근 시 표시
/// - "예" 클릭 시 로그인 화면으로 이동
class AuthRequiredDialog extends StatelessWidget {
  final String title;
  final String message;

  const AuthRequiredDialog({
    super.key,
    this.title = '로그인이 필요합니다',
    this.message = '회원만 이용 가능한 기능입니다.\n로그인하시겠습니까?',
  });

  /// 다이얼로그 표시
  /// - 반환값: true (로그인으로 이동), false (취소)
  static Future<bool?> show(
    BuildContext context, {
    String? title,
    String? message,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AuthRequiredDialog(
        title: title ?? '로그인이 필요합니다',
        message: message ?? '회원만 이용 가능한 기능입니다.\n로그인하시겠습니까?',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 18.sp,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF1A1C1E),
        ),
      ),
      content: Text(
        message,
        style: TextStyle(
          fontSize: 14.sp,
          fontWeight: FontWeight.w400,
          color: const Color(0xFF6C7278),
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            '아니요',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF6C7278),
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            '예',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ),
      ],
    );
  }
}
