import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:mobile/services/campaign_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:developer' as dev;

import '../const/colors.dart';
import '../models/store_model.dart';
import 'campaign_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final CampaignService _campaignService = CampaignService(
      'https://api.review-maps.com/v1',
      apiKey: '9e53ccafd6e993152e01e9e7a8ca66d1c2224bb5b21c78cf076f6e45dcbc0d12'
  );

  final ScrollController _mainScrollController = ScrollController();

  // 상태 변수 재구성
  Future<List<Store>>? _nearestCampaigns;
  Position? _currentPosition;


  List<Store> _shuffledCampaigns = [];
  List<Store> _visibleCampaigns = [];
  bool _isLoading = false;
  int _currentPage = 0;
  final int _pageSize = 10;
  final int _apiLimit = 50;
  int _apiOffset = 0;          // ← 추가
  int? _apiTotal;              // ← 선택(있으면 정확한 hasMore 판단)

  bool _showNoticeBanner = true; // 기본은 보이기
  static const _kNoticeKey = 'hide_review_policy_notice';

  Future<void> _restoreNoticePref() async {
    final prefs = await SharedPreferences.getInstance();
    final hidden = prefs.getBool(_kNoticeKey) ?? false;
    if (mounted) setState(() => _showNoticeBanner = !hidden);
  }

  Future<void> _dismissNotice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNoticeKey, true);
    if (mounted) setState(() => _showNoticeBanner = false);
  }

  @override
  void initState() {
    super.initState();
    _restoreNoticePref();
    _loadCampaigns(); // 초기 데이터 로드

    _mainScrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _mainScrollController.dispose(); // [수정] 주석 해제
    super.dispose();
  }

  Future<bool> openLink(String raw) async {
    try {
      String s = raw.trim();
      if (!s.startsWith('http://') && !s.startsWith('https://')) {
        s = 'https://$s';
      }
      final uri = Uri.parse(Uri.encodeFull(s));

      // 외부 브라우저 우선
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return true;

      // 실패 시 인앱(Chrome Custom Tabs) 폴백
      return await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (e) {
      print('[openLink][ERR] $e (raw="$raw")');
      return false;
    }
  }


  Future<void> _loadCampaigns() async {
    // 1. 로딩 상태 시작
    setState(() {
      _isLoading = true;
      _nearestCampaigns = _fetchNearestCampaigns();
      _visibleCampaigns = [];
      _shuffledCampaigns = [];
      _currentPage = 0;
      _apiOffset = 0;        // ← 추가
      _apiTotal = null;      // ← 추가
    });

    final firstBatch = await _campaignService.fetchPage(
      limit: _apiLimit,
      offset: _apiOffset,
      sort: '-created_at',
    );

    if (!mounted) return;

    if (firstBatch.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    // 서버가 total을 응답에 주지만, 현재 Service가 total을 안 돌려준다면
    // hasMore 판단은 "마지막 페이지인지"로만 하되, 정확도를 높이려면
    // 아래 “서비스 개선(선택)” 참고
    _apiOffset += firstBatch.length;    // ← offset 누적

    firstBatch.shuffle();
    _shuffledCampaigns = firstBatch;

    final firstPage = _getNextPage();
    setState(() {
      _visibleCampaigns = firstPage;
      _isLoading = false;
    });
  }

  Future<List<Store>> _fetchLatestCampaigns() async {
    final stores = await _campaignService.fetchPage(limit: 200);
    stores.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return stores;
  }

  // 👇 [수정됨] 위치 서비스 확인과 권한 요청 로직을 통합하고 강화했습니다.
  Future<List<Store>> _fetchNearestCampaigns() async {
    // 1. 기기의 위치 서비스(GPS) 활성화 여부 확인
    bool isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isLocationServiceEnabled) {
      // 서비스가 꺼져 있으면 사용자에게 명확한 메시지와 함께 오류 발생
      throw Exception('위치 서비스를 활성화해주세요.');
    }

    // 2. 앱의 위치 권한 상태 확인
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // 권한이 거부된 상태라면 요청
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // 사용자가 요청을 거부한 경우
        throw Exception('위치 권한을 허용해주세요.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // 사용자가 권한을 영구적으로 거부한 경우
      throw Exception('앱 설정에서 위치 권한을 허용해주세요.');
    }

    // 3. 모든 확인이 끝나면 현재 위치 가져오기
    Position position;
    try {
      position = await Geolocator.getCurrentPosition()
          .timeout(const Duration(seconds: 10));
      // [추가] 위치 정보를 상태 변수에 저장
      if (mounted) {
        setState(() => _currentPosition = position);
      }
    } catch (e) {
      throw Exception('현재 위치를 가져올 수 없습니다.');
    }

    return _campaignService.fetchNearest(
      lat: position.latitude,
      lng: position.longitude,
      limit: 10, // 홈 화면에서는 10개만 보여줌
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: const Text(
            '리뷰맵',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        actions: [
          Visibility(
            visible: false,                 // 안 보이지만
            maintainSize: true,             // 공간 유지
            maintainAnimation: true,
            maintainState: true,
            child: IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none)),
          ),
          Visibility(
              visible: false,                 // 안 보이지만
              maintainSize: true,             // 공간 유지
              maintainAnimation: true,
              maintainState: true,
              child: IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadCampaigns,
        child: ListView(
          controller: _mainScrollController,
          physics: const AlwaysScrollableScrollPhysics(), // ← 추가
          children: [
            _buildNoticeBanner(),
            const SizedBox(height: 20),
            _buildExperienceSection(
              title: '가까운 체험단',
              future: _nearestCampaigns,
            ),
            const SizedBox(height: 90),
            _buildRecommendedCampaignsSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildNoticeBanner() {
    if (!_showNoticeBanner) return const SizedBox.shrink(); // 숨김
    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: Colors.blue[100],
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.campaign, color: Colors.blue),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '리뷰 정책이 새롭게 변경되었습니다.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.blue),
            splashRadius: 18,
            onPressed: _dismissNotice,   // ← 닫기
            tooltip: '닫기',
          ),
        ],
      ),
    );
  }
  Widget _buildExperienceSection({
    required String title,
    required Future<List<Store>>? future,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: () async{
                  // future가 완료된 데이터를 기다려서 넘깁니다.
                  final data = await future;        // <-- 이미 Future<List<Store>> 임
                  if (!context.mounted || data == null || _currentPosition == null) return;

                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CampaignListScreen(
                        title: title,
                        // [수정] 파라미터 이름 변경 및 위치 정보 전달
                        initialStores: data.toList(),
                        userPosition: _currentPosition!,
                      ),
                    ),
                  );
                },
                child: Row(
                  children: [
                    Text('더보기', style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(width: 2.0), // 텍스트와 아이콘 사이의 간격 추가
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 12,
                      color: Colors.grey, // 아이콘 색상을 텍스트와 비슷하게 조절
                    ),
                    const SizedBox(width: 20.0), // 오른쪽 끝 여백을 위해 추가 (선택 사항)
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: FutureBuilder<List<Store>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      // "Exception: " 이라는 불필요한 텍스트를 제거하고 보여줌
                      snapshot.error.toString().replaceFirst('Exception: ', ''),
                      textAlign: TextAlign.center,
                    ),
                  );
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('표시할 체험단이 없습니다.'));
                }

                // final stores = snapshot.data!.take(5).toList();
                final stores = snapshot.data!.take(10).toList(); // ✅ 이 줄로 교체


                // 구분선 스타일(원하는 값으로 조절)
                const double kCardW = 150;
                const double kCardH = 150;
                const double kDividerThickness = 1.0;     // 선 두께
                const double kDividerHeight = 80.0;      // 선 길이
                final Color  kDividerColor = Colors.transparent; // 선 색상
                const double kGap = 12.0;                  // 카드와 선 사이 여백


                // return ListView.separated(
                //   scrollDirection: Axis.horizontal,
                //   itemCount: stores.length,
                //   itemBuilder: (context, index) {
                //     return Padding(
                //       padding: const EdgeInsets.only(right: 8.0),
                //       child: _buildExperienceCard(
                //           stores[index],
                //           width: 150,
                //           height: 150
                //       ),
                //     );
                //   },
                //   separatorBuilder: (context, index) => Padding(
                //       padding: const EdgeInsets.symmetric(horizontal: kGap / 2),
                //       child: Center(
                //           child: Container(
                //             width: kDividerThickness,
                //             height: kDividerHeight,
                //             color: kDividerColor,
                //           ),
                //       ),
                //   )
                // );
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: stores.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: _buildExperienceCard(stores[index], width: 150, height: 150),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // _buildExperienceCard, _imagePlaceholder, getLogoPathForPlatform 함수는 이전과 동일
  Widget _buildExperienceCard(Store store, {
    double width = 150,   // 기본값: 150
    double height = 150,  // 기본값: 150

    // bool showCenterDivider = false,
    // double dividerWidth = 120,
    // double dividerThickness = 1,
    // Color dividerColor = const Color(0xFFE5E7EB), // = gray-200
  }) {
    final logoPath = getLogoPathForPlatform(store.platform);
    final platformColor = platformBadgeColor(store.platform);
    return InkWell(
      onTap: (store.companyLink == null || store.companyLink!.isEmpty)
          ? null
          : () async {
        await openLink(store.companyLink!);
      },
      child: SizedBox(
        width: width,       // ← 가변 폭
        height: height,     // ← 가변 높이
        child: Card(
          elevation: 0,
          color: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Stack(
            children: [

              Padding(
                // 카드가 낮아져도 날짜 라인 안 덮게 하단 여백 유지
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Row(
                      children: [
                        // Image.asset(
                        //   getbannerPathForPlatform(store.platform),
                        //   height: 20,
                        //   fit: BoxFit.contain,
                        //   errorBuilder: (_, __, ___) => const SizedBox(height: 20),
                        // ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: platformColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            store.platform,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Container(
                        //   width: 28,
                        //   height: 28,
                        //   decoration: BoxDecoration(
                        //     border: Border.all(color: Color(0xFFE5E7EB)),
                        //     borderRadius: BorderRadius.circular(8),
                        //   ),
                        //   child: const Icon(Icons.shopping_bag_outlined, size: 16, color: Colors.black54),
                        // ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 상호명
                    Text(
                      store.company,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // 오퍼
                    if (store.offer != null && store.offer!.isNotEmpty)
                      Flexible(
                        child: Text(
                          store.offer!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.red, height: 1.2),
                        ),
                      ),
                  ],
                ),
              ),

              // 하단 날짜(바닥 기준 10px 위)
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    if (store.applyDeadline != null)
                      Text(
                        '~${DateFormat('MM.dd').format(store.applyDeadline!)}',
                        style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    if (store.distance != null)
                      Text(
                        '  •  ${store.distance!.toStringAsFixed(1)}km',
                        style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  Widget _imagePlaceholder() {
    return Container(
      height: 120,
      width: 140,
      color: Colors.grey[200],
      child: Center(
          child: Icon(Icons.storefront, color: Colors.grey[400], size: 40)),
    );
  }

  Widget _tagChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.black87)),
    );
  }


  void _loadMoreVisibleCampaigns() {
    if (_isLoading) return;

    final int totalItems = _shuffledCampaigns.length;
    // 이미 모든 아이템을 다 보여줬으면 더 이상 로드하지 않음
    if (_visibleCampaigns.length >= totalItems) {
      return;
    }

    setState(() { _isLoading = true; });

    // 다음 페이지의 시작과 끝 인덱스 계산
    final int startIndex = _currentPage * _pageSize;
    int endIndex = startIndex + _pageSize;
    if (endIndex > totalItems) {
      endIndex = totalItems;
    }

    final newItems = _shuffledCampaigns.getRange(startIndex, endIndex).toList();

    setState(() {
      _visibleCampaigns.addAll(newItems);
      _currentPage++;
      _isLoading = false;
    });
  }

  Future<void> _initializeRecommendedCampaigns() async{
    setState(() {
      _shuffledCampaigns = [];
      _visibleCampaigns = [];
      _currentPage = 0;
      _isLoading = true; // 초기 로딩 시작
    });

    // 1. API에서 대량의 데이터를 가져옴
    final allStores = await _campaignService.fetchPage(limit: 200);
    // 2. 가져온 데이터를 무작위로 섞음
    allStores.shuffle();
    _shuffledCampaigns = allStores;

    // 첫 페이지 데이터를 계산해서 바로 넣어줌
    final int totalItems = _shuffledCampaigns.length;
    int endIndex = _pageSize;
    if (endIndex > totalItems) {
      endIndex = totalItems;
    }

    // 상태 업데이트를 한 번에 처리
    setState(() {
      _visibleCampaigns = _shuffledCampaigns.getRange(0, endIndex).toList();
      _currentPage = 1;
      _isLoading = false; // 모든 초기 로드가 끝난 후 상태 변경
    });

  }

  Widget _buildRecommendedCampaignsSection() {
    // 선 스타일(원하는 값으로 조절)
    final gridLineColor = Colors.grey.shade300; // 연한 회색
    const gridLineWidth = 0.7;                  // 선 두께
    const cols = 2;                             // 그리드 열 수


    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('추천 체험단',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: () {
                  // 추천 데이터로 넘길 리스트 선택: 보이는 것(or 이미 섞어둔 전체 버퍼)
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
                    Text('더보기', style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(width: 2.0), // 텍스트와 아이콘 사이의 간격 추가
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 12,
                      color: Colors.grey, // 아이콘 색상을 텍스트와 비슷하게 조절
                    ),
                    const SizedBox(width: 8.0), // 오른쪽 끝 여백을 위해 추가 (선택 사항)
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ✅ 라인이 끊기지 않게 spacing은 0으로
          GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 0,   // ← 중요
              mainAxisSpacing: 0,    // ← 중요
              childAspectRatio: 150 / 130,
            ),
            itemCount: _visibleCampaigns.length,
            itemBuilder: (context, index) {
              final isRightCol = (index % cols) == cols - 1;
              final isLastRow = index >= _visibleCampaigns.length - cols;

              // 각 칸의 보더 구성: 오른쪽/아래만 그린다
              final boxBorder = Border(
                right: isRightCol
                    ? BorderSide.none
                    : BorderSide(color: gridLineColor, width: gridLineWidth),
                bottom: isLastRow
                    ? BorderSide.none
                    : BorderSide(color: gridLineColor, width: gridLineWidth),
              );

              return DecoratedBox(
                decoration: BoxDecoration(border: boxBorder),
                // 컨텐츠와 선이 붙어 보이지 않게 내부 패딩 살짝
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: _buildExperienceCard(_visibleCampaigns[index]),
                ),
              );
            },
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
          ),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );}

  Future<void> _loadMoreCampaigns() async {
    if (_isLoading) return;

    // 1) 로컬 버퍼 먼저 소진
    final localNext = _getNextPage();
    if (localNext.isNotEmpty) {
      setState(() {
        _visibleCampaigns.addAll(localNext);
      });
      return;
    }

    // 2) 서버 더 없음(총합을 알고 있다면 정확히 차단)
    if (_apiTotal != null && _apiOffset >= _apiTotal!) {
      return;
    }


    setState(() { _isLoading = true; });

    final batch = await _campaignService.fetchPage(
      limit: _apiLimit,
      offset: _apiOffset,
      sort: '-created_at',
    );

    if (!mounted) return;

    if (batch.isEmpty) {
      setState(() { _isLoading = false; });
      return;
    }

    _apiOffset += batch.length;      // ← offset 누적
    batch.shuffle();
    _shuffledCampaigns.addAll(batch);

    final refill = _getNextPage();
    setState(() {
      _visibleCampaigns.addAll(refill);
      _isLoading = false;
    });
  }

  List<Store> _getNextPage() {
    final int startIndex = _currentPage * _pageSize;
    int endIndex = startIndex + _pageSize;

    if (startIndex >= _shuffledCampaigns.length) {
      return [];
    }
    if (endIndex > _shuffledCampaigns.length) {
      endIndex = _shuffledCampaigns.length;
    }
    _currentPage++;
    return _shuffledCampaigns.getRange(startIndex, endIndex).toList();
  }


  void _onScroll() {
    final pos = _mainScrollController.position;
    if (!_isLoading && pos.extentAfter < 400) {
      _loadMoreCampaigns();
    }
  }
}