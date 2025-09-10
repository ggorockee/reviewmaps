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

// 2. 사용자 위치를 저장하는 Provider
final userLocationProvider = StateProvider<Position?>((ref) => null);

// 3. 검색 정렬 옵션을 관리하는 Provider
enum SearchSortOption { newest, deadline, nearest }

final searchSortProvider = StateProvider<SearchSortOption>((ref) => SearchSortOption.newest);

// 4. 검색 결과를 제공하는 Provider (정렬 옵션에 따라 동적으로 변경)
final searchResultsProvider = FutureProvider.family.autoDispose<List<Store>, String>((ref, query) async {
  final service = ref.read(campaignServiceProvider);
  final sortOption = ref.watch(searchSortProvider);
  final userLocation = ref.watch(userLocationProvider);

  // 검색 실행
  final results = await service.searchCampaigns(query: query);

  // 정렬 적용
  switch (sortOption) {
    case SearchSortOption.newest:
      return results;
    case SearchSortOption.deadline:
      return results..sort((a, b) {
        final aDeadline = a.applyDeadline;
        final bDeadline = b.applyDeadline;
        
        if (aDeadline == null && bDeadline == null) return 0;
        if (aDeadline == null) return 1;
        if (bDeadline == null) return -1;
        
        return aDeadline.compareTo(bDeadline);
      });
    case SearchSortOption.nearest:
      if (userLocation == null) {
        // 위치 정보가 없으면 거리순 정렬 불가능
        return results;
      }
      
      // 거리 계산 및 정렬
      final resultsWithDistance = results.map((store) {
        if (store.lat == null || store.lng == null) {
          return MapEntry(store, double.infinity);
        }
        final distance = Geolocator.distanceBetween(
          userLocation.latitude,
          userLocation.longitude,
          store.lat!,
          store.lng!,
        );
        return MapEntry(store, distance);
      }).toList();
      
      // 거리순으로 정렬 (거리가 없는 항목은 마지막에)
      resultsWithDistance.sort((a, b) {
        if (a.value == double.infinity && b.value == double.infinity) return 0;
        if (a.value == double.infinity) return 1;
        if (b.value == double.infinity) return -1;
        return a.value.compareTo(b.value);
      });
      
      return resultsWithDistance.map((entry) => entry.key).toList();
  }
});

class SearchResultsScreen extends ConsumerStatefulWidget {
  final String query;

  const SearchResultsScreen({
    super.key,
    required this.query,
  });

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
    final double maxScale = isTab ? 1.10 : 1.30;

    return ClampTextScale(
      max: maxScale,
      child: Scaffold(
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
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('오류가 발생했습니다: $error'),
                      SizedBox(height: 16.h),
                      ElevatedButton(
                        onPressed: () {
                          ref.invalidate(searchResultsProvider(widget.query));
                        },
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 정렬 옵션 칩들을 표시하는 위젯
  Widget _buildSortChips(SearchSortOption currentSort, Position? userLocation) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildSortChip('신규등록순', SearchSortOption.newest, currentSort),
            SizedBox(width: 8.w),
            _buildSortChip('마감임박순', SearchSortOption.deadline, currentSort),
            SizedBox(width: 8.w),
            _buildSortChip('거리순', SearchSortOption.nearest, currentSort, userLocation),
          ],
        ),
      ),
    );
  }

  /// 개별 정렬 칩을 생성하는 위젯
  Widget _buildSortChip(String label, SearchSortOption option, SearchSortOption currentSort, [Position? userLocation]) {
    final isTab = _isTablet(context);
    final bool isSelected = currentSort == option;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: isTab ? 12.sp : 14.sp,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? Colors.white : Colors.black87,
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
      side: BorderSide(
        color: isSelected ? PRIMARY_COLOR : Colors.grey[300]!,
        width: 1.0,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isTab ? 12.w : 16.w,
        vertical: isTab ? 6.h : 8.h,
      ),
      pressElevation: 0,
    );
  }
}