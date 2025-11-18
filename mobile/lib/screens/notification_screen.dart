import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/keyword_service.dart';
import '../models/keyword_models.dart';

/// 체험단 알림 화면
/// - 2개 탭: 키워드 관리, 알림 기록
/// - 키워드 추가/삭제, 알림 활성화/비활성화 기능
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _keywordController = TextEditingController();
  final KeywordService _keywordService = KeywordService();

  List<KeywordInfo> _keywords = [];
  bool _isLoading = false;
  bool _isInitialLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadKeywords();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _keywordController.dispose();
    _keywordService.dispose();
    super.dispose();
  }

  /// 키워드 목록 로드
  Future<void> _loadKeywords() async {
    if (!mounted) return;

    setState(() {
      _isInitialLoading = true;
    });

    try {
      final keywords = await _keywordService.getMyKeywords();
      if (!mounted) return;

      setState(() {
        _keywords = keywords;
        _isInitialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isInitialLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('키워드 목록을 불러올 수 없습니다: $e'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '닫기',
            textColor: Colors.white70,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    }
  }

  /// 키워드 추가
  Future<void> _addKeyword() async {
    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('키워드를 입력해 주세요'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '닫기',
            textColor: Colors.white70,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
      return;
    }

    if (_keywords.length >= 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('키워드는 최대 20개까지 등록할 수 있습니다'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '닫기',
            textColor: Colors.white70,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final newKeyword = await _keywordService.registerKeyword(keyword);
      if (!mounted) return;

      setState(() {
        _keywords.add(newKeyword);
        _keywordController.clear();
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("'$keyword' 키워드가 추가되었습니다"),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '닫기',
            textColor: Colors.white70,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('키워드 추가 실패: $e'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '닫기',
            textColor: Colors.white70,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    }
  }

  /// 키워드 삭제
  Future<void> _removeKeyword(int index) async {
    final keywordInfo = _keywords[index];
    final keyword = keywordInfo.keyword;

    setState(() {
      _isLoading = true;
    });

    try {
      await _keywordService.deleteKeyword(keywordInfo.id);
      if (!mounted) return;

      setState(() {
        _keywords.removeAt(index);
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("'$keyword' 키워드가 삭제되었습니다"),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '닫기',
            textColor: Colors.white70,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('키워드 삭제 실패: $e'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '닫기',
            textColor: Colors.white70,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    }
  }

  /// 키워드 알림 토글
  void _toggleKeyword(int index) {
    final old = _keywords[index];
    final newIsActive = !old.isActive;

    setState(() {
      // KeywordInfo는 final 필드라서 새 객체를 생성하여 교체
      _keywords[index] = KeywordInfo(
        id: old.id,
        keyword: old.keyword,
        isActive: newIsActive,
        createdAt: old.createdAt,
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("'${old.keyword}' 알림이 ${newIsActive ? '활성화' : '비활성화'}되었습니다"),
        duration: const Duration(seconds: 2),
        backgroundColor: newIsActive ? Colors.green : Colors.orange,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '닫기',
          textColor: Colors.white70,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );

    // TODO: API 연동 시 추가
    // try {
    //   await _keywordService.toggleKeyword(old.id, newIsActive);
    // } catch (e) {
    //   // 실패 시 롤백
    //   setState(() {
    //     _keywords[index] = old;
    //   });
    // }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('체험단 알림'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadKeywords,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: const Color(0xFF6C7278),
          indicatorColor: Theme.of(context).primaryColor,
          labelStyle: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
          ),
          tabs: [
            Tab(
              icon: const Icon(Icons.notifications_outlined),
              text: '키워드 관리 (${_keywords.length}/20)',
            ),
            const Tab(
              icon: Icon(Icons.history),
              text: '알림 기록 (0)',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildKeywordManagementTab(),
          _buildNotificationHistoryTab(),
        ],
      ),
    );
  }

  /// 키워드 관리 탭
  Widget _buildKeywordManagementTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 키워드 추가 섹션
          Row(
            children: [
              Icon(
                Icons.notifications,
                size: 20.sp,
                color: Theme.of(context).primaryColor,
              ),
              SizedBox(width: 8.w),
              Text(
                '키워드 추가',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A1C1E),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),

          // 입력 필드 + 추가 버튼
          Row(
            children: [
              Expanded(
                child: Container(
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
                    controller: _keywordController,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1A1C1E),
                    ),
                    decoration: InputDecoration(
                      hintText: '예: 아이폰, 갤럭시, 노트북',
                      hintStyle: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF9CA3AF),
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14.w,
                        vertical: 13.h,
                      ),
                    ),
                    onSubmitted: (_) => _addKeyword(),
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              ElevatedButton(
                onPressed: _isLoading ? null : _addKeyword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: 20.w,
                    vertical: 13.h,
                  ),
                  minimumSize: Size(0, 46.h),
                ),
                child: _isLoading
                    ? SizedBox(
                        width: 20.w,
                        height: 20.h,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        '추가',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ],
          ),

          SizedBox(height: 4.h),

          // 글자 수 카운터
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${_keywordController.text.length}/20',
              style: TextStyle(
                fontSize: 12.sp,
                color: const Color(0xFF9CA3AF),
              ),
            ),
          ),

          SizedBox(height: 12.h),

          // 안내 문구
          Text(
            '관심있는 상품의 키워드를 등록하면 관련 체험단이 올라올 때 알림을 받을 수 있습니다.',
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF6C7278),
              height: 1.5,
            ),
          ),

          SizedBox(height: 24.h),

          // 키워드 리스트
          if (_isInitialLoading)
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40.h),
                child: CircularProgressIndicator(
                  color: Theme.of(context).primaryColor,
                ),
              ),
            )
          else if (_keywords.isEmpty)
            _buildEmptyState()
          else
            ..._keywords.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: _buildKeywordCard(item, index),
              );
            }),
        ],
      ),
    );
  }

  /// 키워드 카드
  Widget _buildKeywordCard(KeywordInfo item, int index) {
    return Container(
      padding: EdgeInsets.all(16.w),
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
          // 키워드명
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 12.w,
              vertical: 6.h,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFEBF5FF),
              borderRadius: BorderRadius.circular(6.r),
            ),
            child: Text(
              item.keyword,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),

          SizedBox(width: 12.w),

          // 상태 배지
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 8.w,
              vertical: 4.h,
            ),
            decoration: BoxDecoration(
              color: item.isActive
                  ? const Color(0xFFE6F7ED)
                  : const Color(0xFFFFF3E6),
              borderRadius: BorderRadius.circular(4.r),
            ),
            child: Text(
              item.isActive ? '활성' : '비활성',
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
                color: item.isActive
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF59E0B),
              ),
            ),
          ),

          const Spacer(),

          // 토글 스위치 (iOS 스타일로 일관된 크기 유지)
          Transform.scale(
            scale: 0.8,
            child: CupertinoSwitch(
              value: item.isActive,
              onChanged: (_) => _toggleKeyword(index),
              activeTrackColor: Theme.of(context).primaryColor,
            ),
          ),

          SizedBox(width: 12.w),

          // 삭제 버튼
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: Colors.red,
              size: 20.sp,
            ),
            onPressed: () => _removeKeyword(index),
          ),
        ],
      ),
    );
  }

  /// 빈 상태 UI
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: 40.h),
          Icon(
            Icons.notifications_none,
            size: 64.sp,
            color: const Color(0xFFD1D5DB),
          ),
          SizedBox(height: 16.h),
          Text(
            '등록된 키워드가 없습니다',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6C7278),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '관심있는 상품의 키워드를 추가해보세요!\n새로운 체험단이 등록되면 알림을 보내드립니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF9CA3AF),
              height: 1.5,
            ),
          ),
          SizedBox(height: 40.h),
        ],
      ),
    );
  }

  /// 알림 기록 탭
  Widget _buildNotificationHistoryTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 64.sp,
            color: const Color(0xFFD1D5DB),
          ),
          SizedBox(height: 16.h),
          Text(
            '받은 알림이 없습니다',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6C7278),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            '키워드를 등록하고 관련 체험단 알림을 받아보세요!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF9CA3AF),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
