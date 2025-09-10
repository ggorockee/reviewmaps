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
import 'package:intl/intl.dart';

import '../models/store_model.dart';
import '../providers/category_provider.dart';
import '../widgets/build_store_list_item.dart';
import '../widgets/friendly.dart';
import 'map_search_screen.dart';


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
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  late final NaverMapController _naverController;
  final PanelController panelController = PanelController();
  String _currentSortOrder = '-created_at';

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

    // 검색 성공 시 쓰던 계산식 그대로 재사용
    final desiredHeight = _panelMin + _panelHeaderExtra + _itemMinHeight * 1.5;
    final clamped = desiredHeight.clamp(_panelMin, _panelMax);
    final position = (clamped - _panelMin) / (_panelMax - _panelMin);

    await panelController.animatePanelToPosition(
      position.toDouble(),
      duration: const Duration(milliseconds: 220),
    );
  }


  // 현재 뷰포트 검색
  Future<void> _searchInCurrentViewport({bool programmatic = false}) async {
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
        // 패널 열기 (동일)
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          // int guard = 0;
          // while (!panelController.isAttached && guard < 10) {
          //   await Future.delayed(const Duration(milliseconds: 16));
          //   guard++;
          // }
          // final desiredHeight = _panelMin + _panelHeaderExtra + _itemMinHeight * 1.5;
          // final clamped = desiredHeight.clamp(_panelMin, _panelMax);
          // final position = (clamped - _panelMin) / (_panelMax - _panelMin);
          // panelController.animatePanelToPosition(position.toDouble(), duration: const Duration(milliseconds: 220));
          await _animatePanelToListPeek();
        });
        if (mounted) setState(() => _showEmptyResultMessage = false);
      } else {
        // 빈 결과 처리 (중복 로직 정리)
        if (panelController.isAttached) {
          panelController.animatePanelToPosition(0.0, duration: const Duration(milliseconds: 180));
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
      if (AppConfig.isDebugMode) print('[Map][_searchInCurrentViewport] error=$e\n$st');
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
                  await _animatePanelToListPeek();
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
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),

              boxShadow: const <BoxShadow>[],
              panelSnapping: true,     // 스냅 활성화
              snapPoint: 0.55,          // 중간 고정 지점(원하면 조정/삭제 가능)
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
                    onPressed: _isCameraMoving ? null : () => _searchInCurrentViewport(programmatic: false),
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
                      backgroundColor: PRIMARY_COLOR,
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
                      color: Colors.black.withOpacity(0.75),
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
                  const SizedBox(width: 8),
                  _buildSortChip('거리순', 'distance'),
                ],
              ),
            ),
            const SizedBox(height: 8), // 필터와 목록 사이 간격
            // 목록
            Expanded(
              child: Stack(
                children: [
                  _displayedStores.isEmpty
                      ? const Center(child: Text("먼저 '이 위치로 검색'을 눌러주세요."))
                      : ListView.separated(
                    // padding: EdgeInsets.zero,
                    padding: EdgeInsets.only(bottom: 12.h), // 패널 하단 패딩
                    cacheExtent: 500, // 스크롤 성능
                    itemCount: _displayedStores.length,
                    itemBuilder: (context, index) => StoreListItem(
                      store: _displayedStores[index],
                    ),
                    separatorBuilder: (context, index) => Divider(
                      indent: 16,
                      endIndent: 16,
                      color: Colors.grey.shade100,
                    ),
                  ),
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: IgnorePointer(
                      ignoring: true,
                      child: Container(
                        height: 18,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withOpacity(0.0),
                              Colors.white,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ]
      ),
    );
  }

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

    return Container(
      height: t(context, 36.0.h, 44.0.h),
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
          fontSize: 14.sp,
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



  // 검색 박스
  Widget _buildAppBarSearchField() {
    return GestureDetector(
      onTap: () async{
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MapSearchScreen()),
        );

        if (result != null && result is NLatLng && _mapReady) {
          try {
            _naverController.setLocationTrackingMode(NLocationTrackingMode.none);
            _moveByProgram = true; // ✅ 프로그램 이동 플래그 ON
            await _naverController.updateCamera(
              NCameraUpdate.scrollAndZoomTo(target: result, zoom: 16),
            );
            // 검색 호출 X → onCameraIdle에서 실행
          } catch (_) {
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
              '장소·지하철·지역명 검색 (주소 검색 준비중 🙏)',
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


  Widget _buildDeadlineChips(DateTime? deadline) {
    if (deadline == null) {
      return const SizedBox.shrink();
    }
    final today = DateTime.now();
    final d0 = DateTime(today.year, today.month, today.day);
    final d1 = DateTime(deadline.year, deadline.month, deadline.day);
    final daysLeft = d1.difference(d0).inDays;

    final String dLabel;
    Color dColor;
    Color dBg;

    if (daysLeft < 0) {
      dLabel = '마감';
      dColor = Colors.grey.shade700;
      dBg = Colors.grey.shade200;
    } else if (daysLeft == 0) {
      dLabel = 'D-DAY';
      dColor = Colors.red.shade700;
      dBg = Colors.red.shade50;
    } else {
      dLabel = 'D-$daysLeft';
      if (daysLeft <= 3) {
        dColor = Colors.red.shade700;
        dBg = Colors.red.shade50;
      } else if (daysLeft <= 7) {
        dColor = Colors.orange.shade700;
        dBg = Colors.orange.shade50;
      } else {
        dColor = Colors.green.shade700;
        dBg = Colors.green.shade50;
      }
    }

    final dateChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(DateFormat('~MM.dd').format(deadline), style: TextStyle(fontSize: 12.sp)),
    );

    final ddayChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: dBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(dLabel, style: TextStyle(fontSize: 12.sp, color: dColor, fontWeight: FontWeight.w600)),
    );

    return Row(children: [
      dateChip,
      const SizedBox(width: 4),
      ddayChip,
    ]);
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
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
        return; // 권한이 없으면 거리 계산하지 않음
      }

      // 현재 위치 가져오기
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 5));

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

  Future<void> _moveCameraAndSearch(NLatLng target, {double zoom = 16}) async {
    if (!_mapReady) return;

    try {
      // 수동 이동 모드로
      _naverController.setLocationTrackingMode(NLocationTrackingMode.none);

      // 카메라 이동
      await _naverController.updateCamera(
        NCameraUpdate.scrollAndZoomTo(target: target, zoom: zoom),
      );

      // 카메라 업데이트 직후 지도 바운드 계산이 안정되도록 아주 살짝 대기
      await Future.delayed(const Duration(milliseconds: 150));

      // 현재 뷰포트로 바로 검색
      await _searchInCurrentViewport();
    } catch (e) {
      if (!mounted) return;
      showFriendlySnack(context,   '지도를 불러오는데 살짝 삐끗했어요 💦 다시 한 번 시도해볼까요?');
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
