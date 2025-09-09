import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile/config/config.dart';
import 'package:mobile/const/colors.dart';
import 'package:mobile/models/store_model.dart';
import 'package:mobile/services/campaign_service.dart';
import '../widgets/experience_card.dart';
import '../widgets/friendly.dart';

// 1. CampaignService를 제공하는 Provider 정의 (의존성 주입)
final campaignServiceProvider = Provider<CampaignService>((ref) {
  return CampaignService(
    AppConfig.ReviewMapbaseUrl,
    apiKey: AppConfig.ReviewMapApiKey,
  );
});

/// 검색 정렬 옵션 열거형
enum SearchSortOption {
  nearest('거리순', 'distance'),
  deadline('마감임박순', 'apply_deadline'),
  newest('신규등록순', '-created_at');

  const SearchSortOption(this.displayName, this.apiValue);
  final String displayName;
  final String apiValue;
}

// 2. 검색 정렬 상태를 관리하는 Provider
final searchSortProvider = StateProvider.autoDispose<SearchSortOption>((ref) => SearchSortOption.nearest);

// 3. 사용자 위치 상태를 관리하는 Provider
final userLocationProvider = StateProvider<Position?>((ref) => null);

// 4. 검색 쿼리와 정렬 옵션을 조합하여 검색 결과를 제공하는 FutureProvider
final searchResultsProvider = FutureProvider.family.autoDispose<List<Store>, String>((
  ref,
  query,
) async {
  final campaignService = ref.watch(campaignServiceProvider);
  final sortOption = ref.watch(searchSortProvider);
  final userLocation = ref.watch(userLocationProvider);
  
  List<Store> results;
  
  // 거리순 정렬이면서 위치 정보가 있는 경우
  if (sortOption == SearchSortOption.nearest && userLocation != null) {
    results = await campaignService.fetchNearest(
      lat: userLocation.latitude,
      lng: userLocation.longitude,
      limit: 100,
    );
    
    // 검색어로 필터링
    if (query.isNotEmpty) {
      results = results.where((store) {
        return store.title.toLowerCase().contains(query.toLowerCase()) ||
               (store.offer?.toLowerCase().contains(query.toLowerCase()) ?? false);
      }).toList();
    }
  } else {
    // 일반 검색
    results = await campaignService.searchCampaigns(query: query);
    
    // 위치 정보가 있으면 거리 계산 추가
    if (userLocation != null) {
      results = results.map((store) {
        if (store.lat != null && store.lng != null) {
          final distance = Geolocator.distanceBetween(
            userLocation.latitude, userLocation.longitude, 
            store.lat!, store.lng!,
          ) / 1000; // 미터를 킬로미터로 변환
          
          return store.copyWith(distance: distance);
        }
        return store;
      }).toList();
    }
    
    // 클라이언트 사이드 정렬 (서버에서 지원하지 않는 경우)
    switch (sortOption) {
      case SearchSortOption.deadline:
        results.sort((a, b) {
          if (a.applyDeadline == null && b.applyDeadline == null) return 0;
          if (a.applyDeadline == null) return 1;
          if (b.applyDeadline == null) return -1;
          return a.applyDeadline!.compareTo(b.applyDeadline!);
        });
        break;
      case SearchSortOption.newest:
        results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SearchSortOption.nearest:
        // 기본 정렬 유지
        break;
    }
  }
  
  return results;
});

// 5. 위젯을 StatefulWidget -> ConsumerStatefulWidget으로 변경하여 위치 요청 처리
class SearchResultsScreen extends ConsumerStatefulWidget {
  final String query;
  const SearchResultsScreen({super.key, required this.query});

  @override
  ConsumerState<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;

  /// 검색 결과 아이템의 높이를 텍스트 배율과 디바이스에 따라 동적으로 계산
  double _calcItemHeight(BuildContext context) {
    final isTab = _isTablet(context);
    final ts = MediaQuery.textScalerOf(context).textScaleFactor;

    // 기본 높이(폰/태블릿) 완화
    final double base = isTab ? 205.h : 80.h;
    // 텍스트가 커질수록 여유 공간 추가 (계수 낮춤)
    final double scaleOver = (ts - 1.0).clamp(0.0, 0.8);
    final double extra = scaleOver * (isTab ? 50.h : 40.h);
    // 상한 적용: 필요 이상으로 커지지 않도록 제한
    final double maxH = isTab ? 260.h : 200.h;
    return (base + extra).clamp(base, maxH);
  }

  @override
  void initState() {
    super.initState();
    // 위치 정보 가져오기 시도 (백그라운드에서)
    _tryGetUserLocation();
  }

  /// 사용자 위치 가져오기 (에러 시 조용히 무시)
  Future<void> _tryGetUserLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) return;

      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        ref.read(userLocationProvider.notifier).state = position;
      }
    } catch (e) {
      // 위치 가져오기 실패는 조용히 무시
      debugPrint('위치 가져오기 실패: $e');
    }
  }

  /// 정렬 옵션 선택 시 위치 권한 확인
  Future<void> _onSortOptionChanged(SearchSortOption option) async {
    if (option == SearchSortOption.nearest) {
      final userLocation = ref.read(userLocationProvider);
      if (userLocation == null) {
        // 위치 정보가 없으면 다시 시도
        try {
          await _requestLocationPermission();
        } catch (e) {
          if (mounted) {
            showFriendlySnack(context, '위치 권한이 필요합니다. 설정에서 허용해주세요.');
          }
          return; // 위치 획득 실패 시 정렬 변경하지 않음
        }
      }
    }
    
    ref.read(searchSortProvider.notifier).state = option;
  }

  /// 위치 권한 요청
  Future<void> _requestLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('위치 서비스를 켜주세요');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      throw Exception('위치 권한을 허용해주세요');
    }

    final position = await Geolocator.getCurrentPosition();
    ref.read(userLocationProvider.notifier).state = position;
  }

  @override
  Widget build(BuildContext context) {
    final searchResultsAsync = ref.watch(searchResultsProvider(widget.query));
    final currentSort = ref.watch(searchSortProvider);
    final userLocation = ref.watch(userLocationProvider);
    final isTab = _isTablet(context);
    final itemHeight = _calcItemHeight(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "'${widget.query}' 검색 결과",
          style: TextStyle(
            fontSize: isTab ? 14.sp : 18.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          // 정렬 옵션 칩들
          _buildSortChips(currentSort, userLocation),
          
          // 검색 결과 목록
          Expanded(
            child: searchResultsAsync.when(
              data: (results) {
                if (results.isEmpty) {
                  return const Center(child: Text('검색 결과가 없습니다.'));
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(searchResultsProvider(widget.query));
                  },
                  child: ListView.separated(
                    padding: EdgeInsets.only(top: 12.h, bottom: 12.h, left: 16.w, right: 16.w),
                    itemCount: results.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final store = results[index];
                      return Container(
                        constraints: BoxConstraints(minHeight: itemHeight),
                        child: ExperienceCard(
                          store: store,
                          dense: true,
                          compact: false,
                          bottomAlignMeta: false, // 검색 결과는 타이트 간격
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('검색 결과를 불러오는 중 오류가 발생했습니다.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => ref.refresh(searchResultsProvider(widget.query)),
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 정렬 옵션 칩들을 표시하는 위젯
  Widget _buildSortChips(SearchSortOption currentSort, Position? userLocation) {
    final isTab = _isTablet(context);
    
    return Container(
      height: isTab ? 60.h : 50.h,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: SearchSortOption.values.map((option) {
                  final isSelected = currentSort == option;
                  final isDistanceOption = option == SearchSortOption.nearest;
                  final canUseDistance = userLocation != null;
                  
                  return Padding(
                    padding: EdgeInsets.only(right: 8.w),
                    child: SizedBox(
                      width: isTab ? 85.w : 90.w, // 균일한 칩 폭
                      child: ChoiceChip(
                        label: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isDistanceOption && !canUseDistance)
                                Icon(
                                  Icons.location_off,
                                  size: 12.w,
                                  color: Colors.grey[400],
                                ),
                              if (isDistanceOption && !canUseDistance)
                                SizedBox(width: 3.w),
                              Flexible(
                                child: Text(
                                  option.displayName,
                                  style: TextStyle(
                                    fontSize: isTab ? 9.sp : 14.sp,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            _onSortOptionChanged(option);
                          }
                        },
                        selectedColor: PRIMARY_COLOR,
                        backgroundColor: Colors.grey[100],
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[700],
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                        showCheckmark: false,
                        padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        // 거리순이지만 위치 정보가 없으면 비활성화
                        side: (isDistanceOption && !canUseDistance)
                            ? BorderSide(color: Colors.grey[300]!)
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
