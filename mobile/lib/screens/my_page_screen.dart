import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/keyword_service.dart';
import 'package:mobile/const/colors.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/screens/keyword_alerts_screen.dart';
import 'package:mobile/models/auth_models.dart';

/// 내정보 화면
class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  final AuthService _authService = AuthService();
  final KeywordService _keywordService = KeywordService();
  bool _isLoading = true;
  bool _isLoggedIn = false;
  bool _isAnonymous = false;
  UserInfo? _userInfo;
  AnonymousUserInfo? _anonymousUserInfo;
  int _keywordCount = 0;
  int _unreadAlertCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  /// 사용자 정보 로드
  Future<void> _loadUserInfo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final isLoggedIn = await _authService.isLoggedIn();
      final isAnonymous = await _authService.isAnonymous();

      setState(() {
        _isLoggedIn = isLoggedIn;
        _isAnonymous = isAnonymous;
      });

      if (isLoggedIn) {
        if (isAnonymous) {
          // 익명 사용자 정보 로드
          try {
            final anonymousInfo = await _authService.getAnonymousUserInfo();
            setState(() {
              _anonymousUserInfo = anonymousInfo;
            });
          } catch (e) {
            debugPrint('[MyPageScreen] 익명 사용자 정보 조회 실패: $e');
          }
        } else {
          // 일반 사용자 정보 로드
          try {
            final userInfo = await _authService.getUserInfo();
            setState(() {
              _userInfo = userInfo;
            });
          } catch (e) {
            debugPrint('[MyPageScreen] 사용자 정보 조회 실패: $e');
          }
        }

        // 키워드 및 알람 정보 로드
        await _loadKeywordInfo();
      }
    } catch (e) {
      debugPrint('[MyPageScreen] 로그인 상태 확인 실패: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 키워드 및 알람 정보 로드
  Future<void> _loadKeywordInfo() async {
    try {
      final keywords = await _keywordService.getMyKeywords();
      final alerts = await _keywordService.getMyAlerts(isRead: false);
      setState(() {
        _keywordCount = keywords.length;
        _unreadAlertCount = alerts.unreadCount;
      });
    } catch (e) {
      debugPrint('[MyPageScreen] 키워드 정보 조회 실패: $e');
    }
  }

  /// 로그아웃 처리
  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              '로그아웃',
              style: TextStyle(color: primaryColor),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        await _authService.logout();

        if (!mounted) return;

        // 로그인 화면으로 이동
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          ),
          (route) => false,
        );
      } catch (e) {
        if (!mounted) return;

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('알림'),
            content: const Text('로그아웃할 수 없습니다.\n잠시 후 다시 시도해 주세요.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '내정보',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1C1E),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 프로필 카드
                    _buildProfileCard(),

                    SizedBox(height: 32.h),

                    // 익명 사용자 세션 정보
                    if (_isLoggedIn && _isAnonymous && _anonymousUserInfo != null) ...[
                      _buildSectionTitle('세션 정보'),
                      SizedBox(height: 16.h),
                      _buildInfoItem('세션 ID', _anonymousUserInfo!.sessionId),
                      SizedBox(height: 12.h),
                      _buildExpiryWarning(),
                      SizedBox(height: 32.h),
                    ],

                    // 일반 사용자 계정 정보
                    if (_isLoggedIn && !_isAnonymous && _userInfo != null) ...[
                      _buildSectionTitle('계정 정보'),
                      SizedBox(height: 16.h),
                      _buildInfoItem('사용자 ID', _userInfo!.id),
                      SizedBox(height: 12.h),
                      if (_userInfo!.name != null) ...[
                        _buildInfoItem('이름', _userInfo!.name!),
                        SizedBox(height: 12.h),
                      ],
                      _buildInfoItem('이메일', _userInfo!.email),
                      SizedBox(height: 12.h),
                      _buildInfoItem('로그인 방식', _userInfo!.loginMethodDisplayName),
                      SizedBox(height: 32.h),
                    ],

                    // 키워드 알람 섹션
                    if (_isLoggedIn) ...[
                      _buildSectionTitle('키워드 알람'),
                      SizedBox(height: 16.h),
                      _buildKeywordAlertCard(),
                      SizedBox(height: 32.h),
                    ],

                    // 로그아웃 버튼
                    if (_isLoggedIn)
                      _buildLogoutButton(),
                  ],
                ),
              ),
            ),
    );
  }

  /// 프로필 카드
  Widget _buildProfileCard() {
    String title;
    String subtitle;

    if (!_isLoggedIn) {
      title = '로그인 필요';
      subtitle = '로그인하여 더 많은 기능을 이용하세요';
    } else if (_isAnonymous) {
      title = '익명 사용자';
      subtitle = _anonymousUserInfo != null
          ? '남은 시간: ${_anonymousUserInfo!.remainingTimeDisplay}'
          : '세션 정보를 불러오는 중...';
    } else {
      title = _userInfo?.name ?? _userInfo?.email ?? '로그인됨';
      subtitle = _userInfo?.email ?? '';
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: const Color(0xFFEDF1F3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 프로필 아이콘
          Container(
            width: 80.w,
            height: 80.w,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person,
              size: 40.sp,
              color: primaryColor,
            ),
          ),

          SizedBox(height: 16.h),

          // 사용자 상태
          Text(
            title,
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1C1E),
            ),
          ),

          SizedBox(height: 8.h),

          // 사용자 정보 또는 안내 메시지
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF6C7278),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 만료 경고
  Widget _buildExpiryWarning() {
    if (_anonymousUserInfo == null) return const SizedBox.shrink();

    final remainingHours = _anonymousUserInfo!.remainingHours;
    Color warningColor;
    IconData warningIcon;
    String warningText;

    if (remainingHours < 1) {
      warningColor = Colors.red;
      warningIcon = Icons.error;
      warningText = '세션이 곧 만료됩니다. 회원가입하여 데이터를 보존하세요.';
    } else if (remainingHours < 24) {
      warningColor = Colors.orange;
      warningIcon = Icons.warning;
      warningText = '세션 만료까지 ${_anonymousUserInfo!.remainingTimeDisplay} 남았습니다.';
    } else {
      warningColor = Colors.blue;
      warningIcon = Icons.info;
      warningText = '세션 만료까지 ${_anonymousUserInfo!.remainingTimeDisplay} 남았습니다.';
    }

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: warningColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: warningColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            warningIcon,
            size: 20.sp,
            color: warningColor,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              warningText,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: warningColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 키워드 알람 카드
  Widget _buildKeywordAlertCard() {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const KeywordAlertsScreen(),
          ),
        );
        // 돌아왔을 때 정보 새로고침
        _loadKeywordInfo();
      },
      child: Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: const Color(0xFFEDF1F3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // 아이콘
            Container(
              width: 48.w,
              height: 48.w,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                Icons.notifications_active,
                size: 24.sp,
                color: primaryColor,
              ),
            ),

            SizedBox(width: 16.w),

            // 텍스트 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '키워드 알람 관리',
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1C1E),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '등록 키워드 $_keywordCount개 · 읽지 않은 알람 $_unreadAlertCount개',
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF6C7278),
                    ),
                  ),
                ],
              ),
            ),

            // 화살표
            Icon(
              Icons.chevron_right,
              size: 24.sp,
              color: const Color(0xFF6C7278),
            ),
          ],
        ),
      ),
    );
  }

  /// 섹션 제목
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16.sp,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF1A1C1E),
      ),
    );
  }

  /// 정보 항목
  Widget _buildInfoItem(String label, String value) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6C7278),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1A1C1E),
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 로그아웃 버튼
  Widget _buildLogoutButton() {
    return Container(
      width: double.infinity,
      height: 48.h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(
          color: const Color(0xFFEFF0F6),
          width: 1,
        ),
      ),
      child: TextButton(
        onPressed: _handleLogout,
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.r),
          ),
        ),
        child: Text(
          '로그아웃',
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: Colors.red,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _authService.dispose();
    _keywordService.dispose();
    super.dispose();
  }
}
