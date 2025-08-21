import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile/config/config.dart';
import 'package:mobile/const/colors.dart';
import 'package:mobile/services/campaign_service.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/store_model.dart';
import '../widgets/friendly.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final NaverMapController _naverController;
  late final CampaignService _service;
  final PanelController panelController = PanelController();

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

  @override
  void initState() {
    super.initState();
    _service = CampaignService(
      AppConfig.ReviewMapbaseUrl,
      apiKey: AppConfig.ReviewMapApiKey,
    );
    _service.healthCheck();

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

    try {
      await checkPermission(); // 버튼에서만 권한 요청
      _naverController.setLocationTrackingMode(NLocationTrackingMode.follow);

      final b = await _naverController.getContentBounds(withPadding: true);
      final south = b.southWest.latitude;
      final west = b.southWest.longitude;
      final north = b.northEast.latitude;
      final east = b.northEast.longitude;

      final storesInBounds = await _service.fetchInBounds(
        south: south,
        west: west,
        north: north,
        east: east,
      );

      setState(() {
        _allStoresInView
          ..clear()
          ..addAll(storesInBounds);
        _displayedStores = _allStoresInView;
        _selectedStore = null;
      });

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
      // 권한/네트워크 등 단일 스낵바로 안내(중복 노출 방지)
      showFriendlySnack(
        context,
        '권한 또는 네트워크가 필요해요: ${e.toString().replaceFirst('Exception: ', '')}',
        actionLabel: '설정 열기',
        onAction: () => Geolocator.openAppSettings(),
      );
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
                // 권한 승인 전 추적 OFF
                _naverController.setLocationTrackingMode(NLocationTrackingMode.none);
                // ✅ pending 위치가 있으면 첫 1회 즉시 이동
                if (_pendingTarget != null && !_autoCenteredOnce) {
                  await _naverController.updateCamera(
                    NCameraUpdate.scrollAndZoomTo(target: _pendingTarget!, zoom: 15),
                  );
                  _naverController.setLocationTrackingMode(NLocationTrackingMode.follow);
                  _autoCenteredOnce = true;
                  _pendingTarget = null;
                }
              },
              onMapTapped: (point, latLng) {
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
                locationButtonEnable: false,
                rotationGesturesEnable: true,
                scrollGesturesEnable: true,
                tiltGesturesEnable: true,
                zoomGesturesEnable: true,
                contentPadding: EdgeInsets.only(bottom: _mapBottomPadding),
              ),
            ),

            // 슬라이딩 패널
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

            // 상단: 이 위치로 검색
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
                      horizontal: 16,
                      vertical: 10,
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ),

            // 우하단: 내 위치 버튼 (패널 높이에 따라 위로)
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
                  Text(
                    store.company,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                  Row(
                    children: [
                      const Icon(Icons.apps, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        store.platform,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
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
