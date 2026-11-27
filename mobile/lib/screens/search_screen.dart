import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile/screens/search_results_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/category_provider.dart';
import '../widgets/friendly.dart';
import 'campaign_list_screen.dart';

// 1. 최근 검색어 목록을 관리하는 AsyncNotifierProvider 정의
const _recentSearchKey = 'recent_searches';

final recentSearchesProvider =
    AsyncNotifierProvider<RecentSearchesNotifier, List<String>>(
      () => RecentSearchesNotifier(),
    );

final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

class RecentSearchesNotifier extends AsyncNotifier<List<String>> {
  // 초기 상태를 로드하는 build 메서드
  @override
  Future<List<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentSearchKey) ?? [];
  }

  // 검색어 추가
  Future<void> addSearch(String query) async {
    // 현재 상태를 가져와서 업데이트
    final currentState = state.asData?.value ?? [];
    final newList = [query, ...currentState.where((item) => item != query)];
    // 최대 10개만 유지
    state = AsyncData(newList.take(10).toList());
    // SharedPreferences에 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentSearchKey, state.value!);
  }

  // 검색어 삭제
  Future<void> deleteSearch(String query) async {
    final currentState = state.asData?.value ?? [];
    state = AsyncData(currentState.where((item) => item != query).toList());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentSearchKey, state.value!);
  }

  // 전체 삭제
  Future<void> clearAll() async {
    state = const AsyncData([]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentSearchKey);
  }
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  // 2. 디바운싱을 위한 상태 변수 추가
  Timer? _debounce;
  // String _currentQuery = ''; // UI 상태 분기를 위한 현재 검색어
  bool _loading = false;

  bool _isTablet(BuildContext ctx) =>
      MediaQuery.of(ctx).size.shortestSide >= 600;

  T t<T>(BuildContext ctx, T phone, T tablet) =>
      _isTablet(ctx) ? tablet : phone;

  void _setLoading(bool v) {
    if (!mounted) return;
    setState(() => _loading = v);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel(); // 위젯이 제거될 때 타이머도 취소
    super.dispose();
  }

  void _handleSearch(String query) {
    if (query.trim().isEmpty) return;
    final trimmedQuery = query.trim();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(query: trimmedQuery),
      ),
    );

    ref.read(recentSearchesProvider.notifier).addSearch(trimmedQuery);
    _searchController.clear();
    // [수정] 검색 후에는 provider의 상태를 초기화
    ref.read(searchQueryProvider.notifier).state = '';
  }

  Future<void> _onCategoryTapped(int categoryId, String categoryName) async {
    if (_loading) return;      // 연타 방지
    _setLoading(true);         // 탭 즉시 스피너 ON
    try {
      // 1. 위치 권한 확인 및 현재 위치 가져오기
      // (home_screen.dart의 로직을 참고하여 권한 처리 로직 추가 가능)
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) showFriendlySnack(context, '위치 서비스를 켜주세요.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        if (mounted) showFriendlySnack(context, '위치 권한을 허용해주세요.');
        return;
      }

      // 2. 현재 위치를 가져와요
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // 2. 서버에서 해당 카테고리의 주변 캠페인 데이터 가져오기
      final campaignService = ref.read(campaignServiceProvider);
      final stores = await campaignService.fetchNearest(
        lat: position.latitude,
        lng: position.longitude,
        categoryId: categoryId, // ✨ 선택한 카테고리 ID를 전달
        limit: 20,
      );

      if (!mounted) return;

      // 3. CampaignListScreen으로 이동하여 결과 보여주기 (카테고리 결과)
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CampaignListScreen(
            title: categoryName,
            initialStores: stores,
            userPosition: position, // 목록 화면에서 무한 스크롤을 위해 위치 정보 전달
            categoryId: categoryId, // 카테고리 ID 전달
            isSearchResult: false, // 카테고리 결과 (2열 그리드)
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        showFriendlySnack(context, '앗, 정보를 가져오지 못했어요. 잠시 후 다시 시도해 주세요!');
      }
    } finally {
      _setLoading(false);
    }
  }

  Widget _loadingOverlay() {
    return IgnorePointer(
      ignoring: !_loading, // loading일 때만 이벤트 차단
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: _loading ? 1.0 : 0.0,
        child: Container(
          color: Colors.black.withValues(alpha: 0.25),
          alignment: Alignment.center,
          child: const CircularProgressIndicator(),
        ),
      ),
    );
  }

  // 카테고리 이름에 맞는 아이콘 반환 (클라이언트에서 관리)
  Widget _getIconForCategory(String categoryName) {
    // 폰트 배율에 따른 아이콘 크기 조정
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
    final baseIconSize = t(context, 15.sp, 18.sp);
    final iconSize = baseIconSize * (1.0 + (textScaleFactor - 1.0) * 0.3).clamp(1.0, 1.2);

    switch (categoryName) {
      case '맛집':
        return Icon(Icons.restaurant, color: Colors.orange.shade700, size: iconSize);
      case '카페/디저트':
        return Icon(Icons.local_cafe, color: Colors.brown.shade400, size: iconSize);
      case '뷰티/헬스':
        return Icon(Icons.spa, color: Colors.pink.shade300, size: iconSize);
      case '숙박':
        return Icon(Icons.hotel, color: Colors.blue.shade600, size: iconSize);
      case '여행':
        return Icon(Icons.explore, color: Colors.deepPurple.shade400, size: iconSize);
      case '패션/생활':
        return Icon(Icons.checkroom, color: Colors.teal.shade400, size: iconSize);
      case '쇼핑':
        return Icon(Icons.shopping_bag, color: Colors.green.shade600, size: iconSize);
      case '생활서비스':
        return Icon(Icons.handyman, color: Colors.blueGrey.shade500, size: iconSize);
      case '액티비티':
        return Icon(Icons.local_activity, color: Colors.red.shade600, size: iconSize);
      case '반려동물':
        return Icon(Icons.pets, color: Colors.brown.shade600, size: iconSize);
      case '문화/클래스':
        return Icon(Icons.palette, color: Colors.indigo.shade400, size: iconSize);
      case '기타':
        return Icon(Icons.more_horiz, color: Colors.grey.shade600, size: iconSize);
      default:
        return Icon(Icons.circle, color: Colors.black54, size: iconSize);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isTablet = _isTablet(context);
    final double maxScale = isTablet ? 1.10 : 1.30;

    return ClampTextScale(
      max: maxScale,
      child: Scaffold(
        appBar: AppBar(
          leading: const SizedBox.shrink(),
          leadingWidth: 0,
          titleSpacing: t(context, 16.w, 15.w),
          toolbarHeight: t(context, 56.h, 72.h),
          title: Padding(
            padding: EdgeInsets.only(
              top: t(context, 4.h, 8.h),
              bottom: t(context, 6.h, 10.h),
              // 필요하면 오른쪽도: right: t(context, 16.w, 24.w),
            ),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search, // 선택
              decoration: InputDecoration(
                hintText: '지역, 업체, 제안 검색',
                hintStyle: TextStyle(
                  fontSize: t(context, 16.sp, 9.5.sp),
                ),
                border: InputBorder.none,
              ),
              onSubmitted: _handleSearch,
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  if (!mounted) return;
                  // ✅ read만 쓰기 (리빌드 유발 X)
                  ref.read(searchQueryProvider.notifier).state = value;
                });
              },
            ),
          ),
          actions: [
            Padding(
              padding: EdgeInsets.only(
                  right: t(context, 16.sp, 8.sp),
              ),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                    '닫기',
                  style: TextStyle(
                    fontSize: t(context, 16.sp, 8.sp),
                  ),
                ),
              ),
            ),
          ],
        ),
        // 👇 [수정] body를 Stack과 Visibility로 변경하여 화면 구조 안정화
        body: Consumer(
          builder: (context, wref, _) {
            final currentQuery = wref.watch(searchQueryProvider);
            return Stack(
              children: [
                Visibility(
                  visible: currentQuery.isEmpty,
                  maintainState: true,
                  child: _buildRecentAndRecommendedSearches(wref),
                ),
                if (_loading) Positioned.fill(child: _loadingOverlay()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onClearAll}) {
    final titleFontSize = 16.sp;
    final subtitleFontSize = 13.sp;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.bold),
          ),
        ),
        if (onClearAll != null)
          GestureDetector(
            onTap: onClearAll,
            child: Text(
              '전체 삭제',
              style: TextStyle(fontSize: subtitleFontSize, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _buildRecentSearchItem(String term) {
    final fontSize = 15.sp;

    return ListTile(
      onTap: () => _handleSearch(term),
      leading: const Icon(Icons.access_time),
      title: Text(
        term,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: fontSize),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () =>
            ref.read(recentSearchesProvider.notifier).deleteSearch(term),
      ),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildRecentAndRecommendedSearches(WidgetRef wref) {
    final recentSearchesAsync = wref.watch(recentSearchesProvider);
    final categoriesAsync = wref.watch(categoriesProvider);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        categoriesAsync.when(
          data: (categories) {
            if (categories.isEmpty) {
              return SizedBox(
                height: 80.h,
                child: const Center(child: Text("추천 카테고리가 아직 없어요 😅")),
              );
            }
            return SizedBox(
              height: 80.h, // 섹션 높이 지정
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 화면 너비를 기준으로 5.5개 아이템이 보이도록 계산
                  final screenWidth = constraints.maxWidth;
                  final itemWidth = 60.w; // 각 아이템의 너비
                  final itemSpacing = 8.w; // 아이템 간격
                  final leftPadding = 8.w; // 왼쪽 패딩
                  
                  // 5.5개 아이템이 보이도록 ListView의 너비 제한
                  final visibleWidth = leftPadding + (itemWidth * 5.5) + (itemSpacing * 4.5);
                  
                  return SizedBox(
                    width: visibleWidth.clamp(0.0, screenWidth),
                    child: ListView.builder(
                      padding: EdgeInsets.only(left: leftPadding),
                      scrollDirection: Axis.horizontal,
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final category = categories[index];
                        final categoryId = category['id'] as int;
                        final categoryName = category['name'] as String;

                        return Container(
                          width: itemWidth,
                          margin: EdgeInsets.only(right: itemSpacing),
                          child: InkWell(
                            onTap: () => _onCategoryTapped(categoryId, categoryName),
                            borderRadius: BorderRadius.circular(16.r),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _getIconForCategory(categoryName),
                                SizedBox(height: 4.h),
                                // 카테고리 텍스트 줄바꿈 방지 및 폰트 배율 대응
                                Text(
                                  categoryName,
                                  style: TextStyle(
                                    fontSize: t(context, 13.sp, 8.5.sp),
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2, // 최대 2줄까지 허용
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => const Center(child: Text('카테고리를 불러올 수 없습니다.')),
        ),
        SizedBox(height: 8.h),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: recentSearchesAsync.when(
            data: (searches) => Column(
              children: [
                _buildSectionHeader(
                  '최근 검색',
                  onClearAll: searches.isNotEmpty
                      ? () =>
                            ref.read(recentSearchesProvider.notifier).clearAll()
                      : null,
                ),
                SizedBox(height: 8.h),
                if (searches.isEmpty)
                  Text(
                      '최근 검색 기록이 없습니다.',
                    style: TextStyle(
                      fontSize: t(context, 16.sp, 8.5.sp)
                    ),
                  )
                else
                  ...searches.map((term) => _buildRecentSearchItem(term)),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('오류가 발생했습니다: $err')),
          ),
        ),
      ],
    );
  }
}