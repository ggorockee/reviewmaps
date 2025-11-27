import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile/config/config.dart';
import '../models/store_model.dart';
import '../services/campaign_service.dart';
import '../widgets/experience_card.dart';
import '../widgets/friendly.dart';
import '../widgets/sort_filter_widget.dart';
import '../widgets/native_ad_widget.dart'; // 네이티브 광고 위젯
import 'dart:math' as math;

/// 캠페인 리스트 정렬 옵션 (통일된 SortOption 사용)
// CampaignListSortOption을 SortOption으로 매핑하는 헬퍼
class CampaignListSortHelper {
  static SortOption fromCampaignListSort(CampaignListSortOption option) {
    switch (option) {
      case CampaignListSortOption.newest:
        return SortOption.newest;
      case CampaignListSortOption.deadline:
        return SortOption.deadline;
      case CampaignListSortOption.nearest:
        return SortOption.nearest;
    }
  }

  static CampaignListSortOption toCampaignListSort(SortOption option) {
    switch (option) {
      case SortOption.newest:
        return CampaignListSortOption.newest;
      case SortOption.deadline:
        return CampaignListSortOption.deadline;
      case SortOption.nearest:
        return CampaignListSortOption.nearest;
    }
  }
}

// 기존 enum 유지 (API 호출용)
enum CampaignListSortOption {
  nearest('거리순', 'distance'),
  deadline('마감임박순', 'apply_deadline'),
  newest('신규등록순', '-created_at');

  const CampaignListSortOption(this.displayName, this.apiValue);
  final String displayName;
  final String apiValue;
}

// 정렬 상태를 관리하는 Provider (통일된 SortOption 사용)
final campaignListSortProvider = StateProvider.autoDispose<SortOption>((ref) => SortOption.newest);

/// 캠페인 리스트 화면
/// ------------------------------------------------------------
/// 진입 케이스:
///  - 추천 목록: initialStores만 주어지고 userPosition은 null → 무한스크롤 비활성화(더 불러올 기준 없음)
///  - 가까운 목록: initialStores + userPosition 제공 → fetchNearest로 페이지네이션
///
/// 배포 포인트:
///  - 불필요 로그 제거, 사용자 피드백은 스낵바/조용한 폴백으로 처리
///  - 텍스트 스케일 대응(가독성 + 레이아웃 안정)
class CampaignListScreen extends ConsumerStatefulWidget {
  final String title;
  final List<Store> initialStores;
  final Position? userPosition;
  final int? categoryId; // 카테고리 ID 추가
  final bool isSearchResult; // 검색결과인지 카테고리 결과인지 구분

  const CampaignListScreen({
    super.key,
    required this.title,
    required this.initialStores,
    this.userPosition, // 추천 목록 등 위치 없는 경우 null
    this.categoryId, // 카테고리 필터링용
    this.isSearchResult = false, // 기본값은 카테고리 결과
  });

  @override
  ConsumerState<CampaignListScreen> createState() => _CampaignListScreenState();
}

class _CampaignListScreenState extends ConsumerState<CampaignListScreen> {
  // ---------------- State & Services ----------------
  final _scrollController = ScrollController();

  // 근처 목록(위치 기반) 무한스크롤 시 사용
  final _campaignService = CampaignService(
    AppConfig.reviewMapBaseUrl,
    apiKey: AppConfig.reviewMapApiKey,
  );

  final List<Store> _originalStores = []; // 원본 데이터
  final List<Store> _stores = []; // 화면에 보여줄 누적 리스트
  bool _isLoading = false;        // 서버 페치 중 플래그
  bool _hasMore = true;           // 추가 페이지 유무
  final int _limit = 20;          // 서버 페이지 크기
  int _offset = 0;                // 서버 오프셋
  
  CampaignListSortOption? _lastSortOption; // 마지막 정렬 옵션 추적

  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;

  @override
  void initState() {
    super.initState();

    // 1) 초기 데이터 채우기
    _originalStores.addAll(widget.initialStores);
    _stores.addAll(widget.initialStores);
    _offset = _stores.length;

    // 2) 위치가 없으면 더보기(무한스크롤) 비활성화
    if (widget.userPosition == null) {
      _hasMore = false;
    }

    // 3) 스크롤 끝 근처 감지하여 자동 로드
    _scrollController.addListener(_scrollListener);

    // 4) 정렬 변경은 build 메서드에서 처리
  }

  /// 정렬 적용
  void _applySorting(SortOption sortOption) {
    setState(() {
      final sortedStores = List<Store>.from(_originalStores);
      
      switch (sortOption) {
        case SortOption.nearest:
          if (widget.userPosition != null) {
            sortedStores.sort((a, b) {
              final distanceA = a.distance ?? double.maxFinite;
              final distanceB = b.distance ?? double.maxFinite;
              return distanceA.compareTo(distanceB);
            });
          }
          break;
        case SortOption.deadline:
          sortedStores.sort((a, b) {
            if (a.applyDeadline == null && b.applyDeadline == null) return 0;
            if (a.applyDeadline == null) return 1;
            if (b.applyDeadline == null) return -1;
            return a.applyDeadline!.compareTo(b.applyDeadline!);
          });
          break;
        case SortOption.newest:
          sortedStores.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          break;
      }
      
      _stores
        ..clear()
        ..addAll(sortedStores);
    });
  }

  /// 아이템 높이 계산 (텍스트 스케일 대응)
  double _getItemHeight() {
    final bool isTab = _isTablet(context);
    final ts = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.3);
    
    if (widget.isSearchResult) {
      // 검색결과는 한 줄이므로 높이를 더 작게
      final baseHeight = isTab ? 120.0 : 100.0;
      return (baseHeight * ts).h;
    } else {
      // 카테고리 결과는 기존 높이 유지
      final baseHeight = isTab ? 190.0 : 160.0;
      return (baseHeight * ts).h;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------- Infinite Scroll ----------------
  /// 스크롤 잔여 길이가 임계치 이하일 때 다음 페이지 로드
  void _scrollListener() {
    if (_scrollController.position.extentAfter < 300 && !_isLoading && _hasMore) {
      _loadMore();
    }
  }

  /// 위치가 있을 때만(=근처 목록일 때만) 다음 페이지를 서버에서 페치
  Future<void> _loadMore() async {
    if (widget.userPosition == null) return; // 추천 목록일 땐 종료

    setState(() => _isLoading = true);

    try {
      final newStores = await _campaignService.fetchNearest(
        lat: widget.userPosition!.latitude,
        lng: widget.userPosition!.longitude,
        categoryId: widget.categoryId, // 카테고리 필터 적용
        limit: _limit,
        offset: _offset,
      );

      if (!mounted) return;

      setState(() {
        if (newStores.isNotEmpty) {
          _originalStores.addAll(newStores); // 원본에도 추가
          _stores.addAll(newStores);
          _offset += newStores.length;
        } else {
          // 더 이상 가져올 페이지 없음
          _hasMore = false;
        }
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showFriendlySnack(context, '목록을 더 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  // ---------------- Build ----------------
  @override
  Widget build(BuildContext context) {
    final currentSort = ref.watch(campaignListSortProvider);
    final bool isTab = _isTablet(context);
    
    // 리스트 레이아웃에서는 동적 높이 불필요

    // 정렬 옵션이 변경되었을 때 처리
    if (_lastSortOption != null && _lastSortOption != CampaignListSortHelper.toCampaignListSort(currentSort)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applySorting(currentSort);
      });
    }
    _lastSortOption = CampaignListSortHelper.toCampaignListSort(currentSort);

    return ClampTextScale(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
              widget.title,
              style: TextStyle(
                fontSize: isTab ? 22.sp : 18.sp,
                fontWeight: FontWeight.w700,
              ),
          ),
          toolbarHeight: isTab ? 56.h : kToolbarHeight,
          titleSpacing: isTab ? 16.w : 0.w,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        backgroundColor: Colors.white,
        body: Column(
          children: [
            // 통일된 정렬 필터
            SortFilterWidget(
              currentSort: currentSort,
              onSortChanged: (newSort) {
                ref.read(campaignListSortProvider.notifier).state = newSort;
              },
              userPosition: widget.userPosition,
              onLocationRequest: () {
                showFriendlySnack(context, '위치 권한이 필요합니다. 설정에서 허용해주세요.');
              },
            ),
            
            // 목록
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // 격자 스타일 - 카테고리는 2열 그리드 + 네이티브 광고, 검색결과는 1열 리스트
                  if (widget.isSearchResult)
                    // 검색결과는 기존 방식 유지 (1열 리스트)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: 12.0.w, vertical: 8.0.h),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 1,
                          crossAxisSpacing: 0,
                          mainAxisSpacing: 1.0,
                          mainAxisExtent: _getItemHeight(),
                          childAspectRatio: 1.0,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildGridItemWithBorders(_stores[index], index),
                          childCount: _stores.length,
                        ),
                      ),
                    )
                  else
                    // 카테고리는 10개마다 네이티브 광고 삽입 (홈 화면 패턴)
                    ..._buildGridWithAds(),

                  // 하단 로딩 인디케이터(추가 페이지 로딩 중에만 노출)
                  SliverToBoxAdapter(
                    child: _isLoading
                        ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Center(child: CircularProgressIndicator()),
                    )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Grid with Ads ----------------
  /// 카테고리 그리드와 네이티브 광고를 조합하여 반환 (홈 화면 패턴)
  /// 20개 체험단마다 네이티브 광고 1개 삽입
  List<Widget> _buildGridWithAds() {
    final List<Widget> slivers = [];
    const int itemsPerGrid = 20; // 2열 그리드: 20개 아이템

    for (int i = 0; i < _stores.length; i += itemsPerGrid) {
      final int endIndex = math.min(i + itemsPerGrid, _stores.length);
      final List<Store> chunk = _stores.sublist(i, endIndex);

      // 체험단 그리드
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.all(16.0),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 0,
              mainAxisSpacing: 0,
              mainAxisExtent: _getItemHeight(),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final globalIndex = i + index;
                return _buildGridItemWithBorders(chunk[index], globalIndex);
              },
              childCount: chunk.length,
            ),
          ),
        ),
      );

      // 20개마다 네이티브 광고 삽입 (마지막 청크는 제외)
      if (endIndex < _stores.length) {
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

  // ---------------- Grid Item ----------------
  /// 격자 스타일 아이템 빌더 (기존 스타일 복원)
  Widget _buildGridItemWithBorders(Store store, int index) {
    final gridLineColor = Colors.grey.shade300;
    const gridLineWidth = 0.7;
    final cols = widget.isSearchResult ? 1 : 2; // 검색결과는 1열, 카테고리는 2열

    final isRightCol = (index % cols) == cols - 1;
    final rowCount = (_stores.length / cols).ceil();
    final currentRow = (index / cols).floor();
    final isLastRow = currentRow == rowCount - 1;

    final boxBorder = Border(
      right: isRightCol
          ? BorderSide.none
          : BorderSide(color: gridLineColor, width: gridLineWidth),
      bottom: isLastRow && !_hasMore
          ? BorderSide.none
          : BorderSide(color: gridLineColor, width: gridLineWidth),
    );

    return DecoratedBox(
      decoration: BoxDecoration(border: boxBorder),
      child: ExperienceCard(
        store: store,
        dense: true,     // 격자에서는 조밀하게
        compact: widget.isSearchResult, // 검색결과는 더 컴팩트하게
      ),
    );
  }

  /// 실제 카드 UI (플랫폼 뱃지 / 상호 / 오퍼 / 메타)
  // Widget _buildGridItemCard(Store store) {
  //   final platformColor = platformBadgeColor(store.platform);
  //
  //   return InkWell(
  //     onTap: () => _openLink(store.companyLink),
  //     child: Container(
  //       padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
  //       color: Colors.transparent,
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         mainAxisAlignment: MainAxisAlignment.spaceBetween, // 상단/하단 분리 배치
  //         children: [
  //           // ---------- 상단: 플랫폼, 상호, 오퍼 ----------
  //           Column(
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             mainAxisSize: MainAxisSize.min, // 내용만큼만 높이
  //             children: [
  //               // 플랫폼 뱃지
  //               Container(
  //                 padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
  //                 decoration: BoxDecoration(
  //                   color: platformColor,
  //                   borderRadius: BorderRadius.circular(4),
  //                 ),
  //                 child: Text(
  //                   // 플랫폼명은 길지 않으므로 폰트 고정 (가독 우선)
  //                   // 필요 시 ScreenUtil로 .sp 적용 가능
  //                   // '플랫폼', // 접근성 리더에서 store.platform을 그대로 읽게 하려면 아래 Text로 교체
  //                     store.platform,
  //                     style: TextStyle(
  //                       color: Colors.white,
  //                       fontSize: 12.spMin,
  //                       fontWeight: FontWeight.bold,
  //                     ),
  //                 ),
  //               ),
  //               const SizedBox(height: 6),
  //
  //               // 상호명
  //               Text(
  //                 store.company,
  //                 maxLines: 2,
  //                 overflow: TextOverflow.ellipsis,
  //                 style: const TextStyle(
  //                   fontWeight: FontWeight.bold,
  //                   fontSize: 14,
  //                   height: 1.15,
  //                 ),
  //               ),
  //
  //               // 오퍼(있을 때만)
  //               if ((store.offer ?? '').isNotEmpty) ...[
  //                 const SizedBox(height: 2),
  //                 Text(
  //                   store.offer!,
  //                   maxLines: 2,
  //                   overflow: TextOverflow.ellipsis,
  //                   style: TextStyle(
  //                     fontSize: 12,
  //                     height: 1.15,
  //                     color: Colors.grey[700],
  //                   ),
  //                 ),
  //               ],
  //             ],
  //           ),
  //
  //           // ---------- 하단: 메타(마감일/거리) ----------
  //           Row(
  //             children: [
  //               // 마감일 있을 때만 달력 아이콘 + 날짜 표기
  //               if (store.applyDeadline != null) ...[
  //                 Icon(Icons.calendar_today, size: 12, color: Colors.grey[600]),
  //                 const SizedBox(width: 4),
  //                 Text(
  //                   '~${DateFormat('MM.dd').format(store.applyDeadline!)}',
  //                   style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.0),
  //                 ),
  //               ],
  //               const Spacer(),
  //               if (store.distance != null)
  //                 Text(
  //                   '${store.distance!.toStringAsFixed(1)}km',
  //                   style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.0),
  //                 ),
  //             ],
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  // ---------------- Link Helper ----------------
  /// 외부 링크 실행(https 보정 + 외부 브라우저 우선)
  // Future<void> _openLink(String? rawLink) async {
  //   if (rawLink == null || rawLink.isEmpty) return;
  //   try {
  //     String s = rawLink.trim();
  //     if (!s.startsWith('http://') && !s.startsWith('https://')) {
  //       s = 'https://$s';
  //     }
  //     final uri = Uri.parse(Uri.encodeFull(s));
  //     // 외부 브라우저 우선
  //     if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
  //       // 실패 시 인앱 시도
  //       await launchUrl(uri);
  //     }
  //   } catch (_) {
  //     if (!mounted) return;
  //     showFriendlySnack(context, '링크를 열 수 없어요.');
  //   }
  // }

}
