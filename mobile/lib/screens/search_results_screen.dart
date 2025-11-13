import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile/config/config.dart';
import 'package:mobile/const/colors.dart';
import 'package:mobile/models/store_model.dart';
import 'package:mobile/services/campaign_service.dart';
import 'package:mobile/services/interstitial_ad_manager.dart';
import '../widgets/experience_card.dart';
import '../widgets/friendly.dart';
import '../widgets/sort_filter_widget.dart';
import '../widgets/native_ad_widget.dart'; // 네이티브 광고 위젯
import '../providers/location_provider.dart';
import 'dart:math' as math;

// 1. CampaignService를 제공하는 Provider 정의 (의존성 주입)
final campaignServiceProvider = Provider<CampaignService>((ref) {
  return CampaignService(
    AppConfig.ReviewMapbaseUrl,
    apiKey: AppConfig.ReviewMapApiKey,
  );
});

// 2. 검색 정렬 옵션을 관리하는 Provider (통일된 SortOption 사용)
final searchSortProvider = StateProvider<SortOption>((ref) => SortOption.newest);

// 3. 거리 계산 헬퍼 함수
List<Store> _calculateDistances(List<Store> stores, Position? userPosition) {
  if (userPosition == null) {
    return stores.map((store) => store.copyWith(distance: null)).toList();
  }
  
  return stores.map((store) {
    if (store.lat == null || store.lng == null) {
      return store.copyWith(distance: null);
    }
    
    final distance = Geolocator.distanceBetween(
      userPosition.latitude,
      userPosition.longitude,
      store.lat!,
      store.lng!,
    );
    
    return store.copyWith(distance: distance / 1000); // km 단위로 변환
  }).toList();
}

// 4. 검색 결과를 제공하는 Provider (정렬 옵션에 따라 동적으로 변경)
final searchResultsProvider = FutureProvider.family.autoDispose<List<Store>, String>((ref, query) async {
  final service = ref.read(campaignServiceProvider);
  final sortOption = ref.watch(searchSortProvider);
  final locationState = ref.watch(locationProvider);

  // 검색 실행
  final results = await service.searchCampaigns(query: query);

  // 모든 정렬에서 거리 계산 (요청사항에 따라)
  final resultsWithDistance = _calculateDistances(results, locationState.position);

  // 정렬 적용
  switch (sortOption) {
    case SortOption.newest:
      // 1. 최신등록순: createdAt 최신순, 거리는 표시용으로만 사용
      return resultsWithDistance..sort((a, b) {
        final aCreated = a.createdAt;
        final bCreated = b.createdAt;
        
        if (aCreated == null && bCreated == null) return 0;
        if (aCreated == null) return 1;
        if (bCreated == null) return -1;
        
        return bCreated.compareTo(aCreated); // 최신순 (내림차순)
      });
      
    case SortOption.deadline:
      // 2. 마감임박순: applyDeadline 오름차순, deadline 같으면 distance 있는 게 우선
      return resultsWithDistance..sort((a, b) {
        final aDeadline = a.applyDeadline;
        final bDeadline = b.applyDeadline;
        
        // 마감일 비교
        if (aDeadline == null && bDeadline == null) return 0;
        if (aDeadline == null) return 1;
        if (bDeadline == null) return -1;
        
        final deadlineCompare = aDeadline.compareTo(bDeadline);
        if (deadlineCompare != 0) return deadlineCompare;
        
        // 마감일이 같으면 거리 있는 게 우선
        final aHasDistance = a.distance != null;
        final bHasDistance = b.distance != null;
        
        if (aHasDistance && !bHasDistance) return -1;
        if (!aHasDistance && bHasDistance) return 1;
        
        // 둘 다 거리가 있으면 실제 거리 값 비교
        if (aHasDistance && bHasDistance) {
          return a.distance!.compareTo(b.distance!);
        }
        
        return 0;
      });
      
    case SortOption.nearest:
      // 3. 거리순: distance 오름차순, distance 없는 건 맨 뒤로
      return resultsWithDistance..sort((a, b) {
        final aDistance = a.distance;
        final bDistance = b.distance;
        
        // 거리가 없는 경우를 맨 뒤로
        if (aDistance == null && bDistance == null) return 0;
        if (aDistance == null) return 1;
        if (bDistance == null) return -1;
        
        return aDistance.compareTo(bDistance);
      });
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
    // Provider를 통한 위치 정보 업데이트
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locationProvider.notifier).update();

      // 검색 결과 화면 진입 시 전면광고 표시 (무효 트래픽 방지 로직 적용)
      InterstitialAdManager().showInterstitialAdOnEvent(
        eventName: 'search_results_viewed',
      );
    });
  }

  /// 정렬 옵션 선택 시 위치 권한 확인 (Provider 사용)
  Future<void> _onSortOptionChanged(SortOption option) async {
    if (option == SortOption.nearest) {
      final locationState = ref.read(locationProvider);
      if (!locationState.isGranted || locationState.position == null) {
        // Provider를 통한 위치 권한 요청
        await ref.read(locationProvider.notifier).update();
        final updatedLocationState = ref.read(locationProvider);
        
        if (!updatedLocationState.isGranted) {
          if (mounted) {
            showFriendlySnack(
              context, 
              '위치 권한이 필요합니다.',
              actionLabel: '설정 열기',
              onAction: () => ref.read(locationProvider.notifier).openAppSettings(),
            );
          }
          return;
        } else if (updatedLocationState.position == null) {
          if (mounted) {
            showFriendlySnack(
              context, 
              '위치 정보를 가져올 수 없습니다.',
              actionLabel: '설정 열기',
              onAction: () => ref.read(locationProvider.notifier).openLocationSettings(),
            );
          }
          return;
        }
      }
    }
    
    ref.read(searchSortProvider.notifier).state = option;
  }

  @override
  Widget build(BuildContext context) {
    final searchResultsAsync = ref.watch(searchResultsProvider(widget.query));
    final currentSort = ref.watch(searchSortProvider);
    final locationState = ref.watch(locationProvider);
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
              fontSize: isTab ? 22.sp : 18.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: Colors.white,
          elevation: 0.5,
        ),
        body: Column(
          children: [
            // 통일된 정렬 필터
            SortFilterWidget(
              currentSort: currentSort,
              onSortChanged: _onSortOptionChanged,
              userPosition: locationState.position,
              onLocationRequest: () async {
                // Provider를 통한 위치 권한 요청
                await ref.read(locationProvider.notifier).update();
                final updatedLocationState = ref.read(locationProvider);
                
                if (!updatedLocationState.isGranted) {
                  showFriendlySnack(
                    context, 
                    '위치 권한이 필요합니다.',
                    actionLabel: '설정 열기',
                    onAction: () => ref.read(locationProvider.notifier).openAppSettings(),
                  );
                } else if (updatedLocationState.position == null) {
                  showFriendlySnack(
                    context, 
                    '위치 정보를 가져올 수 없습니다.',
                    actionLabel: '설정 열기',
                    onAction: () => ref.read(locationProvider.notifier).openLocationSettings(),
                  );
                }
              },
            ),
            
            // 검색 결과 목록 (10개마다 네이티브 광고 삽입)
            Expanded(
              child: searchResultsAsync.when(
                data: (results) {
                  if (results.isEmpty) {
                    return const Center(child: Text('검색 결과가 없습니다.'));
                  }

                  // 광고 삽입 계산: 16개마다 광고 1개
                  final int itemsPerAd = 16;
                  final int adCount = results.length ~/ itemsPerAd;
                  final int totalItems = results.length + adCount;

                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(searchResultsProvider(widget.query));
                    },
                    child: ListView.builder(
                      padding: EdgeInsets.only(top: 12.h, bottom: 12.h, left: 16.w, right: 16.w),
                      itemCount: totalItems,
                      itemBuilder: (context, index) {
                        // 광고 위치 계산
                        final int adsBefore = index ~/ (itemsPerAd + 1);
                        final int positionInGroup = index % (itemsPerAd + 1);

                        // 광고 위치인 경우
                        if (positionInGroup == itemsPerAd && adsBefore < adCount) {
                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.h),
                            child: const NativeAdListItem(),
                          );
                        }

                        // 실제 데이터 인덱스 계산
                        final int dataIndex = index - adsBefore;

                        if (dataIndex >= results.length) {
                          return const SizedBox.shrink();
                        }

                        final store = results[dataIndex];

                        // Divider 표시 조건:
                        // - 첫 번째 아이템(index == 0)이 아닌 경우
                        // - 광고 바로 다음 아이템(positionInGroup == 0)이 아닌 경우
                        final bool showDivider = index > 0 && positionInGroup != 0;

                        return Container(
                          constraints: BoxConstraints(minHeight: itemHeight),
                          decoration: showDivider
                            ? BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: Colors.grey.shade300, width: 1),
                                ),
                              )
                            : null, // decoration 자체를 null로 설정하여 레이아웃 영향 제거
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

}