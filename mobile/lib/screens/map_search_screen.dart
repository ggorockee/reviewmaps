// mobile/lib/screens/map_search_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/config.dart';
import '../utils/naver_key_rotator.dart';

class Place {
  final String title;
  final String? roadAddress;
  final NLatLng position; // 변환된 최종 위도/경도 객체

  Place({required this.title, this.roadAddress, required this.position});
}

List<String> expandQuery(String q) {
  final s = q.trim();
  final cands = <String>{s};

  // 고촌 → 고촌읍/고촌역/김포 고촌/김포시 고촌읍
  if (s.length <= 4) {
    cands.addAll({'$s읍', '$s동', '$s역', '김포 $s', '김포시 $s', '김포시 $s읍'});
  }
  // 괄호/특수문자 정리 (혹시 모를 경우)
  return cands.map((e) => e.replaceAll(RegExp(r'[<>]'), '')).toList();
}

// ====== [추가] NCloud 지오코딩 폴백 ======
Future<Place?> geocodeFallback(String query) async {
  final uri = Uri.https(
    'naveropenapi.apigw.ntruss.com',
    '/map-geocode/v2/geocode',
    {'query': query},
  );
  final headers = {
    'X-NCP-APIGW-API-KEY-ID': AppConfig.NAVER_MAP_CLIENT_ID,
    'X-NCP-APIGW-API-KEY': AppConfig.NAVER_MAP_CLIENT_SECRET,
  };

  final resp = await http
      .get(uri, headers: headers)
      .timeout(const Duration(seconds: 5));
  if (resp.statusCode != 200) return null;

  final jsonBody = json.decode(utf8.decode(resp.bodyBytes));
  final addresses = (jsonBody['addresses'] as List?) ?? const [];
  if (addresses.isEmpty) return null;

  final a = addresses.first;
  final lat = double.tryParse(a['y']?.toString() ?? '');
  final lng = double.tryParse(a['x']?.toString() ?? '');
  if (lat == null || lng == null) return null;

  return Place(
    title: a['roadAddress'] ?? a['jibunAddress'] ?? query,
    roadAddress: a['roadAddress'] ?? a['jibunAddress'],
    position: NLatLng(lat, lng),
  );
}

// 1. 검색 결과 상태 관리를 위한 Notifier 및 Provider
//======================================================================
class SearchResultNotifier extends AsyncNotifier<List<Place>> {
  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;


  T t<T>(BuildContext ctx, T phone, T tablet) => _isTablet(ctx) ? tablet : phone;


  @override
  FutureOr<List<Place>> build() => [];

  Future<void> search(String query) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final candidates = expandQuery(query);
      const String authority = "openapi.naver.com";
      const String path = "/v1/search/local.json";

      // [수정 1] 최종 결과를 담을 리스트와 중복 체크를 위한 Set 초기화
      List<Place> picked = [];
      final Set<String> uniquePlaceIds = {};

      // 후보 질의들을 순차로 시도
      for (final q in candidates) {
        final params = {'query': q, 'display': '10'}; // 10개 요구
        final uri = Uri.https(authority, path, params);

        final response = await NaverSearchKeyRotator.instance.runWithRotation(
              (headers) => http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 5)),
        );

        if (response.statusCode != 200) continue;

        final data = json.decode(utf8.decode(response.bodyBytes));
        final List<dynamic> items = data['items'] ?? [];
        if (items.isEmpty) continue;

        // 결과 매핑 및 중복 제거 로직
        for (var item in items) {
          final mapxStr = item['mapx'] as String?;
          final mapyStr = item['mapy'] as String?;
          if (mapxStr == null || mapyStr == null) continue;

          final x = double.tryParse(mapxStr);
          final y = double.tryParse(mapyStr);
          if (x == null || y == null) continue;

          final lng = x / 1e7;
          final lat = y / 1e7;
          final position = NLatLng(lat, lng);

          final title = (item['title'] as String? ?? '')
              .replaceAll('<b>', '')
              .replaceAll('</b>', '');
          final road = (item['roadAddress'] as String?)?.trim();
          final addr = (item['address'] as String?)?.trim();

          final place = Place(
            title: title.isNotEmpty ? title : (road ?? addr ?? q),
            roadAddress: (road?.isNotEmpty == true) ? road : addr,
            position: position,
          );

          // [수정 2] 제목과 도로명 주소를 합쳐 고유 ID 생성 후 중복 체크
          final uniqueId = "${place.title}|${place.roadAddress ?? ''}";
          if (uniquePlaceIds.add(uniqueId)) { // Set에 추가 성공 시 (중복이 아닐 시)
            picked.add(place); // 최종 결과 리스트에 추가
          }
        }
        // [삭제] 기존의 if (places.isNotEmpty) { ... break; } 블록은 삭제됨
      }

      // 모든 후보가 실패 → 지오코딩 폴백으로 최소 1건이라도 제공
      if (picked.isEmpty) {
        final g = await geocodeFallback(query);
        if (g != null) picked = [g];
      }

      // 캐시에 저장
      final prefs = await SharedPreferences.getInstance();
      for (final p in picked) {
        final data = {
          'title': p.title,
          'lat': p.position.latitude,
          'lng': p.position.longitude,
          'roadAddress': p.roadAddress,
        };
        await prefs.setString('placeCache:${p.title}', jsonEncode(data));
      }
      return picked;
    });
  }
}

final searchResultProvider =
    AsyncNotifierProvider<SearchResultNotifier, List<Place>>(
      SearchResultNotifier.new,
    );

// 2. 최근 검색어 상태 관리를 위한 Notifier 및 Provider
//======================================================================
class SearchHistoryNotifier extends AsyncNotifier<List<String>> {

  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;


  T t<T>(BuildContext ctx, T phone, T tablet) => _isTablet(ctx) ? tablet : phone;

  static const _historyKey = 'searchHistory';
  @override
  FutureOr<List<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_historyKey) ?? [];
  }

  Future<void> add(String query) async {
    state = await AsyncValue.guard(() async {
      final currentHistory = List<String>.from(state.value ?? []);
      final cleanQuery = query.replaceAll('<b>', '').replaceAll('</b>', '');
      currentHistory.remove(cleanQuery);
      currentHistory.insert(0, cleanQuery);
      final newHistory = currentHistory.length > 10
          ? currentHistory.sublist(0, 10)
          : currentHistory;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_historyKey, newHistory);
      return newHistory;
    });
  }

  Future<void> remove(String query) async {
    state = await AsyncValue.guard(() async {
      final current = List<String>.from(state.value ?? []);
      current.remove(query);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_historyKey, current);
      return current;
    });
  }
}

final searchHistoryProvider =
    AsyncNotifierProvider<SearchHistoryNotifier, List<String>>(
      SearchHistoryNotifier.new,
    );

// 3. UI 위젯
//======================================================================
class MapSearchScreen extends ConsumerStatefulWidget {
  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;


  T t<T>(BuildContext ctx, T phone, T tablet) => _isTablet(ctx) ? tablet : phone;

  const MapSearchScreen({super.key});

  @override
  ConsumerState<MapSearchScreen> createState() => _MapSearchScreenState();
}

class _MapSearchScreenState extends ConsumerState<MapSearchScreen> {
  bool _isTablet(BuildContext context) =>
      MediaQuery.of(context).size.shortestSide >= 600;


  T t<T>(BuildContext ctx, T phone, T tablet) => _isTablet(ctx) ? tablet : phone;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _triggerSearch(String query) {
    if (query.isNotEmpty) {
      ref.read(searchResultProvider.notifier).search(query);
    } else {
      ref.invalidate(searchResultProvider);
    }
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _triggerSearch(_searchController.text);
    });
  }

  Future<void> _submitAndMoveToFirstResult(String query) async {
    _debounce?.cancel();
    if (mounted) setState(() {});

    await ref.read(searchResultProvider.notifier).search(query);
    if (!mounted) return; // ← 추가

    final places = ref
        .read(searchResultProvider)
        .maybeWhen(data: (v) => v, orElse: () => const <Place>[]);

    if (places.isNotEmpty && mounted) {
      final first = places.first;
      await ref.read(searchHistoryProvider.notifier).add(first.title);
      if (!mounted) return; // ← 추가
      Navigator.pop(context, first.position);
    }
  }


  @override
  Widget build(BuildContext context) {
    final showHistory = _searchController.text.isEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: TextStyle(
              fontSize: t(context, 13.sp, 10.5.sp),
          ),
          decoration: InputDecoration(
            hintText: '장소, 지하철, 지역으로 검색',
            hintStyle: TextStyle(
              fontSize: t(context, 13.sp, 10.5.sp),
            ),
            border: InputBorder.none,
          ),
          onSubmitted: _submitAndMoveToFirstResult,
        ),
        actions: [
          if (!showHistory)
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.grey),
              onPressed: () {
                _searchController.clear();
                if (mounted) setState(() {}); // 화면을 최근검색어 뷰로 전환
                ref.invalidate(searchResultProvider); // 이전 검색 결과 상태 초기화(선택)
              },
            ),
        ],

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey[200], height: 1.0),
        ),
      ),

      body: showHistory ? _SearchHistoryView() : _SearchResultsView(),
    );
  }

}


class _SearchHistoryView extends ConsumerStatefulWidget {
  const _SearchHistoryView();
  @override
  ConsumerState<_SearchHistoryView> createState() => _SearchHistoryViewState();
}


class _SearchHistoryViewState extends ConsumerState<_SearchHistoryView> {
  TextEditingController _searchControllerFromWidget(BuildContext context) {
    final state = context.findAncestorStateOfType<_MapSearchScreenState>();
    return state!._searchController;
  }

  @override
  Widget build(BuildContext context) {

    // searchHistoryProvider를 watch하여 상태(로딩, 데이터, 에러)를 감지
    final historyState = ref.watch(searchHistoryProvider);

    // .when을 사용하여 상태에 따라 다른 UI를 보여줌
    return historyState.when(
      data: (history) {
        if (history.isEmpty) {
          return const Center(child: Text('최근 검색 기록이 없습니다.'));
        }
        return ListView.builder(
          itemCount: history.length,
          itemBuilder: (context, index) {
            final query = history[index];
            return ListTile(
              leading: const Icon(Icons.history, color: Colors.grey),
              title: Text(query),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                onPressed: () {
                  // 여긴 await 없음 → 바로 안전
                  ref.read(searchHistoryProvider.notifier).remove(query);
                },
              ),
              onTap: () async {
                // 1) 캐시 먼저 확인
                final prefs = await SharedPreferences.getInstance();
                if (!mounted) return; // ← 중요
                final cached = prefs.getString('placeCache:$query');
                if (cached != null) {
                  final m = jsonDecode(cached) as Map<String, dynamic>;
                  final lat = (m['lat'] as num).toDouble();
                  final lng = (m['lng'] as num).toDouble();
                  // pop 이후엔 절대 ref/read 호출하지 않음
                  if (!mounted) return;
                  Navigator.pop(context, NLatLng(lat, lng));
                  return;
                }

                // 2) 캐시에 없으면: 화면을 '검색결과' 모드로 전환하고 바로 검색
                final controller = _searchControllerFromWidget(context);
                controller.text = query;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: query.length),
                );
                if (mounted) setState(() {}); // 히스토리 → 결과 전환

                await ref.read(searchResultProvider.notifier).search(query);
                if (!mounted) return; // ← 중요

                final places = ref
                    .read(searchResultProvider)
                    .maybeWhen(data: (v) => v, orElse: () => const <Place>[]);
                if (places.isNotEmpty && mounted) {
                  Navigator.pop(context, places.first.position);
                }
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('오류: $error')),
    );
  }
}

// 최근 검색어 UI
class _SearchResultsView extends ConsumerWidget {
  const _SearchResultsView();

  Widget _buildHighlightedTitle(BuildContext context, String title, String query) {
    final shortest = MediaQuery.of(context).size.shortestSide;
    final isTablet = shortest >= 600;
    final fontSize = isTablet ? 16.0 : 13.0;

    final cleanTitle = title.replaceAll('<b>', '').replaceAll('</b>', '');
    final parts = title.split(RegExp(r'<b>|</b>'));

    if (parts.length == 1) {
      return Text(cleanTitle, style: TextStyle(color: Colors.black, fontSize: fontSize));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(color: Colors.black, fontSize: fontSize),
        children: parts.map((part) {
          final isBold = title.contains('<b>$part</b>');
          return TextSpan(
            text: part,
            style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(searchResultProvider);
    // 현재 입력된 검색어를 가져옴
    final query =
        ref.context
            .findAncestorStateOfType<_MapSearchScreenState>()
            ?._searchController
            .text ??
        '';

    return searchState.when(
      data: (places) {
        // if (query.isEmpty) return Container();
        if (places.isEmpty) return const Center(child: Text('검색 결과가 없습니다.'));

        return ListView.builder(
          itemCount: places.length,
          itemBuilder: (context, index) {
            final place = places[index];
            return ListTile(
              leading: const Icon(
                Icons.location_on_outlined,
                color: Colors.grey,
              ),
              title: _buildHighlightedTitle(context, place.title, query), // 강조 효과 적용
              subtitle: Text(place.roadAddress ?? ''),
              onTap: () {
                ref.read(searchHistoryProvider.notifier).add(place.title);
                Navigator.pop(context, place.position);
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('오류가 발생했습니다:\n$error')),
    );
  }
}
