import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/services/keyword_service.dart';
import 'package:mobile/const/colors.dart';
import 'package:mobile/models/keyword_models.dart';

/// 키워드 알람 관리 화면
class KeywordAlertsScreen extends StatefulWidget {
  const KeywordAlertsScreen({super.key});

  @override
  State<KeywordAlertsScreen> createState() => _KeywordAlertsScreenState();
}

class _KeywordAlertsScreenState extends State<KeywordAlertsScreen>
    with SingleTickerProviderStateMixin {
  final KeywordService _keywordService = KeywordService();
  late TabController _tabController;

  bool _isLoading = true;
  List<KeywordInfo> _keywords = [];
  List<AlertInfo> _allAlerts = [];
  List<AlertInfo> _unreadAlerts = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  /// 데이터 로드
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final keywords = await _keywordService.getMyKeywords();
      final allAlertsResponse = await _keywordService.getMyAlerts();
      final unreadAlertsResponse =
          await _keywordService.getMyAlerts(isRead: false);

      setState(() {
        _keywords = keywords;
        _allAlerts = allAlertsResponse.alerts;
        _unreadAlerts = unreadAlertsResponse.alerts;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[KeywordAlertsScreen] 데이터 로드 실패: $e');
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        _showErrorDialog('데이터를 불러올 수 없습니다.\n잠시 후 다시 시도해 주세요.');
      }
    }
  }

  /// 키워드 추가
  Future<void> _addKeyword() async {
    final controller = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('키워드 등록'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '키워드를 입력하세요',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.of(context).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              '등록',
              style: TextStyle(color: PRIMARY_COLOR),
            ),
          ),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      try {
        await _keywordService.registerKeyword(controller.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('키워드가 등록되었습니다.')),
          );
        }
        _loadData();
      } catch (e) {
        if (mounted) {
          _showErrorDialog('키워드를 등록할 수 없습니다.\n잠시 후 다시 시도해 주세요.');
        }
      }
    }
  }

  /// 키워드 삭제
  Future<void> _deleteKeyword(KeywordInfo keyword) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('키워드 삭제'),
        content: Text('\'${keyword.keyword}\' 키워드를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              '삭제',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _keywordService.deleteKeyword(keyword.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('키워드가 삭제되었습니다.')),
          );
        }
        _loadData();
      } catch (e) {
        if (mounted) {
          _showErrorDialog('키워드를 삭제할 수 없습니다.\n잠시 후 다시 시도해 주세요.');
        }
      }
    }
  }

  /// 알람 읽음 처리
  Future<void> _markAlertsAsRead(List<int> alertIds) async {
    try {
      await _keywordService.markAlertsAsRead(alertIds);
      _loadData();
    } catch (e) {
      debugPrint('[KeywordAlertsScreen] 알람 읽음 처리 실패: $e');
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '키워드 알람',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1C1E),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1A1C1E)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: PRIMARY_COLOR,
          unselectedLabelColor: const Color(0xFF6C7278),
          indicatorColor: PRIMARY_COLOR,
          tabs: const [
            Tab(text: '등록 키워드'),
            Tab(text: '알람'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildKeywordsTab(),
                _buildAlertsTab(),
              ],
            ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: _addKeyword,
              backgroundColor: PRIMARY_COLOR,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  /// 키워드 탭
  Widget _buildKeywordsTab() {
    if (_keywords.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64.sp,
              color: const Color(0xFF6C7278),
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
              '관심 키워드를 등록하면\n새로운 체험단이 등록될 때 알려드립니다',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF6C7278),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(16.w),
      itemCount: _keywords.length,
      separatorBuilder: (context, index) => SizedBox(height: 12.h),
      itemBuilder: (context, index) {
        final keyword = _keywords[index];
        return _buildKeywordCard(keyword);
      },
    );
  }

  /// 키워드 카드
  Widget _buildKeywordCard(KeywordInfo keyword) {
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
          // 키워드 아이콘
          Container(
            width: 40.w,
            height: 40.w,
            decoration: BoxDecoration(
              color: PRIMARY_COLOR.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(
              Icons.label,
              size: 20.sp,
              color: PRIMARY_COLOR,
            ),
          ),

          SizedBox(width: 12.w),

          // 키워드 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  keyword.keyword,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1C1E),
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  _formatDate(keyword.createdAt),
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF6C7278),
                  ),
                ),
              ],
            ),
          ),

          // 삭제 버튼
          IconButton(
            onPressed: () => _deleteKeyword(keyword),
            icon: const Icon(Icons.delete_outline),
            color: Colors.red,
            iconSize: 20.sp,
          ),
        ],
      ),
    );
  }

  /// 알람 탭
  Widget _buildAlertsTab() {
    if (_allAlerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none,
              size: 64.sp,
              color: const Color(0xFF6C7278),
            ),
            SizedBox(height: 16.h),
            Text(
              '알람이 없습니다',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF6C7278),
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              '등록한 키워드와 일치하는 체험단이 있으면\n알림을 보내드립니다',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF6C7278),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(16.w),
      itemCount: _allAlerts.length,
      separatorBuilder: (context, index) => SizedBox(height: 12.h),
      itemBuilder: (context, index) {
        final alert = _allAlerts[index];
        return _buildAlertCard(alert);
      },
    );
  }

  /// 알람 카드
  Widget _buildAlertCard(AlertInfo alert) {
    return GestureDetector(
      onTap: () {
        if (!alert.isRead) {
          _markAlertsAsRead([alert.id]);
        }
        // TODO: 캠페인 상세 화면으로 이동
      },
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: alert.isRead ? Colors.white : PRIMARY_COLOR.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: alert.isRead
                ? const Color(0xFFEDF1F3)
                : PRIMARY_COLOR.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                // 키워드 뱃지
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: PRIMARY_COLOR.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                  child: Text(
                    alert.keyword,
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: PRIMARY_COLOR,
                    ),
                  ),
                ),
                const Spacer(),
                // 읽음 상태
                if (!alert.isRead)
                  Container(
                    width: 8.w,
                    height: 8.w,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),

            SizedBox(height: 12.h),

            // 캠페인 제목
            Text(
              alert.campaignTitle,
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1C1E),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            SizedBox(height: 8.h),

            // 날짜
            Text(
              _formatDate(alert.createdAt),
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF6C7278),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 날짜 포맷
  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 7) {
        return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
      } else if (difference.inDays > 0) {
        return '${difference.inDays}일 전';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}시간 전';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}분 전';
      } else {
        return '방금 전';
      }
    } catch (e) {
      return dateString;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _keywordService.dispose();
    super.dispose();
  }
}
