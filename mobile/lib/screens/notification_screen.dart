import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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

  // 임시 데이터 (향후 API 연동 시 제거)
  final List<KeywordItem> _keywords = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  /// 키워드 추가
  void _addKeyword() {
    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('키워드를 입력해 주세요'),
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'X',
            textColor: Colors.white,
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
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'X',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
      return;
    }

    setState(() {
      _keywords.add(KeywordItem(
        keyword: keyword,
        isActive: true,
        createdAt: DateTime.now(),
      ));
      _keywordController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("'$keyword' 키워드가 추가되었습니다"),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: 'X',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  /// 키워드 삭제
  void _removeKeyword(int index) {
    final keyword = _keywords[index].keyword;
    setState(() {
      _keywords.removeAt(index);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("'$keyword' 키워드가 삭제되었습니다"),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'X',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  /// 키워드 알림 토글
  void _toggleKeyword(int index) {
    setState(() {
      _keywords[index].isActive = !_keywords[index].isActive;
    });

    final keyword = _keywords[index].keyword;
    final isActive = _keywords[index].isActive;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("'$keyword' 알림이 ${isActive ? '활성화' : '비활성화'}되었습니다"),
        duration: const Duration(seconds: 2),
        backgroundColor: isActive ? Colors.green : Colors.orange,
        action: SnackBarAction(
          label: 'X',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
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
            onPressed: () {
              // TODO: 새로고침 기능
            },
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
                onPressed: _addKeyword,
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
                child: Text(
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
          if (_keywords.isEmpty)
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
  Widget _buildKeywordCard(KeywordItem item, int index) {
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

/// 키워드 아이템 모델
class KeywordItem {
  final String keyword;
  bool isActive;
  final DateTime createdAt;

  KeywordItem({
    required this.keyword,
    required this.isActive,
    required this.createdAt,
  });
}
