import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/ads/rewarded_ad_service.dart';
import 'package:mobile/const/colors.dart';

/// ExitRewardDialog
/// ------------------------------------------------------------
/// 앱 종료 시 표시되는 리워드 광고 제안 다이얼로그
/// - 사용자 친화적인 메시지로 광고 시청 유도
/// - 광고 시청 완료 시 보상 제공 (프리미엄 정보 등)
class ExitRewardDialog extends StatelessWidget {
  final VoidCallback onExit;
  final VoidCallback? onRewardEarned;

  const ExitRewardDialog({
    super.key,
    required this.onExit,
    this.onRewardEarned,
  });

  /// 다이얼로그 표시
  static Future<bool?> show(
    BuildContext context, {
    VoidCallback? onRewardEarned,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ExitRewardDialog(
        onExit: () => Navigator.of(context).pop(true),
        onRewardEarned: onRewardEarned,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = _isTablet(context);
    final rewardedAdService = RewardedAdService();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 아이콘
            Container(
              width: 80.w,
              height: 80.w,
              decoration: BoxDecoration(
                color: PRIMARY_COLOR.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(40.r),
              ),
              child: Icon(
                Icons.card_giftcard,
                size: 40.w,
                color: PRIMARY_COLOR,
              ),
            ),
            
            SizedBox(height: 20.h),
            
            // 제목
            Text(
              '잠깐만요! 🎁',
              style: TextStyle(
                fontSize: isTablet ? 28.sp : 24.sp,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            
            SizedBox(height: 12.h),
            
            // 설명
            Text(
              '광고를 보시면 더 많은 프리미엄\n체험단 정보를 확인하실 수 있어요!',
              style: TextStyle(
                fontSize: isTablet ? 18.sp : 16.sp,
                color: Colors.grey[600],
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            
            SizedBox(height: 8.h),
            
            // 혜택 설명
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.star,
                    color: Colors.orange,
                    size: 18.w,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    '신규 체험단 정보 + 특별 혜택',
                    style: TextStyle(
                      fontSize: isTablet ? 16.sp : 14.sp,
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 24.h),
            
            // 버튼들
            Row(
              children: [
                // 나가기 버튼
                Expanded(
                  child: OutlinedButton(
                    onPressed: onExit,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                    child: Text(
                      '나가기',
                      style: TextStyle(
                        fontSize: isTablet ? 18.sp : 16.sp,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                
                SizedBox(width: 12.w),
                
                // 광고 보기 버튼
                Expanded(
                  child: ElevatedButton(
                    onPressed: rewardedAdService.isAdReady
                        ? () => _showRewardedAd(context, rewardedAdService)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: PRIMARY_COLOR,
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.play_circle_outline,
                          color: Colors.white,
                          size: 18.w,
                        ),
                        SizedBox(width: 6.w),
                        Text(
                          '광고 보기',
                          style: TextStyle(
                            fontSize: isTablet ? 18.sp : 16.sp,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 12.h),
            
            // 작은 안내 텍스트
            Text(
              '광고는 30초 정도 소요됩니다',
              style: TextStyle(
                fontSize: isTablet ? 14.sp : 12.sp,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 리워드 광고 표시
  void _showRewardedAd(BuildContext context, RewardedAdService adService) {
    adService.showAd(
      onRewarded: (ad, reward) {
        // 보상 지급 로직
        debugPrint('🎁 리워드 획득: ${reward.amount} ${reward.type}');
        onRewardEarned?.call();
        
        // 보상 완료 스낵바
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('🎉 프리미엄 정보가 해제되었습니다!'),
              backgroundColor: PRIMARY_COLOR,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      },
      onAdClosed: () {
        if (context.mounted) {
          Navigator.of(context).pop(false); // 앱 종료하지 않음
        }
      },
    );
  }
  
  /// 태블릿 여부 확인
  bool _isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide >= 600;
  }
}
