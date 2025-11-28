// home_screen.dart
//
// 홈 탭: 추천/가까운 체험단 피드 + 공지 배너 + 무한 스크롤
// 배포 기준으로 불필요한 로그/미사용 코드 제거, 주석 강화

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile/screens/search_screen.dart';
import 'package:mobile/services/campaign_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ads/banner.dart';
import '../models/store_model.dart';
import '../widgets/experience_card.dart';
import '../widgets/friendly.dart'; // ← ClampTextScale, showFriendlySnack 여기서 사용
import '../widgets/native_ad_widget.dart'; // ← 네이티브 광고 위젯
import 'campaign_list_screen.dart';




List<Widget> buildChannelIcons(String? channelStr) {
  if (channelStr == null || channelStr.isEmpty) return [];

  final channels = channelStr.split(',').map((c) => c.trim()).toList();

  // 매핑 정의
  final Map<String, String> iconMap = {
    'blog': 'asset/icons/blog_logo.png',
    'youtube': 'asset/icons/youtube_logo.png',
    'instagram': 'asset/icons/instagram_logo.png',
    'clip': 'asset/icons/clip_logo.png',
    'blog_clip': 'asset/icons/clip_logo.png',
    'reels': 'asset/icons/reels_logo.png',
    // 'unknown': 'asset/icons/etc.png',
    // 'etc': 'asset/icons/etc.png',
  };


  return channels.where((ch) {
    return ch != 'etc' && ch != 'unknown';
  }).map((ch) {
    final path = iconMap[ch];
    if (path == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Image.asset(
        path,
        width: 16,
        height: 16,
        fit: BoxFit.contain,
      ),
    );
  }).toList();
}





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
  // Controllers
  // ---------------------------
  final ScrollController _mainScrollController = ScrollController();

  // ---------------------------
  // State
  // ---------------------------
  Future<List<Store>>? _nearestCampaigns; // 근처 체험단 Future (권한/위치 OK 후 세팅)
  Position? _currentPosition;
  // _HomeScreenState 안에 헬퍼 하나 추가
  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;

  T t<T>(BuildContext ctx, T phone, T tablet) => _isTablet(ctx) ? tablet : phone;


  // 사용자 설정
  bool _autoShowNearest = false; // 앱 진입 시 자동으로 근처 보여줄지
 // 공지 배너 노출 여부

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
  final int _apiLimit = 20; // 서버 한 번에 가져오는 개수 (50→20으로 축소)
  int _apiOffset = 0;

  // SharedPreferences Keys
  static const _kAutoNearestKey = 'auto_show_nearest';
  static const _kFirstRunKey = 'first_run_done';
 // ← 누락돼 있던 키 추가

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
  // 초기화: 캐시 우선 표시 → 병렬로 설정/데이터 로딩
  // ------------------------------------------------------------
  Future<void> _initialize() async {
    final stopwatch = Stopwatch()..start();

    // 1. 캐시된 데이터가 있으면 즉시 표시 (UI 블로킹 없음)
    final cachedData = CampaignCacheManager.instance.getCachedRecommended();
    if (cachedData != null && cachedData.isNotEmpty) {
      debugPrint('[HomeScreen] 캐시 히트 - 즉시 표시');
      _shuffledCampaigns = cachedData;
      final firstPage = _getNextPage();
      if (mounted) {
        setState(() {
          _visibleCampaigns = firstPage;
          _isLoading = false;
        });
      }
      // 비동기로 거리 계산
      _calculateDistancesForStoresAsync(cachedData);
    }

    // 2. 병렬로 설정 복원 및 추가 데이터 로딩
    await Future.wait([
      _restorePrefsAndCheckFirstRun(),
      // 캐시가 없을 때만 추천 캠페인 로드
      if (cachedData == null || cachedData.isEmpty) _loadRecommendedCampaigns(),
    ]);

    // 3. 자동 근처 표시 설정이 켜져있으면 로드 (비동기로 처리)
    if (_autoShowNearest) {
      _updateNearestCampaigns(); // 백그라운드에서 실행
    }

    stopwatch.stop();
    debugPrint('[HomeScreen] 초기화 완료: ${stopwatch.elapsedMilliseconds}ms');
  }

  /// 설정 복원 및 첫 실행 체크 (병렬 실행용)
  Future<void> _restorePrefsAndCheckFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    final firstRunDone = prefs.getBool(_kFirstRunKey) ?? false;

    if (!mounted) return;
    setState(() {
      _autoShowNearest = prefs.getBool(_kAutoNearestKey) ?? false;
    });

    if (!firstRunDone) {
      _autoShowNearest = false;
      await prefs.setBool(_kFirstRunKey, true);
    }
  }

  // 당겨서 새로고침: 캐시 무효화 후 추천+근처(옵션) 동시 갱신
  Future<void> _handleRefresh() async {
    // 캐시 무효화 (강제 새로고침)
    CampaignCacheManager.instance.invalidateAll();

    final futures = <Future>[
      _loadRecommendedCampaigns(forceRefresh: true),
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
  // 데이터 로딩(추천) - 캐시 매니저 기반 최적화
  // ------------------------------------------------------------
  Future<void> _loadRecommendedCampaigns({bool forceRefresh = false}) async {
    // 이미 로딩 중이면 스킵
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _visibleCampaigns = [];
      _shuffledCampaigns = [];
      _currentPage = 0;
      _apiOffset = 0;
    });

    try {
      // 캐시 매니저를 통해 데이터 로드 (캐시 히트 시 즉시 반환)
      final firstBatch = await CampaignCacheManager.instance.getRecommended(
        limit: _apiLimit,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;

      _apiOffset = firstBatch.length;

      // 거리 계산은 비동기로 나중에 수행 (UI 블로킹 방지)
      _calculateDistancesForStoresAsync(firstBatch);

      _shuffledCampaigns = firstBatch;

      final firstPage = _getNextPage();
      setState(() {
        _visibleCampaigns = firstPage;
        _isLoading = false;
      });

      debugPrint('[HomeScreen] 추천 캠페인 로드 완료: ${firstBatch.length}개');
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

    // 2) 로컬 큐 고갈 시 서버에서 보충 (캐시 매니저 사용)
    setState(() => _isLoading = true);
    try {
      final batch = await CampaignCacheManager.instance.fetchMoreRecommended(
        offset: _apiOffset,
        limit: _apiLimit,
      );
      if (!mounted) return;

      _apiOffset += batch.length;
      batch.shuffle();

      // 거리 계산은 비동기로 나중에 수행 (UI 블로킹 방지)
      _calculateDistancesForStoresAsync(batch);

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
  // 거리 계산 유틸리티
  // ------------------------------------------------------------

  /// 비동기 거리 계산 (UI 블로킹 없이 백그라운드에서 실행)
  /// 완료되면 setState로 UI 업데이트
  void _calculateDistancesForStoresAsync(List<Store> stores) {
    _calculateDistancesForStores(stores).then((_) {
      if (mounted) setState(() {}); // 거리 계산 완료 후 UI 갱신
    });
  }

  Future<void> _calculateDistancesForStores(List<Store> stores) async {
    try {
      // 위치 권한 확인
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
        return; // 권한이 없으면 거리 계산하지 않음
      }

      // 현재 위치 가져오기 (캐시된 위치 우선 사용)
      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {}

      // 캐시된 위치가 없으면 새로 가져오기
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium, // high→medium으로 변경 (속도 향상)
        ),
      ).timeout(const Duration(seconds: 3)); // 5초→3초로 단축

      // 각 스토어에 대해 거리 계산하고 리스트 업데이트
      for (int i = 0; i < stores.length; i++) {
        final store = stores[i];
        if (store.lat != null && store.lng != null) {
          final distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            store.lat!,
            store.lng!,
          ) / 1000; // km 단위로 변환

          // 새로운 Store 객체로 교체
          stores[i] = store.copyWith(distance: distance);
        }
      }
    } catch (_) {
      // 위치 정보를 가져올 수 없으면 거리 계산하지 않음
    }
  }
  Future<List<Store>> _fetchNearestCampaigns(Position position) async {
    try {
      // 캐시 매니저를 통해 가까운 캠페인 로드
      return CampaignCacheManager.instance.getNearest(
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
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
          toolbarHeight: t(context, 56.0.h, 64.0.h), // 폰/패드 높이만 조절
          title: Padding(
            padding: EdgeInsets.only(top: 12.h, left: isTab ? 10.w : 5.w),
            child: Text(
              '리뷰맵',
              style: TextStyle(
                fontSize: t(context, 22.0.sp, 18.0.sp),  // 태블릿에서 더 큼
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // 디자인 정렬 유지용 placeholder 아이콘(오른쪽 여백 균형)
          actions: [
            Opacity(opacity: 0, child: Icon(Icons.notifications_none)),
            // Opacity(opacity: 0, child: Icon(Icons.notifications_none)),
            Padding(
              padding: EdgeInsets.only(top: 12.h, right: isTab ? 10.w : 20.w),
              child: IconButton(
                  icon: Icon(Icons.search),
                iconSize: t(context, 24.0.h, 28.0.h),
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
              // SliverToBoxAdapter(child: _buildNoticeBanner()),
              SliverToBoxAdapter(child: MyBannerAdWidget()),
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

              // 추천 그리드 (네이티브 광고 포함)
              if (_isLoading && _visibleCampaigns.isEmpty)
                const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                ..._buildRecommendedGridWithAds(),

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
            if (_shuffledCampaigns.isEmpty && _visibleCampaigns.isEmpty) return;

            final listForNext = [
              ..._visibleCampaigns,
              ...(_shuffledCampaigns.isNotEmpty
                  ? _shuffledCampaigns.skip(_visibleCampaigns.length)
                  : const <Store>[]),
            ];
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
              Text('더보기', style: TextStyle(color: Colors.grey[600], fontSize: isTab ? 15.sp : 13.sp)),
              SizedBox(width: 2.w),
              Icon(Icons.arrow_forward_ios, size: 12.sp, color: Colors.grey),
              SizedBox(width: 8.w),
            ],
          ),
        ),
      ],
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
                        TextStyle(color: Colors.grey[600], fontSize: isTab ? 15.sp : 13.sp)),
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
                            fontSize: isTab ? 13.sp : 11.sp, // ← 태블릿에서 크게
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _requestAndLoadNearest,
                        child: Text('보여주기',
                          style: TextStyle(
                            fontSize: isTab ? 13.sp : 11.sp, // ← 태블릿에서 크게
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
                              width: _nearestItemWidth(context),
                              dense: true,
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

  double _nearestItemWidth(BuildContext context) {
    final ts = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.3);
    final t = ((ts - 1.0) / (1.3 - 1.0)).clamp(0.0, 1.0);
    return lerpDouble(150.w, 170.w, t)!; // 글자 커지면 카드 폭도 살짝 증가
  }

  // 공지 닫기: 사용자 설정 저장

  // 근처 가로 카드 영역의 동적 높이(텍스트 스케일 반영)
  double _nearestRowHeight(BuildContext context) {
    final bool isTab = _isTablet(context);
    final double ts = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.3);

    final double denom = isTab ? (1.10 - 1.00) : (1.30 - 1.00);
    final double t = denom == 0 ? 0 : ((ts - 1.0) / denom).clamp(0.0, 1.0);

    final double minH = isTab ? 190.h : 130.h; // 폰 기본 살짝 ↑
    final double maxH = isTab ? 230.h : 200.h; // 상한도 ↑
    return lerpDouble(minH, maxH, t)!;
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
    final double ts = MediaQuery.textScalerOf(context).scale(1.0);

    final double denom = isTab ? (1.10 - 1.00) : (1.30 - 1.00);
    final double t = denom == 0 ? 0 : ((ts - 1.0) / denom).clamp(0.0, 1.0);

    final double minH = isTab ? 175.h : 145.h;
    final double maxH = isTab ? 180.h : 190.h;

    return ui.lerpDouble(minH, maxH, t)!;
  }

  // 추천 그리드와 네이티브 광고를 조합하여 반환
  // 20개 체험단마다 네이티브 광고 1개 삽입
  List<Widget> _buildRecommendedGridWithAds() {
    final List<Widget> slivers = [];
    const int itemsPerGrid = 20; // 2열 그리드: 20개 아이템

    for (int i = 0; i < _visibleCampaigns.length; i += itemsPerGrid) {
      final int endIndex = math.min(i + itemsPerGrid, _visibleCampaigns.length);
      final List<Store> chunk = _visibleCampaigns.sublist(i, endIndex);

      // 체험단 그리드
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 0.1.w,
              mainAxisSpacing: 0.1.w,
              childAspectRatio: _gridAspectRatioRecommended(context),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final gridLineColor = Colors.grey.shade300;
                final bool isLeftColumn = index % 2 == 0;
                final int totalRows = (chunk.length / 2).ceil();
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
                  key: ValueKey(chunk[index].id),
                  decoration: BoxDecoration(border: border),
                  child: ExperienceCard(
                    store: chunk[index],
                    dense: true,
                  ),
                );
              },
              childCount: chunk.length,
            ),
          ),
        ),
      );

      // 20개마다 네이티브 광고 삽입 (마지막 청크는 제외)
      if (endIndex < _visibleCampaigns.length) {
        slivers.add(
          SliverToBoxAdapter(
            child: Column(
              children: [
                SizedBox(height: 16.h),
                const NativeAdListItem(),
                SizedBox(height: 16.h),
              ],
            ),
          ),
        );
      }
    }

    return slivers;
  }
}


