import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/store_model.dart';
import 'package:mobile/widgets/build_store_list_item.dart';
import 'package:mobile/widgets/experience_card.dart';
import 'package:mobile/widgets/friendly.dart';
import 'package:mobile/widgets/sort_filter_widget.dart';
import 'package:mobile/widgets/stay_availability_badge.dart';

/// 숙박 이용 요일 배지 표시 및 다양한 화면 크기·글자 배율에서
/// RenderFlex 오버플로우/잘림이 없는지 검증하는 위젯 테스트.
void main() {
  final lodgingStoreBoth = Store(
    id: 1,
    categoryId: 3,
    platform: '리뷰플레이스',
    title: '경주 감포라온 오션뷰 독채 스파 풀빌라 펜션 (최대 4인)',
    offer: '평일(일~목) 1박 숙박권 (기준 3인, 정상가 35만원) / 토요일 및 공휴일 제외',
    applyDeadline: DateTime.now().add(const Duration(days: 2)),
    createdAt: DateTime.now(),
    distance: 12.4,
    isNew: true,
  );

  final lodgingStoreExcludedOnly = Store(
    id: 2,
    categoryId: 3,
    platform: '리뷰노트',
    title: '베스트필드 글램핑 & 캠핑장',
    offer: '베스트필드 1박2일 숙박권 (토요일제외) 숯&그릴 제공',
    applyDeadline: DateTime.now().add(const Duration(days: 5)),
    createdAt: DateTime.now(),
    distance: 0.65,
    isNew: false,
  );

  final restaurantStore = Store(
    id: 3,
    categoryId: 1,
    platform: '리뷰노트',
    title: '꽁크 압구정본점',
    offer: '평일 디너 5만원 자유 이용권',
    applyDeadline: DateTime.now().add(const Duration(days: 4)),
    createdAt: DateTime.now(),
    distance: 1.2,
    isNew: false,
  );

  Widget wrapApp({
    required Widget child,
    required Size size,
    required double textScale,
  }) {
    final isTab = size.shortestSide >= 600;
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (context, _) => ClampTextScale(
            max: isTab ? 1.15 : 1.30,
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
  }

  testWidgets('숙박 카드에는 이용 가능·불가 배지가 보이고 맛집 카드에는 보이지 않는다', (tester) async {
    await tester.pumpWidget(
      wrapApp(
        size: const Size(375, 812),
        textScale: 1.0,
        child: SingleChildScrollView(
          child: Column(
            children: [
              ExperienceCard(
                store: lodgingStoreBoth,
                dense: true,
                bottomAlignMeta: false,
              ),
              ExperienceCard(
                store: lodgingStoreExcludedOnly,
                dense: true,
                bottomAlignMeta: false,
              ),
              ExperienceCard(
                store: restaurantStore,
                dense: true,
                bottomAlignMeta: false,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(StayAvailabilityBadge), findsNWidgets(2));
    expect(find.text('평일(일~목) 가능'), findsOneWidget);
    expect(find.text('토·공휴일 불가'), findsOneWidget);
    expect(find.text('토 불가'), findsOneWidget);
  });

  final testViewports = <String, Size>{
    '소형폰(360x640)': const Size(360, 640),
    '기본폰(375x812)': const Size(375, 812),
    '대형폰(412x915)': const Size(412, 915),
    '태블릿(768x1024)': const Size(768, 1024),
  };
  final testScales = <double>[0.85, 1.0, 1.3, 1.6];

  for (final vpEntry in testViewports.entries) {
    for (final scale in testScales) {
      testWidgets('${vpEntry.key} / 배율 ${scale}x 에서 카드·리스트·정렬필터 오버플로우 없음',
          (tester) async {
        final errors = <FlutterErrorDetails>[];
        final prevOnError = FlutterError.onError;
        FlutterError.onError = (details) => errors.add(details);
        addTearDown(() => FlutterError.onError = prevOnError);

        final size = vpEntry.value;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          wrapApp(
            size: size,
            textScale: scale,
            child: Builder(
              builder: (context) {
                final isTab = size.shortestSide >= 600;
                final ts = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.3);
                final gridHeight = (isTab ? 245.0 : 205.0) * ts;
                final recCellH = isTab
                    ? (240.0 + (275.0 - 240.0) * ((ts - 1.0) / 0.15).clamp(0.0, 1.0))
                    : (195.0 + (255.0 - 195.0) * ((ts - 1.0) / 0.30).clamp(0.0, 1.0));

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1) 정렬 필터
                      SortFilterWidget(
                        currentSort: SortOption.newest,
                        onSortChanged: (_) {},
                      ),
                      // 2) 홈 추천 2열 그리드 셀 높이와 동일
                      SizedBox(
                        height: recCellH.h,
                        child: Row(
                          children: [
                            Expanded(
                              child: ExperienceCard(
                                store: lodgingStoreBoth,
                                dense: true,
                                bottomAlignMeta: true,
                              ),
                            ),
                            Expanded(
                              child: ExperienceCard(
                                store: lodgingStoreExcludedOnly,
                                dense: true,
                                bottomAlignMeta: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 3) 카테고리 목록 2열 그리드 높이와 동일
                      SizedBox(
                        height: gridHeight.h,
                        child: Row(
                          children: [
                            Expanded(
                              child: ExperienceCard(
                                store: lodgingStoreBoth,
                                dense: true,
                                bottomAlignMeta: true,
                              ),
                            ),
                            Expanded(
                              child: ExperienceCard(
                                store: restaurantStore,
                                dense: true,
                                bottomAlignMeta: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 4) 검색결과 1열 카드 (7칸 요일 띠 포함)
                      ExperienceCard(
                        store: lodgingStoreBoth,
                        dense: true,
                        compact: false,
                        bottomAlignMeta: false,
                        showDayStrip: true,
                      ),
                      // 5) 지도 리스트 아이템 (7칸 요일 띠 포함)
                      StoreListItem(
                        store: lodgingStoreBoth,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
        await tester.pump();
        FlutterError.onError = prevOnError;

        expect(
          errors,
          isEmpty,
          reason: '${vpEntry.key} @ ${scale}x 에서 레이아웃 오류 발생: '
              '${errors.map((e) => e.exceptionAsString()).join('\n')}',
        );
      });
    }
  }
}
