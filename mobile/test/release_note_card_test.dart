import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/release_note.dart';
import 'package:mobile/models/version_check_models.dart';
import 'package:mobile/services/release_note_presenter.dart';
import 'package:mobile/services/release_note_service.dart';
import 'package:mobile/widgets/release_note_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

const longPage = ReleaseNotePage(
  title: '이용 가능한 요일이 목록에서 바로 보이는 아주 긴 제목입니다',
  body: '숙박·여행 체험단은 상세 페이지를 열지 않아도 요일 정보를 목록에서 확인할 수 있어요. '
      '설명이 길어져도 카드 안에서 위아래로 넘겨 볼 수 있어야 합니다.',
  image: 'asset/image/release_notes/stay_days.png',
);

const threePages = ReleaseNote(
  version: '2.3.0',
  pages: [longPage, ReleaseNotePage(title: '둘째 장', icon: 'new'), ReleaseNotePage(title: '셋째 장')],
);

const onePage = ReleaseNote(version: '2.3.0', pages: [ReleaseNotePage(title: '한 장', icon: 'update')]);

void setScreen(WidgetTester tester, Size size, {double textScale = 1.0}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// 버튼을 누르면 [open]을 실행하는 화면
Widget host(Future<void> Function(BuildContext) open) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: TextButton(onPressed: () => open(context), child: const Text('열기')),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in const [Size(320, 568), Size(375, 812), Size(768, 1024), Size(812, 375)]) {
    for (final textScale in [1.0, 1.3, 1.6]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()} 배율 $textScale 에서 넘치지 않는다', (tester) async {
        setScreen(tester, size, textScale: textScale);
        for (final type in ReleaseCardType.values) {
          await tester.pumpWidget(
            MaterialApp(home: ReleaseNoteCard(key: ValueKey(type), note: threePages, type: type)),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$type');
        }
      });
    }
  }

  testWidgets('카드는 화면의 가로 90%, 세로 80%', (tester) async {
    setScreen(tester, const Size(400, 800));
    await tester.pumpWidget(
      const MaterialApp(home: ReleaseNoteCard(note: onePage, type: ReleaseCardType.afterUpdate)),
    );
    final card = tester.getSize(
      find.descendant(of: find.byType(Dialog), matching: find.byType(Column)).first,
    );
    expect(card.width, 360);
    expect(card.height, 640);
  });

  testWidgets('새로워진 점: 다음으로 넘기고 마지막 장에서 확인하면 본 것으로 저장한다', (tester) async {
    setScreen(tester, const Size(375, 812));
    final events = <(String, Map<String, Object>)>[];
    final notes = ReleaseNoteService(
      currentVersion: '2.3.0',
      loadBundled: () async =>
          '{"version": "2.3.0", "pages": [{"title": "첫째"}, {"title": "둘째"}]}',
      remoteSource: () => '',
    );
    final presenter = ReleaseNotePresenter(notes: notes, logEvent: (n, p) async => events.add((n, p)));

    await tester.pumpWidget(host(presenter.showWhatsNew));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('새로워진 점 · v2.3.0'), findsOneWidget);
    expect(find.text('확인했어요'), findsNothing);
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인했어요'));
    await tester.pumpAndSettle();

    expect(find.byType(ReleaseNoteCard), findsNothing);
    expect(await notes.pendingAfterUpdate(), isNull);
    expect(events.map((e) => e.$1), ['update_card_shown', 'update_card_action']);
    expect(events.last.$2, containsPair('action', 'confirm'));
    expect(events.last.$2, containsPair('last_page', 2));
    expect(events.last.$2, containsPair('card_type', 'after'));
  });

  testWidgets('한 장이면 점과 "다음" 없이 바로 확인 버튼', (tester) async {
    setScreen(tester, const Size(375, 812));
    await tester.pumpWidget(
      const MaterialApp(home: ReleaseNoteCard(note: onePage, type: ReleaseCardType.afterUpdate)),
    );
    expect(find.text('다음'), findsNothing);
    expect(find.text('확인했어요'), findsOneWidget);
    expect(find.byType(AnimatedContainer), findsNothing);
  });

  group('업데이트하기 전', () {
    final response = VersionCheckResponse(
      latestVersion: '9.9.9',
      minVersion: '0.0.0',
      forceUpdate: false,
      storeUrl: 'https://example.com/store',
    );

    Future<(List<(String, Map<String, Object>)>, List<Uri>)> openCard(
      WidgetTester tester, {
      required bool forced,
      bool storeOpens = true,
    }) async {
      setScreen(tester, const Size(375, 812));
      final events = <(String, Map<String, Object>)>[];
      final opened = <Uri>[];
      final presenter = ReleaseNotePresenter(
        notes: ReleaseNoteService(remoteSource: () => ''),
        logEvent: (n, p) async => events.add((n, p)),
        openUrl: (url) async {
          opened.add(url);
          return storeOpens;
        },
      );
      await tester.pumpWidget(host((c) => presenter.showUpdate(c, response, forced: forced)));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      return (events, opened);
    }

    Future<bool> skipped() async =>
        (await SharedPreferences.getInstance()).getKeys().any((k) => k.contains('skip'));

    testWidgets('"나중에"를 누르면 일정 기간 건너뛴다', (tester) async {
      final (events, opened) = await openCard(tester, forced: false);
      await tester.tap(find.text('나중에'));
      await tester.pumpAndSettle();
      expect(find.byType(ReleaseNoteCard), findsNothing);
      expect(opened, isEmpty);
      expect(await skipped(), isTrue);
      expect(events.last.$2, containsPair('action', 'later'));
    });

    testWidgets('닫기(X)도 건너뛰기로 처리한다', (tester) async {
      final (events, _) = await openCard(tester, forced: false);
      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();
      expect(await skipped(), isTrue);
      expect(events.last.$2, containsPair('action', 'close'));
    });

    testWidgets('업데이트를 누르면 스토어를 열고 카드를 닫는다', (tester) async {
      final (events, opened) = await openCard(tester, forced: false);
      await tester.tap(find.text('업데이트 하기'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://example.com/store')]);
      expect(find.byType(ReleaseNoteCard), findsNothing);
      expect(await skipped(), isFalse);
      expect(events.last.$2, containsPair('action', 'update'));
    });

    testWidgets('스토어를 못 열면 카드가 남고 알려준다', (tester) async {
      await openCard(tester, forced: false, storeOpens: false);
      await tester.tap(find.text('업데이트 하기'));
      await tester.pumpAndSettle();
      expect(find.byType(ReleaseNoteCard), findsOneWidget);
      expect(find.text('스토어를 열 수 없어요'), findsOneWidget);
    });

    testWidgets('강제 업데이트는 닫기·나중에·뒤로 가기가 없고 스토어에 다녀와도 남는다', (tester) async {
      final (events, opened) = await openCard(tester, forced: true);
      expect(find.byTooltip('닫기'), findsNothing);
      expect(find.text('나중에'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReleaseNoteCard), findsOneWidget);

      await tester.tapAt(const Offset(5, 5)); // 카드 밖
      await tester.pumpAndSettle();
      await tester.tap(find.text('업데이트 하기'));
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
      expect(find.byType(ReleaseNoteCard), findsOneWidget);
      expect(events.last.$2, containsPair('action', 'update'));
    });

    testWidgets('권장 업데이트는 뒤로 가기로 닫으면 건너뛴다', (tester) async {
      await openCard(tester, forced: false);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReleaseNoteCard), findsNothing);
      expect(await skipped(), isTrue);
    });
  });
}
