import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/version_check_models.dart';
import '../services/version_service.dart';

/// 앱 업데이트 안내 다이얼로그
///
/// 네이버 스타일의 깔끔한 디자인으로 업데이트를 안내합니다.
/// - 강제 업데이트: 닫기 버튼 없이 스토어로만 이동 가능
/// - 권장 업데이트: "나중에" 버튼으로 닫을 수 있으며, 일정 기간 재표시 방지
class UpdateDialog extends StatelessWidget {
  final VersionCheckResponse versionInfo;
  final bool isForceUpdate;
  final VoidCallback? onSkip;

  const UpdateDialog({
    super.key,
    required this.versionInfo,
    required this.isForceUpdate,
    this.onSkip,
  });

  /// 스토어 URL 열기
  Future<void> _openStore(BuildContext context) async {
    final url = Uri.parse(versionInfo.storeUrl);

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('스토어를 열 수 없습니다')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('스토어 열기 실패: $e')),
        );
      }
    }
  }

  /// "나중에" 버튼 클릭 처리
  void _handleSkip(BuildContext context) {
    onSkip?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // 강제 업데이트 vs 권장 업데이트에 따른 문구 결정
    final String title = isForceUpdate
        ? (versionInfo.messageTitle ?? '업데이트 안내')
        : (versionInfo.messageTitle ?? '새 버전이 있어요');

    final String body = isForceUpdate
        ? (versionInfo.messageBody ?? '최신 버전으로 업데이트한 뒤 이용해 주세요.')
        : (versionInfo.messageBody ?? '더 나은 서비스 이용을 위해 업데이트를 추천드려요.');

    return PopScope(
      // 강제 업데이트일 경우 뒤로가기 버튼 비활성화
      canPop: !isForceUpdate,
      child: Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
        elevation: 8,
        shadowColor: Colors.black26,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 28.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 제목
              Text(
                title,
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16.h),

              // 본문
              Text(
                body,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.black54,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24.h),

              // 버튼 영역
              if (isForceUpdate)
                // 강제 업데이트: 업데이트하러가기 버튼만 표시
                _buildPrimaryButton(context, '업데이트하러가기')
              else
                // 권장 업데이트: 업데이트하러가기 + 나중에 버튼
                Column(
                  children: [
                    _buildPrimaryButton(context, '업데이트하러가기'),
                    SizedBox(height: 8.h),
                    _buildSecondaryButton(context, '나중에'),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 주요 버튼 (업데이트하러가기)
  Widget _buildPrimaryButton(BuildContext context, String text) {
    return SizedBox(
      width: double.infinity,
      height: 48.h,
      child: ElevatedButton(
        onPressed: () => _openStore(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
          elevation: 2,
          shadowColor: Theme.of(context).primaryColor.withValues(alpha: 0.3),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15.sp,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// 보조 버튼 (나중에)
  Widget _buildSecondaryButton(BuildContext context, String text) {
    return SizedBox(
      width: double.infinity,
      height: 44.h,
      child: TextButton(
        onPressed: () => _handleSkip(context),
        style: TextButton.styleFrom(
          foregroundColor: Colors.black54,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// 강제 업데이트 다이얼로그 표시
  ///
  /// 뒤로가기, 바깥 영역 클릭으로 닫을 수 없습니다.
  static Future<void> showForceUpdate(
    BuildContext context,
    VersionCheckResponse versionInfo,
  ) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UpdateDialog(
        versionInfo: versionInfo,
        isForceUpdate: true,
      ),
    );
  }

  /// 권장 업데이트 다이얼로그 표시
  ///
  /// "나중에" 선택 시 일정 기간 동안 다시 표시하지 않습니다.
  static Future<void> showRecommendedUpdate(
    BuildContext context,
    VersionCheckResponse versionInfo,
  ) {
    final versionService = VersionService();

    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => UpdateDialog(
        versionInfo: versionInfo,
        isForceUpdate: false,
        onSkip: () {
          // "나중에" 선택 시 스킵 기록 저장
          versionService.skipRecommendedUpdate();
        },
      ),
    );
  }

  /// 레거시 호환용 show 메서드
  @Deprecated('Use showForceUpdate or showRecommendedUpdate instead')
  static Future<void> show(
    BuildContext context,
    VersionCheckResponse versionInfo,
  ) {
    if (versionInfo.requiresForceUpdate) {
      return showForceUpdate(context, versionInfo);
    } else {
      return showRecommendedUpdate(context, versionInfo);
    }
  }
}
