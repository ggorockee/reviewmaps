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
  List<KeywordInfo> _keywords = [];
  List<AlertInfo> _allAlerts = [];

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

      setState(() {
        _keywords = keywords;
        _allAlerts = allAlertsResponse.alerts;
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

        return Container(
          constraints: BoxConstraints(minHeight: 80.h),
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
    );
  }

  /// 알람 카드 - 검색 결과와 동일한 디자인
  Widget _buildAlertCard(AlertInfo alert) {
    final bool isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    final platform = alert.campaignPlatform ?? '체험단';

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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 플랫폼 로고
            _buildPlatformLogo(platform),
            SizedBox(width: 16.w),

            // 텍스트 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 첫째줄: 플랫폼 뱃지 + 업체명 + 채널 아이콘 + NEW
                  _buildTitleRow(alert, isTablet),

                  SizedBox(height: 4.h),

                  // 두번째줄: 제공 내역 (빨간색)
                  if (alert.campaignOffer != null && alert.campaignOffer!.isNotEmpty)
                    _buildOfferRow(alert, isTablet),

                  SizedBox(height: 8.h),

                  // 세번째줄: D-day + 거리 + 키워드 매칭 표시
                  _buildMetaRow(alert, isTablet),
                ],
              ),
            ),

            // 읽지 않은 알림 표시
            if (!alert.isRead)
              Container(
                width: 8.w,
                height: 8.w,
                margin: EdgeInsets.only(left: 8.w),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 플랫폼 로고
  Widget _buildPlatformLogo(String platform) {
    final String logoAssetPath = _getLogoPathForPlatform(platform);

    return Container(
      width: 48.w,
      height: 48.h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.r),
        color: Colors.white,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.r),
        child: Image.asset(
          logoAssetPath,
          width: 48.w,
          height: 48.h,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Container(
            width: 48.w,
            height: 48.h,
            color: Colors.white,
            child: Icon(
              Icons.image_not_supported,
              color: Colors.grey[400],
              size: 20.sp,
            ),
          ),
        ),
      ),
    );
  }

  /// 첫째줄: 플랫폼 뱃지 + 업체명 + 채널 아이콘 + NEW
  Widget _buildTitleRow(AlertInfo alert, bool isTablet) {
    final platform = alert.campaignPlatform ?? '체험단';
    // 업체명 우선, 없으면 title 사용
    final title = alert.campaignCompany?.isNotEmpty == true
        ? alert.campaignCompany!
        : alert.campaignTitle;
    final isNew = _isNewAlert(alert.createdAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 플랫폼 뱃지
        Container(
          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
          decoration: BoxDecoration(
            color: platformBadgeColor(platform),
            borderRadius: BorderRadius.circular(4.r),
          ),
          child: Text(
            platform,
            style: TextStyle(
              fontSize: isTablet ? 8.sp : 8.5.sp,
              color: Colors.white,
              fontWeight: FontWeight.bold,
              height: 1.0,
            ),
          ),
        ),
        SizedBox(height: 4.h),
        // 업체명 + 채널 아이콘 + NEW
        RichText(
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            children: [
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
        ),
      ],
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

  /// 세번째줄: D-day + 거리 + 키워드 매칭
  Widget _buildMetaRow(AlertInfo alert, bool isTablet) {
    return Row(
      children: [
        // D-day
        if (alert.dDayText.isNotEmpty) ...[
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
            decoration: BoxDecoration(
              color: _getDDayColor(alert.dDay).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4.r),
            ),
            child: Text(
              alert.dDayText,
              style: TextStyle(
                fontSize: isTablet ? 11.sp : 10.sp,
                fontWeight: FontWeight.w600,
                color: _getDDayColor(alert.dDay),
              ),
            ),
          ),
          SizedBox(width: 8.w),
        ],

        // 거리
        if (alert.distanceText.isNotEmpty) ...[
          Icon(
            Icons.location_on_outlined,
            size: 14.sp,
            color: Colors.grey[600],
          ),
          SizedBox(width: 2.w),
          Text(
            alert.distanceText,
            style: TextStyle(
              fontSize: isTablet ? 12.sp : 11.sp,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(width: 8.w),
        ],

        // 매칭 키워드
        Expanded(
          child: Row(
            children: [
              Icon(
                Icons.label_outline,
                size: 14.sp,
                color: PRIMARY_COLOR,
              ),
              SizedBox(width: 2.w),
              Flexible(
                child: Text(
                  alert.keyword,
                  style: TextStyle(
                    fontSize: isTablet ? 11.sp : 10.sp,
                    color: PRIMARY_COLOR,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
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

  /// 플랫폼별 로고 경로
  String _getLogoPathForPlatform(String platform) {
    final Map<String, String> logoMap = {
      '스토리앤미디어': 'asset/image/logo/storymedia.png',
      '링블': 'asset/image/logo/ringble.png',
      '캐시노트': 'asset/image/logo/cashnote.png',
      '놀러와': 'asset/image/logo/noleowa.png',
      '체허미': 'asset/image/logo/chehumi.png',
      '링뷰': 'asset/image/logo/ringvue.png',
      '미블': 'asset/image/logo/mrble.png',
      '강남맛집': 'asset/image/logo/gannam.png',
      '가보자': 'asset/image/logo/gaboja.png',
      '레뷰': 'asset/image/logo/revu.png',
      '포블로그': 'asset/image/logo/4blog2.png',
      '포포몬': 'asset/image/logo/popomon.png',
      '리뷰노트': 'asset/image/logo/reviewnote.png',
      '리뷰플레이스': 'asset/image/logo/reviewplace.png',
      '디너의여왕': 'asset/image/logo/dinnerqueen.png',
      '체험뷰': 'asset/image/logo/chehumview.png',
      '아싸뷰': 'asset/image/logo/assaview.png',
      '체리뷰': 'asset/image/logo/cherryview.png',
      '오마이블로그': 'asset/image/logo/ohmyblog.png',
      '구구다스': 'asset/image/logo/gugudas.png',
      '티블': 'asset/image/logo/tble.png',
      '디노단': 'asset/image/logo/dinodan.png',
      '데일리뷰': 'asset/image/logo/dailiview.png',
      '똑똑체험단': 'asset/image/logo/ddokddok.png',
      '리뷰메이커': 'asset/image/logo/reviewmaker.png',
      '리뷰어랩': 'asset/image/logo/reviewerlab.png',
      '리뷰어스': 'asset/image/logo/reviewus.png',
      '리뷰웨이브': 'asset/image/logo/reviewwave.png',
      '리뷰윙': 'asset/image/logo/reviewwing.png',
      '리뷰퀸': 'asset/image/logo/reviewqueen.png',
      '리얼리뷰': 'asset/image/logo/realreview.png',
      '마녀체험단': 'asset/image/logo/witch_review.png',
      '모두의블로그': 'asset/image/logo/moble.png',
      '모두의체험단': 'asset/image/logo/modan.png',
      '뷰티의여왕': 'asset/image/logo/beauti_queen.png',
      '블로그원정대': 'asset/image/logo/review_one.png',
      '서울오빠': 'asset/image/logo/seoulobba.png',
      '서포터즈픽': 'asset/image/logo/supporterzpick.png',
      '샐러뷰': 'asset/image/logo/celuvu.png',
      '시원뷰': 'asset/image/logo/coolvue.png',
      '와이리': 'asset/image/logo/waili.png',
      '이음체험단': 'asset/image/logo/iumchehum.png',
      '츄블': 'asset/image/logo/chuble.png',
      '클라우드리뷰': 'asset/image/logo/cloudreview.png',
      '키플랫체험단': 'asset/image/logo/keyplat.png',
      '택배의여왕': 'asset/image/logo/taebae_queen.png',
      '파블로체험단': 'asset/image/logo/pablochehum.png',
      '후기업': 'asset/image/logo/whogiup.png',
      '플레이체험단': 'asset/image/logo/playchehum.png',
    };

    return logoMap[platform] ?? 'asset/image/logo/default_log.png';
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
