import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/keyword_service.dart';
import '../models/keyword_models.dart';
import '../const/colors.dart';
import 'home_screen.dart'; // buildChannelIcons, platformBadgeColor

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

    // 서버에서 키워드 제한 검증 (AppSetting 기반으로 동적 관리)

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

      // 서버 에러 메시지 사용 (키워드 제한 초과 등)
      _showSnackBar('$e', isError: true);
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

      // 토글 성공 시 토스트 메시지 제거 (사용자 요청)
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
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            itemCount: _alerts.length,
            itemBuilder: (context, index) {
              final alert = _alerts[index];
              final bool showDivider = index > 0;

              return Container(
                decoration: showDivider
                    ? BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade300, width: 1),
                        ),
                      )
                    : null,
                child: _buildAlertCard(alert),
              );
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

  /// 알림 카드 - 검색 결과와 동일한 디자인
  Widget _buildAlertCard(AlertInfo alert) {
    final bool isTablet = MediaQuery.of(context).size.shortestSide >= 600;

    return InkWell(
      onTap: () {
        _markAlertAsRead(alert);
        _openCampaignLink(alert.campaignContentLink);
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 첫째줄: 플랫폼 뱃지
            _buildPlatformBadge(alert, isTablet),

            SizedBox(height: 4.h),

            // 둘째줄: 업체명 + 채널 아이콘 + NEW
            _buildTitleRow(alert, isTablet),

            SizedBox(height: 4.h),

            // 셋째줄: 제공 내역 (빨간색)
            if (alert.campaignOffer != null && alert.campaignOffer!.isNotEmpty)
              Text(
                alert.campaignOffer!,
                style: TextStyle(
                  fontSize: isTablet ? 13.sp : 11.sp,
                  color: Colors.red[600],
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

            SizedBox(height: 8.h),

            // 넷째줄: D-day + 거리 + 키워드 매칭 표시
            _buildMetaRow(alert, isTablet),
          ],
        ),
      ),
    );
  }

  /// 플랫폼 뱃지
  Widget _buildPlatformBadge(AlertInfo alert, bool isTablet) {
    final platform = alert.campaignPlatform ?? '체험단';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: platformBadgeColor(platform),
        borderRadius: BorderRadius.circular(4.r),
      ),
      child: Text(
        platform,
        style: TextStyle(
          fontSize: isTablet ? 10.sp : 10.sp,
          color: Colors.white,
          fontWeight: FontWeight.bold,
          height: 1.0,
        ),
      ),
    );
  }

  /// 업체명 + 채널 아이콘 + NEW (한 줄에 표시)
  Widget _buildTitleRow(AlertInfo alert, bool isTablet) {
    final title = alert.campaignCompany?.isNotEmpty == true
        ? alert.campaignCompany!
        : alert.campaignTitle;
    final isNew = _isNewAlert(alert.createdAt);

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          // 업체명
          TextSpan(
            text: title,
            style: TextStyle(
              fontSize: isTablet ? 16.sp : 14.sp,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              height: 1.3,
            ),
          ),
          // 채널 아이콘
          if (alert.campaignChannel != null && alert.campaignChannel!.isNotEmpty) ...[
            WidgetSpan(
              child: Padding(
                padding: EdgeInsets.only(left: 4.w),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: buildChannelIcons(alert.campaignChannel),
                ),
              ),
            ),
          ],
          // NEW 뱃지
          if (isNew) ...[
            WidgetSpan(
              child: Padding(
                padding: EdgeInsets.only(left: 4.w),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    'NEW',
                    style: TextStyle(
                      fontSize: isTablet ? 11.sp : 9.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                ),
              ),
            ),
          ],
          // 읽지 않은 표시
          if (!alert.isRead) ...[
            WidgetSpan(
              child: Padding(
                padding: EdgeInsets.only(left: 6.w),
                child: Container(
                  width: 8.w,
                  height: 8.w,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// D-day + 거리 + 키워드 매칭 (검색 결과 스타일)
  Widget _buildMetaRow(AlertInfo alert, bool isTablet) {
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);

    final double baseHorizontalPadding = isTablet ? 16.0 : 8.0;
    final double baseVerticalPadding = isTablet ? 8.0 : 3.0;
    final double baseFontSize = isTablet ? 16.0 : 12.0;
    final double baseBorderRadius = isTablet ? 20.0 : 12.0;

    final adjustedHorizontalPadding = (baseHorizontalPadding * textScaleFactor.clamp(0.8, 1.4)).w;
    final adjustedVerticalPadding = (baseVerticalPadding * textScaleFactor.clamp(0.8, 1.4)).h;
    final adjustedFontSize = (baseFontSize * textScaleFactor.clamp(0.8, 1.4));
    final adjustedBorderRadius = (baseBorderRadius * textScaleFactor.clamp(0.8, 1.4)).r;

    return Wrap(
      spacing: isTablet ? 6.w : 4.w,
      runSpacing: isTablet ? 6.h : 4.h,
      children: [
        // D-day 칩
        if (alert.dDayText.isNotEmpty)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: adjustedHorizontalPadding,
              vertical: adjustedVerticalPadding,
            ),
            decoration: BoxDecoration(
              color: _getDDayColor(alert.dDay).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(adjustedBorderRadius),
              border: Border.all(
                color: _getDDayColor(alert.dDay).withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Text(
              alert.dDayText,
              style: TextStyle(
                fontSize: adjustedFontSize,
                fontWeight: FontWeight.w500,
                color: _getDDayColor(alert.dDay),
                height: 1.2,
              ),
            ),
          ),

        // 거리 칩
        if (alert.distanceText.isNotEmpty)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: adjustedHorizontalPadding,
              vertical: adjustedVerticalPadding,
            ),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(adjustedBorderRadius),
              border: Border.all(
                color: Colors.blue.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Text(
              alert.distanceText,
              style: TextStyle(
                fontSize: adjustedFontSize,
                fontWeight: FontWeight.w500,
                color: Colors.blue[700],
                height: 1.2,
              ),
            ),
          ),

        // 키워드 매칭 칩
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: adjustedHorizontalPadding,
            vertical: adjustedVerticalPadding,
          ),
          decoration: BoxDecoration(
            color: PRIMARY_COLOR.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(adjustedBorderRadius),
            border: Border.all(
              color: PRIMARY_COLOR.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.label_outline,
                size: adjustedFontSize,
                color: PRIMARY_COLOR,
              ),
              SizedBox(width: 2.w),
              Text(
                alert.keyword,
                style: TextStyle(
                  fontSize: adjustedFontSize,
                  fontWeight: FontWeight.w500,
                  color: PRIMARY_COLOR,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 캠페인 링크 열기
  Future<void> _openCampaignLink(String? link) async {
    if (link == null || link.isEmpty) return;

    final uri = Uri.parse(link);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// 새 알림 여부 (24시간 이내)
  bool _isNewAlert(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      return now.difference(date).inHours < 24;
    } catch (e) {
      return false;
    }
  }

  /// D-day 색상
  Color _getDDayColor(int? dDay) {
    if (dDay == null) return Colors.grey;
    if (dDay < 0) return Colors.grey;
    if (dDay <= 3) return Colors.red;
    if (dDay <= 7) return Colors.orange;
    return PRIMARY_COLOR;
  }
}
