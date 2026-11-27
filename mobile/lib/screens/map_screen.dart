import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile/config/config.dart';
import 'package:mobile/const/colors.dart';
import 'package:mobile/screens/search_results_screen.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/store_model.dart';
import '../providers/category_provider.dart';
import '../widgets/build_store_list_item.dart';
import '../widgets/friendly.dart';
import '../widgets/sort_filter_widget.dart';
import '../providers/location_provider.dart';

import 'map_search_screen.dart';

/// MapScreen 정렬 옵션 매핑 헬퍼
class MapSortHelper {
  static SortOption fromString(String sortValue) {
    switch (sortValue) {
      case '-created_at':
        return SortOption.newest;
      case 'apply_deadline':
        return SortOption.deadline;
      case 'distance':
        return SortOption.nearest;
      default:
        return SortOption.newest;
    }
  }

  static String toSortString(SortOption option) {
    switch (option) {
      case SortOption.newest:
        return '-created_at';
      case SortOption.deadline:
        return 'apply_deadline';
      case SortOption.nearest:
        return 'distance';
    }
  }
}

List<Widget> buildChannelIcons(String? channelStr, {double size = 16}) {
  if (channelStr == null || channelStr.isEmpty) return [];
  final channels = channelStr.split(',').map((c) => c.trim()).toList();

  final Map<String, String> iconMap = {
    'blog': 'asset/icons/blog_logo.png',
    'youtube': 'asset/icons/youtube_logo.png',
    'instagram': 'asset/icons/instagram_logo.png',
    'clip': 'asset/icons/clip_logo.png',
    'blog_clip': 'asset/icons/clip_logo.png',
    'reels': 'asset/icons/reels_logo.png',
  };

  return channels.where((ch) => ch != 'etc' && ch != 'unknown').map((ch) {
    final path = iconMap[ch];
    if (path == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Image.asset(
        path,
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }).toList();
}

class MapScreen extends ConsumerStatefulWidget {
  final bool autoSearchOnReady;

  const MapScreen({super.key, this.autoSearchOnReady = false});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  late final NaverMapController _naverController;
  final PanelController panelController = PanelController();
  String _currentSortOrder = '-created_at';

  // 최초 진입 여부 추적
  bool _isFirstSearch = true;
  
  // 패널 위치 상태 추적 대신, 실제 포지션 기억
  double _panelPos = 0.0;           // 패널 비율 (0.0~1.0)
  double? _lastPanelHeight;          // 실제 픽셀 높이 저장

  static const double _itemMinHeight = 108.0;
  // 핸들(_panelMin=40) + 정렬칩 영역(대략)
  static const double _panelHeaderExtra = 56.0;


 // 살짝만 올라와도 열린 걸로 간주

  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;


  T t<T>(BuildContext ctx, T phone, T tablet) => _isTablet(ctx) ? tablet : phone;

  bool _mapReady = false;

  // 처음 1회 자동 센터링 제어
  bool _autoCenteredOnce = false;

  // onMapReady 전에 위치가 준비되면 여기에 보관
  NLatLng? _pendingTarget;

  // 패널/지도 패딩
  // 중복 선언된 _panelPos 제거 (위에서 이미 선언됨)
  static const double _panelMin = 40.0;      // 패널 최소 높이(핸들)
  double _panelMax = 600.0;                  // 패널 최대 높이(화면에 따라 동적 조정)
  double _mapBottomPadding = 80.0;           // 지도 하단 패딩(패널/버튼 등 UI 요소 고려)

  // 초기 카메라
  static const double _initialLat = 37.6345;
  static const double _initialLng = 126.8340;
  static const double _initialZoom = 14;

  // 목록/선택 상태
  final List<Store> _allStoresInView = [];
  List<Store> _displayedStores = [];

  int? _selectedCategoryId; // null이면 '전체'를 의미
  bool _showEmptyResultMessage = false;

  Timer? _emptyMessageTimer;

   // 이동 끝나면 자동검색할지
  // 제스처(손가락) 말고 코드로 움직인 건지
  bool _isCameraMoving = false;
  // 손가락 드래그인지
  bool _moveByProgram = false;      // 검색 등으로 코드가 카메라를 움직였는지
  // bool _lastMoveByGesture = false;  // 손가락 드래그인지
  int _searchSeq = 0;               // 검색 시퀀스(경쟁 방지)
  bool _searchInFlight = false;      // 중복 호출 방지
      // 최근 검색 중심
         // 최근 검색 줌





  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final media = MediaQuery.of(context);
      final screenHeight = media.size.height;
      final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);

      // 폰트 배율에 따른 동적 조정
      final bool isTablet = _isTablet(context);
      final double maxScale = isTablet ? 1.10 : 1.30;
      final double clampedScale = textScaleFactor.clamp(1.0, maxScale);
      
      // 폰트 배율이 클 때 더 많은 여백 필요
      final scaleMultiplier = (1.0 + (clampedScale - 1.0) * 0.5).clamp(1.0, 1.3);

      // 버튼 위치와 크기 (Positioned에서 사용한 것과 동일하게 계산)
      final buttonTop = t(context, 45.0.h, 60.0.h);
      final buttonHeight = t(context, 30.0.h, 30.0.h);
      final buttonBottom = buttonTop + buttonHeight;

      // 폰트 배율에 따른 동적 안전 여백
      final baseSafePadding = 250.h;
      final safePadding = baseSafePadding * scaleMultiplier;

      // 최대 높이 = 화면 전체 높이 - (버튼 bottom + safePadding)
      final maxAllowed = screenHeight - buttonBottom - safePadding;

      // 폰트 배율에 따른 아이템 높이 조정
      final adjustedItemHeight = _itemMinHeight * scaleMultiplier;
      final minContent = _panelMin + _panelHeaderExtra + adjustedItemHeight * 1.5;

      setState(() {
        _panelMax = maxAllowed.clamp(minContent, screenHeight * 0.9);
      });

      if (AppConfig.isDebugMode) {
        debugPrint('📐 screen=$screenHeight, textScale=$textScaleFactor, clampedScale=$clampedScale');
        debugPrint('📐 buttonBottom=$buttonBottom, safePadding=$safePadding, scaleMultiplier=$scaleMultiplier');
        debugPrint('👉 panelMax=$_panelMax, adjustedItemHeight=$adjustedItemHeight');
      }
    });

    // 지도 탭 처음 들어올 때만 내 위치로 이동 시도
    _centerToMyLocationOnFirstOpen();
  }

  // 권한 체크 (Provider 사용)
  Future<void> checkPermission() async {
    await ref.read(locationProvider.notifier).update();
    final locationState = ref.read(locationProvider);
    
    if (!locationState.isGranted) {
      throw Exception('위치 권한을 허가해주세요');
    }
    
    if (locationState.position == null) {
      throw Exception('위치 정보를 가져올 수 없어요');
    }
  }

  double _currentPanelHeight() =>
      _panelMin + (_panelMax - _panelMin) * _panelPos;


  // 패널을 살짝만 올리는 함수 (지도 터치 시 사용)
  Future<void> _animatePanelToSlightPeek() async {
    if (!panelController.isAttached) {
      // 패널 컨트롤러 붙을 때까지 잠깐 대기 (최대 ~160ms)
      int guard = 0;
      while (!panelController.isAttached && guard < 10) {
        await Future.delayed(const Duration(milliseconds: 16));
        guard++;
      }
    }
    if (!panelController.isAttached) return;
    if (!mounted) return; // 위젯이 dispose된 경우 중단

    // 폰트 배율에 따른 동적 조정
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
    final bool isTablet = _isTablet(context);
    final double maxScale = isTablet ? 1.10 : 1.30;
    final double clampedScale = textScaleFactor.clamp(1.0, maxScale);
    final double scaleMultiplier = (1.0 + (clampedScale - 1.0) * 0.5).clamp(1.0, 1.3);

    // 폰트 배율에 따른 아이템 높이 조정
    final adjustedItemHeight = _itemMinHeight * scaleMultiplier;
    
    // 기본 높이 (헤더 + 1개 아이템)
    final desiredHeight = _panelMin + _panelHeaderExtra + adjustedItemHeight * 1.0;

    // 아이템 최소 1.5개 보장
    final minHeight = _panelMin + _panelHeaderExtra + adjustedItemHeight * 1.5;

    // 패널이 버튼을 절대 가리지 않도록 제한
    final buttonTop = t(context, 45.0.h, 60.0.h);
    final buttonHeight = t(context, 30.0.h, 30.0.h);
    final buttonBottom = buttonTop + buttonHeight;
    final baseSafePadding = 20.h;
    final safePadding = baseSafePadding * scaleMultiplier;
    final maxAllowed = MediaQuery.of(context).size.height - buttonBottom - safePadding;

    // 최종 높이
    final clamped = desiredHeight.clamp(minHeight, maxAllowed);
    final position = (clamped - _panelMin) / (_panelMax - _panelMin);

    await panelController.animatePanelToPosition(
      position,
      duration: const Duration(milliseconds: 220),
    );

    _panelPos = position;
    _lastPanelHeight = clamped; // 픽셀 높이 직접 저장
  }

  Future<void> _animatePanelToListPeek() async {
    if (!panelController.isAttached) {
      // 패널 컨트롤러 붙을 때까지 잠깐 대기 (최대 ~160ms)
      int guard = 0;
      while (!panelController.isAttached && guard < 10) {
        await Future.delayed(const Duration(milliseconds: 16));
        guard++;
      }
    }
    if (!panelController.isAttached) return;
    if (!mounted) return; // 위젯이 dispose된 경우 중단

    // 폰트 배율에 따른 동적 조정
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
    final bool isTablet = _isTablet(context);
    final double maxScale = isTablet ? 1.10 : 1.30;
    final double clampedScale = textScaleFactor.clamp(1.0, maxScale);
    final double scaleMultiplier = (1.0 + (clampedScale - 1.0) * 0.5).clamp(1.0, 1.3);

    // 폰트 배율에 따른 아이템 높이 조정
    final adjustedItemHeight = _itemMinHeight * scaleMultiplier;
    
    // 기본 높이 (헤더 + 2개 아이템)
    final desiredHeight = _panelMin + _panelHeaderExtra + adjustedItemHeight * 2.0;

    // 아이템 최소 1.5개 보장
    final minHeight = _panelMin + _panelHeaderExtra + adjustedItemHeight * 1.5;

    // 패널이 버튼을 절대 가리지 않도록 제한
    final buttonTop = t(context, 45.0.h, 60.0.h);
    final buttonHeight = t(context, 30.0.h, 30.0.h);
    final buttonBottom = buttonTop + buttonHeight;
    final baseSafePadding = 20.h;
    final safePadding = baseSafePadding * scaleMultiplier;
    final maxAllowed = MediaQuery.of(context).size.height - buttonBottom - safePadding;

    // 최종 높이
    final clamped = desiredHeight.clamp(minHeight, maxAllowed);
    final position = (clamped - _panelMin) / (_panelMax - _panelMin);

    await panelController.animatePanelToPosition(
      position,
      duration: const Duration(milliseconds: 220),
    );

    _panelPos = position;
    _lastPanelHeight = clamped; // 픽셀 높이 직접 저장
  }

  // 패널 위치 기억
  void _rememberPanelPosition() {
    if (panelController.isAttached) {
      _lastPanelHeight = _currentPanelHeight();
      if (AppConfig.isDebugMode) {
        debugPrint('[Map][_rememberPanelPosition] 저장된 패널 높이(px): $_lastPanelHeight');
      }
    }
  }

  // 패널 위치 복원 (저장된 픽셀값 → 현재 maxHeight 기준 비율로 변환)
  Future<void> _restorePanelPosition() async {
    if (panelController.isAttached && _lastPanelHeight != null) {
      final height = _lastPanelHeight!.clamp(_panelMin, _panelMax);
      final pos = (height - _panelMin) / (_panelMax - _panelMin);
      if (AppConfig.isDebugMode) {
        debugPrint('[Map][_restorePanelPosition] 복원할 비율: $pos');
      }
      await panelController.animatePanelToPosition(
        pos,
        duration: const Duration(milliseconds: 220),
      );
      _panelPos = pos;
    }
  }

  // 현재 뷰포트 검색
  Future<void> _searchInCurrentViewport({bool programmatic = false, bool shouldOpenPanel = true}) async {
    if (!_mapReady) { showFriendlySnack(context, '지도를 준비 중이에요. 잠시만요 🧭'); return; }
    if (_searchInFlight) return; // 중복 막기

    _searchInFlight = true;
    final int mySeq = ++_searchSeq; // 내 시퀀스

    try {
      _naverController.setLocationTrackingMode(NLocationTrackingMode.none);

      final b = await _naverController.getContentBounds(withPadding: true);
      final service = ref.read(campaignServiceProvider);

      // 거리순이 아닌 경우에만 서버에서 정렬, 거리순은 클라이언트에서 처리
      final sortParam = _currentSortOrder == 'distance' ? '-created_at' : _currentSortOrder;
      
      final storesInBounds = await service.fetchInBounds(
        south: b.southWest.latitude,
        west: b.southWest.longitude,
        north: b.northEast.latitude,
        east: b.northEast.longitude,
        categoryId: _selectedCategoryId,
        sort: sortParam,
      );

      // 더 최신 검색이 도착했다면 버린다.
      if (mySeq != _searchSeq) return;

      // 디버그 로그 추가
      if (AppConfig.isDebugMode) {
        debugPrint('[Map][_searchInCurrentViewport] 검색된 체험단 수: ${storesInBounds.length}');
        debugPrint('[Map][_searchInCurrentViewport] 뷰포트: south=${b.southWest.latitude}, west=${b.southWest.longitude}, north=${b.northEast.latitude}, east=${b.northEast.longitude}');
        if (storesInBounds.isNotEmpty) {
          debugPrint('[Map][_searchInCurrentViewport] 첫 번째 체험단: ${storesInBounds.first.title}');
        }
      }

      // 거리 계산 추가
      await _calculateDistancesForStores(storesInBounds);

      // 정렬 적용
      _applySorting(storesInBounds);

      setState(() {
        _allStoresInView
          ..clear()
          ..addAll(storesInBounds);
        _displayedStores = _allStoresInView;
      });

      await _naverController.clearOverlays(type: NOverlayType.marker);
      final overlays = storesInBounds.map<NAddableOverlay>((s) {
        final m = NMarker(id: 'camp_${s.id}', position: NLatLng(s.lat ?? _initialLat, s.lng ?? _initialLng));
        m.setOnTapListener((_) {
          setState(() {
            _displayedStores = [s];
          });
          if (panelController.isPanelClosed) panelController.open();
        });
        return m;
      }).toSet();
      await _naverController.addOverlayAll(overlays);

      if (storesInBounds.isNotEmpty) {
        // 패널 위치 처리
        if (!programmatic && shouldOpenPanel) {
          // 사용자가 직접 "이 위치로 검색" 버튼을 눌렀을 때만 패널 높이 변경
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            if (_isFirstSearch) {
              await _animatePanelToSlightPeek(); // 첫 검색 → 대기높이
              _isFirstSearch = false;
            } else {
              await _animatePanelToListPeek(); // 이후 검색 → 실행높이
            }
          });
        } else if (programmatic || !shouldOpenPanel) {
          // 정렬/필터 클릭 시 또는 shouldOpenPanel이 false일 때 → 저장된 패널 위치 그대로 유지
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            await _restorePanelPosition();
          });
        }
        if (mounted) setState(() => _showEmptyResultMessage = false);
      } else {
        // 빈 결과 처리
        if (programmatic || !shouldOpenPanel) {
          // 정렬/필터 클릭 시 또는 shouldOpenPanel이 false일 때 → 저장된 패널 위치 그대로 유지
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            await _restorePanelPosition();
          });
        } else {
          // 사용자가 직접 검색한 경우에만 패널 내리기
          if (panelController.isAttached) {
            panelController.animatePanelToPosition(0.0, duration: const Duration(milliseconds: 180));
            _lastPanelHeight = _panelMin; // 패널이 닫힌 상태도 저장
          }
        }
        if (mounted) {
          setState(() => _showEmptyResultMessage = true);
          _emptyMessageTimer?.cancel();
          _emptyMessageTimer = Timer(const Duration(milliseconds: 1800), () {
            if (mounted) setState(() => _showEmptyResultMessage = false);
          });
        }
      }
    } catch (e, st) {
      if (AppConfig.isDebugMode) debugPrint('[Map][_searchInCurrentViewport] error=$e\n$st');
      if (mounted) {
        showFriendlySnack(context, '앗! 주변 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요 🗺️');
      }
    } finally {
      _searchInFlight = false;
    }
  }


  // 내 위치 이동
  Future<void> _goToMyLocation() async {
    if (!_mapReady) return;
    try {
      await ref.read(locationProvider.notifier).update();
      final loc = ref.read(locationProvider).position;

      if (loc == null) throw Exception('위치 정보를 가져올 수 없어요.');

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
        onAction: () => ref.read(locationProvider.notifier).openAppSettings(),
      );
    }
  }

  // UI
  @override
  Widget build(BuildContext context) {
    final bool isTablet = _isTablet(context);
    final double maxScale = isTablet ? 1.10 : 1.30;
    
    return ClampTextScale(
      max: maxScale,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white, // 배경 흰색
          elevation: 0, // 그림자 제거
          toolbarHeight: t(context, 56.0.h, 72.0.h),
          titleSpacing: t(context, 8.w, 20.w),
          title: Padding(
            padding: EdgeInsets.only(
              top: t(context, 2.h, 6.h),
              bottom: t(context, 6.h, 8.h),
            ),
            child: _buildAppBarSearchField(),
          ),
        ),
        body: Stack(
          children: [
            Container(
              color: Colors.white,
              child: NaverMap(
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
                  if (widget.autoSearchOnReady) {
                    _isFirstSearch = false;
                    final pos = ref.read(locationProvider).position;
                    if (pos != null) {
                      await _naverController.updateCamera(
                        NCameraUpdate.scrollAndZoomTo(
                          target: NLatLng(pos.latitude, pos.longitude),
                          zoom: 14.6,
                        ),
                      );
                    }
                    await Future<void>.delayed(const Duration(milliseconds: 800));
                    if (mounted) {
                      await _searchInCurrentViewport(programmatic: false, shouldOpenPanel: true);
                    }
                  }
                },
                onCameraChange: (reason, isAnimated) {
                  _isCameraMoving = true;
                  // setState(() {}); // 버튼 disabled 반영 (선택)
                },
                onCameraIdle: () {
                  _isCameraMoving = false;
                  if (mounted) setState(() {});

                  // 💡 사용자가 직접 움직였을 땐 아무 것도 하지 않는다.
                  // 💡 프로그램적으로 움직였을 때만 자동검색 실행
                  if (_moveByProgram) {
                    _moveByProgram = false;
                    Future.delayed(const Duration(milliseconds: 1500), () {
                      if (mounted) {
                        _searchInCurrentViewport(programmatic: true);
                      }
                    });

                    // _searchInCurrentViewport(programmatic: true); // 토스트 억제
                  }
                },
                onMapTapped: (NPoint point, NLatLng latLng) async {
                  if (!panelController.isAttached) return;
                  if (_displayedStores.isNotEmpty) {
                    await _animatePanelToSlightPeek(); // 대기높이로 올리기
                  } else {
                    panelController.animatePanelToPosition(
                      0.0,
                      duration: const Duration(milliseconds: 180),
                    );
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
            ),

            // if (_isPanelOpen)
            //   Positioned.fill(
            //     child: GestureDetector(
            //       behavior: HitTestBehavior.translucent, // 빈 공간 탭도 잡기
            //       onTap: () async {
            //         if (_displayedStores.isNotEmpty) {
            //           await _animatePanelToListPeek(); // ✅ 같은 위치로 내리기
            //         } else if (panelController.isAttached) {
            //           panelController.animatePanelToPosition(0.0, duration: const Duration(milliseconds: 180));
            //         }
            //       },
            //     ),
            //   ),

            _buildCategoryFilters(),
            // Positioned(
            //   top: 0,
            //   left: 0,
            //   right: 0,
            //   child: _buildTopSearchBar(context),
            // ),

            SlidingUpPanel(
              controller: panelController,
              panel: _buildPanel(),
              minHeight: _panelMin,
              maxHeight: _panelMax,
              color: Colors.transparent,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),

              boxShadow: const <BoxShadow>[],
              panelSnapping: false,     // 스냅 비활성화하여 maxHeight 제한이 제대로 작동하도록
              onPanelSlide: (pos) async {
                // setState(() {
                //   _panelPos = pos;
                //   _mapBottomPadding = 80.0 + (_panelMax - _panelMin) * pos;
                // });
                final p = double.parse(pos.toStringAsFixed(2));
                if ((p - _panelPos).abs() < 0.03) return; // 3% 이내 변화는 무시
                setState(() {
                  _panelPos = p;
                  _mapBottomPadding = 80.0 + (_panelMax - _panelMin) * p;
                });

                // try {
                //   await _naverController.updateContentPadding(
                //     EdgeInsets.only(bottom: _mapBottomPadding),
                //   );
                // } catch (_) {}
              },
            ),
            Positioned(
              // top: 30.h + 5.h,
              // left: 0,
              // right: 0,
              top: t(context, 45.0.h, 60.0.h),
              left: t(context, 0.0.h, 12.0.h),
              right: t(context, 0.0.h, 12.0.h),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    // ✅ 태블릿에서 버튼 자체 크기를 확 키움
                    minWidth: _isTablet(context) ? 100.w : 100.w,
                    minHeight: _isTablet(context) ? 30.h  : 30.h,
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _isCameraMoving ? null : () {
                      _rememberPanelPosition(); // 현재 패널 위치 저장
                      _searchInCurrentViewport(programmatic: false, shouldOpenPanel: false);
                    },
                    icon: Icon(
                      Icons.refresh,
                      size: _isTablet(context) ? 11.sp : 18.sp,
                    ),
                    label: Text(
                      '이 위치로 검색',
                      style: TextStyle(
                        fontSize: _isTablet(context) ? 8.5.sp : 14.sp,
                        fontWeight: FontWeight.w200,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          _isTablet(context) ? 20.r : 20.r,
                        ),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: _isTablet(context) ? 8.w : 8.w,
                        vertical:   _isTablet(context) ? 8.h : 8.h,
                      ),
                      elevation: 4,
                      minimumSize: Size(
                        _isTablet(context) ? 100.w : 130.w,
                        _isTablet(context) ? 30.h  : 30.h,
                      ),
                    ),
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
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: const Text(
                      '주변에 등록된 체험단이 없네요. \n지도를 살짝 옮겨 다른 동네를 구경해볼까요? 😉',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              right: t(context, 16.0.h, 24.0.h),
              bottom: 4.h + _currentPanelHeight(),
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


  Widget _buildPanel() {
    return LayoutBuilder(
      builder: (context, constraints) {
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
              // 통일된 정렬 필터
              SortFilterWidget(
                currentSort: MapSortHelper.fromString(_currentSortOrder),
                onSortChanged: (newSort) {
                  _rememberPanelPosition();
                  setState(() {
                    _currentSortOrder = MapSortHelper.toSortString(newSort);
                  });
                  // 정렬 변경 → 프로그램적 이동 (패널 위치 유지)
                  _searchInCurrentViewport(programmatic: true);
                },
                userPosition: ref.watch(locationProvider).position,
                onLocationRequest: () async {
                  // ScaffoldMessenger를 미리 캡처 (async gap 이전)
                  final messenger = ScaffoldMessenger.of(context);
                  // Provider를 통한 위치 권한 요청
                  await ref.read(locationProvider.notifier).update();
                  if (!mounted) return; // 위젯이 dispose된 경우 중단
                  final locationState = ref.read(locationProvider);

                  if (!locationState.isGranted) {
                    messenger.hideCurrentSnackBar();
                    messenger.clearSnackBars();
                    messenger.showSnackBar(SnackBar(
                      content: const Text('위치 권한이 필요합니다.'),
                      behavior: SnackBarBehavior.floating,
                      action: SnackBarAction(
                        label: '설정 열기',
                        onPressed: () => ref.read(locationProvider.notifier).openAppSettings(),
                      ),
                    ));
                  } else if (locationState.position == null) {
                    messenger.hideCurrentSnackBar();
                    messenger.clearSnackBars();
                    messenger.showSnackBar(SnackBar(
                      content: const Text('위치 정보를 가져올 수 없습니다.'),
                      behavior: SnackBarBehavior.floating,
                      action: SnackBarAction(
                        label: '설정 열기',
                        onPressed: () => ref.read(locationProvider.notifier).openLocationSettings(),
                      ),
                    ));
                  }
                },
              ),
              const SizedBox(height: 8),
              // 리스트
              Expanded(
                child: _displayedStores.isEmpty
                    ? const Center(child: Text("먼저 '이 위치로 검색'을 눌러주세요."))
                    : ListView.separated(
                        padding: EdgeInsets.only(bottom: 12.h),
                        itemCount: _displayedStores.length,
                        itemBuilder: (context, index) =>
                            StoreListItem(
                              store: _displayedStores[index],
                              onTap: () => _openStoreLink(_displayedStores[index]),
                            ),
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
      },
    );
  }

  // 패널 내용
  
  // 개별 아이템
  // Widget _buildStoreListItem(Store store) {
  //   final String logoAssetPath = getLogoPathForPlatform(store.platform);
  //   final Widget logoWidget = Image.asset(
  //     logoAssetPath,
  //     width: 56.w,
  //     height: 56.h,
  //     fit: BoxFit.contain,
  //     errorBuilder: (_, __, ___) => Container(
  //       width: 56.w,
  //       height: 56.h,
  //       color: Colors.grey[200],
  //       child: Icon(Icons.image_not_supported, color: Colors.grey[400]),
  //     ),
  //   );
  //
  //   return InkWell(
  //     onTap: () async {
  //       final link = store.companyLink;
  //       if (link == null || link.isEmpty) return;
  //       final uri = Uri.parse(link);
  //       if (await canLaunchUrl(uri)) {
  //         await launchUrl(uri, mode: LaunchMode.externalApplication);
  //       } else if (mounted) {
  //         showFriendlySnack(context, '연결할 수 없는 링크입니다.');
  //       }
  //     },
  //     child: Padding(
  //       padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
  //       child: Row(
  //         children: [
  //           ClipRRect(borderRadius: BorderRadius.circular(8.0), child: logoWidget),
  //           const SizedBox(width: 16),
  //           Expanded(
  //             child: Column(
  //               crossAxisAlignment: CrossAxisAlignment.start,
  //               children: [
  //                 Wrap(
  //                   spacing: 6,
  //                   runSpacing: 2, // 줄 바뀔 때 세로 간격
  //                   crossAxisAlignment: WrapCrossAlignment.center,
  //                   children: [
  //                     // 제목
  //                     ConstrainedBox(
  //                       constraints: const BoxConstraints(minWidth: 0, maxWidth: double.infinity),
  //                       child: Text(
  //                         store.company,
  //                         style: TextStyle(
  //                           fontSize: t(context, 16.0.sp, 16.0.sp), // 태블릿에서 조금 키움
  //                           fontWeight: FontWeight.bold,
  //                         ),
  //                         maxLines: 2,
  //                         overflow: TextOverflow.ellipsis,
  //                         softWrap: true,
  //                       ),
  //                     ),
  //                     // NEW 뱃지
  //                     if (store.isNew)
  //                       Container(
  //                         padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  //                         decoration: BoxDecoration(
  //                           color: Colors.redAccent,
  //                           borderRadius: BorderRadius.circular(4),
  //                         ),
  //                         child: const Text(
  //                           'NEW',
  //                           style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
  //                         ),
  //                       ),
  //                   ],
  //                 ),
  //                 const SizedBox(height: 4),
  //                 if ((store.offer ?? '').isNotEmpty)
  //                   Text(
  //                     store.offer ?? '',
  //                     style: TextStyle(
  //                       color: Colors.red,
  //                       fontSize: t(context, 13.0.sp, 16.0.sp),
  //                     ),
  //                     maxLines: 2,
  //                     overflow: TextOverflow.ellipsis,
  //                   ),
  //                 const SizedBox(height: 4),
  //
  //                 // 👇 [수정] 플랫폼과 지원 마감일을 함께 표시하는 Row
  //                 // Row(
  //                 //   children: [
  //                 //     // 플랫폼 아이콘과 이름
  //                 //     const Icon(Icons.apps, size: 14, color: Colors.grey),
  //                 //     const SizedBox(width: 4),
  //                 //     Text(
  //                 //       store.platform,
  //                 //       style: TextStyle(color: Colors.grey[600], fontSize: 12),
  //                 //     ),
  //                 //
  //                 //     // applyDeadline 데이터가 있을 때만 마감일 표시
  //                 //     if (store.applyDeadline != null) ...[
  //                 //       const SizedBox(width: 20), // 플랫폼과 마감일 사이 간격
  //                 //       Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey[600]),
  //                 //       const SizedBox(width: 4),
  //                 //       Text(
  //                 //         // 날짜를 '~MM.dd 마감' 형식으로 변환
  //                 //         '${DateFormat('~MM.dd').format(store.applyDeadline!)} 마감',
  //                 //         style: TextStyle(color: Colors.grey[600], fontSize: 12),
  //                 //       ),
  //                 //     ]
  //                 //   ],
  //                 // ),
  //                 _buildPlatformAndDeadlineRow(store),
  //               ],
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  Future<void> _centerToMyLocationOnFirstOpen() async {
    if (_autoCenteredOnce) return;
    try {
      // 권한 체크/요청
      await ref.read(locationProvider.notifier).update();
      final pos = ref.read(locationProvider).position;
      if (pos == null) throw Exception('위치 정보를 가져올 수 없어요.');

      final target = NLatLng(pos.latitude, pos.longitude);

      if (_mapReady) {
        // 지도 이미 준비됨 → 바로 이동
        await _naverController.updateCamera(
          NCameraUpdate.scrollAndZoomTo(target: target, zoom: 15),
        );
        _naverController.setLocationTrackingMode(NLocationTrackingMode.follow);
        _autoCenteredOnce = true;
      } else {
        // 아직 준비 전 → onMapReady에서 적용
        _pendingTarget = target;
      }
    } catch (_) {
      // 권한 거절/타임아웃 등은 조용히 패스: 사용자가 FAB/버튼으로도 이동 가능
    }
  }

  Widget _buildCategoryFilters() {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Container(
      height: t(context, 36.0.h, 44.0.h),
      color: primaryColor,
      child: categoriesAsync.when(
        data: (categories) {
          final List<Widget> chips = [
            _buildCategoryChip('전체', _selectedCategoryId == null, () {
              if (_selectedCategoryId != null) {
                _rememberPanelPosition();
                setState(() => _selectedCategoryId = null);
                _searchInCurrentViewport(programmatic: true);
              }
            }),
            ...categories.map((category) {
              final categoryId = category['id'] as int;
              final categoryName = category['name'] as String;
              final wittyName = _getWittyCategoryName(categoryName);
              final isSelected = _selectedCategoryId == categoryId;
              return _buildCategoryChip(wittyName, isSelected, () {
                if (!isSelected) {
                  _rememberPanelPosition();
                  setState(() => _selectedCategoryId = categoryId);
                  _searchInCurrentViewport(programmatic: true);
                }
              });
            })
          ];

          // 👇 [핵심 수정] 태블릿과 폰에 다른 UI 적용
          if (_isTablet(context)) {
            return LayoutBuilder(builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth - 32.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: chips
                        .map((w) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: w,
                    ))
                        .toList(),
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
    );
  }

  Widget _buildCategoryChip(String name, bool isSelected, VoidCallback onTap) {
    final Color selectedColor = Colors.white;
    final Color unselectedColor = Colors.white.withValues(alpha: 0.8);

    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: isSelected ? selectedColor : unselectedColor,
        // 👇 버튼 내부의 좌우 패딩을 0으로 만들어 텍스트에 딱 맞게 조절
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4.0),
        minimumSize: Size.zero, // 버튼의 최소 사이즈 제한 제거
        tapTargetSize: MaterialTapTargetSize.shrinkWrap, // 버튼의 터치 영역을 최소화
        splashFactory: NoSplash.splashFactory,
        overlayColor: Colors.white.withValues(alpha: 0.1),
      ),
      child: Text(
        name,
        style: TextStyle(
          fontSize: _isTablet(context) ? 16.sp : 14.sp,
          color: isSelected ? selectedColor : unselectedColor,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          decoration: isSelected ? TextDecoration.underline : TextDecoration.none,
          decorationColor: Colors.white,
          decorationThickness: 2.0,
        ),
      ),
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



  // 스토어 링크 열기
  Future<void> _openStoreLink(Store store) async {
    try {
      final link = store.contentLink;
      if (link == null || link.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('연결할 수 있는 링크가 없습니다.')),
          );
        }
        return;
      }
      
      String url = link.trim();
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }
      
      final uri = Uri.parse(Uri.encodeFull(url));
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('연결할 수 없는 링크입니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('링크를 열 수 없습니다.')),
        );
      }
    }
  }

  // 검색 박스
  Widget _buildAppBarSearchField() {
    return GestureDetector(
      onTap: () async{
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MapSearchScreen()),
        );
        if (!mounted) return; // 위젯이 dispose된 경우 중단

        if (result != null && result is NLatLng && _mapReady) {
          try {
            _naverController.setLocationTrackingMode(NLocationTrackingMode.none);
            _moveByProgram = true; // ✅ 프로그램 이동 플래그 ON
            await _naverController.updateCamera(
              NCameraUpdate.scrollAndZoomTo(target: result, zoom: 16),
            );
            // 검색 호출 X → onCameraIdle에서 실행
          } catch (_) {
            if (!mounted) return; // 위젯이 dispose된 경우 중단
            _moveByProgram = false;
            showFriendlySnack(context, '앗! 지도가 잠깐 삐끗했어요 💦 다시 한 번 시도해볼까요?');
          }
        }
      },
      child: Container(
        height: t(context, 35.0.h, 46.0.h),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Color((0xffd7d7d7))),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: t(context, 12.0.h, 16.0.h)),
              child: Icon(Icons.search, color: Colors.grey[600], size: t(context, 20.0.h, 24.0.h)),
            ),
            Text(
              '장소, 지하철, 지역명 검색',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: t(context, 13.0.sp, 10.0.sp),
              ),
            ),
          ],
        ),
      ),
    );
  }


  // 정렬 적용 함수
  void _applySorting(List<Store> stores) {
    switch (_currentSortOrder) {
      case 'distance':
        // 거리순 정렬 (클라이언트 사이드)
        stores.sort((a, b) {
          final distanceA = a.distance ?? double.maxFinite;
          final distanceB = b.distance ?? double.maxFinite;
          return distanceA.compareTo(distanceB);
        });
        break;
      case 'apply_deadline':
        // 마감임박순 정렬 (클라이언트 사이드)
        stores.sort((a, b) {
          if (a.applyDeadline == null && b.applyDeadline == null) return 0;
          if (a.applyDeadline == null) return 1;
          if (b.applyDeadline == null) return -1;
          return a.applyDeadline!.compareTo(b.applyDeadline!);
        });
        break;
      case '-created_at':
        // 최신등록순 정렬 (클라이언트 사이드)
        stores.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      default:
        // 기본값은 서버에서 처리된 정렬 유지
        break;
    }
  }

  // 거리 계산 유틸리티 (홈화면과 동일)
  Future<void> _calculateDistancesForStores(List<Store> stores) async {
    try {
      // 위치 권한 확인
      // final permission = await Geolocator.checkPermission();
      // if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
      //   return; // 권한이 없으면 거리 계산하지 않음
      // }

      // 현재 위치 가져오기
      final pos = ref.read(locationProvider).position;
      if (pos == null) throw Exception('위치 정보를 가져올 수 없어요.');


      // 각 스토어에 대해 거리 계산하고 리스트 업데이트
      for (int i = 0; i < stores.length; i++) {
        final store = stores[i];
        if (store.lat != null && store.lng != null) {
          final distance = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
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

}
