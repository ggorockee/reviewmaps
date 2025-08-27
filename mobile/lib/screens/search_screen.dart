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

// =============== 검색어 입력 -======================
// 검색어 추천 목록 데이터 (실제 앱에서는 서버에서 가져옴)
// const List<String> _searchKeywords = [
//   '검정원피스', '검정치마lp', '검정치마', '검도', '검정블라우스', '검도호구', '검정고시', '검도복',
//   '김포맛집', '김포공항', '김포카페', '김포 현대아울렛',
//   '서울여행', '서울맛집', '서울페스타', '서울의 봄',
//   '애플워치', '에어팟', '아이패드', '아이폰',
// ];

// 연관 검색어를 제공하는 FutureProvider.family
// final suggestionsProvider = FutureProvider.family<List<String>, String>((ref, query) async {
//   // 쿼리가 비어있으면 빈 리스트 반환
//   if (query.isEmpty) {
//     return [];
//   }
//
//   // 네트워크 지연 시뮬레이션
//   await Future.delayed(const Duration(milliseconds: 200));
//
//   // 쿼리를 포함하는 키워드 필터링
//   return _searchKeywords.where((keyword) => keyword.toLowerCase().contains(query.toLowerCase())).toList();
// });
// =======================================================

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

      // 3. CampaignListScreen으로 이동하여 결과 보여주기
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CampaignListScreen(
            title: categoryName,
            initialStores: stores,
            userPosition: position, // 목록 화면에서 무한 스크롤을 위해 위치 정보 전달
          ),
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context); // 로딩 닫기
      if (mounted)
        showFriendlySnack(context, '앗, 정보를 가져오지 못했어요. 잠시 후 다시 시도해 주세요!');
    }
  }

  // 카테고리 이름에 맞는 아이콘 반환 (클라이언트에서 관리)
  Widget _getIconForCategory(String categoryName) {
    // 아이콘 크기 (폰트 크기에 반응하도록 .sp 사용)
    // 이전 답변에서 .sp로 변경했던 것을 유지합니다.
    final double iconSize = 18.sp; // Tab

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
    // final currentQuery = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const SizedBox.shrink(),
        leadingWidth: 0,
        title: TextField(
          controller: _searchController,
          autofocus: true,
          textInputAction: TextInputAction.search, // 선택
          decoration: const InputDecoration(
            hintText: '찾고 있는 장소나 가게 이름이 있나요?',
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
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
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onClearAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
        ),
        if (onClearAll != null)
          GestureDetector(
            onTap: onClearAll,
            child: Text(
              '전체 삭제',
              style: TextStyle(fontSize: 13.sp, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Widget _buildRecentSearchItem(String term) {
    return ListTile(
      onTap: () => _handleSearch(term),
      leading: const Icon(Icons.access_time),
      title: Text(term),
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
              child: ListView.builder(
                // 👇 [수정] 리스트의 시작 부분에만 왼쪽 여백(16)을 추가합니다.
                padding: EdgeInsets.only(left: 16.w),
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final categoryId = category['id'] as int;
                  final categoryName = category['name'] as String;

                  // 👇 [수정] 각 아이템의 왼쪽 대신 오른쪽에 여백(24)을 주어 간격을 넓힙니다.
                  return Padding(
                    padding: EdgeInsets.only(right: 28.w),
                    child: InkWell(
                      onTap: () => _onCategoryTapped(categoryId, categoryName),
                      borderRadius: BorderRadius.circular(16.r),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _getIconForCategory(categoryName),
                          SizedBox(height: 4.h),
                          Text(categoryName, style: TextStyle(fontSize: 13.sp)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => const Center(child: Text('카테고리를 불러올 수 없습니다.')),
        ),
        // const Divider(),
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
                  const Text('최근 검색 기록이 없습니다.')
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

  // Widget _buildSuggestionsList(String query) {
  //   final suggestionsAsync = ref.watch(suggestionsProvider(query));
  //   return suggestionsAsync.when(
  //     data: (suggestions) {
  //       if (suggestions.isEmpty) {
  //         return const Center(child: Text('연관 검색어가 없습니다.'));
  //       }
  //       return ListView.builder(
  //         itemCount: suggestions.length,
  //         itemBuilder: (context, index) {
  //           final suggestion = suggestions[index];
  //           return ListTile(
  //             leading: const Icon(Icons.search),
  //             title: _buildHighlightedText(suggestion, query),
  //             onTap: () => _handleSearch(suggestion),
  //           );
  //         },
  //       );
  //     },
  //     loading: () => const Center(child: LinearProgressIndicator()),
  //     error: (err, stack) => const Center(child: Text('검색어를 불러올 수 없습니다.')),
  //   );
  // }

  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return Text(text, style: const TextStyle(color: Colors.black));
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    final startIndex = lowerText.indexOf(lowerQuery);
    if (startIndex == -1) {
      return Text(text, style: const TextStyle(color: Colors.black));
    }

    final endIndex = startIndex + query.length;

    final before = text.substring(0, startIndex);
    final highlight = text.substring(startIndex, endIndex);
    final after = text.substring(endIndex);

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black, fontSize: 16), // 기본 스타일
        children: [
          TextSpan(text: before),
          TextSpan(
            text: highlight,
            style: TextStyle(
              color: Theme.of(context).primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }
}
