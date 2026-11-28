import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/config/app_version.dart';
import 'package:mobile/models/release_note.dart';
import 'package:mobile/models/version_check_models.dart';
import 'package:mobile/services/release_note_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String noteJson(String version, {String title = '제목', int pages = 1}) {
  final list = List.generate(pages, (i) => '{"title": "$title ${i + 1}"}').join(',');
  return '{"version": "$version", "pages": [$list]}';
}

ReleaseNoteService service({
  String current = '2.3.0',
  String bundled = '',
  String remote = '',
  bool Function()? enabled,
}) => ReleaseNoteService(
  currentVersion: current,
  loadBundled: () async => bundled,
  remoteSource: () => remote,
  afterUpdateEnabled: enabled ?? () => true,
);

VersionCheckResponse policy({String latest = '2.4.0', String? title, String? body}) =>
    VersionCheckResponse(
      latestVersion: latest,
      minVersion: '0.0.0',
      forceUpdate: false,
      storeUrl: 'https://example.com',
      messageTitle: title,
      messageBody: body,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ReleaseNote.tryParse', () {
    test('형식이 틀리면 null', () {
      for (final source in ['', 'abc', '[]', '{"pages": []}', '{"version": "1.0.0", "pages": "x"}', '{"version": 1, "pages": []}']) {
        expect(ReleaseNote.tryParse(source), isNull, reason: source);
      }
    });

    test('3장까지만 쓰고 제목 없는 장은 버린다', () {
      expect(ReleaseNote.tryParse(noteJson('1.0.0', pages: 5))!.pages, hasLength(3));
      final note = ReleaseNote.tryParse(
        '{"version": "1.0.0", "pages": [{"body": "제목 없음"}, {"title": " "}, {"title": "남는 장"}, 3]}',
      )!;
      expect(note.pages.map((p) => p.title), ['남는 장']);
    });

    test('그림은 앱 asset 이나 https 만 받는다', () {
      final note = ReleaseNote.tryParse(
        '{"version": "1.0.0", "pages": ['
        '{"title": "a", "image": "asset/image/a.png"},'
        '{"title": "b", "image": "https://example.com/b.png"},'
        '{"title": "c", "image": "http://example.com/c.png"}]}',
      )!;
      expect(note.pages.map((p) => p.image), ['asset/image/a.png', 'https://example.com/b.png', null]);
    });
  });

  group('업데이트한 뒤 새로워진 점', () {
    test('새로 설치하면 보여주지 않는다', () async {
      final s = service(bundled: noteJson('2.3.0'));
      await s.recordFirstInstall();
      expect(await s.pendingAfterUpdate(), isNull);
    });

    test('쓰던 사용자가 업데이트하면 한 번 보여준다', () async {
      SharedPreferences.setMockInitialValues({ReleaseNoteService.firstRunKey: true});
      final s = service(bundled: noteJson('2.3.0'));
      await s.recordFirstInstall();
      expect((await s.pendingAfterUpdate())!.version, '2.3.0');
      await s.markSeen();
      expect(await s.pendingAfterUpdate(), isNull);
    });

    test('다음 버전으로 올리면 다시 보여준다', () async {
      SharedPreferences.setMockInitialValues({ReleaseNoteService.seenVersionKey: '2.2.3'});
      expect(await service(bundled: noteJson('2.3.0')).pendingAfterUpdate(), isNotNull);
    });

    test('Remote Config에서 끄면 안 보이고, 다시 켜면 한 번 보인다', () async {
      SharedPreferences.setMockInitialValues({ReleaseNoteService.seenVersionKey: '2.2.3'});
      var on = false;
      final s = service(bundled: noteJson('2.3.0'), enabled: () => on);
      expect(await s.pendingAfterUpdate(), isNull);
      on = true;
      expect(await s.pendingAfterUpdate(), isNotNull);
      await s.markSeen();
      expect(await s.pendingAfterUpdate(), isNull);
    });

    test('꺼도 업데이트 전 안내는 그대로다', () {
      final note = service(remote: noteJson('2.4.0'), enabled: () => false).beforeUpdate(policy(), forced: false);
      expect(note.version, '2.4.0');
    });

    test('버전을 내리면 보여주지 않는다', () async {
      SharedPreferences.setMockInitialValues({ReleaseNoteService.seenVersionKey: '2.4.0'});
      expect(await service(bundled: noteJson('2.3.0')).pendingAfterUpdate(), isNull);
    });

    test('다른 버전용 안내나 빈 안내는 쓰지 않는다', () async {
      expect(await service(bundled: noteJson('2.2.0')).pendingAfterUpdate(), isNull);
      expect(await service(bundled: noteJson('2.3.0', pages: 0)).pendingAfterUpdate(), isNull);
    });

    test('이 버전용 원격 안내가 있으면 앱에 든 것보다 먼저 쓴다', () async {
      final s = service(bundled: noteJson('2.3.0', title: '내장'), remote: noteJson('2.3.0', title: '원격'));
      expect((await s.pendingAfterUpdate())!.pages.first.title, '원격 1');
      final other = service(bundled: noteJson('2.3.0', title: '내장'), remote: noteJson('2.4.0', title: '원격'));
      expect((await other.pendingAfterUpdate())!.pages.first.title, '내장 1');
    });
  });

  group('업데이트하기 전 안내', () {
    test('새 버전용 원격 안내를 쓴다', () {
      final note = service(remote: noteJson('2.4.0', pages: 2)).beforeUpdate(policy(), forced: false);
      expect(note.pages, hasLength(2));
    });

    test('원격 안내가 다른 버전용이면 기본 한 장', () {
      final note = service(remote: noteJson('2.3.0', pages: 2)).beforeUpdate(policy(), forced: false);
      expect(note.version, '2.4.0');
      expect(note.pages.single.title, '새 버전이 있어요');
    });

    test('Remote Config 문구가 있으면 기본 장에 쓴다', () {
      final note = service().beforeUpdate(policy(title: '큰 변화', body: '설명'), forced: true);
      expect(note.pages.single.title, '큰 변화');
      expect(note.pages.single.body, '설명');
    });
  });

  group('앱에 든 asset/release_notes.json', () {
    final note = ReleaseNote.tryParse(File(ReleaseNoteService.assetPath).readAsStringSync());

    test('현재 앱 버전용이어야 한다 (알릴 것이 없으면 pages 를 비운다)', () {
      expect(note, isNotNull);
      expect(note!.version, AppVersion.current);
    });

    test('가리키는 그림 파일이 있어야 한다', () {
      for (final page in note!.pages) {
        final image = page.image;
        if (image != null && image.startsWith('asset/')) {
          expect(File(image).existsSync(), isTrue, reason: image);
        }
      }
    });
  });
}
