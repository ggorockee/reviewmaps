import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mobile/services/keyword_service.dart';
import 'package:mobile/const/colors.dart';
import 'package:mobile/models/keyword_models.dart';
import 'package:mobile/screens/home_screen.dart'; // buildChannelIcons

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
  bool _isLoadingInProgress = false; // 중복 호출 방지
  List<KeywordInfo> _keywords = [];
  List<AlertInfo> _allAlerts = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadData();
  }

  void _onTabChanged() {
    // 탭 전환 시 UI 업데이트 (AppBar의 "모두 읽음" 버튼 표시 갱신)
    if (mounted) setState(() {});
  }

  /// 데이터 로드 (중복 호출 방지)
  Future<void> _loadData({bool showLoading = true}) async {
    // 이미 로딩 중이면 무시
    if (_isLoadingInProgress) {
      debugPrint('[KeywordAlertsScreen] 이미 로딩 중, 중복 요청 무시');
      return;
    }

    _isLoadingInProgress = true;

    if (showLoading) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // 병렬로 API 호출
      final results = await Future.wait([
        _keywordService.getMyKeywords(),
        _keywordService.getMyAlerts(),
      ]);

      if (!mounted) return;

      setState(() {
        _keywords = results[0] as List<KeywordInfo>;
        _allAlerts = (results[1] as AlertListResponse).alerts;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[KeywordAlertsScreen] 데이터 로드 실패: $e');
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showErrorDialog('데이터를 불러올 수 없습니다.\n잠시 후 다시 시도해 주세요.');
    } finally {
      _isLoadingInProgress = false;
      // mounted 상태일 때만 _isLoading을 확실하게 false로 설정
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 키워드 추가
  Future<void> _addKeyword() async {
    final controller = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
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
              style: TextStyle(color: primaryColor),
            ),
          ),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      try {
        final newKeyword = await _keywordService.registerKeyword(controller.text.trim());
        if (!mounted) return;

        // UI 즉시 업데이트 (전체 리로드 없이)
        setState(() {
          _keywords.insert(0, newKeyword);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('키워드가 등록되었습니다.')),
        );
      } catch (e) {
        if (mounted) {
          // "Exception: " 접두어 제거하여 사용자 친화적 메시지 표시
          final errorMessage = e.toString().replaceFirst('Exception: ', '');
          _showErrorDialog(errorMessage);
        }
      }
    }
  }

  /// 키워드 삭제
  Future<void> _deleteKeyword(KeywordInfo keyword) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
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
        if (!mounted) return;

        // UI 즉시 업데이트 (전체 리로드 없이)
        setState(() {
          _keywords.removeWhere((k) => k.id == keyword.id);
          // 해당 키워드의 알림도 제거
          _allAlerts.removeWhere((a) => a.keyword == keyword.keyword);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('키워드가 삭제되었습니다.')),
        );
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
      if (!mounted) return;

      // UI 즉시 업데이트 (전체 리로드 없이)
      setState(() {
        for (int i = 0; i < _allAlerts.length; i++) {
          if (alertIds.contains(_allAlerts[i].id) && !_allAlerts[i].isRead) {
            _allAlerts[i] = _allAlerts[i].copyWithRead(true);
          }
        }
      });
    } catch (e) {
      debugPrint('[KeywordAlertsScreen] 알람 읽음 처리 실패: $e');
    }
  }

  /// 모든 알람 읽음 처리
  Future<void> _markAllAsRead() async {
    final unreadAlerts = _allAlerts.where((a) => !a.isRead).toList();
    if (unreadAlerts.isEmpty) return;

    final alertIds = unreadAlerts.map((a) => a.id).toList();

    try {
      await _keywordService.markAlertsAsRead(alertIds);
      if (!mounted) return;

      // UI 즉시 업데이트
      setState(() {
        for (int i = 0; i < _allAlerts.length; i++) {
          if (!_allAlerts[i].isRead) {
            _allAlerts[i] = _allAlerts[i].copyWithRead(true);
          }
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${alertIds.length}개의 알림을 읽음 처리했습니다.'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('[KeywordAlertsScreen] 모든 알람 읽음 처리 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('읽음 처리 실패: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 에러 다이얼로그 표시
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
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
    // 읽지 않은 알림 수 계산
    final unreadCount = _allAlerts.where((a) => !a.isRead).length;

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
        actions: [
          // 알람 탭에서만 "모두 읽음" 버튼 표시
          if (_tabController.index == 1 && unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: Text(
                '모두 읽음',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: primaryColor,
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: primaryColor,
          unselectedLabelColor: const Color(0xFF6C7278),
          indicatorColor: primaryColor,
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
              backgroundColor: primaryColor,
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
            SizedBox(height: 12.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.w),
              child: Text(
                '※ 키워드 등록 이후에 새로 등록된 캠페인에 대해서만 알림을 받습니다.',
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF9CA3AF),
                ),
                textAlign: TextAlign.center,
              ),
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
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(
              Icons.label,
              size: 20.sp,
              color: primaryColor,
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

  /// 알람 탭 - 검색 결과와 동일한 디자인
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

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      itemCount: _allAlerts.length,
      itemBuilder: (context, index) {
        final alert = _allAlerts[index];
        final bool showDivider = index > 0;

        return Dismissible(
          key: Key('alert_${alert.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: EdgeInsets.only(right: 20.w),
            color: Colors.red,
            child: Icon(
              Icons.delete,
              color: Colors.white,
              size: 24.sp,
            ),
          ),
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.white,
                title: const Text('알림 삭제'),
                content: const Text('이 알림을 삭제하시겠습니까?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('취소'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('삭제'),
                  ),
                ],
              ),
            ) ?? false;
          },
          onDismissed: (direction) {
            _deleteAlert(alert.id, index);
          },
          child: Container(
            constraints: BoxConstraints(minHeight: 80.h),
            decoration: showDivider
                ? BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300, width: 1),
                    ),
                  )
                : null,
            child: _buildAlertCard(alert),
          ),
        );
      },
    );
  }

  /// 알림 삭제
  Future<void> _deleteAlert(int alertId, int index) async {
    // 먼저 UI에서 제거 (이미 Dismissible에서 제거됨)
    final removedAlert = _allAlerts[index];
    setState(() {
      _allAlerts.removeAt(index);
    });

    try {
      await _keywordService.deleteAlert(alertId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('알림이 삭제되었습니다.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[KeywordAlertsScreen] 알림 삭제 실패: $e');
      // 삭제 실패 시 복원
      setState(() {
        _allAlerts.insert(index, removedAlert);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('삭제 실패: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 알람 카드 - 검색 결과와 동일한 디자인
  Widget _buildAlertCard(AlertInfo alert) {
    final bool isTablet = MediaQuery.of(context).size.shortestSide >= 600;

    return InkWell(
      onTap: () {
        if (!alert.isRead) {
          _markAlertsAsRead([alert.id]);
        }
        // 캠페인 링크 열기
        _openCampaignLink(alert.campaignContentLink);
      },
      child: Container(
        constraints: BoxConstraints(minHeight: 80.h),
        padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 0),
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
              _buildOfferRow(alert, isTablet),

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
    // 업체명 우선, 없으면 title 사용
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
        ],
      ),
    );
  }

  /// 두번째줄: 제공 내역
  Widget _buildOfferRow(AlertInfo alert, bool isTablet) {
    return Text(
      alert.campaignOffer!,
      style: TextStyle(
        fontSize: isTablet ? 13.sp : 11.sp,
        color: Colors.red[600],
        fontWeight: FontWeight.w500,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 세번째줄: D-day + 거리 + 키워드 매칭 (검색 결과 스타일)
  Widget _buildMetaRow(AlertInfo alert, bool isTablet) {
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);

    // DeadlineChips와 동일한 스타일 파라미터
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

        // 거리 칩 (검색 결과와 동일한 파란색 스타일)
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

        // 키워드 매칭 칩 (초록색)
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: adjustedHorizontalPadding,
            vertical: adjustedVerticalPadding,
          ),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(adjustedBorderRadius),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.label_outline,
                size: adjustedFontSize,
                color: primaryColor,
              ),
              SizedBox(width: 2.w),
              Text(
                alert.keyword,
                style: TextStyle(
                  fontSize: adjustedFontSize,
                  fontWeight: FontWeight.w500,
                  color: primaryColor,
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
    return primaryColor;
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
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _keywordService.dispose();
    super.dispose();
  }
}
