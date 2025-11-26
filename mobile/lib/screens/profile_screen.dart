import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/auth_provider.dart';
import 'auth/login_screen.dart';
import 'notification_screen.dart';

/// 내정보 화면
/// - 비회원: 로그인 안내 표시
/// - 회원: 프로필 정보 및 메뉴 리스트
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('내정보'),
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: authState.isRegularUser
          ? _buildAuthenticatedContent(context, authState)
          : _buildUnauthenticatedContent(context),
    );
  }

  /// 비회원 콘텐츠
  Widget _buildUnauthenticatedContent(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            size: 64.sp,
            color: const Color(0xFFD1D5DB),
          ),
          SizedBox(height: 16.h),
          Text(
            '로그인이 필요합니다',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A1C1E),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '회원만 이용 가능한 기능입니다.',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF6C7278),
            ),
          ),
          SizedBox(height: 24.h),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const LoginScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: 32.w,
                vertical: 14.h,
              ),
            ),
            child: Text(
              '로그인하기',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 회원 콘텐츠
  Widget _buildAuthenticatedContent(
    BuildContext context,
    AuthState authState,
  ) {
    final userInfo = authState.userInfo;
    final displayName = userInfo?.name ?? userInfo?.email ?? '사용자';
    final profileImageUrl = userInfo?.profileImage;

    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 프로필 섹션
          Container(
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(
                color: const Color(0xFFEDF1F3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // 프로필 이미지
                _buildProfileImage(profileImageUrl),
                SizedBox(width: 16.w),
                // 사용자 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1A1C1E),
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Row(
                        children: [
                          _buildLoginMethodBadge(userInfo?.loginMethod),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              userInfo?.email ?? '',
                              style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF6C7278),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 24.h),

          // 메뉴 리스트
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(
                color: const Color(0xFFEDF1F3),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                _buildMenuItem(
                  icon: Icons.notifications_outlined,
                  title: '알림 설정',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const NotificationScreen(),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                // 설정 메뉴 (향후 사용 예정)
                // _buildMenuItem(
                //   icon: Icons.settings_outlined,
                //   title: '설정',
                //   onTap: () {
                //     // TODO: 설정 화면으로 이동
                //   },
                // ),
                // _buildDivider(),
                _buildMenuItem(
                  icon: Icons.logout,
                  title: '로그아웃',
                  textColor: Colors.red,
                  onTap: () async {
                    final confirmed = await _showLogoutDialog(context);
                    if (confirmed == true) {
                      await ref.read(authProvider.notifier).logout();
                    }
                  },
                ),
              ],
            ),
          ),

          SizedBox(height: 24.h),

          // 앱 정보 (논리 버전 사용)
          Center(
            child: Text(
              '리뷰맵 v2.0.0',
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF9CA3AF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 프로필 이미지 위젯
  Widget _buildProfileImage(String? imageUrl) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 32.r,
        backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        backgroundImage: NetworkImage(imageUrl),
        onBackgroundImageError: (_, __) {
          // 이미지 로드 실패 시 기본 아이콘 표시
        },
        child: null,
      );
    }

    return CircleAvatar(
      radius: 32.r,
      backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
      child: Icon(
        Icons.person,
        size: 32.sp,
        color: Theme.of(context).primaryColor,
      ),
    );
  }

  /// 로그인 방식 뱃지
  Widget _buildLoginMethodBadge(String? loginMethod) {
    if (loginMethod == null || loginMethod == 'email') {
      return const SizedBox.shrink();
    }

    String? assetPath;

    switch (loginMethod) {
      case 'kakao':
        assetPath = 'asset/image/login/kakao.png';
        break;
      case 'google':
        assetPath = 'asset/image/login/google.png';
        break;
      case 'apple':
        assetPath = 'asset/image/login/apple.png';
        break;
      case 'naver':
        // 네이버 이미지가 없으면 기본 아이콘 사용
        return Container(
          padding: EdgeInsets.all(4.w),
          decoration: BoxDecoration(
            color: const Color(0xFF03C75A),
            borderRadius: BorderRadius.circular(4.r),
          ),
          child: Text(
            'N',
            style: TextStyle(
              fontSize: 10.sp,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4.r),
      child: Image.asset(
        assetPath,
        width: 20.w,
        height: 20.w,
        fit: BoxFit.contain,
      ),
    );
  }

  /// 메뉴 아이템
  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? textColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16.w,
          vertical: 16.h,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24.sp,
              color: textColor ?? const Color(0xFF6C7278),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                  color: textColor ?? const Color(0xFF1A1C1E),
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20.sp,
              color: const Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
  }

  /// 구분선
  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: const Color(0xFFEDF1F3),
    );
  }

  /// 로그아웃 확인 다이얼로그
  Future<bool?> _showLogoutDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
        title: Text(
          '로그아웃',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1C1E),
          ),
        ),
        content: Text(
          '정말 로그아웃하시겠습니까?',
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF6C7278),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              '취소',
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
              '로그아웃',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
