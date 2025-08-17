import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_svg/svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:location/location.dart';
import 'package:mobile/const/colors.dart';
import 'package:mobile/services/campaign_service.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/store_model.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final NaverMapController _naverController;
  late final CampaignService _service;
  final Location _location = Location();
  final panelController = PanelController();
  bool _mapReady = false;

  // 패널/패딩 상태값
  double _panelPos = 0.0; // 0.0(닫힘) ~ 1.0(열림)
  static const double _panelMin = 40.0;
  static const double _panelMax = 500.0;
  double _mapBottomPadding = 80.0;

  // 지도 초기 카메라 (네이버 타입 사용)
  static const double _initialLat = 37.6345;
  static const double _initialLng = 126.8340;
  static const double _initialZoom = 14;

  // final List<Store> _visibleStores = [];
  // --- 상태 변수 추가 및 수정 ---
  // 기존 _visibleStores는 뷰포트 내 모든 스토어를 담는 용도로 변경
  final List<Store> _allStoresInView = [];
  // 사용자가 선택한 스토어 (선택 안했을 시 null)
  Store? _selectedStore;
  // 슬라이드업 패널에 '실제로 보여줄' 목록 (상황에 따라 전체 또는 단일 항목)
  List<Store> _displayedStores = [];


  @override
  void initState() {
    super.initState();
    _service = CampaignService(
      'https://api.review-maps.com/v1',
      apiKey: '9e53ccafd6e993152e01e9e7a8ca66d1c2224bb5b21c78cf076f6e45dcbc0d12',
    );
    // 네트워크 헬스체크
    _service.healthCheck();
  }

  Future<void> checkPermission() async {
    final isLocationEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isLocationEnabled) {
      throw Exception('위치 기능을 활성화 해주세요');
    }

    LocationPermission checkedPermission = await Geolocator.checkPermission();
    if (checkedPermission == LocationPermission.denied) {
      checkedPermission = await Geolocator.requestPermission();
    }
    if (checkedPermission != LocationPermission.always &&
        checkedPermission != LocationPermission.whileInUse) {
      throw Exception('위치 권한을 허가해주세요');
    }
  }

  // 현재 패널 높이(픽셀)
  double _currentPanelHeight() =>
      _panelMin + (_panelMax - _panelMin) * _panelPos;


  // viewport 필터 함수(안전하게 재사용) ✅
  bool _inViewport({
    required double south, required double west,
    required double north, required double east,
    required double lat, required double lng,
  }) {
    // 경도는 180도 경계(anti-meridian)도 대비
    final inLat = (lat >= south && lat <= north);
    final inLng = (west <= east) ? (lng >= west && lng <= east)
        : (lng >= west || lng <= east);
    return inLat && inLng;
  }

  // 현재 보이는 지도 뷰포트에서 검색
  // ✅ 현재 화면만(전부) 표시 — bbox 지원/미지원 상관없이 동작
  Future<void> _searchInCurrentViewport() async {
    if (!_mapReady) return;

    try {
      final b = await _naverController.getContentBounds(withPadding: true);
      final south = b.southWest.latitude;
      final west  = b.southWest.longitude;
      final north = b.northEast.latitude;
      final east  = b.northEast.longitude;

      if (kDebugMode) {
        dev.log('[BBOX] south=$south, west=$west, north=$north, east=$east', name: 'MapScreen');
      }

      // 2) 서버에 해당 영역의 데이터만 요청.
      final storesInBounds = await _service.fetchInBounds(
        south: south, west: west, north: north, east: east,
      );

      if (kDebugMode) {
        final sample = storesInBounds.take(3).map((e) => {
          'id': e.id, 'company': e.company, 'lat': e.lat, 'lng': e.lng,
        }).toList();
        dev.log('[RESULT] count=${storesInBounds.length}, sample=$sample', name: 'MapScreen');
      }

      // 3) 받아온 데이터를 상태에 반영하고 마커를 그림
      setState(() {
        _allStoresInView.clear();
        _allStoresInView.addAll(storesInBounds);

        // 보여줄 목록은 전체 목록으로 초기화
        _displayedStores = _allStoresInView;
        // 선택된 스토어는 없음으로 초기화
        _selectedStore = null;
      });

      await _naverController.clearOverlays(type: NOverlayType.marker);
      final overlays = storesInBounds.map<NAddableOverlay>((s) {
        final m = NMarker(
          id: 'camp_${s.id}',
          position: NLatLng(s.lat!, s.lng!),
        );
        m.setOnTapListener((_) {
          setState(() {
            // 선택된 스토어를 현재 탭한 스토어로 지정
            _selectedStore = s;
            // 보여줄 목록을 '선택된 스토어 하나만' 담은 리스트로 교체
            _displayedStores = [s];
          });

          if (panelController.isPanelClosed) panelController.open();
        });
        return m;
      }).toSet();
      await _naverController.addOverlayAll(overlays);

      if (kDebugMode) {
        dev.log('[MARKERS] placed=${overlays.length}', name: 'MapScreen');
      }
    }
    catch (e){
      // 일반적인 네트워크 오류 등에 대한 예외 처리
      if (kDebugMode) {
        dev.log('[ERROR] Failed to search in viewport: $e', name: 'MapScreen');
      }
      // 사용자에게 오류 스낵바 등을 보여줄 수 있습니다.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터를 불러오는 데 실패했습니다: $e')),
        );
      }
    }
  }

  // 우하단 "내 위치" 버튼 동작
  Future<void> _goToMyLocation() async {
    if (!_mapReady) return;
    final loc = await Geolocator.getCurrentPosition();
    await _naverController.updateCamera(
      NCameraUpdate.scrollAndZoomTo(
        target: NLatLng(loc.latitude, loc.longitude),
        zoom: 15,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('주변 탐색'),
        centerTitle: true,
      ),
      body: FutureBuilder(
        future: checkPermission(),
        builder: (context, asyncSnapshot) {
          if (asyncSnapshot.hasError) {
            return Center(
              child: Text(asyncSnapshot.error.toString()),
            );
          }

          return Stack(
            children: [
              // 1) 지도 - 네이버맵
              NaverMap(
                onMapReady: (controller) async {
                  _naverController = controller;
                  _mapReady = true;

                  // 내 위치 추적 모드 설정 (파란 점 + 카메라 따라가기)
                  _naverController.setLocationTrackingMode(NLocationTrackingMode.follow);

                },
                onMapTapped: (point, latLng) {
                  // 특정 스토어가 선택된 상태에서만 전체 목록으로 돌아감
                  if (_selectedStore != null) {
                    setState(() {
                      _selectedStore = null;
                      _displayedStores = _allStoresInView;
                    });
                  }
                },
                options: NaverMapViewOptions(
                  initialCameraPosition: const NCameraPosition(
                    target: NLatLng(_initialLat, _initialLng),
                    zoom: _initialZoom,
                  ),
                  mapType: NMapType.basic,
                  locationButtonEnable: false, // 커스텀 FAB 사용
                  indoorEnable: false,
                  liteModeEnable: false,
                  logoClickEnable: false,
                  rotationGesturesEnable: true,
                  scrollGesturesEnable: true,
                  tiltGesturesEnable: true,
                  zoomGesturesEnable: true,
                  contentPadding:
                  EdgeInsets.only(bottom: _mapBottomPadding),
                ),
              ),

              // 2) 슬라이딩 패널
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

              // 3) 상단 가운데 "이 위치로 검색" 버튼
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
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
                          horizontal: 16, vertical: 10),
                      elevation: 2,
                    ),
                  ),
                ),
              ),

              // 4) 우하단 내 위치 버튼 — 패널 높이에 맞춰 같이 올라감
              Positioned(
                right: 16,
                bottom: 4 + _currentPanelHeight(),
                child: FloatingActionButton(
                  heroTag: 'myLoc',
                  onPressed: _goToMyLocation,
                  backgroundColor: Colors.white,
                  elevation: 3,
                  mini: true,
                  child:
                  const Icon(Icons.my_location, color: Colors.blue),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // 슬라이딩 패널 내용
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
          // 목록
          Expanded(
            child: _displayedStores.isEmpty
                ? const Center(child: Text("먼저 '이 위치로 검색'을 눌러주세요."))
                : ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _displayedStores.length,
              itemBuilder: (context, index) {
                return _buildStoreListItem(
                    _displayedStores[index]);
              },
              separatorBuilder: (context, index) => Divider(indent: 16, endIndent: 16, color: Colors.grey.shade100,),
            ),
          ),
        ],
      ),
    );
  }

  // 개별 아이템
  Widget _buildStoreListItem(Store store) {
    final String logoAssetPath = getLogoPathForPlatform(store.platform);

    // 로고를 표시할 위젯을 미리 정의합니다.
    Widget logoWidget;

    logoWidget = Image.asset(
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
        if (store.companyLink != null && store.companyLink!.isNotEmpty) {
          final uri = Uri.parse(store.companyLink!);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('연결할 수 없는 링크입니다: ${store.companyLink}')),
              );
            }
          }
        }
      },
      child: Padding(
        padding:
        const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: logoWidget,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(store.company,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  if ((store.offer ?? '').isNotEmpty)
                    Text(
                      store.offer ?? '',
                      style: const TextStyle(
                          color: Colors.red, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.apps,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(store.platform,
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 12)),
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
}
