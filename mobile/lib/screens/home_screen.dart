// home_screen.dart
//
// 홈 탭: 추천/가까운 체험단 피드 + 공지 배너 + 무한 스크롤
// 배포 기준으로 불필요한 로그/미사용 코드 제거, 주석 강화

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:mobile/config/config.dart';
import 'package:mobile/screens/search_screen.dart';
import 'package:mobile/services/campaign_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../const/colors.dart';
import '../models/store_model.dart';
import '../widgets/friendly.dart'; // ← ClampTextScale, showFriendlySnack 여기서 사용
import 'campaign_list_screen.dart';

/// 외부 링크 열기 유틸
/// - http/https 누락 시 https로 보정
/// - 외부 브라우저 우선, 실패 시 인앱 시도
/// - 배포: 로그 제거(조용히 실패)
Future<void> openLink(String raw) async {
  try {
    String s = raw.trim();
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    final uri = Uri.parse(Uri.encodeFull(s));
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri);
    }
  } catch (_) {
    // no-op: 필요 시 상위에서 스낵바 처리
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// 홈 화면 상태
/// - 추천 피드: 무한 스크롤(페이지네이션은 클라이언트 셔플 + 서버 페이징 혼합)
/// - 가까운 체험단: 권한→현재위치→근처 API
/// - 공지 배너: SharedPreferences로 노출 여부 저장
class _HomeScreenState extends State<HomeScreen> {
  // ---------------------------
  // Services & Controllers
  // ---------------------------
  final CampaignService _campaignService = CampaignService(
    AppConfig.ReviewMapbaseUrl,
    apiKey: AppConfig.ReviewMapApiKey,
  );
  final ScrollController _mainScrollController = ScrollController();

  // ---------------------------
  // State
  // ---------------------------
  Future<List<Store>>? _nearestCampaigns; // 근처 체험단 Future (권한/위치 OK 후 세팅)
  Position? _currentPosition;
  // _HomeScreenState 안에 헬퍼 하나 추가
  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;

  // 사용자 설정
  bool _autoShowNearest = false; // 앱 진입 시 자동으로 근처 보여줄지
  bool _showNoticeBanner = true; // 공지 배너 노출 여부

  // 내부 플래그
  bool _isRequestingPermission = false; // 버튼 연타 방지
  bool _permAskedOnce = false;          // 한 세션당 권한 요청 1회
  bool _serviceSettingsOpened = false;  // OS 설정 화면 1회만

  // 추천 피드 페이징 상태
  List<Store> _shuffledCampaigns = [];
  List<Store> _visibleCampaigns = [];
  bool _isLoading = false;
  int _currentPage = 0;
  final int _pageSize = 10;
  final int _apiLimit = 50; // 서버 한 번에 가져오는 개수
  int _apiOffset = 0;

  // SharedPreferences Keys
  static const _kAutoNearestKey = 'auto_show_nearest';
  static const _kFirstRunKey = 'first_run_done';
  static const _kNoticeKey = 'hide_review_policy_notice'; // ← 누락돼 있던 키 추가

  @override
  void initState() {
    super.initState();
    _initialize();
    _mainScrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _mainScrollController.removeListener(_onScroll);
    _mainScrollController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // 초기화: 사용자 설정 복원 → (옵션) 근처 로딩 → 추천 피드 로딩
  // ------------------------------------------------------------
  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final firstRunDone = prefs.getBool(_kFirstRunKey) ?? false;

    await _restorePrefs();

    if (!firstRunDone) {
      // 첫 실행에서는 강제로 자동 근처 OFF
      _autoShowNearest = false;
      await prefs.setBool(_kFirstRunKey, true);
    } else if (_autoShowNearest) {
      // 사용자가 이전에 허용해둔 경우에만 자동 실행
      _updateNearestCampaigns(); // ← 여기서 권한 팝업이 뜸(사용자 선택 반영)
    }

    await _loadRecommendedCampaigns();
  }

  Future<void> _restorePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _showNoticeBanner = !(prefs.getBool(_kNoticeKey) ?? false);
      _autoShowNearest = prefs.getBool(_kAutoNearestKey) ?? false;
    });
  }

  // 당겨서 새로고침: 추천+근처(옵션) 동시 갱신
  Future<void> _handleRefresh() async {
    final futures = <Future>[
      _loadRecommendedCampaigns(),
      if (_autoShowNearest) _refreshNearestCampaigns(),
    ];
    await Future.wait(futures);
  }

  // 근처 데이터만 새로고침
  Future<void> _refreshNearestCampaigns() async {
    await _updateNearestCampaigns();
  }

  // ------------------------------------------------------------
  // 권한/위치
  // ------------------------------------------------------------
  /// 위치 권한과 서비스 상태를 점검하고 필요 시 1회 요청/유도
  Future<void> _ensureLocationPermissionOnce() async {
    // 위치 서비스(기기 GPS) 꺼짐
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!_serviceSettingsOpened && mounted) {
        _serviceSettingsOpened = true;
        showFriendlySnack(
          context,
          '위치 서비스를 켜주세요.',
          actionLabel: '설정 열기',
          onAction: () => Geolocator.openLocationSettings(),
        );
      }
      throw Exception('위치 서비스를 켜주세요.');
    }

    // 권한 확인/요청
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied && !_permAskedOnce) {
      _permAskedOnce = true;
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.denied) {
      throw Exception('위치 권한을 허용해주세요.');
    }
    if (perm == LocationPermission.deniedForever) {
      if (mounted) {
        showFriendlySnack(
          context,
          '앗, 권한이 영구 거부되어 있어요.',
          actionLabel: '설정 열기',
          onAction: () => Geolocator.openAppSettings(),
        );
      }
      throw Exception('앱 설정에서 위치 권한을 허용해주세요.');
    }
  }

  // ------------------------------------------------------------
  // 데이터 로딩(추천)
  // ------------------------------------------------------------
  Future<void> _loadRecommendedCampaigns() async {
    setState(() {
      _isLoading = true;
      _visibleCampaigns = [];
      _shuffledCampaigns = [];
      _currentPage = 0;
      _apiOffset = 0;
    });
    try {
      final firstBatch = await _campaignService.fetchPage(
        limit: _apiLimit,
        offset: _apiOffset,
        sort: '-created_at',
      );
      if (!mounted) return;

      _apiOffset += firstBatch.length;
      firstBatch.shuffle();             // 노출 다양화
      _shuffledCampaigns = firstBatch;  // 로컬 큐로 축적

      final firstPage = _getNextPage();
      setState(() {
        _visibleCampaigns = firstPage;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showFriendlySnack(context, '추천 체험단을 불러오는데 실패했습니다.');
    }
  }

  // 추천: 스크롤 끝 근처에서 다음 페이지 공급(로컬 큐 → 부족하면 서버 추가 페치)
  void _onScroll() {
    if (!_isLoading && _mainScrollController.position.extentAfter < 400) {
      _loadMoreCampaigns();
    }
  }

  Future<void> _loadMoreCampaigns() async {
    if (_isLoading) return;

    // 1) 로컬 큐에서 먼저 꺼내 보여준다
    final localNext = _getNextPage();
    if (localNext.isNotEmpty) {
      setState(() => _visibleCampaigns.addAll(localNext));
      return;
    }

    // 2) 로컬 큐 고갈 시 서버에서 보충
    setState(() => _isLoading = true);
    try {
      final batch = await _campaignService.fetchPage(
        limit: _apiLimit,
        offset: _apiOffset,
        sort: '-created_at',
      );
      if (!mounted) return;

      _apiOffset += batch.length;
      batch.shuffle();
      _shuffledCampaigns.addAll(batch);

      final refill = _getNextPage();
      setState(() {
        _visibleCampaigns.addAll(refill);
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 추천: 로컬 큐에서 다음 페이지 슬라이스
  List<Store> _getNextPage() {
    final startIndex = _currentPage * _pageSize;
    if (startIndex >= _shuffledCampaigns.length) return [];
    final endIndex = math.min(startIndex + _pageSize, _shuffledCampaigns.length); // ← 타입 안전
    _currentPage++;
    return _shuffledCampaigns.getRange(startIndex, endIndex).toList();
  }

  // ------------------------------------------------------------
  // 데이터 로딩(근처)
  // ------------------------------------------------------------
  Future<List<Store>> _fetchNearestCampaigns(Position position) async {
    try {
      return _campaignService.fetchNearest(
        lat: position.latitude,
        lng: position.longitude,
        limit: 10,
      );
    } catch (_) {
      throw Exception('가까운 체험단 정보를 불러오지 못했습니다.');
    }
  }

  /// 근처 섹션 업데이트 파이프라인
  /// - 권한체크 → 현재위치 → 근처 API → FutureBuilder에 바인딩
  Future<void> _updateNearestCampaigns() async {
    try {
      await _ensureLocationPermissionOnce();

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      final future = _fetchNearestCampaigns(position);
      setState(() {
        _currentPosition = position;
        _nearestCampaigns = future;
      });

      // 여기서 await하여 오류를 화면/스낵바로 뿌릴 수 있게 함
      await future;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _nearestCampaigns = Future.error(e);
      });
      showFriendlySnack(
        context,
        e.toString().replaceFirst('Exception: ', '앗, '),
        actionLabel: '설정 열기',
        onAction: () => Geolocator.openAppSettings(),
      );
    }
  }

  /// 근처 섹션 버튼 눌렀을 때:
  /// - 권한 파이프라인 실행 + 자동노출 설정 저장
  Future<void> _requestAndLoadNearest() async {
    if (_isRequestingPermission) return;
    _isRequestingPermission = true;
    try {
      await _updateNearestCampaigns();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAutoNearestKey, true);
      if (mounted) setState(() => _autoShowNearest = true);
    } finally {
      _isRequestingPermission = false;
    }
  }

  // ------------------------------------------------------------
  // Build
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final bool isTab = _isTablet(context);
    // 태블릿은 접근성 스케일 상한을 더 낮게(레이아웃 안정)
    final double maxScale = isTab ? 1.10 : 1.30;

    return ClampTextScale(
      max: maxScale,
      child: Scaffold(
        appBar: AppBar(
          title: Padding(
            padding: EdgeInsets.only(top: 24.h), // [ScreenUtil]
            child: const Text('리뷰맵', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          // 디자인 정렬 유지용 placeholder 아이콘(오른쪽 여백 균형)
          actions: [
            Opacity(opacity: 0, child: Icon(Icons.notifications_none)),
            // Opacity(opacity: 0, child: Icon(Icons.notifications_none)),
            Padding(
              padding: EdgeInsets.only(top: 12.h, right: 12), // [ScreenUtil]
              child: IconButton(
                  icon: Icon(Icons.search),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SearchScreen()),
                    );
                  },
                tooltip: '검색',
              ),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _handleRefresh,
          child: CustomScrollView(
            controller: _mainScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 공지 배너
              SliverToBoxAdapter(child: _buildNoticeBanner()),
              SliverToBoxAdapter(child: SizedBox(height: 20.h)), // [ScreenUtil]

              // 가까운 체험단
              SliverToBoxAdapter(child: _buildNearestCampaignsSection()),
              SliverToBoxAdapter(child: SizedBox(height: 50.h)), // [ScreenUtil]

              // 추천 헤더
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w), // [ScreenUtil]
                  child: _buildRecommendedHeader(context),
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: 12.h)),

              // 추천 그리드
              if (_isLoading && _visibleCampaigns.isEmpty)
                const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 0.1.w,  // [ScreenUtil]
                      mainAxisSpacing: 0.1.w,   // [ScreenUtil]
                      childAspectRatio: _gridAspectRatioRecommended(context),
                    ),
                    delegate: SliverChildBuilderDelegate(
                          (context, index) {
                        final gridLineColor = Colors.grey.shade300;
                        final bool isLeftColumn = index % 2 == 0;
                        final int totalRows = (_visibleCampaigns.length / 2).ceil();
                        final int currentRow = (index / 2).floor();
                        final bool isLastRow = currentRow == totalRows - 1;

                        final border = Border(
                          right: isLeftColumn
                              ? BorderSide(color: gridLineColor, width: 0.7.w)
                              : BorderSide.none,
                          bottom: !isLastRow
                              ? BorderSide(color: gridLineColor, width: 0.7.w)
                              : BorderSide.none,
                        );

                        return Container(
                          key: ValueKey(_visibleCampaigns[index].id), // id는 non-null
                          decoration: BoxDecoration(border: border),
                          child: ExperienceCard(
                            store: _visibleCampaigns[index],
                            dense: true,
                          ),
                        );
                      },
                      childCount: _visibleCampaigns.length,
                    ),
                  ),
                ),

              // 하단 로딩 인디케이터
              if (_isLoading && _visibleCampaigns.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              SliverToBoxAdapter(child: SizedBox(height: 24.h)),
            ],
          ),
        ),
      ),
    );
  }

  // 추천 헤더(더보기)
  Widget _buildRecommendedHeader(BuildContext context) {
    final bool isTab = _isTablet(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('추천 체험단',
            style: TextStyle(fontSize: isTab ? 14.sp : 18.sp, fontWeight: FontWeight.bold)),
        GestureDetector(
          onTap: () {
            final listForNext = _shuffledCampaigns.isNotEmpty
                ? _shuffledCampaigns.toList()
                : _visibleCampaigns.toList();
            if (listForNext.isEmpty) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CampaignListScreen(
                  title: '추천 체험단',
                  initialStores: listForNext,
                ),
              ),
            );
          },
          child: Row(
            children: [
              Text('더보기',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13.sp)),
              SizedBox(width: 2.w),
              Icon(Icons.arrow_forward_ios, size: 12.sp, color: Colors.grey),
              SizedBox(width: 8.w),
            ],
          ),
        ),
      ],
    );
  }

  // 공지 배너
  Widget _buildNoticeBanner() {
    if (!_showNoticeBanner) return const SizedBox.shrink();
    return Container(
      margin: EdgeInsets.all(16.w),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: Colors.blue[100],
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.campaign, color: Colors.blue),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              '리뷰 정책이 새롭게 변경되었습니다.',
              style:
              TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.blue),
            splashRadius: 18.r,
            onPressed: _dismissNotice,
            tooltip: '닫기',
          ),
        ],
      ),
    );
  }

  // 가까운 체험단 섹션(권한 안내 → 로딩 → 목록/없음)
  Widget _buildNearestCampaignsSection() {
    final bool isTab = _isTablet(context);
    return Padding(
      padding: EdgeInsets.only(left: 16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타이틀 + 더보기
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('가까운 체험단',
                  style: TextStyle(
                    fontSize: isTab ? 14.sp : 18.sp,
                    fontWeight: FontWeight.bold,
                  )),
              GestureDetector(
                onTap: () async {
                  final data = await _nearestCampaigns;
                  if (!mounted || data == null || _currentPosition == null) {
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ClampTextScale(
                        child: CampaignListScreen(
                          title: '가까운 체험단',
                          initialStores: data.toList(),
                          userPosition: _currentPosition!,
                        ),
                      ),
                    ),
                  );
                },
                child: Row(
                  children: [
                    Text('더보기',
                        style:
                        TextStyle(color: Colors.grey[600], fontSize: 13.sp)),
                    SizedBox(width: 2.w),
                    Icon(Icons.arrow_forward_ios, size: 12.sp, color: Colors.grey),
                    SizedBox(width: 8.w),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),

          // 콘텐츠
          FutureBuilder<List<Store>>(
            future: _nearestCampaigns,
            builder: (context, snapshot) {
              // 1) 아직 요청 전(권한 버튼 노출)
              if (_nearestCampaigns == null) {
                return Container(
                  height: 150.h,
                  margin: EdgeInsets.only(right: 16.w),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.place, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '내 주변 체험단을 보여드릴게요!\n아래 버튼을 눌러 위치 권한을 허용해 주세요 😊',
                          style: TextStyle(
                            color: Colors.blue[900],
                            fontSize: isTab ? 11.sp : 11.sp, // ← 태블릿에서 크게
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _requestAndLoadNearest,
                        child: Text('보여주기',
                          style: TextStyle(
                            fontSize: isTab ? 11.sp : 11.sp, // ← 태블릿에서 크게
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              // 2) 로딩 중
              if (snapshot.connectionState == ConnectionState.waiting) {
                return SizedBox(
                  height: 150.h,
                  child: const Center(child: CircularProgressIndicator()),
                );
              }

              // 3) 에러
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Text(
                      snapshot.error.toString().replaceFirst('Exception: ', ''),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              // 4) 데이터 없음
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Container(
                  margin: const EdgeInsets.only(right: 16.0),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      '현재 위치 주변에 진행중인 체험단이 없습니다.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                );
              }

              // 5) 정상 데이터
              final stores = snapshot.data!.take(10).toList();
              return SizedBox(
                height: _nearestRowHeight(context),
                child: RepaintBoundary(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.only(right: 8.w),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: stores
                          .map(
                            (store) => Padding(
                          padding: EdgeInsets.only(right: 8.w),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12.r),
                            child: ExperienceCard(
                              key: ValueKey(store.id), // id는 non-null
                              store: store,
                              width: 150.w,
                              compact: false,
                            ),
                          ),
                        ),
                      )
                          .toList(),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // 공지 닫기: 사용자 설정 저장
  Future<void> _dismissNotice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNoticeKey, true);
    if (mounted) setState(() => _showNoticeBanner = false);
  }

  // 근처 가로 카드 영역의 동적 높이(텍스트 스케일 반영)
  double _nearestRowHeight(BuildContext context) {
    final bool isTab = _isTablet(context);

    // ClampTextScale로 이미 상한을 묶었으니 “현재” 스케일을 그대로 신뢰
    final double ts = MediaQuery.textScalerOf(context).textScaleFactor;

    // 보간 민감도(분모) — 태블릿은 더 완만하게
    final double denom = isTab ? (1.10 - 1.00) : (1.30 - 1.00);
    final double t = denom == 0 ? 0 : ((ts - 1.0) / denom).clamp(0.0, 1.0);

    // 높이 범위 — 태블릿은 더 낮고 촘촘하게
    final double minH = isTab ? 190.h : 128.h;
    final double maxH = isTab ? 160.h : 180.h;

    return ui.lerpDouble(minH, maxH, t)!;
  }

  // 추천 그리드: childAspectRatio 계산
  double _gridAspectRatioRecommended(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontalPadding = 16.w * 2;
    final crossSpacing = 0.1.w;
    final cellW = (width - horizontalPadding - crossSpacing) / 2;
    final cellH = _recommendedCellHeight(context);
    return cellW / cellH;
  }

  // 추천 그리드: 텍스트 스케일에 따른 셀 높이 보간
  double _recommendedCellHeight(BuildContext context) {
    final bool isTab = _isTablet(context);
    final double ts = MediaQuery.textScalerOf(context).textScaleFactor;

    final double denom = isTab ? (1.10 - 1.00) : (1.30 - 1.00);
    final double t = denom == 0 ? 0 : ((ts - 1.0) / denom).clamp(0.0, 1.0);

    final double minH = isTab ? 175.h : 145.h;
    final double maxH = isTab ? 170.h : 190.h;

    return ui.lerpDouble(minH, maxH, t)!;
  }
}

// ========================
// 카드/메타 UI
// ========================

class ExperienceCard extends StatelessWidget {
  final Store store;
  final double? width;
  final bool dense;
  final bool compact;

  const ExperienceCard({
    super.key,
    required this.store,
    this.width,
    this.dense = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final platformColor = platformBadgeColor(store.platform);

    final bool isTab = MediaQuery.of(context).size.shortestSide >= 600;


    // [ScreenUtil] 여백 프리셋
    final double pad = dense ? 10.w : 12.w;
    final double gapBadgeBody = dense ? 3.h : 4.h;
    final double gapTitleOffer = dense ? 3.h : 4.h;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: (store.companyLink ?? '').isEmpty
            ? null
            : () => openLink(store.companyLink!),
        child: SizedBox(
          width: width,
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단 그룹: 플랫폼 뱃지 + 회사명 + 제공내역
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 플랫폼 뱃지
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
                      decoration: BoxDecoration(
                        color: platformColor,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      child: Text(
                        store.platform,
                        style: TextStyle(
                          fontSize: isTab ? 8.sp : 11.sp,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          height: 1.0,
                        ),
                      ),
                    ),
                    SizedBox(height: gapBadgeBody),

                    // 업체명
                    Text(
                      store.company,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: isTab ? 12.5.sp :13.5.sp,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: gapTitleOffer),

                    // 제공내역(있을 때)
                    if ((store.offer ?? '').isNotEmpty)
                      Text(
                        store.offer!,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isTab ? 9.5.sp :10.5.sp,
                          color: Colors.red,
                          height: 1.2,
                        ),
                      ),
                  ],
                ),

                // 하단 메타(마감일/거리)
                const Spacer(),
                Padding(
                  padding: EdgeInsets.only(bottom: 1.h),
                  child: _MetaAdaptiveLine(
                    deadline: store.applyDeadline,
                    distance: store.distance,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaAdaptiveLine extends StatelessWidget {

  final DateTime? deadline;
  final double? distance;

  const _MetaAdaptiveLine({required this.deadline, this.distance});

  @override
  Widget build(BuildContext context) {
    final bool isTab = MediaQuery.of(context).size.shortestSide >= 600;

    final style = TextStyle(
      fontSize: isTab ? 10.5.sp: 11.5.sp,
      height: 1.3,
      color: Colors.grey[600],
    );
    final dateStr = (deadline != null) ? '~${DateFormat('MM.dd').format(deadline!)}' : null;
    final distStr = (distance != null) ? '${distance!.toStringAsFixed(1)}km' : null;

    if (dateStr == null && distStr == null) return const SizedBox.shrink();

    Widget buildInfoRow(IconData icon, String text) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              icon,
              size: isTab ? 10.5.sp: 12.sp,
              color: Colors.grey[600],
          ),
          SizedBox(width: 4.w),
          Text(text, style: style),
        ],
      );
    }

    if (distStr == null) return buildInfoRow(Icons.calendar_today_outlined, dateStr!);
    if (dateStr == null) return buildInfoRow(Icons.near_me_outlined, distStr);

    return Wrap(
      spacing: 8.w,
      runSpacing: 2.h,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        buildInfoRow(Icons.calendar_today_outlined, dateStr),
        buildInfoRow(Icons.near_me_outlined, distStr),
      ],
    );
  }
}

// (선택) 권한 안내 위젯 – 현재 화면에서는 미사용, 필요 시 재활용
class _PermissionHelp extends StatelessWidget {
  final String message;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;
  const _PermissionHelp({
    required this.message,
    required this.onRequest,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.place, size: 48, color: Colors.blue),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                ElevatedButton(onPressed: onRequest, child: const Text('권한 요청')),
                OutlinedButton(onPressed: onOpenSettings, child: const Text('설정 열기')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
