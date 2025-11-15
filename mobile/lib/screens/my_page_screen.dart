import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/const/colors.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/models/auth_models.dart';

/// 내정보 화면
class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  bool _isLoggedIn = false;
  bool _isAnonymous = false;
  UserInfo? _userInfo;

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
        _isLoading = false;
      });

      // 로그인되어 있으면 사용자 정보 가져오기
      if (isLoggedIn) {
        try {
          final userInfo = await _authService.getUserInfo();
          setState(() {
            _userInfo = userInfo;
          });
        } catch (e) {
          debugPrint('[MyPageScreen] 사용자 정보 조회 실패: $e');
        }
      }
    } catch (e) {
      debugPrint('[MyPageScreen] 로그인 상태 확인 실패: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 로그아웃 처리
  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃 하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              '로그아웃',
              style: TextStyle(color: PRIMARY_COLOR),
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
            content: const Text('로그아웃에 실패했습니다.\n잠시 후 다시 시도해 주세요.'),
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

                    // 계정 정보
                    if (_isLoggedIn && _userInfo != null) ...[
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
                      _buildInfoItem(
                        '계정 유형',
                        _userInfo!.isAnonymous ? '익명 사용자' : '일반 사용자'
                      ),
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
              color: PRIMARY_COLOR.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person,
              size: 40.sp,
              color: PRIMARY_COLOR,
            ),
          ),

          SizedBox(height: 16.h),

          // 사용자 상태
          Text(
            _isLoggedIn
                ? (_isAnonymous ? '익명 사용자' : '로그인됨')
                : '로그인 필요',
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1C1E),
            ),
          ),

          SizedBox(height: 8.h),

          // 사용자 정보 또는 안내 메시지
          Text(
            _isLoggedIn
                ? (_userInfo != null
                    ? (_userInfo!.name ?? _userInfo!.email)
                    : '정보를 불러오는 중...')
                : '로그인하여 더 많은 기능을 이용하세요',
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
          Text(
            value,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1A1C1E),
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
    super.dispose();
  }
}
