import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile/config/config.dart';
import 'package:mobile/const/colors.dart';
import 'package:mobile/screens/search_results_screen.dart';
import 'package:mobile/services/campaign_service.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../models/store_model.dart';
import '../providers/category_provider.dart';
import '../widgets/friendly.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  late final NaverMapController _naverController;
  final PanelController panelController = PanelController();
  late final CampaignService _service;
  String _currentSortOrder = '-created_at';

  bool _isTablet(BuildContext context) {
    // 화면의 짧은 쪽 길이가 600 이상이면 태블릿으로 간주
    return MediaQuery.of(context).size.shortestSide >= 600;
  }


  bool _mapReady = false;

  // 처음 1회 자동 센터링 제어
  bool _autoCenteredOnce = false;

  // onMapReady 전에 위치가 준비되면 여기에 보관
  NLatLng? _pendingTarget;

  // 패널/지도 패딩
  double _panelPos = 0.0;
  static const double _panelMin = 40.0;
  static const double _panelMax = 500.0;
  double _mapBottomPadding = 80.0;

  // 초기 카메라
  static const double _initialLat = 37.6345;
  static const double _initialLng = 126.8340;
  static const double _initialZoom = 14;

  // 목록/선택 상태
  final List<Store> _allStoresInView = [];
  Store? _selectedStore;
  List<Store> _displayedStores = [];

  int? _selectedCategoryId; // null이면 '전체'를 의미
  bool _showEmptyResultMessage = false;
  Timer? _emptyMessageTimer;


  @override
  void initState() {
    super.initState();
    // _service = CampaignService(
    //   AppConfig.ReviewMapbaseUrl,
    //   apiKey: AppConfig.ReviewMapApiKey,
    // );
    // _service.healthCheck();

    // 지도 탭 처음 들어올 때만 내 위치로 이동 시도
    _centerToMyLocationOnFirstOpen();
  }

  // 권한 체크
  Future<void> checkPermission() async {
    final isLocationEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isLocationEnabled) {
      throw Exception('위치 기능을 활성화 해주세요');
    }
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p != LocationPermission.always && p != LocationPermission.whileInUse) {
      throw Exception('위치 권한을 허가해주세요');
    }
  }

  double _currentPanelHeight() =>
      _panelMin + (_panelMax - _panelMin) * _panelPos;

  // (미사용 가능) 뷰포트 포함 여부
  bool _inViewport({
    required double south,
    required double west,
    required double north,
    required double east,
    required double lat,
    required double lng,
  }) {
    final inLat = (lat >= south && lat <= north);
    final inLng =
    (west <= east) ? (lng >= west && lng <= east) : (lng >= west || lng <= east);
    return inLat && inLng;
  }

  // 현재 뷰포트 검색
  Future<void> _searchInCurrentViewport() async {
    if (!_mapReady) return;
    _naverController.setLocationTrackingMode(NLocationTrackingMode.none);

    try {
      final b = await _naverController.getContentBounds(withPadding: true);
      final service = ref.read(campaignServiceProvider);
      final storesInBounds = await service.fetchInBounds(
        south: b.southWest.latitude,
        west: b.southWest.longitude,
        north: b.northEast.latitude,
        east: b.northEast.longitude,
        categoryId: _selectedCategoryId,
        sort: _currentSortOrder,
      );

      setState(() {
        _allStoresInView.clear();
        _allStoresInView.addAll(storesInBounds);
        _displayedStores = _allStoresInView;
        _selectedStore = null;
      });

      if (storesInBounds.isNotEmpty) {
        if (panelController.isPanelClosed) {
          panelController.animatePanelToPosition(0.4);
        }
      } else {
        // 👇 [추가] 결과가 없을 때 메시지 표시 로직
        setState(() => _showEmptyResultMessage = true);
        // 기존 타이머가 있으면 취소
        _emptyMessageTimer?.cancel();
        // 3초 후에 메시지 자동으로 숨기기
        _emptyMessageTimer = Timer(const Duration(milliseconds: 2000), () {
          if (mounted) {
            setState(() => _showEmptyResultMessage = false);
          }
        });
      }

      await _naverController.clearOverlays(type: NOverlayType.marker);
      final overlays = storesInBounds.map<NAddableOverlay>((s) {
        final lat = s.lat ?? _initialLat;
        final lng = s.lng ?? _initialLng;
        final m = NMarker(id: 'camp_${s.id}', position: NLatLng(lat, lng));
        m.setOnTapListener((_) {
          setState(() {
            _selectedStore = s;
            _displayedStores = [s];
          });
          if (panelController.isPanelClosed) panelController.open();
        });
        return m;
      }).toSet();
      await _naverController.addOverlayAll(overlays);

    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(context, '앗! 주변 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요 🗺️');
    }
  }

  // 내 위치 이동
  Future<void> _goToMyLocation() async {
    if (!_mapReady) return;
    try {
      await checkPermission();
      final loc = await Geolocator.getCurrentPosition();
      await _naverController.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: NLatLng(loc.latitude, loc.longitude),
          zoom: 15,
        ),
      );
      _naverController.setLocationTrackingMode(NLocationTrackingMode.follow);
    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(
        context,
        '내 위치로 이동할 수 없어요: ${e.toString().replaceFirst('Exception: ', '')}',
        actionLabel: '설정 열기',
        onAction: () => Geolocator.openAppSettings(),
      );
    }
  }

  // UI
  @override
  Widget build(BuildContext context) {
    return ClampTextScale(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('주변 탐색'),
          centerTitle: true,
        ),
        body: Stack(
          children: [
            NaverMap(
              onMapReady: (controller) async {
                _naverController = controller;
                _mapReady = true;
                _naverController.setLocationTrackingMode(NLocationTrackingMode.none);
                if (_pendingTarget != null && !_autoCenteredOnce) {
                  await _naverController.updateCamera(
                    NCameraUpdate.scrollAndZoomTo(target: _pendingTarget!, zoom: 15),
                  );
                  _naverController.setLocationTrackingMode(NLocationTrackingMode.follow);
                  _autoCenteredOnce = true;
                  _pendingTarget = null;
                }
              },
              // 👇 [수정] onMapTapped 로직 보강
              onMapTapped: (point, latLng) {
                // 선택된 마커가 있으면 선택 해제
                if (_selectedStore != null) {
                  setState(() {
                    _selectedStore = null;
                    _displayedStores = _allStoresInView;
                  });
                }
                // 패널이 닫혀있지 않으면 닫기
                if (!panelController.isPanelClosed) {
                  panelController.close();
                }
              },
              options: NaverMapViewOptions(
                initialCameraPosition: const NCameraPosition(
                  target: NLatLng(_initialLat, _initialLng),
                  zoom: _initialZoom,
                ),
                locationButtonEnable: false,
                rotationGesturesEnable: true,
                scrollGesturesEnable: true,
                tiltGesturesEnable: true,
                zoomGesturesEnable: true,
                contentPadding: EdgeInsets.only(bottom: _mapBottomPadding),
              ),
            ),

            _buildCategoryFilters(),

            SlidingUpPanel(
              controller: panelController,
              panel: _buildPanel(),
              minHeight: _panelMin,
              maxHeight: _panelMax,
              color: Colors.transparent,
              boxShadow: const <BoxShadow>[],
              onPanelSlide: (pos) {
                setState(() {
                  _panelPos = pos;
                  _mapBottomPadding = 80.0 + (_panelMax - _panelMin) * pos;
                });
              },
            ),

            Positioned(
              top: 30.h + 15.h,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topCenter,
                child: ElevatedButton.icon(
                  onPressed: _searchInCurrentViewport,
                  icon: const Icon(Icons.refresh),
                  label: const Text('이 위치로 검색'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PRIMARY_COLOR,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    elevation: 4,
                  ),
                ),
              ),
            ),

            Align(
              alignment: Alignment.center,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _showEmptyResultMessage ? 1.0 : 0.0,
                child: IgnorePointer( // 메시지가 떠 있어도 지도 조작 가능하게 함
                  ignoring: !_showEmptyResultMessage,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: const Text(
                      '주변에 등록된 체험단이 없네요. \n지도를 살짝 옮겨 다른 동네를 구경해볼까요? 😉',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              right: 16,
              bottom: 4 + _currentPanelHeight(),
              child: FloatingActionButton(
                heroTag: 'myLoc',
                onPressed: _goToMyLocation,
                backgroundColor: Colors.white,
                elevation: 3,
                mini: true,
                child: const Icon(Icons.my_location, color: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 패널 내용
  Widget _buildPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24.0),
          topRight: Radius.circular(24.0),
        ),
      ),
      child: Column(
        children: [
          // 핸들
          SizedBox(
            height: _panelMin,
            child: Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[500],
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _buildSortChip('최신등록순', '-created_at'),
                const SizedBox(width: 8),
                _buildSortChip('마감임박순', 'apply_deadline'),
              ],
            ),
          ),
          const SizedBox(height: 8), // 필터와 목록 사이 간격
          // 목록
          Expanded(
            child: _displayedStores.isEmpty
                ? const Center(child: Text("먼저 '이 위치로 검색'을 눌러주세요."))
                : ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _displayedStores.length,
              itemBuilder: (context, index) =>
                  _buildStoreListItem(_displayedStores[index]),
              separatorBuilder: (context, index) => Divider(
                indent: 16,
                endIndent: 16,
                color: Colors.grey.shade100,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 개별 아이템
  Widget _buildStoreListItem(Store store) {
    final String logoAssetPath = getLogoPathForPlatform(store.platform);
    final Widget logoWidget = Image.asset(
      logoAssetPath,
      width: 80,
      height: 80,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Container(
        width: 80,
        height: 80,
        color: Colors.grey[200],
        child: Icon(Icons.image_not_supported, color: Colors.grey[400]),
      ),
    );

    return InkWell(
      onTap: () async {
        final link = store.companyLink;
        if (link == null || link.isEmpty) return;
        final uri = Uri.parse(link);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else if (mounted) {
          showFriendlySnack(context, '연결할 수 없는 링크입니다.');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(8.0), child: logoWidget),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        store.company,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(width: 6),
                      // isNew가 true일 때만 뱃지 표시
                      if (store.isNew)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'NEW',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if ((store.offer ?? '').isNotEmpty)
                    Text(
                      store.offer ?? '',
                      style: const TextStyle(color: Colors.red, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),

                  // 👇 [수정] 플랫폼과 지원 마감일을 함께 표시하는 Row
                  Row(
                    children: [
                      // 플랫폼 아이콘과 이름
                      const Icon(Icons.apps, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        store.platform,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),

                      // applyDeadline 데이터가 있을 때만 마감일 표시
                      if (store.applyDeadline != null) ...[
                        const SizedBox(width: 20), // 플랫폼과 마감일 사이 간격
                        Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          // 날짜를 '~MM.dd 마감' 형식으로 변환
                          '${DateFormat('~MM.dd').format(store.applyDeadline!)} 마감',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ]
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _centerToMyLocationOnFirstOpen() async {
    if (_autoCenteredOnce) return;
    try {
      // 권한 체크/요청
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('위치 서비스를 켜주세요.');

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        throw Exception('위치 권한을 허용해주세요.');
      }

      // 현재 위치
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));

      final target = NLatLng(pos.latitude, pos.longitude);

      if (_mapReady) {
        // 지도 이미 준비됨 → 바로 이동
        await _naverController.updateCamera(
          NCameraUpdate.scrollAndZoomTo(target: target, zoom: 15),
        );
        _naverController.setLocationTrackingMode(NLocationTrackingMode.follow);
      } else {
        // 아직 준비 전 → onMapReady에서 적용
        _pendingTarget = target;
      }

      _autoCenteredOnce = true;
    } catch (_) {
      // 권한 거절/타임아웃 등은 조용히 패스: 사용자가 FAB/버튼으로도 이동 가능
    }
  }

  Widget _buildCategoryFilters() {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 30.h,
        color: PRIMARY_COLOR,
        child: categoriesAsync.when(
          data: (categories) {
            final List<Widget> chips = [
              _buildCategoryChip('전체', _selectedCategoryId == null, () {
                if (_selectedCategoryId != null) {
                  setState(() => _selectedCategoryId = null);
                  _searchInCurrentViewport();
                }
              }),
              ...categories.map((category) {
                final categoryId = category['id'] as int;
                final categoryName = category['name'] as String;
                final wittyName = _getWittyCategoryName(categoryName);
                final isSelected = _selectedCategoryId == categoryId;
                return _buildCategoryChip(wittyName, isSelected, () {
                  if (!isSelected) {
                    setState(() => _selectedCategoryId = categoryId);
                    _searchInCurrentViewport();
                  }
                });
              })
            ];

            // 👇 [핵심 수정] 태블릿과 폰에 다른 UI 적용
            if (_isTablet(context)) {
              // --- 태블릿용 UI: 균등 정렬 ---
              return LayoutBuilder(builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth - 32.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: chips,
                    ),
                  ),
                );
              });
            } else {
              // --- 휴대폰용 UI: 좌우 스크롤 ---
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                itemCount: chips.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12.0),
                itemBuilder: (context, index) => chips[index],
              );
            }
          },
          loading: () => const Center(child: LinearProgressIndicator(
            backgroundColor: Colors.white24,
            valueColor: AlwaysStoppedAnimation(Colors.white),
          )),
          error: (err, stack) => const Center(child: Text('카테고리 로딩 실패', style: TextStyle(color: Colors.white))),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String name, bool isSelected, VoidCallback onTap) {
    final Color selectedColor = Colors.white;
    final Color unselectedColor = Colors.white.withOpacity(0.8);

    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: isSelected ? selectedColor : unselectedColor,
        // 👇 버튼 내부의 좌우 패딩을 0으로 만들어 텍스트에 딱 맞게 조절
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4.0),
        minimumSize: Size.zero, // 버튼의 최소 사이즈 제한 제거
        tapTargetSize: MaterialTapTargetSize.shrinkWrap, // 버튼의 터치 영역을 최소화
        splashFactory: NoSplash.splashFactory,
        overlayColor: Colors.white.withOpacity(0.1),
      ),
      child: Text(
        name,
        style: TextStyle(
          fontSize: 14,
          color: isSelected ? selectedColor : unselectedColor,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          decoration: isSelected ? TextDecoration.underline : TextDecoration.none,
          decorationColor: Colors.white,
          decorationThickness: 2.0,
        ),
      ),
    );
  }
  Widget _buildSortChip(String label, String sortValue) {
    final bool isSelected = _currentSortOrder == sortValue;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _currentSortOrder = sortValue;
          });
          _searchInCurrentViewport(); // 정렬 변경 시 데이터 다시 불러오기
        }
      },
      // --- 👇 스타일링 수정 ---
      // 선택되었을 때의 배경색
      selectedColor: PRIMARY_COLOR,
      // 선택되지 않았을 때의 배경색 (흰색으로 깔끔하게)
      backgroundColor: Colors.white,
      // 선택되지 않았을 때만 테두리를 표시
      side: isSelected
          ? BorderSide.none
          : BorderSide(color: Colors.grey.shade300),
      // 글자 스타일
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: FontWeight.w500,
      ),
      // 동그란 '약' 모양으로 변경
      shape: const StadiumBorder(),
      // 체크 아이콘은 표시하지 않음
      showCheckmark: false,
      // 내부 여백 조절
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
      // 그림자 효과 제거
      elevation: 0,
      pressElevation: 0,
    );
  }

  String _getWittyCategoryName(String originalName) {
    switch (originalName) {
      // case '전체': return '다 보여줘';
      // case '맛집': return '밥집🍚';
      // case '카페/디저트': return '감성카페☕';
      // case '뷰티/헬스': return '예뻐지기✨';
      // case '숙박': return '호캉스🏖️';
      // case '여행': return '떠나볼까✈️';
      // case '패션/생활': return '꾸미기🛍️';
      // case '쇼핑': return '득템찬스';
      // case '생활서비스': return '편리하게';
      // case '액티비티': return '꿀잼보장🍯';
      // case '반려동물': return '댕댕이랑🐾';
      // case '문화/클래스': return '취미생활';
      // case '기타': return '또뭐있지🤔';
      default: return originalName; // 매칭되는 문구가 없으면 원래 이름 사용
    }
  }
}

// 권한 안내 위젯(필요 시 재사용)
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
