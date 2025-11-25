import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import '../services/keyword_service.dart';
import '../models/keyword_models.dart';

/// 체험단 알림 화면
/// - 2개 탭: 키워드 관리, 알림 기록
/// - 키워드 추가/삭제, 알림 활성화/비활성화 기능
/// - 위치 기반 거리순 정렬 지원
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
  List<AlertInfo> _alerts = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  bool _isInitialLoading = true;
  bool _isAlertsLoading = true;
  bool _isRefreshing = false;

  // 위치 정보
  double? _userLat;
  double? _userLng;
  String _sortType = 'distance'; // 기본 정렬: 거리순

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadKeywords();
    _getUserLocation();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _keywordController.dispose();
    _keywordService.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && _alerts.isEmpty && !_isAlertsLoading) {
      _loadAlerts();
    }
  }

  /// 사용자 위치 가져오기
  Future<void> _getUserLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        // 위치 권한이 없으면 기본값 사용 (서울 시청)
        _userLat = 37.5666805;
        _userLng = 126.9784147;
        _loadAlerts();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );

      if (mounted) {
        setState(() {
          _userLat = position.latitude;
          _userLng = position.longitude;
        });
        _loadAlerts();
      }
    } catch (e) {
      debugPrint('위치 가져오기 실패: $e');
      // 기본값 사용
      _userLat = 37.5666805;
      _userLng = 126.9784147;
      _loadAlerts();
    }
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

      _showSnackBar('키워드 목록을 불러올 수 없습니다', isError: true);
    }
  }

  /// 알림 목록 로드
  Future<void> _loadAlerts() async {
    if (!mounted) return;

    setState(() {
      _isAlertsLoading = true;
    });

    try {
      final response = await _keywordService.getMyAlerts(
        lat: _userLat,
        lng: _userLng,
        sort: _sortType,
      );

      if (!mounted) return;

      setState(() {
        _alerts = response.alerts;
        _unreadCount = response.unreadCount;
        _isAlertsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isAlertsLoading = false;
      });

      debugPrint('알림 목록 로드 실패: $e');
    }
  }

  /// 새로고침 (비동기)
  Future<void> _onRefresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      if (_tabController.index == 0) {
        await _loadKeywords();
      } else {
        await _loadAlerts();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  /// 키워드 추가
  Future<void> _addKeyword() async {
    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty) {
      _showSnackBar('키워드를 입력해 주세요');
      return;
    }

    if (_keywords.length >= 20) {
      _showSnackBar('키워드는 최대 20개까지 등록할 수 있습니다');
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

      _showSnackBar("'$keyword' 키워드가 추가되었습니다", isSuccess: true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnackBar('키워드 추가 실패: $e', isError: true);
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

      _showSnackBar("'$keyword' 키워드가 삭제되었습니다");
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnackBar('키워드 삭제 실패: $e', isError: true);
    }
  }

  /// 키워드 알림 토글 (API 연동)
  Future<void> _toggleKeyword(int index) async {
    final old = _keywords[index];

    // 낙관적 업데이트
    setState(() {
      _keywords[index] = KeywordInfo(
        id: old.id,
        keyword: old.keyword,
        isActive: !old.isActive,
        createdAt: old.createdAt,
      );
    });

    try {
      final updated = await _keywordService.toggleKeyword(old.id);
      if (!mounted) return;

      setState(() {
        _keywords[index] = updated;
      });

      final statusText = updated.isActive ? '활성화' : '비활성화';
      _showSnackBar(
        "'${old.keyword}' 알림이 $statusText되었습니다",
        isSuccess: updated.isActive,
      );
    } catch (e) {
      if (!mounted) return;

      // 실패 시 롤백
      setState(() {
        _keywords[index] = old;
      });

      _showSnackBar('상태 변경 실패: $e', isError: true);
    }
  }

  /// 알림 읽음 처리
  Future<void> _markAlertAsRead(AlertInfo alert) async {
    if (alert.isRead) return;

    try {
      await _keywordService.markAlertsAsRead([alert.id]);
      if (!mounted) return;

      setState(() {
        final index = _alerts.indexWhere((a) => a.id == alert.id);
        if (index != -1) {
          _alerts[index] = AlertInfo(
            id: alert.id,
            keyword: alert.keyword,
            campaignId: alert.campaignId,
            campaignTitle: alert.campaignTitle,
            campaignOffer: alert.campaignOffer,
            campaignAddress: alert.campaignAddress,
            campaignLat: alert.campaignLat,
            campaignLng: alert.campaignLng,
            campaignImgUrl: alert.campaignImgUrl,
            matchedField: alert.matchedField,
            isRead: true,
            createdAt: alert.createdAt,
            distance: alert.distance,
          );
          _unreadCount = _unreadCount > 0 ? _unreadCount - 1 : 0;
        }
      });
    } catch (e) {
      debugPrint('알림 읽음 처리 실패: $e');
    }
  }

  /// 정렬 방식 변경
  void _changeSortType(String sortType) {
    if (_sortType == sortType) return;

    setState(() {
      _sortType = sortType;
    });

    _loadAlerts();
  }

  /// 스낵바 표시
  void _showSnackBar(String message, {bool isError = false, bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: isError ? Colors.red : (isSuccess ? Colors.green : null),
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('체험단 알림'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          // 새로고침 버튼
          IconButton(
            icon: _isRefreshing
                ? SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).primaryColor,
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _onRefresh,
            tooltip: '새로고침',
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
            Tab(
              icon: Stack(
                children: [
                  const Icon(Icons.history),
                  if (_unreadCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: EdgeInsets.all(4.w),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: BoxConstraints(
                          minWidth: 14.w,
                          minHeight: 14.w,
                        ),
                        child: Text(
                          _unreadCount > 99 ? '99+' : '$_unreadCount',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8.sp,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              text: '알림 기록 (${_alerts.length})',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          RefreshIndicator(
            onRefresh: _loadKeywords,
            child: _buildKeywordManagementTab(),
          ),
          RefreshIndicator(
            onRefresh: _loadAlerts,
            child: _buildNotificationHistoryTab(),
          ),
        ],
      ),
    );
  }

  /// 키워드 관리 탭
  Widget _buildKeywordManagementTab() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
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
    if (_isAlertsLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).primaryColor,
        ),
      );
    }

    if (_alerts.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: Center(
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
          ),
        ),
      );
    }

    return Column(
      children: [
        // 정렬 옵션
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '정렬: ',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: const Color(0xFF6C7278),
                ),
              ),
              _buildSortChip('거리순', 'distance'),
              SizedBox(width: 8.w),
              _buildSortChip('최신순', 'created_at'),
            ],
          ),
        ),
        // 알림 목록
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.all(16.w),
            itemCount: _alerts.length,
            separatorBuilder: (context, index) => SizedBox(height: 12.h),
            itemBuilder: (context, index) {
              final alert = _alerts[index];
              return _buildAlertCard(alert);
            },
          ),
        ),
      ],
    );
  }

  /// 정렬 칩
  Widget _buildSortChip(String label, String sortType) {
    final isSelected = _sortType == sortType;
    return GestureDetector(
      onTap: () => _changeSortType(sortType),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).primaryColor
                : const Color(0xFFEDF1F3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF6C7278),
          ),
        ),
      ),
    );
  }

  /// 알림 카드
  Widget _buildAlertCard(AlertInfo alert) {
    return GestureDetector(
      onTap: () {
        _markAlertAsRead(alert);
        // TODO: 캠페인 상세 페이지로 이동
      },
      child: Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: alert.isRead ? Colors.white : const Color(0xFFF0F7FF),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: alert.isRead
                ? const Color(0xFFEDF1F3)
                : Theme.of(context).primaryColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 캠페인 이미지
            ClipRRect(
              borderRadius: BorderRadius.circular(8.r),
              child: alert.campaignImgUrl != null && alert.campaignImgUrl!.isNotEmpty
                  ? Image.network(
                      alert.campaignImgUrl!,
                      width: 60.w,
                      height: 60.w,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: 60.w,
                          height: 60.w,
                          color: const Color(0xFFEDF1F3),
                          child: Center(
                            child: SizedBox(
                              width: 20.w,
                              height: 20.w,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: const Color(0xFF9CA3AF),
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 60.w,
                        height: 60.w,
                        color: const Color(0xFFEDF1F3),
                        child: Icon(
                          Icons.image_not_supported,
                          color: const Color(0xFF9CA3AF),
                          size: 24.sp,
                        ),
                      ),
                    )
                  : Container(
                      width: 60.w,
                      height: 60.w,
                      color: const Color(0xFFEDF1F3),
                      child: Icon(
                        Icons.campaign,
                        color: const Color(0xFF9CA3AF),
                        size: 24.sp,
                      ),
                    ),
            ),
            SizedBox(width: 12.w),
            // 알림 내용
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 키워드 뱃지 + 읽음 상태
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.w,
                          vertical: 2.h,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                        child: Text(
                          alert.keyword,
                          style: TextStyle(
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                      const Spacer(),
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
                  SizedBox(height: 4.h),
                  // 캠페인 제목
                  Text(
                    alert.campaignTitle,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1C1E),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4.h),
                  // 주소 및 거리
                  if (alert.campaignAddress != null)
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 12.sp,
                          color: const Color(0xFF9CA3AF),
                        ),
                        SizedBox(width: 4.w),
                        Expanded(
                          child: Text(
                            alert.campaignAddress!,
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: const Color(0xFF6C7278),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (alert.distance != null) ...[
                          SizedBox(width: 8.w),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6.w,
                              vertical: 2.h,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6F7ED),
                              borderRadius: BorderRadius.circular(4.r),
                            ),
                            child: Text(
                              alert.distanceText,
                              style: TextStyle(
                                fontSize: 10.sp,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  SizedBox(height: 4.h),
                  // 날짜
                  Text(
                    _formatDate(alert.createdAt),
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
