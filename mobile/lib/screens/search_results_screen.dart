import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile/config/config.dart';
import 'package:mobile/models/store_model.dart';
import 'package:mobile/services/campaign_service.dart';
import 'package:mobile/screens/home_screen.dart';

// 1. CampaignService를 제공하는 Provider 정의 (의존성 주입)
final campaignServiceProvider = Provider<CampaignService>((ref) {
  return CampaignService(
    AppConfig.ReviewMapbaseUrl,
    apiKey: AppConfig.ReviewMapApiKey,
  );
});

// 2. 검색 쿼리를 인자로 받아 검색 결과를 제공하는 FutureProvider.family 정의
final searchResultsProvider = FutureProvider.family<List<Store>, String>((ref, query) async {
  // campaignServiceProvider를 통해 서비스 인스턴스를 가져옴
  final campaignService = ref.watch(campaignServiceProvider);
  return campaignService.searchCampaigns(query: query);
});


// 3. 위젯을 StatefulWidget -> ConsumerWidget으로 변경
class SearchResultsScreen extends ConsumerWidget {
  final String query;
  const SearchResultsScreen({super.key, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 4. ref.watch를 사용하여 검색 결과 Provider를 구독
    final searchResultsAsync = ref.watch(searchResultsProvider(query));

    return Scaffold(
      appBar: AppBar(
        title: Text("'$query' 검색 결과"),
      ),
      // 5. AsyncValue.when을 사용하여 로딩/에러/데이터 상태에 따라 UI 렌더링
      body: searchResultsAsync.when(
        data: (results) {
          if (results.isEmpty) {
            return const Center(child: Text('검색 결과가 없습니다.'));
          }
          return ListView.separated(
            padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 16.w),
            itemCount: results.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, index) {
              final store = results[index];
              return SizedBox(
                height: 120.h,
                child: ExperienceCard(store: store),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('검색 결과를 불러오는 중 오류가 발생했습니다.')),
      ),
    );
  }
}